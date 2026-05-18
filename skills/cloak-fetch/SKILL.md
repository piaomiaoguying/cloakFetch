---
name: cloak-fetch
description: Use as a fallback when a web page won't load via WebFetch, curl, or any HTTP client because it's Cloudflare-protected or returns 403/Forbidden/"Just a moment". Routes the URL through CloakBrowser (a stealth Chromium that passes bot challenges) headlessly, then extracts clean markdown via defuddle. PROACTIVELY USE whenever a recent fetch attempt returned HTTP 403, "Cloudflare", "access denied", "Just a moment", "Enable JavaScript", "Resource was not loaded", or any pattern suggesting bot detection — do not tell the user a page is unfetchable until you've tried this skill.
license: MIT
homepage: https://github.com/Agents365-ai/cloakFetch
compatibility: Requires CloakBrowser (https://github.com/CloakHQ/CloakBrowser) installed with the `cloakbrowser` Python package importable. Also needs `npx` for defuddle. Set `CLOAKBROWSER_PYTHON` to your cloakbrowser-enabled Python if not in the default location.
platforms: [macos, linux, windows]
metadata: {"openclaw":{"requires":{"bins":["python3","npx"]},"emoji":"🥷"},"hermes":{"tags":["webfetch","cloudflare","stealth-browser","bot-bypass","fallback","scraping"],"category":"web","requires_tools":["python3","npx"],"related_skills":[]},"author":"Agents365-ai","version":"0.1.0"}
---

# cloak-fetch — Cloudflare-aware fetch fallback

When a normal HTTP fetcher fails because the target site uses bot protection,
route the same URL through CloakBrowser (a real Chromium with anti-bot patches
at the C++ level) and return clean markdown via defuddle. The agent never has
to tell the user "the page is unfetchable" — it can try this skill first.

## When to trigger

Use **immediately** after any of these symptoms from a recent fetch tool call:

| Symptom in tool output | Likely cause |
|---|---|
| `HTTP 403`, `403 Forbidden` | Bot protection or rate-limit block |
| `Cloudflare`, `Just a moment`, `Enable JavaScript and cookies` | Cloudflare interstitial |
| `Resource was not loaded` | CF blocked the underlying fetch |
| `Access denied`, `Blocked` | WAF / generic bot detection |
| Page rendered as a near-empty shell with a JS challenge script | SPA-only page or anti-bot challenge |

Also trigger when the user explicitly asks to fetch a page that's known to be
behind Cloudflare (publishers like science.org, nature.com, sciencedirect.com,
many news sites, financial dashboards, etc.) — going straight to this skill
avoids a guaranteed-to-fail `WebFetch` round trip.

## When NOT to trigger

| Symptom | Why this skill won't help |
|---|---|
| `404 Not Found` | Page genuinely doesn't exist |
| `500 Internal Server Error` | Origin is broken, not blocking you |
| `401 Unauthorized` | Login required — CloakBrowser doesn't carry credentials |
| Plain network error (DNS, connection refused) | Network unreachable, not a bot block |
| The normal fetcher already succeeded | No need to re-fetch |

In these cases, report the actual failure to the user instead of masking it.

## How to invoke

One command — the wrapper picks the right Python, runs the headless browser,
pipes through defuddle, and writes clean markdown to stdout:

```bash
<SKILL_DIR>/cloak_fetch.sh "<URL>"
```

Where `<SKILL_DIR>` is wherever this skill is installed. Common locations:

- Claude Code: `~/.claude/skills/cloak-fetch`
- OpenClaw: `~/.openclaw/skills/cloak-fetch`
- Codex: `~/.codex/skills/cloak-fetch`
- Project-local: `.claude/skills/cloak-fetch` or `skills/cloak-fetch`

A portable invocation that finds the skill across these locations:

```bash
for d in \
  "$HOME/.claude/skills/cloak-fetch" \
  "$HOME/.openclaw/skills/cloak-fetch" \
  "$HOME/.codex/skills/cloak-fetch" \
  ".claude/skills/cloak-fetch" \
  "skills/cloak-fetch"; do
  if [ -x "$d/cloak_fetch.sh" ]; then
    SKILL_DIR="$d"; break
  fi
done

"$SKILL_DIR/cloak_fetch.sh" "https://www.science.org/content/page/information-authors-research-articles"
```

The wrapper streams clean markdown on stdout. Save to a file with `> out.md` or
pipe directly into further processing.

## Behavior

- **Headless by default** — no browser window opens.
- **Latency:** ~20–40 s per call (browser launch + page render + content settle).
- **Output:** clean markdown via defuddle. Page chrome, navigation, ads, and
  cookie banners stripped. Headings, lists, links, and code blocks preserved.
- **Failure modes:** exits non-zero with a message on stderr if no
  cloakbrowser-enabled Python is found, the browser couldn't reach the URL, or
  CloakBrowser couldn't pass the challenge. Surface the failure honestly to
  the user — do not fabricate page content.

## Configuration

| Env var | Purpose | Default |
|---|---|---|
| `CLOAKBROWSER_PYTHON` | Path to the Python interpreter with `cloakbrowser` installed | `~/github/CloakBrowser/.venv/bin/python`, falling back to `python3` |

For more advanced tuning (headless toggle, content-selector wait list, settle
timing), edit `cloak_fetch.py` directly — see comments in that file.

## Example end-to-end

User: "Get the authors info from https://www.science.org/content/page/information-authors-research-articles"

1. Agent tries `WebFetch` — gets `HTTP 403 Forbidden`.
2. Agent recognises the 403 → invokes this skill:
   ```bash
   ~/.claude/skills/cloak-fetch/cloak_fetch.sh \
     "https://www.science.org/content/page/information-authors-research-articles"
   ```
3. ~25 s later, ~26 KB of clean markdown lands on stdout.
4. Agent answers the user from the markdown — no need to mention the
   underlying fetch took two attempts.

## Related

- [cloakFetch hook](../../hooks/) — same fallback wired up as a Claude Code
  `PostToolUse` hook (fully automatic, no agent decision required). Use the
  hook on Claude Code; use this skill on agents that lack a hook system
  (Codex, OpenCode, OpenClaw, etc.).
