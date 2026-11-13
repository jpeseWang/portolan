#!/usr/bin/env bash
# sdw-evidence: entries, working-tree hash, validity vs HEAD (covered paths, doc filter), stamps, ship check, pr-lines.
. "$(dirname "$0")/_lib.sh"
sedi() { sed -i.bak "$1" "$2" && rm -f "$2.bak"; }

cp -R "$PLUGIN" "$tmp/plug"
printf '#!/bin/sh\n[ "$1" = --test-paths ] && grep -E "\\\\.test\\\\." ; exit 0\n' > "$tmp/plug/bin/sdw-tamper"
chmod +x "$tmp/plug/bin/sdw-tamper"
export PATH="$tmp/plug/bin:$PATH"

A="$tmp/app"
mkrepo "$A"
mkdir -p "$A/.sdw"
cd "$A" || exit 1
sdw-exclude >/dev/null || fail setup exclude
printf 'app:src | full: true\n' > .sdw/gates
git checkout -q -b feat
echo 'export const a = 2' > src/a.ts
echo 'test("a", () => {})' > src/a.test.ts
E=.sdw/work/feat/evidence.jsonl

expect_rc 2 "add rejects unknown kind" sdw-evidence add --kind qa --key k --result pass
expect_rc 2 "add needs a value" sdw-evidence add --kind gate:full --key
expect_rc 0 "full gate writes evidence" sdw-gate --full
[ "$(grep -c . "$E")" = 1 ] || fail "one entry" "$(cat "$E")"
python3 -c 'import json,sys; e=json.loads(open(sys.argv[1]).readline()); assert e["v"]==1 and e["kind"]=="gate:full" and e["key"]=="app:src" and e["repo"]=="app" and e["paths"]==["src"] and len(e["tree"])==40 and e["result"]=="pass" and e["detail"]=="true", e' "$E" || fail "entry shape" "$(cat "$E")"
ok "entry shape"
expect_rc 0 "list before commit" sdw-evidence list
case "$OUT" in "invalid:changed:src/"*) ;; *) fail "uncommitted is invalid for HEAD" "$OUT" ;; esac
expect_rc 0 "list --valid-for WORKTREE" sdw-evidence list --valid-for WORKTREE
case "$OUT" in "valid gate:full app:src pass "*) ;; *) fail "valid for worktree" "$OUT" ;; esac
git add -A && git commit -qm feat
expect_rc 0 "list after committing exactly that state" sdw-evidence list
case "$OUT" in "valid gate:full app:src pass "*) ;; *) fail "tree equals HEAD^{tree}" "$OUT" ;; esac
git status --porcelain | grep -q .sdw && fail "exclude" ".sdw tracked"

expect_rc 0 "check TRIVIAL" sdw-evidence check --lane TRIVIAL
printf '%s\n' "$OUT" | grep -qx 'PASS gate app:src: pass' || fail "check gate" "$OUT"
printf '%s\n' "$OUT" | grep -qx 'WARN NOT PROVEN src/a.test.ts: no redcheck' || fail "check not proven" "$OUT"
[ "$(printf '%s\n' "$OUT" | tail -n 1)" = "RESULT: ok" ] || fail "check result" "$OUT"

echo more >> README.md; mkdir -p docs; echo d > docs/n.txt; git add -A; git commit -qm docs
expect_rc 0 "doc change keeps it valid" sdw-evidence list --valid-for HEAD
[ -n "$OUT" ] || fail "doc filter" "entry invalidated"
echo x > other.ts; git add -A; git commit -qm other
expect_rc 0 "uncovered path keeps it valid" sdw-evidence list --valid-for HEAD
[ -n "$OUT" ] || fail "uncovered path" "entry invalidated"

expect_rc 1 "check STANDARD without QA/review" sdw-evidence check --lane STANDARD
printf '%s\n' "$OUT" | grep -q '^FAIL qa: ' && printf '%s\n' "$OUT" | grep -qx 'FAIL review: no review yet; type /sdw:review' || fail "standard needs qa+review" "$OUT"
W=.sdw/work/feat
ST=$(sdw-evidence stamp)
RUN=$(printf '%s' "$ST" | python3 -c 'import json,re,sys; print(json.loads(re.search(r"\{.*\}", sys.stdin.read()).group(0))["repos"][0]["tree"][:7])')
printf '%s\nVerdict: READY\n## NOT RUN\nnone\n## Test data created\nnone\n## Questions for PO\nnone\n' "$ST" > "$W/qa-report.md"
printf '%s\nOpen: S1 0, S2 0, S3 2, S4 0\n' "$ST" > "$W/review.md"
printf '%s\n## Code quality\n- [S3] src/a.ts:1 — naming\n' "$ST" > "$W/review-raw.md"
head -n 1 "$W/qa-report.md" | grep -Eq '^<!-- sdw-stamp \{"repos":\[\{"repo":"app","head":"[0-9a-f]{40}","tree":"[0-9a-f]{40}"\}\],"paths":\["\."\],"ts":"[^"]+"\} -->$' || fail "stamp format" "$(head -n 1 "$W/qa-report.md")"
ok "stamp format"
printf '# Plan: x\nLane: STANDARD — y\n| ID | Given/When/Then | Source | Status | Evidence |\n|---|---|---|---|---|\n| AC-1 | a | ticket AC | TODO | |\n' > "$W/plan.md"
H='| ID | Source | Technique | Pri | Preconditions & data | Steps | Expected (with source) | Layer | Automate | Test name | Result | Evidence | Run |'
row() { printf '| %s | %s | %s | %s | anon | %s | %s | api | no | | %s | %s | %s |\n' "$@"; }
design() { { echo "$H"; echo '|---|'; row TC-01 AC-1 partition P1 '1. GET /a' '1. 200 (AC-1)' '' '' ''; row TC-02 'spec 2' partition P2 '1. GET /b' '1. 200 (spec 2)' '' '' ''; } > "$W/.cases.design.md"; }
design
{ echo "$H"; echo '|---|'; row TC-01 AC-1 partition P1 '1. GET /a' '1. 200 (AC-1)' PASS '200 ok' "$RUN"; row TC-02 'spec 2' partition P2 '1. GET /b' '1. 200 (spec 2)' PASS '200 ok' "$RUN"; } > "$W/cases.md"
expect_rc 0 "qa-verdict READY" sdw-evidence qa-verdict --write
[ "$(printf '%s\n' "$OUT" | head -n 1)" = "Verdict: READY" ] || fail "qa-verdict" "$OUT"
expect_rc 0 "check STANDARD with valid QA and review" sdw-evidence check
printf 'Title: t\nSeverity: S2\nStatus: open\n' > "$W/bugs-tmp"; mkdir -p "$W/bugs"; mv "$W/bugs-tmp" "$W/bugs/BUG-01.md"
expect_rc 1 "open S2 bug blocks" sdw-evidence check
printf '%s\n' "$OUT" | grep -qx 'FAIL bug BUG-01.md: open S2' || fail "bug line" "$OUT"
printf 'Title: t\nSeverity: S2\nStatus: fixed\n' > "$W/bugs/BUG-01.md"
expect_rc 1 "fixed S2 without a retest blocks" sdw-evidence check
printf '%s\n' "$OUT" | grep -q '^FAIL bug BUG-01.md: fixed S2' || fail "fixed bug" "$OUT"
printf '%s\n' "$OUT" | grep -q '^FAIL qa: NOT READY.*type /sdw:qa retest' || fail "retest pointer" "$OUT"
printf 'Title: t\nSeverity: S2\nStatus: wontfix\n' > "$W/bugs/BUG-01.md"
expect_rc 1 "wontfix without Decided-by blocks" sdw-evidence check
printf 'Title: t\nSeverity: S2\nStatus: wontfix\nDecided-by: PO in standup\n' > "$W/bugs/BUG-01.md"
expect_rc 0 "wontfix with Decided-by passes" sdw-evidence check
printf 'Title: t\nSeverity: S2\nStatus: preexisting\n## Regression vs base\nyes — new\n' > "$W/bugs/BUG-01.md"
expect_rc 1 "unknown status blocks" sdw-evidence check
printf '%s\n' "$OUT" | grep -qx 'FAIL bug BUG-01.md: preexisting (unknown status) S2' || fail "unknown status" "$OUT"
printf 'Title: t\nSeverity: S2\nStatus: verified\n' > "$W/bugs/BUG-01.md"
expect_rc 0 "verified passes" sdw-evidence check
pre() { printf 'Title: t\nSeverity: S1\nStatus: pre-existing\nSource: %s\n## Regression vs base\n%s\n## Server log\n' "$1" "$2" > "$W/bugs/BUG-01.md"; }
pre 'consistent with /orders' 'no — shots/base-orders.json shows it'
expect_rc 1 "pre-existing citing a missing base capture blocks" sdw-evidence check
printf '%s\n' "$OUT" | grep -qx 'FAIL bug BUG-01.md: pre-existing unproven S1' || fail "missing base file" "$OUT"
mkdir -p "$W/shots"; echo '{}' > "$W/shots/base-orders.json"
expect_rc 0 "proven pre-existing S1 does not block" sdw-evidence check
printf '%s\n' "$OUT" | grep -qx 'WARN bug BUG-01.md: pre-existing S1 (not blocking)' || fail "pre-existing warn" "$OUT"
expect_rc 0 "qa-verdict lists a pre-existing bug apart" sdw-evidence qa-verdict
printf '%s\n' "$OUT" | head -n 1 | grep -qx 'Verdict: READY' && printf '%s\n' "$OUT" | grep -qx -- '- pre-existing: bug BUG-01.md S1' || fail "pre-existing line" "$OUT"
pre 'consistent with /orders' 'unknown — no base run'
expect_rc 1 "pre-existing without base evidence blocks" sdw-evidence check
printf '%s\n' "$OUT" | grep -qx 'FAIL bug BUG-01.md: pre-existing unproven S1' || fail "unproven pre-existing" "$OUT"
pre 'consistent with /orders' 'no base run was done'
expect_rc 1 "pre-existing without a base file blocks" sdw-evidence check
for src in 'AC-1' 'ac-1' 'AC 1' 'AC1'; do
  pre "$src" 'no — shots/base-orders.json shows it'
  expect_rc 1 "pre-existing bug naming $src blocks" sdw-evidence check
done
rm -r "$W/bugs" "$W/shots"
cp "$W/review-raw.md" "$tmp/raw.ok"
printf '%s\n## Code quality\n- none\n## Pre-existing\n- src/old.ts:9 — no rate limit\n## Not reviewed\n- none\n' "$ST" > "$W/review-raw.md"
expect_rc 0 "untagged Pre-existing items are not open" sdw-evidence check
printf '%s\n## Pre-existing\n- [S1] src/a.ts:1 — SQL built by concatenation\n' "$ST" > "$W/review-raw.md"
expect_rc 1 "a tagged S1 under Pre-existing still counts" sdw-evidence check
printf '%s\n' "$OUT" | grep -q '^FAIL review: open S1 1, S2 0' || fail "tagged Pre-existing" "$OUT"
cp "$tmp/raw.ok" "$W/review-raw.md"

# The verdict is computed, not read.
v() { sdw-evidence qa-verdict > "$tmp/v.out" 2>&1; VRC=$?; VOUT=$(cat "$tmp/v.out"); }
blocks() { v; [ "$VRC" = 1 ] && printf '%s\n' "$VOUT" | grep -q -- "- blocks: $1" || fail "qa-verdict blocks: $1" "$VOUT"; ok "qa-verdict blocks: $1"; }
cp "$W/cases.md" "$tmp/cases.ok"
sedi 's/| PASS | 200 ok | '"$RUN"' |$/| PASS |  | '"$RUN"' |/' "$W/cases.md"; blocks 'TC-01 PASS without evidence'
cp "$tmp/cases.ok" "$W/cases.md"; sedi 's/1\. 200 (AC-1)/1. 201 (AC-1)/' "$W/cases.md"; blocks 'TC-01 Expected changed after design'
cp "$tmp/cases.ok" "$W/cases.md"; sedi "s/| $RUN |\$/| abc1234 |/" "$W/cases.md"; blocks 'TC-01 (P1) NOT RUN'
cp "$tmp/cases.ok" "$W/cases.md"; rm "$W/.cases.design.md"; blocks 'no design snapshot'
design
printf '| AC-2 | b | ticket AC | TODO | |\n' >> "$W/plan.md"; blocks 'AC-2 has no passing case'
printf '# Plan: x\nLane: STANDARD — y\n| ID | Given/When/Then | Source | Status | Evidence |\n|---|---|---|---|---|\n| AC-1 | a | ticket AC | TODO | |\n## Surfaces\n- GET /api/orders/{id}\n' > "$W/plan.md"
blocks 'no authz case for GET /api/orders/{id}'
v; printf '%s\n' "$VOUT" | grep -q -- '- blocks: no idor case' || fail "idor" "$VOUT"; ok "qa-verdict needs an idor case for an id route"
cp "$W/cases.md" "$tmp/cases.keep"; cp "$W/.cases.design.md" "$tmp/design.keep"
printf '# Plan: x\nLane: STANDARD — y\n| ID | Given/When/Then | Source | Status | Evidence |\n|---|---|---|---|---|\n| AC-1 | a | ticket AC | TODO | |\n## Surfaces\n- GET /api/items/{id}\n- POST /api/items\n- DELETE /api/items/{id}\n' > "$W/plan.md"
surf() { # surf <row>... : the rows become both the design snapshot and the run cases, all PASS
  { echo "$H"; echo '|---|'; row TC-01 AC-1 partition P1 '1. GET /a' '1. 200 (AC-1)' '' '' ''; for r in "$@"; do eval "row $r '' '' ''"; done; } > "$W/.cases.design.md"
  { echo "$H"; echo '|---|'; row TC-01 AC-1 partition P1 '1. GET /a' '1. 200 (AC-1)' PASS '200 ok' "$RUN"; for r in "$@"; do eval "row $r PASS 'ok' '$RUN'"; done; } > "$W/cases.md"
}
GETS="\"TC-02 'spec 3' authz P1 '1. GET /api/items/1 with no header' '1. 401 (spec 3)'\" \"TC-03 'spec 3' idor P1 '1. GET /api/items/1 as bob' '1. 404 (spec 3)'\""
eval "surf $GETS"
blocks 'no authz case for POST /api/items'
printf '%s\n' "$VOUT" | grep -q -- '- blocks: no authz case for DELETE /api/items/{id}' || fail "method-aware surfaces" "$VOUT"
printf '%s\n' "$VOUT" | grep -q -- 'for GET /api/items/{id}' && fail "GET covered" "$VOUT"
eval "surf $GETS \"TC-04 'spec 3' authz P1 '1. curl -X POST http://localhost:3000/api/items' '1. 401 (spec 3)'\" \"TC-05 'spec 3' authz P1 '1. curl -X DELETE http://localhost:3000/api/items/1' '1. 401 (spec 3)'\" \"TC-06 'spec 3' idor P1 '1. curl -X DELETE http://localhost:3000/api/items/1 as bob' '1. 404 (spec 3)'\""
v; [ "$VRC" = 0 ] || fail "method-aware surfaces pass" "$VOUT"; ok "qa-verdict: each Surfaces endpoint needs a case naming its method and path"
cp "$tmp/cases.keep" "$W/cases.md"; cp "$tmp/design.keep" "$W/.cases.design.md"
printf '# Plan: x\nLane: STANDARD — y\n| ID | Given/When/Then | Source | Status | Evidence |\n|---|---|---|---|---|\n| AC-1 | a | ticket AC | TODO | |\n' > "$W/plan.md"
cp "$W/qa-report.md" "$tmp/rep.ok"
printf '%s\nVerdict: PENDING\n## NOT RUN\nnone\n## Test data created\nnone\n## Questions for PO\n- Q1 rounding of totals — affects AC-1 — blocks: yes\n' "$ST" > "$W/qa-report.md"
blocks 'AC-1 unverifiable'
printf '%s\nVerdict: PENDING\n## NOT RUN\nnone\n## Test data created\nnone\n## Questions for PO\n- Q1 rounding of totals — affects AC-1 — blocks: yes — ask: BE lead\n' "$ST" > "$W/qa-report.md"
blocks 'AC-1 unverifiable'
cp "$tmp/rep.ok" "$W/qa-report.md"
mkdir -p "$W/shots"
printf '{"url":"http://localhost:3000/orders","console":[{"type":"error","text":"boom"}],"pageerror":[],"requests":[]}' > "$W/shots/tc-01.json"
blocks 'new on /orders: console: boom'
printf '{"url":"http://localhost:3999/orders","console":[{"type":"error","text":"boom"}],"pageerror":[],"requests":[]}' > "$W/shots/base-orders.json"
v; [ "$VRC" = 0 ] || fail "pre-existing console error on base" "$VOUT"; ok "qa-verdict: an error the base capture shows is not new"
rm -r "$W/shots"
sedi 's/^Lane: STANDARD/Lane: RISKY/' "$W/plan.md"; blocks 'RISKY needs at least one charter'
sedi 's/^Lane: RISKY.*/Lane: RISKY — bug: authz/' "$W/plan.md"; blocks 'RISKY needs at least one charter'
printf '## Coverage gaps\n- none — branch adds one route only\n' >> "$W/qa-report.md"
v; printf '%s\n' "$VOUT" | grep -q 'coverage gap' && fail "none with a reason" "$VOUT"
cp "$tmp/rep.ok" "$W/qa-report.md"; printf '## Coverage gaps\n- none of the routes are covered\n' >> "$W/qa-report.md"
blocks 'coverage gap: none of the routes are covered'
cp "$tmp/rep.ok" "$W/qa-report.md"
sedi 's/^Lane: RISKY/Lane: STANDARD/' "$W/plan.md"
printf 'Verdict: NOT READY\n' >> "$W/qa-report.md"
v; [ "$VRC" = 0 ] || fail "written verdict ignored" "$VOUT"; ok "qa-verdict ignores the written verdict"
cp "$tmp/rep.ok" "$W/qa-report.md"

echo 'export const a = 3' > src/a.ts; git add -A; git commit -qm change
expect_rc 1 "covered change invalidates gate, QA and review" sdw-evidence check
printf '%s\n' "$OUT" | grep -q '^FAIL gate app:src: pass, invalid:changed:src/a.ts' || fail "gate invalid" "$OUT"
printf '%s\n' "$OUT" | grep -q '^FAIL qa: invalid:changed:src/a.ts' || fail "qa invalid" "$OUT"

printf '{"v":1,"ts":"2099-01-01T00:00:00Z","kind":"gate:full","key":"app:src","repo":"app","head":"x","tree":"%s","paths":["src"],"result":"pass","detail":"","artifacts":[]}\n' 0123456789012345678901234567890123456789 >> "$E"
expect_rc 0 "missing tree" sdw-evidence list
printf '%s\n' "$OUT" | head -n 1 | grep -q '^invalid:tree-missing ' || fail "tree-missing" "$OUT"

sdw-gate --full >/dev/null
expect_rc 0 "redcheck evidence" sdw-evidence add --kind redcheck --key src/a.test.ts --result 'RED(assertion)' --path src/a.test.ts
expect_rc 0 "check proven" sdw-evidence check --lane TRIVIAL
printf '%s\n' "$OUT" | grep -qx 'PASS proven src/a.test.ts: RED(assertion)' || fail "proven" "$OUT"
expect_rc 0 "pr-lines" sdw-evidence pr-lines
printf '%s\n' "$OUT" | grep -qx 'Tests added: 1 (1 proven failing before the change)' || fail "pr-lines tests" "$OUT"
printf '%s\n' "$OUT" | grep -q '^Checks run: `true`' || fail "pr-lines checks" "$OUT"
printf '%s\n' "$OUT" | grep -Eq '[0-9a-f]{40}|BUG-|S[1-4]|TRIVIAL|STANDARD|RISKY' && fail "pr-lines jargon" "$OUT"
[ "$(printf '%s\n' "$OUT" | grep -c .)" -le 8 ] || fail "pr-lines count" "$OUT"
ok "pr-lines: no hashes or workflow jargon"

echo 'test("b", () => {})' > src/b.test.ts; echo 'test("c", () => {})' > src/c.test.ts; git add -A; git commit -qm more-tests
sdw-gate --full >/dev/null
expect_rc 0 "mutation evidence" sdw-evidence add --kind redcheck --key src/b.test.ts --result 'RED(mutation)' --path src/b.test.ts --detail 'mutation abc1234 exit 1: src/b.ts: -x +y'
sdw-evidence add --kind redcheck --key src/c.test.ts --result 'RED(build/import)' --path src/c.test.ts >/dev/null || fail "build evidence" add
expect_rc 0 "check counts a mutation proof" sdw-evidence check --lane TRIVIAL
printf '%s\n' "$OUT" | grep -qx 'PASS proven src/b.test.ts: RED(mutation)' || fail "mutation proven" "$OUT"
printf '%s\n' "$OUT" | grep -qx 'WARN NOT PROVEN src/c.test.ts: RED(build/import)' || fail "build not proven" "$OUT"
expect_rc 0 "pr-lines with a mutation proof" sdw-evidence pr-lines
printf '%s\n' "$OUT" | grep -qx 'Tests added: 3 (1 proven failing before the change, 1 by breaking the new code)' || fail "pr-lines mutation" "$OUT"
sdw-evidence add --kind redcheck --key src/a.test.ts --result GREEN --path src/a.test.ts --detail 'mutation abc1234 exit 0: src/a.ts: -x +y' >/dev/null || fail "surviving mutation" add
sdw-evidence add --kind redcheck --key src/b.test.ts --result 'RED(build/import)' --path src/b.test.ts --detail 'mutation abc1234 exit 1: src/b.ts: -x +(' >/dev/null || fail "build mutation" add
expect_rc 0 "a later mutation does not erase a proof" sdw-evidence check --lane TRIVIAL
printf '%s\n' "$OUT" | grep -qx 'PASS proven src/a.test.ts: RED(assertion)' || fail "proof kept after GREEN mutation" "$OUT"
printf '%s\n' "$OUT" | grep -qx 'PASS proven src/b.test.ts: RED(mutation)' || fail "proof kept after build-break mutation" "$OUT"

# Fullstack stamp covers every repo the branch touched.
F="$tmp/fs"; mkdir -p "$F/.sdw"; mkrepo "$F/web"; mkrepo "$F/api"
(cd "$F/web" && git checkout -q -b feat && echo 1 >> src/a.ts) && (cd "$F/api" && git checkout -q -b feat && echo 1 >> src/a.ts)
expect_rc 0 "fullstack stamp" sh -c "cd \"$F/web\" && sdw-evidence stamp"
printf '%s' "$OUT" | grep -q '"repo":"web"' && printf '%s' "$OUT" | grep -q '"repo":"api"' || fail "fullstack stamp" "$OUT"
expect_rc 3 "not onboarded" sh -c "cd \"$tmp\" && mkdir -p bare && cd bare && sdw-evidence list"
