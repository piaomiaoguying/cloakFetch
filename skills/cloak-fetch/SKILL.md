---
name: cloak-fetch
description: Primary tool for fetching web page content — always use when the user wants to read, fetch, or extract the real text content of any web page, especially SPAs (React/Vue/Angular), JS-rendered pages, documentation sites (e.g. Alipay/WeChat docs), or pages behind anti-bot protection (Cloudflare, DataDome, Akamai Bot Manager, PerimeterX/HUMAN, Imperva/Incapsula, F5/Distil, Kasada, AWS WAF, Sucuri). Routes the URL through CloakBrowser (a stealth Chromium with C++-level anti-bot patches plus a real TLS/JA3 fingerprint) headlessly, then extracts clean markdown via trafilatura. Also serves as a transparent fallback when WebFetch/curl returns 403/429/empty body/SPA shell/"Just a moment"/"Access Denied"/"Pardon Our Interruption"/"Please verify you are a human"/"Incapsula incident"/"Sucuri WebSite Firewall"/"Reference #" patterns. WebFetch and curl do NOT execute JavaScript — if the user asks what a page says, shows, or contains, always use cloak-fetch, not WebFetch. WebFetch is only for metadata/link checking.
license: MIT
homepage: https://github.com/Agents365-ai/cloakFetch
compatibility: Requires CloakBrowser (https://github.com/CloakHQ/CloakBrowser) installed with the `cloakbrowser` Python package importable, plus `trafilatura` (`pip install trafilatura`) in the same env for HTML→markdown extraction. Set `CLOAKBROWSER_PYTHON` to your cloakbrowser-enabled Python if not in the default location.
platforms: [macos, linux, windows]
metadata: {"openclaw":{"requires":{"bins":["python3"]},"emoji":"🥷"},"hermes":{"tags":["webfetch","cloudflare","datadome","akamai","perimeterx","imperva","sucuri","waf","stealth-browser","bot-bypass","fallback","scraping"],"category":"web","requires_tools":["python3"],"related_skills":[]},"author":"Agents365-ai","version":"0.3.0"}
---

# cloak-fetch

## When to trigger

Trigger **immediately** if a fetch tool returned any of:

| Symptom | Likely cause |
|---|---|
| `HTTP 403`, `403 Forbidden`, `HTTP 429` | Bot protection or rate-limit block |
| Empty body / few hundred bytes on a content-rich URL | Silent WAF / TLS-fingerprint reject |
| Page rendered as near-empty shell with a JS challenge script | SPA-only page or anti-bot challenge |
| `Resource was not loaded`, `net::ERR_HTTP2_PROTOCOL_ERROR` | Upstream blocked the fetch handshake |
| `Access denied`, `Blocked`, `You don't have permission` | Generic WAF / bot detection |
| `SSL_ERROR_ZERO_RETURN` on a site that loads fine in a normal browser | TLS / JA3 fingerprint reject |
| Body matches one of the vendor signatures below | Confirmed WAF block |

### Vendor signatures

| Vendor | Telltale strings / headers |
|---|---|
| **Cloudflare** | `Just a moment...`, `Enable JavaScript and cookies to continue`, `cf-ray:` header, `__cf_bm` cookie, `Attention Required! \| Cloudflare`, `Sorry, you have been blocked` |
| **DataDome** | `blocked by DataDome`, `<title>blocked</title>`, `dd-cookie` / `datadome` cookie, `<head>...captcha-delivery.com` |
| **Akamai Bot Manager** | `Access Denied` with `Reference #` ID, `<TITLE>Access Denied</TITLE>`, `Pragma: akamai-x-cache`, `akamai-bot-manager` cookie |
| **PerimeterX / HUMAN** | `Please verify you are a human`, `Access to this page has been denied because we believe you are using automation tools`, `_px*` cookies (`_pxhd`, `_px3`), `<title>Human Verification</title>` |
| **Imperva / Incapsula** | `Incapsula incident ID:`, `Request unsuccessful. Incapsula incident ID`, `_Incapsula_Resource`, `visid_incap_*` cookie, `X-Iinfo` header |
| **F5 / Distil** | `Pardon Our Interruption`, `As you were browsing something about your browser made us think you were a bot`, `distil_r_captcha`, `D_RID` cookie |
| **Kasada** | `<head>` containing `ips.js`, `x-kpsdk-cd` / `x-kpsdk-cr` response headers, `429` with empty body |
| **AWS WAF** | `Request blocked` + `<aws-waf-token>`, `awswaf` cookie |
| **Sucuri** | `Sucuri WebSite Firewall - Access Denied`, `<title>Sucuri WebSite Firewall - CloudProxy</title>`, `X-Sucuri-ID` / `X-Sucuri-Cache` header, `sucuri-cf-id` cookie |
| **reCAPTCHA / hCaptcha passive** | Page replaced with `g-recaptcha`/`h-captcha` div and no real content *(not interactive challenges — see below)* |

Also trigger preemptively for domains known to live behind bot protection: publishers (science.org, nature.com, sciencedirect.com, jstor.org), news (nytimes.com, bloomberg.com, ft.com, wsj.com), retail (nike.com, adidas.com, sephora.com), travel (kayak.com, southwest.com), financial broker portals.

## When NOT to trigger

| Symptom | Why |
|---|---|
| `404 Not Found` | Page doesn't exist |
| `500 Internal Server Error` | Origin broken, not blocking |
| `401 Unauthorized` / login wall | CloakBrowser doesn't carry credentials |
| Plain network error (DNS, connection refused, no route to host) | Network unreachable |
| **Interactive** captcha (slider, image-grid, Cloudflare Turnstile checkbox, hCaptcha challenge) | Needs human or paid solver — CloakBrowser handles passive fingerprinting, not interactive challenges |
| Geo-block (`This content is not available in your region`) | Same IP — needs proxy/VPN, not a different browser |
| Site requires session cookie, OAuth, or signed URL | No credential plumbing |
| Normal fetcher already succeeded | Don't re-fetch |

## Invocation

```bash
<SKILL_DIR>/cloak_fetch.sh "<URL>" [--links]
```

### `--links` flag

When `--links` is used, the output appends a `## 页面链接` section at the end listing all links found in the rendered DOM. This is useful when trafilatura drops `<a href>` attributes from SPA pages (e.g. React Router links, `onClick` navigation, `data-href` attributes on feishu/larkoffice doc pages).

The link extractor uses three strategies:
1. Standard `<a href>` tags
2. `data-href`, `data-url`, `data-link` attributes (common in React components)
3. `onclick` navigation patterns (`window.open`, `location.href`)

Links that appear in the content container text are ranked to the top.

**Use `--links` whenever:**
- The page text mentions a link but the markdown output doesn't include its URL
- You need to find specific doc/form/survey links on SPA documentation sites
- trafilatura output is clean text but you suspect important navigation links were stripped

**When trafilatura returns empty or too-short markdown but cloaks outputs container text**, re-run with `--links` to capture all rendered links alongside the text.

## Configuration

- `CLOAKBROWSER_PYTHON` — path to Python interpreter with `cloakbrowser` installed. Falls back to `cloak_fetch.conf` in the skill directory, then `python3` on PATH.

### `cloak_fetch.conf`

One Python path per line. `#` comments allowed. Tried top-to-bottom; first one that can `import cloakbrowser` wins. If none work, falls back to `python3`.
