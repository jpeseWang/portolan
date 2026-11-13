#!/usr/bin/env bash
# shellcheck source=tests/bootstrap/_lib.sh
. "$(dirname "$0")/_lib.sh"

make_src v2.0.0
B -h > "$tmp/o" 2>&1; expect_rc help 0 "$?"
has help "usage: bootstrap.sh" "$tmp/o"
ok "-h prints usage, exit 0"

B --bogus > /dev/null 2>&1; expect_rc bad-flag 2 "$?"
B --update --uninstall > /dev/null 2>&1; expect_rc two-modes 2 "$?"
B --migrate > /dev/null 2>&1; expect_rc migrate-no-dir 2 "$?"
B --migrate "$tmp/nope" > /dev/null 2>&1; expect_rc migrate-missing-dir 2 "$?"
B --uninstall --verify-skill > /dev/null 2>&1; expect_rc flag-mode 2 "$?"
B --migrate "$HOME" --dry-run > /dev/null 2>&1; expect_rc migrate-home 2 "$?"
ok "usage errors exit 2"

mkdir -p "$tmp/nojq"
for t in bash dirname date git sed cat; do ln -s "$(command -v "$t")" "$tmp/nojq/$t"; done
ln -s "$STUB/claude" "$tmp/nojq/claude"
PATH="$tmp/nojq" "$tmp/nojq/bash" "$SRC/bootstrap.sh" > "$tmp/o" 2>&1; expect_rc no-jq 4 "$?"
has no-jq "jq not found" "$tmp/o"
rm "$tmp/nojq/claude"
ln -s "$(command -v jq)" "$tmp/nojq/jq"
PATH="$tmp/nojq" "$tmp/nojq/bash" "$SRC/bootstrap.sh" > "$tmp/o" 2>&1; expect_rc no-claude 4 "$?"
has no-claude "claude not found" "$tmp/o"
[ ! -e "$REL" ] || die no-claude "acted before checking prerequisites"
ok "missing jq or claude exits 4 before doing anything"

B --agents-md > "$tmp/o" 2>&1; expect_rc agents-md 0 "$?"
has agents-md "claude plugin configure cc-plugin-agents-md@builtin --values-stdin" "$tmp/o"
hasnt agents-md "configure" "$CST/log"
ok "--agents-md only prints the opt-in"

B --with-qa-tools > "$tmp/o" 2>&1; expect_rc qa-tools 0 "$?"
has qa-tools "npm install -g @playwright/cli@0.1.22" "$BINLOG"
has qa-tools "playwright-cli install-browser chromium" "$BINLOG"
has qa-tools "axe-core@4.10.3" "$BINLOG"
ok "--with-qa-tools installs the pinned playwright-cli, Chromium and axe-core"
