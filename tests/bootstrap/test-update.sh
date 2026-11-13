#!/usr/bin/env bash
# shellcheck source=tests/bootstrap/_lib.sh
. "$(dirname "$0")/_lib.sh"

make_src v2.0.2 v2.0.9
B > "$tmp/out1" 2>&1 || die setup "install failed: $(tail -3 "$tmp/out1")"
[ "$(rel_tag)" = v2.0.9 ] || die setup "clone at $(rel_tag)"

(cd "$SRC" && git commit -q --allow-empty -m next && git tag v2.0.10)
B --update --dry-run > "$tmp/out2" 2>&1; rc=$?
expect_rc dry-update 0 "$rc"
[ "$(rel_tag)" = v2.0.9 ] || die dry-update "dry run moved the clone to $(rel_tag)"
has dry-update "(dry-run) \$ (cd" "$tmp/out2"
ok "update --dry-run prints the checkout and leaves the clone"

B --update > "$tmp/out3" 2>&1; rc=$?
expect_rc update 0 "$rc"
[ "$(rel_tag)" = v2.0.10 ] || die update "clone at '$(rel_tag)', expected v2.0.10 (numeric, not string, order)"
has update "/reload-plugins" "$tmp/out3"
ok "update checks out the numerically newest tag"

touch "$REL/stray file"
B --update > "$tmp/out4" 2>&1; rc=$?
expect_rc dirty 1 "$rc"
has dirty "local changes" "$tmp/out4"
ok "a dirty release clone is refused with exit 1"
