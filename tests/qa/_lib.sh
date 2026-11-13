# Sourced by tests/qa/test-*.sh. Builds an isolated HOME, a fake plugin tree holding copies of
# the bins under test beside stubbed core bins (sdw-workdir, sdw-cfg, sdw-evidence), and a stub
# dir for external tools. Core bins are stubbed so this area tests only its own contract.
set -u

QA_TESTS=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN=$(cd "$QA_TESTS/../../plugin" && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdw-tests-qa.XXXXXX")
tmp=$(cd "$tmp" && pwd -P)
server_pid=""
cleanup() {
  [ -z "$server_pid" ] || { kill "$server_pid"; wait "$server_pid"; } 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

export HOME="$tmp/home"
unset CLAUDE_CONFIG_DIR
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=sdw-test GIT_AUTHOR_EMAIL=sdw-test@example.invalid
export GIT_COMMITTER_NAME=sdw-test GIT_COMMITTER_EMAIL=sdw-test@example.invalid

ok() { echo "ok $1"; }
fail() { echo "FAIL $1: $2"; exit 1; }

# projdir with a space in its path
export FAKE_PROJDIR="$tmp/client proj"
mkdir -p "$FAKE_PROJDIR/.sdw"
export STUB_LOG="$tmp/log"
mkdir -p "$STUB_LOG"
export EVID_LOG="$STUB_LOG/evidence"

FBIN="$tmp/plugin/bin"
STUB="$tmp/stub"
mkdir -p "$FBIN" "$STUB"
ln -s "$PLUGIN/libexec" "$tmp/plugin/libexec"
for b in sdw-ui-shot sdw-ui-diff sdw-login sdw-figma-png; do
  cp "$PLUGIN/bin/$b" "$FBIN/$b"
done

cat > "$FBIN/sdw-workdir" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_PROJDIR:-}" ] || { echo "sdw: not onboarded (run /sdw:onboard)" >&2; exit 3; }
case "${1:-}" in
  --projdir) echo "$FAKE_PROJDIR" ;;
  "") mkdir -p "$FAKE_PROJDIR/.sdw/work/feat" && echo "$FAKE_PROJDIR/.sdw/work/feat" ;;
  *) exit 2 ;;
esac
EOF
cat > "$FBIN/sdw-cfg" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  PROJ_SLUG) echo proj ;;
  FIGMA_FILE_KEY) echo KEYabc ;;
  *) echo "${2:-}" ;;
esac
EOF
cat > "$FBIN/sdw-evidence" <<'EOF'
#!/usr/bin/env bash
{ printf '%s\n' "$@"; echo ---; } >> "$EVID_LOG"
exit "${EVID_RC:-0}"
EOF

# Keychain: one file per item, named "<service>@@<account>", content = secret.
export STUB_KEYCHAIN="$tmp/keychain"
mkdir -p "$STUB_KEYCHAIN"
cat > "$STUB/security" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG/security.argv"
svc="" acct="" w=0
while [ $# -gt 0 ]; do
  case "$1" in
    -s) svc=$2; shift 2 ;;
    -a) acct=$2; shift 2 ;;
    -w) w=1; shift ;;
    *) shift ;;
  esac
done
if [ -n "$acct" ]; then f="$STUB_KEYCHAIN/$svc@@$acct"; else f=$(ls "$STUB_KEYCHAIN/$svc@@"* 2>/dev/null | head -n 1); fi
[ -n "$f" ] && [ -f "$f" ] || { echo "security: The specified item could not be found in the keychain." >&2; exit 44; }
[ "$w" = 1 ] && cat "$f"
exit 0
EOF

chmod +x "$FBIN"/* "$STUB"/*
keychain_put() { printf '%s\n' "$3" > "$STUB_KEYCHAIN/$1@@$2"; }

# Runs a fake-plugin bin with the stub dir first on PATH; stdout/stderr/rc land in $out/$err/$rc.
run() {
  local bin=$1; shift
  out=$(PATH="$STUB:$FBIN:$PATH" "$FBIN/$bin" "$@" 2>"$tmp/stderr")
  rc=$?
  err=$(cat "$tmp/stderr")
}

expect_rc() {
  [ "$rc" = "$2" ] || fail "$1" "exit $rc, expected $2; stdout: $out; stderr: $err"
}
