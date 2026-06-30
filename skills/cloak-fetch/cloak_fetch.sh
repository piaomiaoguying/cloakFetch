#!/usr/bin/env bash
# cloak-fetch wrapper: locate a Python with cloakbrowser, fetch the URL
# headlessly via CloakBrowser, and emit clean markdown (trafilatura).
#
# Usage: cloak_fetch.sh <url> [--links]
# Stdout: clean markdown extracted from the page.
# Stderr: progress + error messages.
# Exit:   0 on success, non-zero on any failure.
# Options:
#   --links  Append a link-list section extracted from the rendered DOM.
#            Helps when trafilatura drops <a href> on SPA pages.

set -uo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "usage: $(basename "$0") <url> [--links]" >&2
  exit 2
fi

URL="$1"
LINK_FLAG="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Find a Python interpreter that can import cloakbrowser ──────────────
# Priority: $CLOAKBROWSER_PYTHON → $SCRIPT_DIR/cloak_fetch.conf → PATH python3
PY=""

# 1. Explicit env var (highest priority).
if [ -n "${CLOAKBROWSER_PYTHON:-}" ] && [ -x "$CLOAKBROWSER_PYTHON" ] \
   && "$CLOAKBROWSER_PYTHON" -c "import cloakbrowser" 2>/dev/null; then
  PY="$CLOAKBROWSER_PYTHON"
fi

# 2. Read the per-skill config file (if it exists).
if [ -z "$PY" ] && [ -f "$SCRIPT_DIR/cloak_fetch.conf" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    # Strip leading/trailing whitespace and skip empty / comment lines.
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue
    if [ -x "$line" ] && "$line" -c "import cloakbrowser" 2>/dev/null; then
      PY="$line"
      break
    fi
  done < "$SCRIPT_DIR/cloak_fetch.conf"
fi

# 3. Fallback: whatever `python3` is on PATH.
if [ -z "$PY" ]; then
  PY="$(command -v python3 2>/dev/null)"
fi

if [ -z "$PY" ] || [ ! -x "$PY" ]; then
  echo "cloak-fetch: no usable Python with 'cloakbrowser' found." >&2
  echo "Set CLOAKBROWSER_PYTHON or add paths to $SCRIPT_DIR/cloak_fetch.conf" >&2
  echo "https://github.com/CloakHQ/CloakBrowser" >&2
  exit 1
fi

# On macOS ARM, always use `arch -arm64` to force native execution.
# The shebang (`#!/usr/bin/env bash`) spawns `/bin/bash`, which is a
# universal binary. On Claude Code's harness, bash sometimes picks the
# x86_64 slice even on ARM Macs (and reports `uname -m = x86_64`), which
# cascades to Python and causes "incompatible architecture" errors on
# arm64-only .so extensions. `arch -arm64` is harmless on native ARM (it's
# a no-op). We probe whether it works rather than guessing from `uname -m`.
# Linux and Intel Macs skip this entirely.
if [[ "$(uname -s)" == "Darwin" ]] && arch -arm64 true 2>/dev/null; then
  exec arch -arm64 "$PY" "$SCRIPT_DIR/cloak_fetch.py" "$URL" ${LINK_FLAG:+"$LINK_FLAG"}
else
  exec "$PY" "$SCRIPT_DIR/cloak_fetch.py" "$URL" ${LINK_FLAG:+"$LINK_FLAG"}
fi
