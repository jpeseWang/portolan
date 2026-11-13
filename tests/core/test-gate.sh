#!/usr/bin/env bash
# sdw-gate: grammar, literal prefix matching, deps (one level), doc filter, fingerprint, fast/full, baseline.
. "$(dirname "$0")/_lib.sh"

W="$tmp/work space"
mkdir -p "$W/.sdw"
mkrepo "$W/web"
mkrepo "$W/api"
mkdir -p "$W/web/apps/site" "$W/web/packages/ui" "$W/web/srcAx"
(cd "$W/web" && touch apps/site/i.ts packages/ui/b.ts srcAx/c.ts && git add -A && git commit -qm more) || fail setup web
G="$W/.sdw/gates"
cat > "$G" <<'EOF'
# comment line

web:apps/site | fast: echo site-fast | full: echo site-full
web:packages/ui | fast: echo ui-fast
web:src.x | fast: echo regex-would-match
deps: web:packages/ui -> web:apps/site
deps: web:apps/site -> api:.
api:. | fast: test -f marker && echo api-ok | full: echo api-full
EOF
cd "$W/web" || exit 1

expect_rc 0 "list" sdw-gate --list
[ "$(printf '%s\n' "$OUT" | paste -sd' ' -)" = "web:apps/site web:packages/ui web:src.x api:." ] || fail list "$OUT"
expect_rc 0 "fingerprint empty on clean tree" sdw-gate --fingerprint
[ -z "$OUT" ] || fail "fingerprint empty" "$OUT"
echo doc >> README.md; mkdir -p docs; echo x > docs/x.txt
expect_rc 0 "doc-only change has no fingerprint" sdw-gate --fingerprint
[ -z "$OUT" ] || fail "doc-only fingerprint" "$OUT"
expect_rc 0 "dry-run for doc-only change" sdw-gate --dry-run
[ -z "$OUT" ] || fail "doc-only dry-run" "$OUT"

echo 1 >> srcAx/c.ts
expect_rc 0 "prefix is literal, not a regex" sdw-gate --dry-run
[ -z "$OUT" ] || fail "literal prefix" "$OUT"
git checkout -q -- srcAx/c.ts

echo 1 >> packages/ui/b.ts
expect_rc 0 "deps one level, not transitive" sdw-gate --dry-run
keys=$(printf '%s\n' "$OUT" | cut -f1 | paste -sd' ' -)
[ "$keys" = "web:apps/site web:packages/ui" ] || fail "deps" "keys: $keys"
dir=$(printf '%s\n' "$OUT" | awk -F'\t' '$1 == "web:apps/site" { print $2 }')
[ "$dir" = "$W/web/apps/site" ] || fail "gate dir" "$dir"
ok "gate dir is <checkout>/<prefix>"
FP1=$(sdw-gate --fingerprint)
[ -n "$FP1" ] || fail fingerprint "empty with a change"
[ "$(sdw-gate --fingerprint)" = "$FP1" ] || fail fingerprint "not stable"
ok "fingerprint stable"
echo 2 >> packages/ui/b.ts
[ "$(sdw-gate --fingerprint)" != "$FP1" ] || fail fingerprint "content change not seen"
ok "fingerprint follows content"

expect_rc 1 "--check stale before a run" sdw-gate --check
expect_rc 0 "fast green" sdw-gate --fast
[ "$OUT" = "green web:apps/site,web:packages/ui" ] || fail "fast green output" "$OUT"
expect_rc 0 "--check fresh after green" sdw-gate --check
case "$OUT" in "fresh "*) ;; *) fail "--check output" "$OUT" ;; esac

echo 1 >> apps/site/i.ts
expect_rc 0 "deps selects api:. in the other repo" sdw-gate --dry-run
printf '%s\n' "$OUT" | grep -q "^api:.	$W/api	" || fail "cross-repo deps" "$OUT"
expect_rc 1 "fast red" sdw-gate --fast
printf '%s\n' "$OUT" | grep -q "^--- api:. ($W/api): test -f marker" || fail "red output" "$OUT"
touch "$W/api/marker"
expect_rc 0 "fast green after fix (untracked file counts)" sdw-gate --fast
rm "$W/api/marker"

# Timeout and missing gate dir.
printf 'web:apps/site | fast: sleep 5\n' > "$G"
SDW_GATE_TIMEOUT=1 expect_rc 1 "timeout is red" sdw-gate --fast
printf '%s\n' "$OUT" | grep -q 'timeout' || fail timeout "$OUT"
printf 'api:missing/dir | fast: true\n' > "$G"
mkdir -p "$W/api/missing/dir"; echo x > "$W/api/missing/dir/a.ts"
(cd "$W/api" && git add missing && git commit -qm m) || fail setup commit
rm -rf "$W/api/missing"
expect_rc 1 "missing gate dir is red, named" sdw-gate --fast
printf '%s\n' "$OUT" | grep -q "gate dir missing: $W/api/missing/dir" || fail "missing dir" "$OUT"
(cd "$W/api" && git reset -q --hard HEAD~1)

# Parse errors.
printf 'web:apps/site | fast: true\nweb apps | fast: x\n' > "$G"
expect_rc 4 "parse error" sdw-gate --list
printf '%s' "$OUT" | grep -q 'gates:2' || fail "parse error line number" "$OUT"
printf 'web:apps/site | full: a | fast: b\n' > "$G"
expect_rc 4 "separators out of order" sdw-gate --list
printf 'web:/abs | fast: a\n' > "$G"
expect_rc 4 "leading slash prefix" sdw-gate --list
printf 'deps: web:a\n' > "$G"
expect_rc 4 "deps without arrow" sdw-gate --list
printf 'web:. | fast: echo a | b && echo c\n' > "$G"
expect_rc 0 "command may contain |" sdw-gate --dry-run
printf '%s' "$OUT" | grep -q 'echo a | b && echo c' || fail "pipe in command" "$OUT"
rm "$G"
expect_rc 4 "gates file missing" sdw-gate --fast

# Baseline: pre-existing diagnostics pass, new ones fail.
printf 'web:. | fast: cat diag.txt; exit 1\n' > "$G"
printf "src/a.ts(3,5): error TS2322: Type 'x' is not assignable.\n" > diag.txt
expect_rc 1 "red without baseline" sdw-gate --fast
expect_rc 0 "write baseline" sdw-gate --write-baseline web:.
[ -f "$W/.sdw/state/gate-baseline/web--_all.txt" ] || fail baseline "file name"
grep -q "^src/a.ts: error TS2322" "$W/.sdw/state/gate-baseline/web--_all.txt" || fail baseline "normalised: $(cat "$W/.sdw/state/gate-baseline/web--_all.txt")"
printf "src/a.ts(9,1): error TS2322: Type 'x' is not assignable.\n" > diag.txt
expect_rc 0 "pre-existing diagnostic moved lines: pass" sdw-gate --fast
printf "src/a.ts(9,1): error TS2322: Type 'x' is not assignable.\nsrc/b.ts(1,1): error TS2304: Cannot find name 'y'.\n" > diag.txt
expect_rc 1 "new diagnostic: red" sdw-gate --fast
printf 'boom\n' > diag.txt
expect_rc 1 "no recognised diagnostic: red" sdw-gate --fast
# A symlinked node_modules prints its real path, outside this checkout.
printf "/elsewhere/main-co/node_modules/@types/x/index.d.ts(1,1): error TS2300: Duplicate identifier 'y'.\n" > diag.txt
expect_rc 0 "write baseline (foreign node_modules path)" sdw-gate --write-baseline web:.
grep -qx "node_modules/@types/x/index.d.ts: error TS2300: Duplicate identifier 'y'." "$W/.sdw/state/gate-baseline/web--_all.txt" || fail baseline "node_modules prefix: $(cat "$W/.sdw/state/gate-baseline/web--_all.txt")"
printf "node_modules/@types/x/index.d.ts(4,2): error TS2300: Duplicate identifier 'y'.\n" > diag.txt
expect_rc 0 "same diagnostic via in-checkout node_modules: pass" sdw-gate --fast

# Full: evidence per key with covered paths.
printf 'web:apps/site | full: echo site-full\nweb:packages/ui | full: exit 3\ndeps: web:packages/ui -> web:apps/site\n' > "$G"
expect_rc 1 "full with a red key" sdw-gate --full
E="$W/.sdw/work/main/evidence.jsonl"
[ -f "$E" ] || fail "full evidence" "no file"
grep -q '"key":"web:apps/site".*"paths":\["apps/site","packages/ui"\].*"result":"pass"' "$E" || fail "full evidence site" "$(cat "$E")"
grep -q '"key":"web:packages/ui".*"result":"fail"' "$E" || fail "full evidence ui" "$(cat "$E")"
ok "full writes one entry per key with covered paths"
expect_rc 0 "full --keys" sdw-gate --full --keys web:apps/site
expect_rc 2 "full --keys unknown" sdw-gate --full --keys web:nope

# Unborn HEAD and a sibling worktree.
mkdir -p "$W/fresh"; (cd "$W/fresh" && git init -q . && echo a > a.ts) || fail setup fresh
printf 'fresh:. | fast: echo fresh-ok\n' > "$G"
expect_rc 0 "unborn HEAD repo gates its files" sh -c "cd \"$W/fresh\" && sdw-gate --dry-run"
printf '%s' "$OUT" | grep -q '^fresh:.' || fail "unborn" "$OUT"
rm -rf "$W/fresh"
git checkout -q -- . 2>/dev/null; git clean -qfd 2>/dev/null
(git worktree add -b wt-branch "$W/web-wt" main >/dev/null 2>&1) || fail setup worktree
printf 'web:apps/site | fast: pwd -P\n' > "$G"
echo dirty >> apps/site/i.ts
echo wt >> "$W/web-wt/apps/site/i.ts"
expect_rc 0 "worktree: runs in the worktree, not the main checkout" sh -c "cd \"$W/web-wt\" && sdw-gate --dry-run"
[ "$(printf '%s\n' "$OUT" | cut -f2 | paste -sd' ' -)" = "$W/web-wt/apps/site" ] || fail "worktree gate dir" "$OUT"
expect_rc 0 "help" sdw-gate -h
expect_rc 2 "no mode" sdw-gate

# Paths git would C-quote (", tab, backslash) are fingerprinted by content and selected by prefix.
cd "$W/api" || exit 1
printf 'api:. | fast: true\n' > "$G"
q='quo"te.ts' t=$(printf 'tab\there.ts')
echo a > "$q"; echo a > "$t"
expect_rc 0 "quoted paths in the change set" sdw-gate --changes
printf '%s\n' "$OUT" | grep -qF "$(printf '\tapi\tquo"te.ts')" || fail "quoted path" "$OUT"
F1=$(sdw-gate --fingerprint); echo b >> "$q"; F2=$(sdw-gate --fingerprint); echo b >> "$t"; F3=$(sdw-gate --fingerprint)
[ "$F1" != "$F2" ] && [ "$F2" != "$F3" ] || fail "quoted path fingerprint" "$F1 $F2 $F3"
ok "fingerprint follows quoted and tab paths"

# From the project dir a linked worktree is not gated: the gate says so instead of a bare green.
(cd "$W/api" && git worktree add -b feat/z "$W/api-z" HEAD >/dev/null 2>&1) || fail setup "linked worktree"
OUT=$(cd "$W" && sdw-gate --fast 2>&1); true
case "$OUT" in *"api has 1 linked worktree(s) not gated from here"*) ok "projdir run names the ungated worktree" ;; *) fail "ungated worktree note" "$OUT" ;; esac
OUT=$(cd "$W/api-z" && sdw-gate --fast 2>&1); true
case "$OUT" in *"not gated from here"*) fail "no note inside a checkout" "$OUT" ;; *) ok "no note inside a checkout" ;; esac
