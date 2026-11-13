# shellcheck disable=SC2034
# Sourced by tests/bootstrap/test-*.sh. Isolated HOME (with a space), git identity, and a
# fake `claude` that records its args and keeps plugin/marketplace state like the real one.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdw-tests-bootstrap.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P)
export HOME="$tmp/my home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=tester@localhost \
  GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=tester@localhost
unset CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT CLAUDE_CONFIG_DIR
STUB="$tmp/stub"
CST="$tmp/claude-state"
BINLOG="$tmp/bins.log"
mkdir -p "$STUB" "$CST"
: > "$CST/log"
: > "$BINLOG"
export SDW_FAKE_CLAUDE_STATE="$CST" SDW_FAKE_BINLOG="$BINLOG"
export PATH="$STUB:$PATH"
REL="$HOME/.local/share/sdw/release"
SET="$HOME/.claude/settings.json"
REC="$HOME/.claude/sdw-bootstrap.json"

ok() { printf 'ok %s\n' "$1"; }
die() { printf 'FAIL %s: %s\n' "$1" "$2"; exit 1; }
expect_rc() { [ "$2" = "$3" ] || die "$1" "exit $3, expected $2"; }
has() { grep -qF -- "$2" "$3" || die "$1" "missing '$2' in $(basename "$3")"; }
hasnt() { if grep -qF -- "$2" "$3"; then die "$1" "unexpected '$2' in $(basename "$3")"; fi; }
jtrue() { jq -e "$2" "$3" >/dev/null 2>&1 || die "$1" "jq check failed: $2"; }
tree_sum() { # checksum of every file and symlink under $1 (content, mode-insensitive)
  (cd "$1" && find . \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r f; do
    if [ -L "$f" ]; then printf '%s -> %s\n' "$f" "$(readlink "$f")"; else printf '%s %s\n' "$f" "$(cksum < "$f")"; fi
  done)
}

cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
st=$SDW_FAKE_CLAUDE_STATE
printf '%s\n' "$*" >> "$st/log"
set_json() { # set_json <jq filter>: edit ~/.claude/settings.json the way claude does
  d="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; f="$d/settings.json"; mkdir -p "$d"
  [ -s "$f" ] || printf '{}\n' > "$f"
  jq "$1" "$f" > "$f.t" && mv "$f.t" "$f"
}
case "$1 $2 ${3:-}" in
  "plugin marketplace list")
    if [ -f "$st/market" ]; then jq -n --arg p "$(cat "$st/market")" '[{name:"sdw-local",source:"directory",path:$p}]'
    else echo '[]'; fi ;;
  "plugin marketplace add")
    printf '%s' "$4" > "$st/market"; set_json '.extraKnownMarketplaces["sdw-local"] = {source: {source: "directory"}}' ;;
  "plugin marketplace remove")
    [ -f "$st/market" ] || exit 1; rm -f "$st/market"; set_json 'del(.extraKnownMarketplaces["sdw-local"])' ;;
  "plugin list "*|"plugin list")
    if [ -f "$st/plugin" ]; then echo '[{"id":"sdw@sdw-local","scope":"user","enabled":true}]'; else echo '[]'; fi ;;
  "plugin install "*)
    touch "$st/plugin"; set_json '.enabledPlugins["sdw@sdw-local"] = true' ;;
  "plugin uninstall "*)
    [ -f "$st/plugin" ] || exit 1; rm -f "$st/plugin"; set_json 'del(.enabledPlugins["sdw@sdw-local"])' ;;
esac
exit 0
EOF
for s in npm playwright-cli security curl gh node npx; do
  printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" %s "$*" >> "$SDW_FAKE_BINLOG"\n' "$s" > "$STUB/$s"
done
chmod +x "$STUB"/*

# make_src [tags…]: a release-source repo holding the current bootstrap.sh and templates,
# with stub sdw-exclude/sdw-doctor that only record their cwd and args.
SRC="$tmp/sdw src"
make_src() {
  mkdir -p "$SRC/plugin/bin" "$SRC/.claude-plugin"
  cp "$ROOT/bootstrap.sh" "$SRC/"
  cp -R "$ROOT/templates" "$SRC/"
  printf '{"name":"sdw-local","owner":{"name":"t"},"plugins":[{"name":"sdw","source":"./plugin"}]}\n' \
    > "$SRC/.claude-plugin/marketplace.json"
  for b in sdw-exclude sdw-doctor; do
    printf '#!/usr/bin/env bash\nprintf "%%s|%%s|%%s\\n" %s "$PWD" "$*" >> "$SDW_FAKE_BINLOG"\n' "$b" > "$SRC/plugin/bin/$b"
    chmod +x "$SRC/plugin/bin/$b"
  done
  (cd "$SRC" && git init -q . && git add -A && git commit -qm init) || exit 1
  local t
  for t in "$@"; do (cd "$SRC" && git commit -q --allow-empty -m "$t" && git tag "$t"); done
}
B() { "$SRC/bootstrap.sh" "$@"; }
claude_calls() { grep -c -- "$1" "$CST/log" || true; }
rel_tag() { (cd "$REL" && git describe --tags --exact-match --match 'v[0-9]*.[0-9]*.[0-9]*' HEAD 2>/dev/null); }
