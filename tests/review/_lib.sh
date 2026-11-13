# Sourced by tests/review/test-*.sh. Sets up an isolated $tmp, $BIN and git identity.
set -u
PLUGIN=$(cd "$(dirname "$0")/../../plugin" && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdw-tests-review.XXXXXX")
tmp=$(cd "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home" "$tmp/t" "$tmp/stub" "$tmp/bin"
export HOME="$tmp/home" TMPDIR="$tmp/t/" GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_CONFIG_DIR
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
[ "$(uname)" = Darwin ] && ln -s /bin/bash "$tmp/stub/bash"

# Real plugin bins.
for f in "$PLUGIN"/bin/*; do ln -s "$f" "$tmp/bin/$(basename "$f")"; done
export PATH="$tmp/stub:$tmp/bin:$PATH"

fail() { echo "FAIL $1: $2"; exit 1; }
ok() { echo "ok $1"; }

# expect_rc <case> <rc> <cmd...>: runs cmd, stores stdout in $out, asserts the exact exit code.
expect_rc() {
  local name=$1 want=$2; shift 2
  out=$("$@" 2>"$tmp/err"); local rc=$?
  [ "$rc" = "$want" ] || fail "$name" "exit $rc, want $want; out: $out; err: $(cat "$tmp/err")"
}

new_repo() {
  mkdir -p "$1" && (cd "$1" && git init -q && git symbolic-ref HEAD refs/heads/main)
}

commit_all() { (cd "$1" && git add -A && git commit -q -m "${2:-c}"); }
