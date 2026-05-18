#!/Users/niehu/github/CloakBrowser/.venv/bin/python
"""Fetch a Cloudflare-gated URL via CloakBrowser and print rendered HTML to stdout.

Usage: cloak_fetch.py <url>

Stdout: fully-rendered HTML of the page.
Stderr: progress messages (safe to /dev/null).
Exit 0 on success, 1 on failure.
"""

import sys
import time

if len(sys.argv) != 2:
    print("usage: cloak_fetch.py <url>", file=sys.stderr)
    sys.exit(1)

url = sys.argv[1]

try:
    from cloakbrowser import launch
except ImportError as e:
    print(f"cloakbrowser import failed: {e}", file=sys.stderr)
    sys.exit(1)

try:
    print(f"[cloak] launching headless browser", file=sys.stderr)
    browser = launch(headless=True)
    page = browser.new_page()

    print(f"[cloak] navigating to {url}", file=sys.stderr)
    page.goto(url, wait_until="networkidle", timeout=90000)

    # Cloudflare interstitial flips the title to "Just a moment..." — poll for
    # the real title up to 30s.
    deadline = time.time() + 30
    while time.time() < deadline:
        title = page.title() or ""
        if title and "Just a moment" not in title:
            break
        time.sleep(1)

    # Wait for some plausible content container — SPA pages render late.
    try:
        page.wait_for_selector(
            "main, article, .article__body, .core-container, .pb-page-body",
            timeout=15000,
        )
    except Exception as e:
        print(f"[cloak] content selector wait skipped: {e}", file=sys.stderr)

    time.sleep(2)  # extra settle for late-loading JS chunks

    print(f"[cloak] title: {page.title()}", file=sys.stderr)
    html = page.evaluate("() => document.documentElement.outerHTML")
    sys.stdout.write(html)
    browser.close()
    print(f"[cloak] done, {len(html)} bytes", file=sys.stderr)
except Exception as e:
    print(f"[cloak] failed: {e}", file=sys.stderr)
    sys.exit(1)
