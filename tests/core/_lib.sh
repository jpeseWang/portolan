# Sourced by tests/core/test-*.sh. Isolated HOME and git identity, stubbed network/Keychain tools.
set -u

PLUGIN=$(cd "$(dirname "$0")/../../plugin" && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdw-tests-core.XXXXXX")
tmp=$(cd "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home" TMPDIR="$tmp/tmpdir"
unset CLAUDE_CONFIG_DIR
mkdir -p "$HOME" "$tmp/stub" "$TMPDIR"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=sdw-test GIT_AUTHOR_EMAIL=sdw-test@example.invalid
export GIT_COMMITTER_NAME=sdw-test GIT_COMMITTER_EMAIL=sdw-test@example.invalid
export CLAUDE_PLUGIN_ROOT="$PLUGIN"
unset CLAUDE_PROJECT_DIR CLAUDE_ENV_FILE SDW_ASK_MODE SDW_STOP_MODE SDW_WD SDW_GATE_TIMEOUT SDW_RELAX SDW_CONFIG_DIR XDG_CONFIG_HOME
for s in security curl gh claude npx node; do
  printf '#!/bin/sh\nexit 0\n' > "$tmp/stub/$s"
  chmod +x "$tmp/stub/$s"
done
export PATH="$tmp/stub:$PLUGIN/bin:$PATH"

CASE=""
ok() { echo "ok $1"; }
fail() { echo "FAIL $1: $2"; exit 1; }

# expect_rc <want> <case> <cmd...>; output kept in $OUT
expect_rc() {
  local want=$1 name=$2 rc
  shift 2
  OUT=$("$@" 2>&1); rc=$?
  [ "$rc" = "$want" ] || fail "$name" "exit $rc, want $want; output: $(printf '%s' "$OUT" | tail -n 5)"
  ok "$name"
}

# mkrepo <dir> [branch]: repo with one commit of src/a.ts and README.md.
mkrepo() {
  mkdir -p "$1/src"
  (
    cd "$1" && git init -q . && git symbolic-ref HEAD "refs/heads/${2:-main}" &&
    echo 'export const a = 1' > src/a.ts && echo readme > README.md &&
    git add -A && git commit -qm init
  ) || fail mkrepo "$1"
}

json_str() {
  if command -v jq >/dev/null 2>&1; then printf '%s' "$1" | jq -Rs .
  else printf '%s' "$1" | python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))'
  fi
}

# hook_json <hook> <json>: runs the hook with stdin; sets RC and OUT (stdout) and ERR (stderr).
hook_json() {
  local h=$1
  shift
  printf '%s' "$1" | "$PLUGIN/hooks/$h" > "$tmp/.out" 2> "$tmp/.err"
  RC=$?
  OUT=$(cat "$tmp/.out"); ERR=$(cat "$tmp/.err")
}
