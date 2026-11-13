#!/usr/bin/env bash
# A symlinked ~/.claude/settings.json (dotfiles) is merged through the link, never replaced.
# shellcheck source=tests/bootstrap/_lib.sh
. "$(dirname "$0")/_lib.sh"

make_src v2.0.0
mkdir -p "$HOME/.claude" "$HOME/dotfiles"
printf '{"model":"opus"}\n' > "$HOME/dotfiles/settings.json"
ln -s ../dotfiles/settings.json "$SET"
printf '%s' "$REL" > "$CST/market"; touch "$CST/plugin"

B > "$tmp/out" 2>&1; rc=$?
expect_rc install 0 "$rc"
[ -L "$SET" ] || die symlink "settings.json is no longer a symlink"
jtrue symlink '.model == "opus" and .attribution.pr == ""' "$HOME/dotfiles/settings.json"
ok "symlinked settings.json merged through the link"
