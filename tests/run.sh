#!/usr/bin/env bash
# Runs tests/<area>/test-*.sh, each in its own process. On macOS `bash` resolves to /bin/bash
# (3.2) for the tests and every script they start, so 3.2 breakage fails here, not on a laptop.
set -u
# A developer shell may point Claude Code at another profile; tests must never touch it.
unset CLAUDE_CONFIG_DIR
here=$(cd "$(dirname "$0")" && pwd -P)

case "${1:-}" in
  -h|--help)
    echo "usage: tests/run.sh [area…]   areas: $(cd "$here" && ls -d */ 2>/dev/null | tr -d / | tr '\n' ' ')"
    exit 0 ;;
esac

shim=""
if [ "$(uname -s)" = Darwin ] && [ -x /bin/bash ]; then
  shim=$(mktemp -d "${TMPDIR:-/tmp}/sdw-tests-shim.XXXXXX") || exit 1
  ln -s /bin/bash "$shim/bash"
  PATH="$shim:$PATH"
  export PATH
fi
log=$(mktemp "${TMPDIR:-/tmp}/sdw-tests-log.XXXXXX") || exit 1
trap 'rm -f "$log"; [ -z "$shim" ] || rm -rf "$shim"' EXIT

if [ $# -gt 0 ]; then areas="$*"; else areas=$(cd "$here" && ls -d */ 2>/dev/null | tr -d /); fi
pass=0 failed=0 missing=0
for a in $areas; do
  if [ ! -d "$here/$a" ]; then echo "FAIL $a: no such area"; missing=$((missing + 1)); continue; fi
  for t in "$here/$a"/test-*.sh; do
    [ -e "$t" ] || continue
    if bash "$t" > "$log" 2>&1; then
      echo "PASS $a/$(basename "$t")"
      pass=$((pass + 1))
    else
      echo "FAIL $a/$(basename "$t")"
      tail -n 30 "$log" | sed 's/^/    /'
      failed=$((failed + 1))
    fi
  done
done
echo "$pass passed, $failed failed$([ "$missing" = 0 ] || echo ", $missing unknown areas") ($(bash -c 'echo "bash $BASH_VERSION"'))"
[ "$failed" = 0 ] && [ "$missing" = 0 ]
