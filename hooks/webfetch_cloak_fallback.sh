#!/usr/bin/env bash
# PostToolUse hook: when WebFetch fails with a Cloudflare/bot-block pattern,
# transparently retry with CloakBrowser + defuddle and inject the markdown back
# as additionalContext.
#
# Reads hook payload as JSON on stdin:
#   { "tool_name": "WebFetch",
#     "tool_input":  { "url": "...", "prompt": "..." },
#     "tool_response": "..." }
#
# Exits 0 silently on any non-trigger or any failure inside the fallback path
# (we never want to break the original WebFetch error chain).

set -uo pipefail

CLOAK_FETCH="/Users/niehu/.claude/hooks/cloak_fetch.py"
FAILURE_REGEX="403|forbidden|cloudflare|just a moment|resource was not loaded|access denied|blocked"

# Read full payload
payload=$(cat)

tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty')
if [ "$tool_name" != "WebFetch" ]; then
  exit 0
fi

# tool_response can be a string or an object depending on harness version —
# coerce to string for the regex check.
response=$(printf '%s' "$payload" | jq -r '.tool_response | if type=="string" then . else tojson end // empty')
if ! printf '%s' "$response" | grep -qiE "$FAILURE_REGEX"; then
  exit 0
fi

url=$(printf '%s' "$payload" | jq -r '.tool_input.url // empty')
if [ -z "$url" ]; then
  exit 0
fi

# Sanity-check the fetcher exists and is executable
if [ ! -x "$CLOAK_FETCH" ]; then
  exit 0
fi

# Run the fallback. Both temp files cleaned up at end regardless of outcome.
tmp_html=$(mktemp -t cloak_html.XXXXXX) || exit 0
tmp_md=$(mktemp -t cloak_md.XXXXXX) || { rm -f "$tmp_html"; exit 0; }
trap 'rm -f "$tmp_html" "$tmp_md"' EXIT

if ! "$CLOAK_FETCH" "$url" > "$tmp_html" 2>/dev/null; then
  exit 0
fi

if [ ! -s "$tmp_html" ]; then
  exit 0
fi

# Convert to markdown. Use npx -y so defuddle doesn't need a global install.
if ! npx -y defuddle parse "$tmp_html" --md -o "$tmp_md" >/dev/null 2>&1; then
  exit 0
fi

if [ ! -s "$tmp_md" ]; then
  exit 0
fi

# Emit additionalContext so Claude sees the fallback content.
md_body=$(cat "$tmp_md")
context=$(printf 'WebFetch was blocked by Cloudflare/bot-protection for %s.\nFallback CloakBrowser fetch succeeded. Page content (clean markdown via defuddle) follows:\n\n---\n\n%s' "$url" "$md_body")

jq -n --arg ctx "$context" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
