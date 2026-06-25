#!/usr/bin/env python3
"""Fetch a URL via CloakBrowser and print clean markdown to stdout.

Usage: cloak_fetch.py <url>

Stdout: clean markdown extracted from the rendered page via trafilatura.
Stderr: progress messages (safe to /dev/null).
Exit 0 on success, 1 on failure.

SPA-aware extraction strategy:
  1. goto + extra settle time for SPA routers
  2. Scroll to trigger lazy rendering
  3. Unhide collapsed sections (accordions, "show more")
  4. If the page looks like a shell with a doc tree, click nav→tree to
     reveal the content panel
  5. Prefer well-known content containers; fall back to body.outerHTML
  6. trafilatura pass with container-text / innerText as fallback
"""

import re
import sys
import time
from urllib.parse import parse_qs, urlparse

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
    import trafilatura
except ImportError as e:
    print(f"trafilatura import failed: {e}", file=sys.stderr)
    print("install via: pip install trafilatura", file=sys.stderr)
    sys.exit(1)

# ═══════════════════════════════════════════════════════════════════════════
# Content-container selectors — ordered by specificity (most → least)
# ═══════════════════════════════════════════════════════════════════════════
CONTENT_SELECTORS = [
    ".dev-con-detail-doc",
    ".doc-content",
    ".api-content",
    ".content-detail",
    ".article-content",
    ".markdown-body",
    ".richtext",
    ".prose",
    "[class*='detail-doc']",
    "[class*='doc-body']",
    "[class*='article-body']",
    "[class*='content-panel']",
    "main",
    "article",
]

# ═══════════════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════════════


def _strip_tags(raw: str) -> str:
    """Naive tag stripper — enough for residual inline markup in innerText."""
    raw = re.sub(r"<br\s*/?>", "\n", raw)
    raw = re.sub(
        r"</?(p|div|tr|h[1-6]|li|ul|ol|table|thead|tbody|th|"
        r"section|header|footer|nav|article|aside|pre|blockquote|hr|dl|dt|dd|"
        r"fieldset|form|figure|figcaption|details|summary)[^>]*>",
        "\n", raw, flags=re.I,
    )
    raw = re.sub(r"<[^>]+>", "", raw)
    raw = re.sub(r"\n{3,}", "\n\n", raw)
    raw = re.sub(r"[ \t]{2,}", " ", raw)
    return raw.strip()


def _pick_content(page) -> str | None:
    """Return visible text of the first content container with ≥200 chars."""
    for sel in CONTENT_SELECTORS:
        try:
            el = page.query_selector(sel)
            if not el or not el.is_visible():
                continue
            text = (el.inner_text() or "").strip()
            if len(text) >= 200:
                print(f"[cloak] content container: {sel} ({len(text)} chars)",
                      file=sys.stderr)
                return text
        except Exception:
            continue
    return None


def _body_text_len(page) -> int:
    try:
        return page.evaluate("() => (document.body?.innerText || '').length")
    except Exception:
        return 0


def _has_tree(page) -> bool:
    return page.evaluate("""() => {
        const sels = '.one-tree-title, .one-tree-node-content-wrapper, ' +
            '[class*="tree-title"], [class*="tree-node"] span, ' +
            '[class*="sidebar"] [class*="item"], [class*="toc"] a';
        return !!document.querySelector(sels);
    }""")


def _unhide(page) -> int:
    """Click collapsed accordions / 'show more' — skips tree-nav nodes."""
    return page.evaluate("""() => {
        const triggers = document.querySelectorAll(
            '[class*="collapse"] [class*="header"], ' +
            '[class*="accordion"] [class*="header"], ' +
            '[class*="expand"], [class*="collapsed"], ' +
            '[aria-expanded="false"], details > summary:not([open])'
        );
        let count = 0;
        for (const el of triggers) {
            if (el.closest('[class*="tree"]') || el.closest('[class*="sidebar"]') ||
                el.closest('[class*="toc"]') || el.closest('[class*="nav"]')) continue;
            try { el.click(); count++; } catch(e) {}
        }
        return count;
    }""")


def _scroll(page) -> None:
    """Scroll top→bottom→top to trigger lazy rendering."""
    page.evaluate("() => window.scrollTo(0, 0)")
    time.sleep(0.3)
    for _ in range(3):
        page.evaluate("() => window.scrollBy(0, window.innerHeight * 0.8)")
        time.sleep(0.4)
    page.evaluate("() => window.scrollTo(0, document.body.scrollHeight)")
    time.sleep(1)
    page.evaluate("() => window.scrollTo(0, 0)")
    time.sleep(0.5)


def _get_top_nav(page) -> list[str]:
    """Return unique visible top-nav button texts (de-duplicated)."""
    return page.evaluate("""() => {
        const sel = '.one-nav-item, [class*="nav-item"], [class*="menu-item"], nav a';
        const seen = new Set();
        const items = [];
        for (const el of document.querySelectorAll(sel)) {
            const t = (el.textContent || '').trim();
            if (t && !seen.has(t)) { seen.add(t); items.push(t); }
        }
        return items.slice(0, 12);
    }""")


def _click_nav(page, label: str) -> bool:
    """Click a top-level nav item by exact visible text."""
    return page.evaluate(f"""() => {{
        const sel = '.one-nav-item, [class*="nav-item"], [class*="menu-item"], ' +
            'nav a, [role="menubar"] [role="menuitem"], [role="tab"]';
        for (const el of document.querySelectorAll(sel)) {{
            if ((el.textContent || '').trim() === {_s(label)}) {{ el.click(); return true; }}
        }}
        return false;
    }}""")


def _click_tree_node(page, prefer_unselected: bool = True) -> str | None:
    """Click the first visible tree node, optionally preferring unselected ones."""
    return page.evaluate(f"""() => {{
        const nodes = document.querySelectorAll(
            '.one-tree-title, [class*="tree-title"], [class*="tree-node"] span, ' +
            '[class*="sidebar"] [class*="item"], [class*="toc"] a'
        );
        // First pass: prefer unselected / closed nodes
        for (const n of nodes) {{
            const txt = (n.textContent || '').trim();
            if (!txt || txt.length > 80) continue;
            const p = n.closest('[class*="node-content-wrapper"]');
            if ({str(prefer_unselected).lower()} && p && p.className.includes('selected')) continue;
            n.click();
            return txt;
        }}
        // Second pass: click anything
        for (const n of nodes) {{
            const txt = (n.textContent || '').trim();
            if (txt && txt.length <= 80) {{ n.click(); return txt; }}
        }}
        return null;
    }}""")


def _s(s: str) -> str:
    """Safe JS single-quoted string literal."""
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n") + "'"


def _url_has_doc_params(u: str) -> bool:
    """Whether the URL carries query params that look like doc identifiers."""
    doc_keys = {"nodeId", "pageId", "docId", "articleId", "contentId", "path", "section"}
    return bool(set(parse_qs(urlparse(u).query).keys()) & doc_keys)


# Rank nav items — prefer items that sound like "docs" / "API" / "guide"
_DOC_NAV_KEYWORDS = ["文档", "API", "Docs", "Guide", "Reference", "开发", "Tutorial"]


def _pick_best_nav(nav_items: list[str]) -> str | None:
    """Return the best nav item to click for doc content, or None."""
    candidates = [n for n in nav_items if n not in ("首页", "登录", "帮助", "Home", "Login", "")]
    if not candidates:
        return None
    # Prefer items matching doc keywords
    for kw in _DOC_NAV_KEYWORDS:
        for c in candidates:
            if kw in c:
                return c
    # Fallback: first non-trivial item (skip very short labels too)
    for c in candidates:
        if len(c) >= 3:
            return c
    return None


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

try:
    print("[cloak] launching headless browser", file=sys.stderr)
    browser = launch(headless=True)
    page = browser.new_page()

    print(f"[cloak] navigating to {url}", file=sys.stderr)
    page.goto(url, wait_until="domcontentloaded", timeout=120000)

    # ── Cloudflare interstitial guard ────────────────────────────────────
    deadline = time.time() + 30
    while time.time() < deadline:
        title = page.title() or ""
        if title and "Just a moment" not in title:
            break
        time.sleep(1)

    # ── Settle: wait for SPA router hydration ────────────────────────────
    deadline = time.time() + 15
    while time.time() < deadline:
        ct = _pick_content(page)
        if ct:
            break
        if _has_tree(page):
            break
        time.sleep(1)

    # ── Scroll + unhide collapsed sections ────────────────────────────────
    _scroll(page)
    _unhide(page)
    time.sleep(0.5)

    # ── First extraction attempt ──────────────────────────────────────────
    container_text = _pick_content(page)
    has_tree = _has_tree(page)
    body_len = _body_text_len(page)
    has_params = _url_has_doc_params(url)

    print(f"[cloak] body_text={body_len} has_tree={has_tree} has_params={has_params}",
          file=sys.stderr)

    # ── SPA navigation ───────────────────────────────────────────────────
    # If we already have good content from a container, skip nav interaction.
    if not container_text and (has_tree or has_params or body_len < 5000):
        nav_items = _get_top_nav(page)
        print(f"[cloak] top nav: {nav_items}", file=sys.stderr)

        best_nav = _pick_best_nav(nav_items)
        if best_nav:
            print(f"[cloak] clicking nav: {best_nav}", file=sys.stderr)
            _click_nav(page, best_nav)
            time.sleep(5)

            ct = _pick_content(page)
            if ct:
                container_text = ct
            elif _has_tree(page):
                # Tree appeared — click the first node
                clicked = _click_tree_node(page, prefer_unselected=False)
                if clicked:
                    print(f"[cloak] clicked tree: {clicked}", file=sys.stderr)
                    time.sleep(4)
                    ct = _pick_content(page)
                    if ct:
                        container_text = ct

    # ── Second pass: still no content, tree exists — click deeper ───────
    if not container_text and _has_tree(page):
        for _ in range(3):
            clicked = _click_tree_node(page, prefer_unselected=True)
            if not clicked:
                break
            print(f"[cloak] clicked tree: {clicked}", file=sys.stderr)
            time.sleep(2)
            ct = _pick_content(page)
            if ct:
                container_text = ct
                break

    # ── Final settle ──────────────────────────────────────────────────────
    _scroll(page)
    _unhide(page)
    time.sleep(0.5)

    if not container_text:
        container_text = _pick_content(page)

    # ── Build extraction source ───────────────────────────────────────────
    print(f"[cloak] title: {page.title()}", file=sys.stderr)
    print(f"[cloak] url: {page.url}", file=sys.stderr)

    if container_text:
        print(f"[cloak] using container text ({len(container_text)} chars)",
              file=sys.stderr)
        clean_text = _strip_tags(container_text)
        source = container_text
    else:
        clean_text = None
        source = page.evaluate("() => document.documentElement.outerHTML")

    print(f"[cloak] source size: {len(source)} bytes", file=sys.stderr)

    # ── trafilatura ──────────────────────────────────────────────────────
    md = trafilatura.extract(
        source,
        url=url,
        output_format="markdown",
        include_links=True,
        include_images=False,
        include_comments=False,
        favor_recall=True,
    )

    md_len = len(md or "")
    clean_len = len(clean_text or "")

    # Output decision
    if not md:
        if clean_text:
            print("[cloak] trafilatura empty → emitting container text",
                  file=sys.stderr)
            sys.stdout.write(clean_text)
        else:
            inner = page.evaluate("() => (document.body?.innerText || '')")
            print(f"[cloak] emitting innerText fallback ({len(inner)} chars)",
                  file=sys.stderr)
            sys.stdout.write(_strip_tags(inner) or source)
    elif md_len < 2000 and clean_len > md_len * 1.5:
        print("[cloak] trafilatura too short → emitting container text",
              file=sys.stderr)
        sys.stdout.write(clean_text)
    else:
        sys.stdout.write(md)
        print(f"[cloak] done, {md_len} bytes markdown", file=sys.stderr)

    browser.close()

except Exception as e:
    print(f"[cloak] failed: {e}", file=sys.stderr)
    sys.exit(1)
