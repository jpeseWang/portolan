#!/usr/bin/env bash
# CLAUDE_CONFIG_DIR: settings, record and skills land in that profile, ~/.claude stays untouched,
# and no CLAUDE.md is written there.
# shellcheck source=tests/bootstrap/_lib.sh
. "$(dirname "$0")/_lib.sh"

make_src v2.0.9
ALT="$tmp/alt profile"
mkdir -p "$ALT"

CLAUDE_CONFIG_DIR="$ALT" B --verify-skill > "$tmp/out" 2>&1; rc=$?
expect_rc config-dir 0 "$rc"
jtrue config-dir '.enabledPlugins["sdw@sdw-local"] == true and .attribution.pr == ""' "$ALT/settings.json"
[ -f "$ALT/sdw-bootstrap.json" ] || die config-dir "no record in $ALT"
[ -f "$ALT/skills/verify/SKILL.md" ] || die config-dir "verify skill not in $ALT"
[ ! -e "$ALT/CLAUDE.md" ] || die config-dir "CLAUDE.md written into $ALT"
[ ! -e "$HOME/.claude" ] || die config-dir "~/.claude touched: $(ls -A "$HOME/.claude")"
has config-dir "memory stays in ~/.claude/CLAUDE.md" "$tmp/out"
ok "CLAUDE_CONFIG_DIR profile gets settings, record and skills; ~/.claude untouched"

CLAUDE_CONFIG_DIR="$ALT" B --uninstall > "$tmp/out2" 2>&1; rc=$?
expect_rc config-dir-uninstall 0 "$rc"
[ ! -e "$ALT/skills/verify" ] || die config-dir-uninstall "verify skill left in $ALT"
if [ -f "$ALT/settings.json" ]; then
  if jq -e '.enabledPlugins["sdw@sdw-local"]' "$ALT/settings.json" >/dev/null 2>&1; then die config-dir-uninstall "sdw still enabled"; fi
fi
ok "uninstall cleans the same profile"
