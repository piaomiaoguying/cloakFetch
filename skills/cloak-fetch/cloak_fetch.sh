#!/usr/bin/env bash
# cloak-fetch wrapper: locate a Python with cloakbrowser, fetch the URL
# headlessly via CloakBrowser, and emit clean markdown (trafilatura).
#
# Usage: cloak_fetch.sh <url>
# Stdout: clean markdown extracted from the page.
# Stderr: progress + error messages.
# Exit:   0 on success, non-zero on any failure.

set -uo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $(basename "$0") <url>" >&2
  exit 2
fi

URL="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find a Python interpreter that can import cloakbrowser.
# Order: explicit env var → default install location → PATH python3.
PY=""
for candidate in \
  "${CLOAKBROWSER_PYTHON:-}" \
  "$HOME/github/CloakBrowser/.venv/bin/python" \
  "$(command -v python3 2>/dev/null)"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" -c "import cloakbrowser" 2>/dev/null; then
    PY="$candidate"
    break
  fi
done

if [ -z "$PY" ]; then
  echo "cloak-fetch: no Python with 'cloakbrowser' importable." >&2
  echo "Install CloakBrowser (https://github.com/CloakHQ/CloakBrowser) and set" >&2
  echo "CLOAKBROWSER_PYTHON to its venv python." >&2
  exit 1
fi

# `arch -arm64` forces native Apple Silicon mode even when the bash
# subprocess runs under Rosetta (x86_64). Without it the universal binary
# Python picks x86_64 and can't load arm64-compiled native extensions.
exec arch -arm64 "$PY" "$SCRIPT_DIR/cloak_fetch.py" "$URL"
