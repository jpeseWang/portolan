#!/usr/bin/env bash
# shellcheck source=tests/bootstrap/_lib.sh
. "$(dirname "$0")/_lib.sh"

make_src v2.0.0
mkdir -p "$HOME/.claude"
cat > "$SET" <<'EOF'
{"model":"opus","attribution":{"commit":"mine"},
 "permissions":{"allow":["Bash(make *)","Bash(git status)"],"deny":["Read(./**/.env)"]}}
EOF
cp "$SET" "$tmp/settings.orig"
B --verify-skill > "$tmp/out1" 2>&1 || die setup "install failed: $(tail -3 "$tmp/out1")"
cmp -s "$HOME/.claude/skills/verify/SKILL.md" "$ROOT/templates/verify-skill/SKILL.md" || die setup "verify skill not installed"

# The user keeps working: a new allow entry, and a changed value bootstrap had added.
jq '.permissions.allow += ["Bash(npm test)"] | .attribution.pr = "custom"' "$SET" > "$tmp/s" && mv "$tmp/s" "$SET"

B --uninstall > "$tmp/out2" 2>&1; rc=$?
expect_rc uninstall 0 "$rc"
has uninstall "plugin uninstall sdw@sdw-local --scope user" "$CST/log"
has uninstall "plugin marketplace remove sdw-local" "$CST/log"
ok "plugin and marketplace removed"

jq -S 'del(.enabledPlugins, .extraKnownMarketplaces)' "$SET" > "$tmp/got"
jq -S '.permissions.allow += ["Bash(npm test)"] | .attribution.pr = "custom"' "$tmp/settings.orig" > "$tmp/want"
cmp -s "$tmp/got" "$tmp/want" || { diff "$tmp/want" "$tmp/got"; die settings "uninstall did not restore the pre-install settings plus the user's later edits"; }
has settings "attribution.pr: changed since install" "$tmp/out2"
jtrue settings '.permissions.allow | index("Bash(git status)") != null' "$SET"
ok "only recorded entries removed; pre-existing and later user entries kept"

[ ! -e "$REL" ] || die files "release clone still present"
[ ! -e "$REC" ] || die files "record still present"
[ ! -e "$HOME/.claude/skills/verify" ] || die files "verify skill still present"
[ ! -e "$HOME/.claude/CLAUDE.md" ] || die files "unchanged CLAUDE.md not removed"
ls "$HOME/.claude"/settings.json.sdw-backup-* >/dev/null 2>&1 || die files "no backup before uninstall"
ok "release clone, record, verify skill and untouched CLAUDE.md removed"

cp "$SET" "$tmp/s2"
B --uninstall > "$tmp/out3" 2>&1; rc=$?
expect_rc again 0 "$rc"
cmp -s "$SET" "$tmp/s2" || die again "second uninstall changed settings"
has again "not installed" "$tmp/out3"
ok "second uninstall is a no-op"

B > /dev/null 2>&1 || die edited "reinstall failed"
printf '\n- my own rule\n' >> "$HOME/.claude/CLAUDE.md"
B --uninstall > "$tmp/out4" 2>&1; rc=$?
expect_rc edited 0 "$rc"
[ -f "$HOME/.claude/CLAUDE.md" ] || die edited "edited CLAUDE.md was removed"
has edited "edited since install" "$tmp/out4"
ok "edited CLAUDE.md kept"

mkdir -p "$HOME/.claude/skills/verify"; printf -- '---\nname: verify\n---\nmine\n' > "$HOME/.claude/skills/verify/SKILL.md"
B --verify-skill > "$tmp/out5" 2>&1 || die foreign "install failed"
has foreign "is not the sdw one" "$tmp/out5"
B --uninstall > /dev/null 2>&1
grep -q mine "$HOME/.claude/skills/verify/SKILL.md" || die foreign "foreign verify skill touched"
ok "a foreign verify skill is never installed over or removed"
