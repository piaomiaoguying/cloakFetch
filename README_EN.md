# cloakFetch — Web Scraping for AI Agents  🛡️

**English** · [中文](README.md)

cloakFetch is the go-to web scraping skill for AI Agents. It routes URLs through [CloakBrowser](https://github.com/CloakHQ/CloakBrowser) (a patched Chromium with C++-level anti-bot patches) + [trafilatura](https://github.com/adbar/trafilatura) to output clean markdown, handling SPA rendering and WAF/CDN bypass.

## Core Rule

**Always prefer cloakFetch. Never use WebFetch or curl to scrape page content.**

`WebFetch` and `curl` don't execute JavaScript — they can't render SPAs or bypass anti-bot protection. Use `WebFetch` only for checking meta tags, verifying links, or fetching static API responses. If the response is empty or <500 chars, immediately retry with cloakFetch.

## Setup

### 1. Install dependencies

```bash
pip install cloakbrowser trafilatura
```

### 2. Place in skills directory

```
~/.claude/skills/cloak-fetch/    # global
.claude/skills/cloak-fetch/      # per-project
```

### 3. Configure CLAUDE.md

Add this rule to `~/.claude/CLAUDE.md` so your Agent auto-prefers cloakFetch:

> ## Web Content Fetching Rule
> When the user asks to view, read, or fetch the actual content of a web page, always prefer the cloak-fetch skill. **Never use WebFetch or curl to scrape content directly.** Reason: WebFetch and curl don't execute JavaScript — they can't render SPAs (like Alipay/WeChat docs) and can't bypass WAF/CDN protection.
> WebFetch is only acceptable for: checking meta tags, verifying links are alive, fetching pure static API responses.
> If a WebFetch response is empty or very short (<500 chars), immediately retry with the cloak-fetch skill.

## Python Interpreter

The skill needs a Python that can `import cloakbrowser`. Three options (by priority):

**Environment variable** (recommended):
```bash
export CLOAKBROWSER_PYTHON=/path/to/your/venv/bin/python
```

**Config file** (`cloak_fetch.conf`), one path per line:
```ini
/home/alice/CloakBrowser/.venv/bin/python
```

**Auto-discovery**: falls back to `python3` from PATH.

## Limitations

- Interactive captchas (Turnstile checkbox, reCAPTCHA grids, etc.) require human intervention
- Rare strong CF challenges may need headless mode disabled

## 📄 License

[MIT](LICENSE)
