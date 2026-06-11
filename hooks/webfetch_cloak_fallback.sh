#!/usr/bin/env bash
# PostToolUse hook: when WebFetch fails with a WAF / bot-protection pattern
# (Cloudflare, DataDome, Akamai, PerimeterX/HUMAN, Imperva, F5/Distil, Kasada,
# AWS WAF, Sucuri, etc.), transparently retry with CloakBrowser + trafilatura
# and inject the markdown back as additionalContext.
#
# Reads hook payload as JSON on stdin:
#   { "tool_name": "WebFetch",
#     "tool_input":  { "url": "...", "prompt": "..." },
#     "tool_response": "..." }
#
# Exits 0 silently on any non-trigger or any failure inside the fallback path
# (we never want to break the original WebFetch error chain).

set -uo pipefail

# Path to the Python fetcher. Override if you keep it elsewhere.
CLOAK_FETCH="${CLOAK_FETCH:-$HOME/.claude/hooks/cloak_fetch.py}"

# Python interpreter with `cloakbrowser` importable. Override by setting
# CLOAKBROWSER_PYTHON (e.g. to your CloakBrowser venv) in your shell rc.
# The default looks for the common install location; final fallback is `python3`.
CLOAK_PY="${CLOAKBROWSER_PYTHON:-$HOME/github/CloakBrowser/.venv/bin/python}"
if [ ! -x "$CLOAK_PY" ]; then
  CLOAK_PY="$(command -v python3 2>/dev/null)"
fi

# Matched case-insensitively against tool_response. Covers the major bot /
# WAF vendors — adding niche brand names (datadome, akamai, sucuri etc.) is
# safe because they rarely appear in legitimate page content, but is a real
# trigger when the upstream block page mentions them. Status codes 403/429
# catch the common rate-limit / forbidden envelope.
FAILURE_REGEX="403|429|forbidden|cloudflare|just a moment|enable javascript and cookies|resource was not loaded|access denied|blocked|datadome|akamai|please verify you are a human|incapsula|pardon our interruption|kasada|aws-waf|sucuri"

# SPA shell threshold — WebFetch often returns HTTP 200 but with near-empty
# content (e.g. "Based on the provided web page content, here is what I can
# extract..." + page title only). These are JS-rendered pages that curl/WebFetch
# can't execute. If the tool_response is under this byte count, we fire the
# fallback anyway.
SPA_SHELL_MAX_BYTES=500

# Regex patterns that indicate WebFetch's model judged the page was empty/truncated.
# These match the language WebFetch uses to report missing content.
EMPTY_BODY_REGEX="only the page title|source material provided contains only|truncated to just the heading|no additional body text|no body text|no article content|content available.*none"

# Read full payload
payload=$(cat)

tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty')
if [ "$tool_name" != "WebFetch" ]; then
  exit 0
fi

# tool_response can be a string or an object depending on harness version —
# coerce to string for the regex check.
response=$(printf '%s' "$payload" | jq -r '.tool_response | if type=="string" then . else tojson end // empty')

# Decide whether to trigger the fallback — three independent paths:
# 1. Explicit WAF/bot-block string match (the original trigger)
# 2. WebFetch model reports "only the page title" or equivalent empty-body phrasing
# 3. Tool response is abnormally short — SPA shell, no real content rendered
trigger=0
if printf '%s' "$response" | grep -qiE "$FAILURE_REGEX"; then
  trigger=1
elif printf '%s' "$response" | grep -qiE "$EMPTY_BODY_REGEX"; then
  trigger=1
elif [ "${#response}" -lt "$SPA_SHELL_MAX_BYTES" ]; then
  trigger=1
fi

if [ "$trigger" -eq 0 ]; then
  exit 0
fi

url=$(printf '%s' "$payload" | jq -r '.tool_input.url // empty')
if [ -z "$url" ]; then
  exit 0
fi

# Sanity-check we have both the fetcher and a usable Python interpreter
if [ ! -f "$CLOAK_FETCH" ] || [ -z "$CLOAK_PY" ] || [ ! -x "$CLOAK_PY" ]; then
  exit 0
fi

# Run the fallback. Temp file cleaned up at end regardless of outcome.
tmp_md=$(mktemp -t cloak_md.XXXXXX) || exit 0
trap 'rm -f "$tmp_md"' EXIT

# cloak_fetch.py writes clean markdown (trafilatura) directly to stdout.
# Use `arch -arm64` to force native Apple Silicon — the bash harness may
# run under Rosetta (x86_64) translation, which would cause the universal
# binary Python to pick the wrong arch and fail to load arm64 extensions.
if ! arch -arm64 "$CLOAK_PY" "$CLOAK_FETCH" "$url" > "$tmp_md" 2>/dev/null; then
  exit 0
fi

if [ ! -s "$tmp_md" ]; then
  exit 0
fi

# Emit additionalContext so Claude sees the fallback content.
md_body=$(cat "$tmp_md")
context=$(printf 'WebFetch was blocked by bot-protection / WAF for %s.\nFallback CloakBrowser fetch succeeded. Page content (clean markdown via trafilatura) follows:\n\n---\n\n%s' "$url" "$md_body")

jq -n --arg ctx "$context" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
