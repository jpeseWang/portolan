#!/usr/bin/env bash
# shellcheck source=tests/bootstrap/_lib.sh
. "$(dirname "$0")/_lib.sh"

make_src v1.9.0 v2.0.2 v2.0.9 v1-installer
mkdir -p "$HOME/.claude"
cat > "$SET" <<'EOF'
{"model":"opus","attribution":{"commit":"mine"},
 "permissions":{"allow":["Bash(make *)"],"deny":["Read(./**/.env)"]}}
EOF
cp "$SET" "$tmp/settings.orig"

B > "$tmp/out1" 2>&1; rc=$?
expect_rc install 0 "$rc"
[ "$(rel_tag)" = v2.0.9 ] || die install "release clone at '$(rel_tag)', expected v2.0.9"
has install "plugin marketplace add $REL --scope user" "$CST/log"
has install "plugin install sdw@sdw-local --scope user" "$CST/log"
ok "clone at newest tag, marketplace added, plugin installed"

jtrue merge '.model == "opus" and .attribution.commit == "mine" and .attribution.pr == ""' "$SET"
jtrue merge '.permissions.allow | index("Bash(make *)") != null and index("Bash(sdw-gate *)") != null' "$SET"
jtrue merge '[.permissions.deny[] | select(. == "Read(./**/.env)")] | length == 1' "$SET"
jtrue merge '.permissions.ask | index("Bash(gh pr merge *)") != null' "$SET"
jtrue merge '.enabledPlugins["sdw@sdw-local"] == true' "$SET"
jtrue merge '[.permissions.allow[] | select(. == "Bash" or . == "Read" or endswith("(*)"))] | length == 0' "$SET"
has merge "note: attribution.commit: yours kept" "$tmp/out1"
ok "settings merged, user values kept, no blanket allow"

ls "$HOME/.claude"/settings.json.sdw-backup-* >/dev/null 2>&1 || die backup "no settings backup"
bk=$(ls "$HOME/.claude"/settings.json.sdw-backup-* | head -1)
jq -S 'del(.enabledPlugins, .extraKnownMarketplaces)' "$bk" > "$tmp/bk.cmp"
jq -S . "$tmp/settings.orig" > "$tmp/orig.cmp"
cmp -s "$tmp/bk.cmp" "$tmp/orig.cmp" || die backup "backup is not the pre-merge settings"
ok "backup holds the pre-merge settings"

jtrue record '.settings_added | map(.item // .value) | index("Read(./**/.env)") == null' "$REC"
jtrue record '[.settings_added[] | select(.path == ["attribution","commit"])] | length == 0' "$REC"
jtrue record '[.settings_added[] | select(.path == ["attribution","pr"])] | length == 1' "$REC"
jtrue record 'any(.settings_created[]; . == ["permissions","ask"])' "$REC"
ok "record holds only what was added"

cmp -s "$HOME/.claude/CLAUDE.md" "$ROOT/templates/global-memory.md" || die claude-md "CLAUDE.md is not the template"
ok "CLAUDE.md created from template"

cp "$SET" "$tmp/s1"; cp "$REC" "$tmp/r1"
adds=$(claude_calls "marketplace add"); inst=$(claude_calls "plugin install")
B > "$tmp/out2" 2>&1; rc=$?
expect_rc idempotent 0 "$rc"
[ "$(claude_calls "marketplace add")" = "$adds" ] || die idempotent "marketplace added twice"
[ "$(claude_calls "plugin install")" = "$inst" ] || die idempotent "plugin installed twice"
cmp -s "$SET" "$tmp/s1" || die idempotent "settings changed on a second run"
cmp -s "$REC" "$tmp/r1" || die idempotent "record changed on a second run"
[ "$(ls "$HOME/.claude"/settings.json.sdw-backup-* | wc -l | tr -d ' ')" = 1 ] || die idempotent "second backup written"
has idempotent "nothing to add" "$tmp/out2"
ok "second run changes nothing"

rm -rf "${HOME:?}" "${CST:?}"/*; mkdir -p "$HOME/.claude"; : > "$CST/log"
printf 'MINE\n' > "$HOME/.claude/CLAUDE.md"
B > "$tmp/out3" 2>&1; rc=$?
expect_rc keep-claude-md 0 "$rc"
[ "$(cat "$HOME/.claude/CLAUDE.md")" = MINE ] || die keep-claude-md "existing CLAUDE.md overwritten"
jtrue keep-claude-md 'has("claude_md_cksum") | not' "$REC"
ok "existing CLAUDE.md untouched"

rm -rf "$HOME" "$SRC"; mkdir -p "$HOME"; : > "$CST/log"; rm -f "$CST/market" "$CST/plugin"
make_src
B > "$tmp/out4" 2>&1; rc=$?
expect_rc no-tag 1 "$rc"
has no-tag "no vX.Y.Z tag" "$tmp/out4"
[ "$(claude_calls "plugin install")" = 0 ] || die no-tag "installed without a release tag"
ok "no release tag: refuses with exit 1"
