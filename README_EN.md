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

The script will ask where to install the browser (~300MB Chromium):

| Option | Description |
|---|---|
| **System default** | `pip3 install` into current Python, zero-config |
| **Isolated venv** | Create a standalone venv, clean separation. Custom path or default `~/clkbrowser-venv` |

Everything else is automatic: clone skill files → pip install deps → copy to `~/.claude/skills/cloak-fetch/` → configure Python → append CLAUDE.md rule.

> **Network**: `git clone` and `pip3 install` may be slow from some regions — set a proxy first if needed.

## Usage

```bash
# Basic: extract page content
cloak_fetch.sh "https://example.com"

# Extract all rendered links (for SPA pages where href is dropped)
cloak_fetch.sh "https://example.com" --links
```

### `--links` flag

On SPA pages (React/Vue), trafilatura may drop `<a>` href attributes during extraction. With `--links`, the output includes a "Page Links" section listing all links from the rendered DOM. Three extraction strategies:

1. Standard `<a href>` tags
2. `data-href`, `data-url`, `data-link` attributes
3. `onclick` with `window.open` / `location.href` navigation

Links found in the content text are ranked to the top.

**Use cases**: Feishu form links, SPA doc site navigation, extracting target URLs from docs, etc.

## Limitations

- Interactive captchas (Turnstile checkbox, reCAPTCHA grids, etc.) require human intervention
- Rare strong CF challenges may need headless mode disabled

## License

[MIT](LICENSE)
