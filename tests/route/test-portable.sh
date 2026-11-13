#!/usr/bin/env bash
# route: nothing machine-specific in the repo, env.zsh and setup.sh behave from another path, README prompt in step.
set -u
here=$(cd "$(dirname "$0")" && pwd -P)
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found"; exit 1; }
exec python3 -I -B "$here/test_portable.py"
