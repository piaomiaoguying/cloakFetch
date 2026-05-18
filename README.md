# cloakFetch

Two paths for the same idea: when a web fetch is blocked by [Cloudflare](https://www.cloudflare.com/) (or similar bot protection), route the URL through [CloakBrowser](https://github.com/CloakHQ/CloakBrowser) — a stealth Chromium that passes the JS challenge — and return clean markdown via [defuddle](https://github.com/kepano/defuddle).

- **[Path A: PostToolUse hook](#path-a--claude-code-posttooluse-hook)** — fully automatic on Claude Code. Every blocked `WebFetch` silently falls back; the agent never sees the failure.
- **[Path B: SKILL.md skill](#path-b--skillmd-skill-for-hookless-agents)** — reactive fallback for any SKILL.md-aware agent (Codex, OpenCode, OpenClaw, SkillsMP). Agent decides to invoke it after seeing a 403/CF pattern.

## Why

Claude Code's built-in `WebFetch` (and `curl`, and `requests`, and most HTTP clients) can't pass Cloudflare's JS challenge — so any request to a CF-protected site (`science.org`, many publishers, lots of news sites) comes back as:

```
The server returned HTTP 403 Forbidden.
```

CloakBrowser is a real Chromium with anti-bot patches at the C++ level that *does* pass those challenges. cloakFetch wires CloakBrowser + defuddle into Claude Code (and other agents) so the agent never has to tell the user "this page is unfetchable."

## Two activation paths

|  | Path A: Hook | Path B: Skill |
|---|---|---|
| **Trigger** | Automatic — fires on every WebFetch result | Reactive — agent decides after seeing a failed fetch |
| **Agent cognition** | Zero — invisible upgrade | Has to notice 403/CF pattern + recall skill |
| **Runtime support** | Claude Code only (needs `PostToolUse` hook system) | Any SKILL.md-aware agent: Claude Code, OpenClaw, Codex, OpenCode, SkillsMP |
| **Latency on hit** | ~25–40 s | ~25–40 s |
| **Latency on miss** | ~milliseconds (regex check, no browser) | None (skill not invoked) |
| **Install** | Copy 2 scripts + edit `~/.claude/settings.json` | Drop skill folder into the agent's skills dir |
| **Files** | `hooks/cloak_fetch.py` + `hooks/webfetch_cloak_fallback.sh` | `skills/cloak-fetch/SKILL.md` + `cloak_fetch.py` + `cloak_fetch.sh` |

Same `cloak_fetch.py` underneath both — the difference is just *how* it gets activated.

## Repo layout

```
cloakFetch/
├── hooks/                          # Path A — Claude Code PostToolUse
│   ├── cloak_fetch.py              #   headless CloakBrowser → rendered HTML
│   └── webfetch_cloak_fallback.sh  #   payload matcher + orchestrator
├── skills/cloak-fetch/             # Path B — SKILL.md skill
│   ├── SKILL.md                    #   pushy description + trigger heuristics
│   ├── cloak_fetch.py              #   (same script, env-python shebang)
│   └── cloak_fetch.sh              #   wrapper: locate python, fetch, defuddle
├── settings.snippet.json           #   PostToolUse JSON block to paste into ~/.claude/settings.json
└── README.md
```

---

## Path A — Claude Code PostToolUse hook

### Architecture

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

### Install (hook)

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

### Test (hook)

Simulate the harness by piping a fake failed-WebFetch payload to the hook:

```bash
echo '{
  "tool_name": "WebFetch",
  "tool_input": {"url": "https://www.science.org/content/page/information-authors-research-articles", "prompt": "x"},
  "tool_response": "The server returned HTTP 403 Forbidden."
}' | ~/.claude/hooks/webfetch_cloak_fallback.sh
```

Expected: `{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "WebFetch was blocked... <markdown>"}}` on stdout, exit code 0.

For a live test, ask Claude inside a Claude Code session to fetch any Cloudflare-protected URL. You should see the `WebFetch` 403 immediately followed by a `PostToolUse:WebFetch hook additional context: ...` block in the conversation.

### Configuration knobs (hook)

Inside `hooks/webfetch_cloak_fallback.sh`:

| Variable | Default | Purpose |
|---|---|---|
| `CLOAK_FETCH` | `/Users/niehu/.claude/hooks/cloak_fetch.py` | Path to the Python fetcher |
| `FAILURE_REGEX` | `403\|forbidden\|cloudflare\|just a moment\|resource was not loaded\|access denied\|blocked` | Case-insensitive regex against `tool_response`. Widen / narrow to taste. |

---

## Path B — SKILL.md skill (for hookless agents)

The hook approach only works on Claude Code. For agents that don't have a `PostToolUse` system — Codex CLI, OpenCode, OpenClaw, SkillsMP — install cloakFetch as a SKILL.md-format skill. The agent reads the SKILL.md when relevant and invokes the wrapper script after recognising a Cloudflare failure pattern.

### Install (skill)

| Agent | Install path |
|---|---|
| **Claude Code** (global) | `cp -r skills/cloak-fetch ~/.claude/skills/cloak-fetch` |
| **Claude Code** (project) | `cp -r skills/cloak-fetch .claude/skills/cloak-fetch` |
| **OpenClaw** (global) | `cp -r skills/cloak-fetch ~/.openclaw/skills/cloak-fetch` |
| **OpenClaw** (project) | `cp -r skills/cloak-fetch skills/cloak-fetch` |
| **SkillsMP** | search for `cloak-fetch` on [skillsmp.com](https://skillsmp.com) |

If your CloakBrowser venv isn't at the default path, set the env var (in your shell rc or per-invocation):

```bash
export CLOAKBROWSER_PYTHON=/path/to/your/cloakbrowser/.venv/bin/python
```

### Invoke (skill)

The agent runs this single command after a normal fetcher returns a 403/CF pattern:

```bash
~/.claude/skills/cloak-fetch/cloak_fetch.sh "<URL>"
```

The wrapper handles everything: finds a `cloakbrowser`-importable Python, launches the headless browser, runs defuddle, prints clean markdown on stdout. Stderr carries progress messages; exit non-zero on any failure.

### Test (skill)

```bash
~/.claude/skills/cloak-fetch/cloak_fetch.sh "https://www.science.org/content/page/information-authors-research-articles"
```

Expected: ~20–40 s, then ~25 KB of clean markdown on stdout (page title is "Information for Authors-Research Articles").

For a sanity check on a non-Cloudflare site:

```bash
~/.claude/skills/cloak-fetch/cloak_fetch.sh "https://example.com"
# → "This domain is for use in documentation examples..."
```

### Configuration knobs (skill)

| Env var | Default | Purpose |
|---|---|---|
| `CLOAKBROWSER_PYTHON` | (auto-detect: `~/github/CloakBrowser/.venv/bin/python`, then `python3`) | Python interpreter with `cloakbrowser` importable |

Inside `skills/cloak-fetch/cloak_fetch.py`:

| Knob | Default | Purpose |
|---|---|---|
| `headless=True` | `True` | Flip to `False` to see the browser window for debugging |
| Selector wait list | `main, article, .article__body, .core-container, .pb-page-body` | Selectors that signal SPA content has rendered. Extend if a target site needs something more specific. |
| `time.sleep(2)` settle | 2 s | Extra wait for late-loading JS. |

---

## Prerequisites (both paths)

- [CloakBrowser](https://github.com/CloakHQ/CloakBrowser) installed with the `cloakbrowser` Python package importable (a venv with `pip install cloakbrowser` works)
- `npx` (for invoking `defuddle` on demand — no global install needed)
- Path A only: `jq` (for parsing the hook payload)

## Behaviour & safety

- **Fail-closed.** Both paths leave the original failure intact if something inside cloakFetch breaks (no Python with cloakbrowser, network down, CloakBrowser can't pass the challenge). The agent is never tricked into thinking a fetch succeeded when it didn't.
- **Silent on the happy path.** The hook does nothing when the regex doesn't match; the skill is simply not invoked when there's no failure to recover from.
- **Cost.** A triggered fallback runs a real browser — ~20–40 s wall clock, non-trivial memory. The hook's regex check on the happy path costs ~milliseconds.
- **Trust boundary.** Both paths act only on URLs the agent already chose to send to its fetch tool. They do not introduce a new way for the agent to reach the internet — same URL surface, just a more capable backend.

## Limitations

- Cloudflare's hardest challenges (interactive Turnstile, etc.) may still defeat headless mode — flip `headless=False` in `cloak_fetch.py` if you need full CF coverage.
- The hook reads `tool_response` as a string for regex matching. If a future Claude Code version changes the payload shape, the matcher's `jq` selector needs updating.
- `additionalContext` size is bounded by Claude Code's hook output handling — very large pages are persisted to disk and only previewed inline (the persisted file path is shown so the agent can `Read` it).
- The skill is **reactive**: it works only when the agent recognises the failure and recalls the skill. If the agent gives up after the first 403 without trying again, the skill doesn't help. The SKILL.md description is intentionally pushy to combat this — review and tweak if your agent under-triggers.

## License

MIT
