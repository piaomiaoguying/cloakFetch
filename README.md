# cloakFetch

Claude Code `PostToolUse` hook that transparently falls back to [CloakBrowser](https://github.com/CloakHQ/CloakBrowser) when the built-in `WebFetch` tool is blocked by Cloudflare or similar bot protection.

## Why

Claude Code's `WebFetch` goes through a backend HTTP client and `curl` can't pass Cloudflare's JS challenge — so any request to a CF-protected site (`science.org`, many publishers, lots of news sites) comes back as:

```
The server returned HTTP 403 Forbidden.
```

CloakBrowser is a real Chromium with anti-bot patches at the C++ level that passes those challenges. This hook wires the two together: when `WebFetch` fails with a recognisable bot-block pattern, the hook retries through CloakBrowser headlessly, runs [defuddle](https://github.com/kepano/defuddle) to strip page chrome, and injects the clean markdown back into the agent's context as `additionalContext`. The agent never sees the failure.

## Architecture

```
┌───────────────────┐    fails (CF 403)
│  WebFetch (built- │ ─────────────────┐
│  in Claude tool)  │                  │
└───────────────────┘                  ▼
                          ┌──────────────────────────────┐
                          │ webfetch_cloak_fallback.sh   │
                          │ (PostToolUse hook)           │
                          │                              │
                          │ 1. read payload from stdin   │
                          │ 2. regex-match failure       │
                          │ 3. extract tool_input.url    │
                          │ 4. call cloak_fetch.py       │
                          │ 5. defuddle → markdown       │
                          │ 6. emit additionalContext    │
                          └──────────────────────────────┘
                                         │
                                         ▼
                          ┌──────────────────────────────┐
                          │ cloak_fetch.py               │
                          │ (CloakBrowser headless)      │
                          │                              │
                          │ launch → goto → wait for CF  │
                          │ to clear → wait for content  │
                          │ → dump rendered DOM to stdout│
                          └──────────────────────────────┘
```

Two independent files so failure-detection regex (bash) and browser logic (Python) evolve separately.

## Prerequisites

- [Claude Code](https://github.com/anthropics/claude-code)
- [CloakBrowser](https://github.com/CloakHQ/CloakBrowser) installed somewhere with a working Python venv (e.g. `/Users/niehu/github/CloakBrowser/.venv`)
- `jq` (for parsing the hook payload)
- `npx` (for invoking `defuddle` on demand — no global install needed)

## Install

```bash
# 1. Copy the hook scripts into Claude Code's hook directory
mkdir -p ~/.claude/hooks
cp hooks/cloak_fetch.py hooks/webfetch_cloak_fallback.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/cloak_fetch.py ~/.claude/hooks/webfetch_cloak_fallback.sh

# 2. Point cloak_fetch.py's shebang at your CloakBrowser venv (edit line 1)
#    Default: #!/Users/niehu/github/CloakBrowser/.venv/bin/python

# 3. Register the hook in ~/.claude/settings.json — add the contents of
#    settings.snippet.json as a new entry inside the "PostToolUse" array.
#    Example final shape:
```

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "WebFetch",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/niehu/.claude/hooks/webfetch_cloak_fallback.sh"
          }
        ]
      }
    ]
  }
}
```

The hook becomes active on the next tool call — no Claude Code restart required.

## Test

Simulate the harness by piping a fake failed-WebFetch payload to the hook:

```bash
echo '{
  "tool_name": "WebFetch",
  "tool_input": {"url": "https://www.science.org/content/page/information-authors-research-articles", "prompt": "x"},
  "tool_response": "The server returned HTTP 403 Forbidden."
}' | ~/.claude/hooks/webfetch_cloak_fallback.sh
```

Expected: `{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "WebFetch was blocked... <markdown>"}}` on stdout, exit code 0.

For a live test, ask Claude inside a Claude Code session to fetch any Cloudflare-protected URL. You should see the WebFetch 403 immediately followed by a `PostToolUse:WebFetch hook additional context: ...` block in the conversation.

## Configuration knobs

All inside `hooks/webfetch_cloak_fallback.sh`:

| Variable | Default | Purpose |
|---|---|---|
| `CLOAK_FETCH` | `/Users/niehu/.claude/hooks/cloak_fetch.py` | Path to the Python fetcher |
| `FAILURE_REGEX` | `403\|forbidden\|cloudflare\|just a moment\|resource was not loaded\|access denied\|blocked` | Case-insensitive regex against `tool_response`. Widen / narrow to taste. |

Inside `hooks/cloak_fetch.py`:

| Knob | Default | Purpose |
|---|---|---|
| Shebang line | `#!/Users/niehu/github/CloakBrowser/.venv/bin/python` | Which Python (and thus which venv) executes the script. Must have `cloakbrowser` importable. |
| `headless=True` (line 31) | `True` | Flip to `False` if you want to see the browser window for debugging |
| Selector wait list (line 44) | `main, article, .article__body, .core-container, .pb-page-body` | Selectors that signal SPA content has rendered. Extend if a target site needs something more specific. |
| `time.sleep(2)` after selector wait | 2s | Extra settle for late-loading JS. |

## Behaviour & safety

- **Fail-closed**: the hook always exits `0`, even when CloakBrowser or defuddle fails. The original WebFetch error is never replaced with a worse one.
- **Silent on the happy path**: if `WebFetch` succeeded, or the failure doesn't match the regex, or the tool isn't `WebFetch`, the hook exits `0` with no stdout — zero impact.
- **Cost**: a triggered fallback runs a real browser, takes ~20–40 s, and uses non-trivial memory. The regex match is cheap and runs on every WebFetch call.
- **Trust boundary**: the hook only acts on URLs that *Claude* already chose to send to `WebFetch`. It does not introduce a new way for the agent to reach the internet — same URL surface as before, just a more capable backend.

## Limitations

- Cloudflare's hardest challenges (interactive Turnstile, etc.) may still defeat headless mode — flip `headless=False` in `cloak_fetch.py` if you need full CF coverage.
- The hook reads `tool_response` as a string for regex matching. If a future Claude Code version changes the payload shape, the matcher needs updating (`jq` selector at the top of the bash script).
- `additionalContext` size is bounded by Claude Code's hook output handling — very large pages are persisted to disk and only previewed inline.

## License

MIT
