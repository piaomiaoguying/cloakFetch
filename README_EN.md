# cloakFetch — Web scraping for AI Agents  🛡️

**English** · [中文](README.md)

When `WebFetch` / `curl` hits a Cloudflare block (or any WAF), cloakFetch routes the URL through [CloakBrowser](https://github.com/CloakHQ/CloakBrowser) — a real Chromium with C++-level anti-bot patches — and returns clean markdown via [trafilatura](https://github.com/adbar/trafilatura). The agent never has to tell the user "this page is unfetchable."

Works with any SKILL.md-aware agent: Claude Code, Codex CLI, OpenCode, OpenClaw, SkillsMP.

## Why

```
WebFetch → science.org → 403 Forbidden
         → nytimes.com → empty body
         → datanexus.qq.com → SPA shell (no JS)
```

`WebFetch`, `curl`, `requests` — none of these run JavaScript. CloakBrowser does. It's a patched Chromium that passes fingerprint checks, JS challenges, and passive bot detection. cloakFetch is the thin wrapper that wires it into your agent.

## Install

Drop the skill folder into your agent's skills directory:

| Agent | Path |
|---|---|
| Claude Code (global) | `~/.claude/skills/cloak-fetch/` |
| Claude Code (project) | `.claude/skills/cloak-fetch/` |
| OpenClaw (global) | `~/.openclaw/skills/cloak-fetch/` |
| OpenClaw (project) | `skills/cloak-fetch/` |
| Codex CLI | `~/.codex/skills/cloak-fetch/` |
| SkillsMP | Search `cloak-fetch` on [skillsmp.com](https://skillsmp.com) |

## Prerequisites

```bash
pip install cloakbrowser trafilatura
```

That's it. The skill auto-discovers the Python interpreter (see [Configuration](#configuration) below).

## Usage

```bash
<skill-dir>/cloak_fetch.sh "https://example.com"
```

Stdout gets clean markdown. Stderr gets progress. Exit 0 on success, non-zero on failure.

**In your agent's CLAUDE.md** (optional but recommended):

> When fetching page content, always use the cloak-fetch skill. Never use WebFetch or curl — they don't execute JavaScript and will return empty shells or 403 on any protected page.

This avoids the wasted round-trip: WebFetch → 403 → then skill.

## Configuration

Three ways to tell the skill which Python has `cloakbrowser`, in priority order:

### 1. Environment variable

```bash
export CLOAKBROWSER_PYTHON=/path/to/your/venv/bin/python
```

Highest priority. Put it in `~/.zshrc` or `~/.bashrc`.

### 2. Config file (`cloak_fetch.conf`)

Edit the file next to `cloak_fetch.sh`. One path per line, `#` for comments. Tried top-to-bottom:

```ini
# my CloakBrowser venv
/home/alice/CloakBrowser/.venv/bin/python
/opt/CloakBrowser/.venv/bin/python
```

### 3. PATH auto-discovery

If neither is set, the skill runs `python3` from PATH. Works when `cloakbrowser` is `pip install`'d into the system Python.

## Tuning

Edit `cloak_fetch.py` directly:

| Knob | Default | What it does |
|---|---|---|
| `launch(headless=)` | `True` | Set to `False` to see the browser window (debug) |
| `page.goto(… timeout=)` | `90000` | Page load timeout in ms |
| `page.wait_for_selector(… timeout=)` | `15000` | Max wait for SPA content container |
| `time.sleep(2)` | 2 s | Extra settle for late-loading JS |
| Selector list | `main, article, .article__body, .core-container, .pb-page-body` | Add site-specific selectors for faster detection |

## Architecture

```
cloak_fetch.sh <url>                 ← one command
   │
   ├─ 1. Find Python (env var → conf → PATH)
   ├─ 2. arch -arm64 (macOS only, prevents x86_64 Rosetta mismatch)
   └─ 3. exec cloak_fetch.py <url>
         │
         ├─ launch(headless=True)    ← CloakBrowser via Playwright-compatible API
         ├─ page.goto(url)
         ├─ Poll for real title      ← "Just a moment…" → wait for CF to clear
         ├─ wait_for_selector()      ← SPA content rendered?
         ├─ time.sleep(2)            ← late JS settle
         ├─ page.evaluate(outerHTML) ← grab full DOM
         └─ trafilatura.extract()    ← HTML → clean markdown
```

## Behaviour

- **Headless** — no browser window.
- **Latency** — ~20–40 s (browser launch + render + settle).
- **Output** — trafilatura markdown: headings, lists, links, code blocks preserved. Ads, nav, cookie banners stripped.
- **Backup** — if trafilatura finds no main content, raw HTML is emitted so the agent still has something.
- **Fail-closed** — exits non-zero with a clear stderr message if anything fails. Never silently returns nothing.

## Limitations

- **Interactive captchas** (Turnstile checkbox, reCAPTCHA image grid, hCaptcha slider) need a human or paid solver. CloakBrowser passes passive fingerprint checks, not interactive challenges.
- **Headless mode** defeats most protections, but the hardest CF challenges may need `headless=False`.
- **Reactive** — the agent must remember to use this skill. A CLAUDE.md rule (see [Usage](#usage)) makes it proactive.
- **Cross-platform** — macOS (ARM/Intel), Linux supported. The `arch -arm64` wrapper only activates on macOS ARM; Linux skips it cleanly.

## Repo layout

```
cloakFetch/
├── skills/cloak-fetch/
│   ├── SKILL.md              ← Agent reads this — trigger heuristics, vendor signatures
│   ├── cloak_fetch.sh        ← Entry point: find Python, cross-platform exec
│   ├── cloak_fetch.py        ← Browser launch + trafilatura extraction
│   └── cloak_fetch.conf      ← User-custom Python paths (optional)
├── LICENSE
├── .gitignore
├── README.md
└── README_EN.md
```

## 📄 License

[MIT](LICENSE)
