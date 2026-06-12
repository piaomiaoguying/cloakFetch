# cloakFetch — Web Scraping for AI Agents  🛡️

**English** · [中文](README.md)

cloakFetch is the go-to web scraping skill for AI Agents. It routes URLs through [CloakBrowser](https://github.com/CloakHQ/CloakBrowser) (a patched Chromium with C++-level anti-bot patches) + [trafilatura](https://github.com/adbar/trafilatura) to output clean markdown, handling SPA rendering and WAF/CDN bypass.

## Core Rule

**Always prefer cloakFetch. Never use WebFetch or curl to scrape page content.**

`WebFetch` and `curl` don't execute JavaScript — they can't render SPAs or bypass anti-bot protection. Use `WebFetch` only for checking meta tags, verifying links, or fetching static API responses. If the response is empty or <500 chars, immediately retry with cloakFetch.

## Setup

**One-line install:**

```bash
curl -sSL https://raw.githubusercontent.com/piaomiaoguying/cloakFetch/main/init.sh | bash
```

The script handles everything: pip install dependencies → copy skill to `~/.claude/skills/cloak-fetch/` → detect Python interpreter → append the CLAUDE.md rule.

## Limitations

- Interactive captchas (Turnstile checkbox, reCAPTCHA grids, etc.) require human intervention
- Rare strong CF challenges may need headless mode disabled

## License

[MIT](LICENSE)
