#!/usr/bin/env bash
# route: quota parsing, priority chains, fallbacks, deny list (stdlib Python, no network).
set -u
here=$(cd "$(dirname "$0")" && pwd -P)
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found"; exit 1; }
exec python3 -I -B "$here/test_routing.py"
