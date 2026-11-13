#!/usr/bin/env bash
# shellcheck source=tests/bootstrap/_lib.sh
. "$(dirname "$0")/_lib.sh"

make_src v2.0.0
mkdir -p "$HOME/.claude"
printf '{"model":"opus"}\n' > "$SET"
before=$(tree_sum "$HOME")
B --dry-run --verify-skill --with-qa-tools > "$tmp/out1" 2>&1; rc=$?
expect_rc dry-install 0 "$rc"
[ "$(tree_sum "$HOME")" = "$before" ] || die dry-install "HOME changed"
if grep -vE '^plugin (marketplace )?list( |$)' "$CST/log" | grep -q .; then die dry-install "mutating claude call: $(cat "$CST/log")"; fi
if grep -v -- ' --version$' "$BINLOG" | grep -q .; then die dry-install "ran $(cat "$BINLOG")"; fi
has dry-install "(dry-run) \$ git clone" "$tmp/out1"
has dry-install "(dry-run) \$ claude plugin install sdw@sdw-local --scope user" "$tmp/out1"
has dry-install "(dry-run) \$ npm install -g @playwright/cli@" "$tmp/out1"
has dry-install "(dry-run) write" "$tmp/out1"
ok "install --dry-run prints every action and changes nothing"

B --verify-skill > /dev/null 2>&1 || die setup "install failed"
before=$(tree_sum "$HOME"); calls=$(wc -l < "$CST/log")
B --uninstall --dry-run > "$tmp/out2" 2>&1; rc=$?
expect_rc dry-uninstall 0 "$rc"
[ "$(tree_sum "$HOME")" = "$before" ] || die dry-uninstall "HOME changed"
if tail -n +"$((calls + 1))" "$CST/log" | grep -vE '^plugin (marketplace )?list( |$)' | grep -q .; then die dry-uninstall "mutating claude call"; fi
has dry-uninstall "(dry-run) remove dir" "$tmp/out2"
ok "uninstall --dry-run changes nothing"
