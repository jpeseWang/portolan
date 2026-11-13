#!/usr/bin/env bash
# --migrate against the real plugin/bin/sdw-exclude and sdw-doctor, not stubs.
# shellcheck source=tests/bootstrap/_lib.sh
. "$(dirname "$0")/_lib.sh"

make_src v2.0.0
rm -rf "$SRC/plugin"
cp -R "$ROOT/plugin" "$SRC/plugin"

P="$tmp/legacy repo"
mkdir -p "$P"
(cd "$P" && git init -q . && git commit -q --allow-empty -m base) || die setup "git"
printf '\n# Solo Dev Workflow — never commit these\nAGENTS.md\nCLAUDE.md\nTASKS.md\n.claude/\n\nkeep-me\n' >> "$P/.git/info/exclude"

B --migrate "$P" > "$tmp/out" 2>&1; rc=$?
expect_rc migrate 0 "$rc"
ex="$P/.git/info/exclude"
hasnt v1-block "Solo Dev Workflow" "$ex"
has sdw-block "# >>> sdw >>>" "$ex"
has sdw-block ".sdw/" "$ex"
has foreign "keep-me" "$ex"
has doctor "step 6: sdw-doctor" "$tmp/out"
ok "real sdw-exclude swaps the v1 block for the sdw block and keeps foreign lines"

cp "$ex" "$tmp/ex1"
B --migrate "$P" > "$tmp/out2" 2>&1; rc=$?
expect_rc rerun 0 "$rc"
cmp -s "$ex" "$tmp/ex1" || die rerun "exclude changed on a second migrate"
ok "second migrate leaves the exclude file alone"
