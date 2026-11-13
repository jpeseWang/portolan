#!/usr/bin/env bash
# shellcheck source=tests/bootstrap/_lib.sh
. "$(dirname "$0")/_lib.sh"

SK="$HOME/.claude/skills/security-audit"
UP="$tmp/upstream skill"
mkdir -p "$UP/skills/security-audit"
printf -- '---\nname: security-audit\ndescription: v1\n---\n' > "$UP/skills/security-audit/SKILL.md"
printf 'x\n' > "$UP/skills/security-audit/HUNTING.md"
printf 'MIT\n' > "$UP/LICENSE"
printf 'not shipped\n' > "$UP/README.md"
(cd "$UP" && git init -q . && git add -A && git commit -qm one) || die setup "fixture repo"
r1=$(cd "$UP" && git rev-parse HEAD)
printf -- '---\nname: security-audit\ndescription: v2\n---\n' > "$UP/skills/security-audit/SKILL.md"
(cd "$UP" && git commit -qam two) || die setup "fixture commit"
export SDW_SECURITY_SKILL_REPO="$UP" SDW_SECURITY_SKILL_REF="$r1"

make_src v2.0.9
B --security-skill --dry-run > "$tmp/out0" 2>&1; rc=$?
expect_rc dry-run 0 "$rc"
[ -e "$SK" ] && die dry-run "dry run created $SK"
has dry-run "(dry-run) \$ git clone" "$tmp/out0"
ok "dry run prints the clone and writes nothing"

B --security-skill > "$tmp/out1" 2>&1; rc=$?
expect_rc install 0 "$rc"
has install "description: v1" "$SK/SKILL.md"
[ -f "$SK/HUNTING.md" ] && [ -f "$SK/LICENSE" ] || die install "companion file or LICENSE missing"
[ -e "$SK/README.md" ] && die install "repo README copied into the skill"
jtrue install ".security_skill == \"$r1\"" "$REC"
ok "installs the pinned commit, not the branch head, with its LICENSE"

B --update > "$tmp/out2" 2>&1; rc=$?
expect_rc current 0 "$rc"
has current "security-audit skill is current" "$tmp/out2"
ok "update keeps a current pinned copy"

r2=$(cd "$UP" && git rev-parse HEAD)
SDW_SECURITY_SKILL_REF="$r2" B --update > "$tmp/out3" 2>&1; rc=$?
expect_rc bump 0 "$rc"
has bump "description: v2" "$SK/SKILL.md"
jtrue bump ".security_skill == \"$r2\"" "$REC"
ok "a new pin replaces the copy on update"

SDW_SECURITY_SKILL_REF=0000000000000000000000000000000000000000 B --update > "$tmp/out4" 2>&1; rc=$?
expect_rc bad-ref 1 "$rc"
has bad-ref "no commit" "$tmp/out4"
has bad-ref "description: v2" "$SK/SKILL.md"
ok "an unknown pin fails and leaves the installed copy"

B --uninstall > "$tmp/out5" 2>&1; rc=$?
expect_rc uninstall 0 "$rc"
[ -e "$SK" ] && die uninstall "$SK left behind"
ok "uninstall removes the recorded skill"

rm -rf "${HOME:?}" "${CST:?}"/*; mkdir -p "$SK"; : > "$CST/log"
printf 'MINE\n' > "$SK/SKILL.md"
B --security-skill > "$tmp/out6" 2>&1; rc=$?
expect_rc foreign 0 "$rc"
has foreign "is not the sdw one" "$tmp/out6"
has foreign "MINE" "$SK/SKILL.md"
B --uninstall > "$tmp/out7" 2>&1
[ -f "$SK/SKILL.md" ] || die foreign "uninstall removed a skill sdw did not install"
ok "a copy sdw did not install is left alone"

B --uninstall --security-skill > "$tmp/out8" 2>&1; rc=$?
expect_rc usage 2 "$rc"
ok "--security-skill is refused with --uninstall"

echo "PASS test-security-skill"
