#!/usr/bin/env bash
# review-pr payload.py: inline only on new-side diff lines, selection, event, input errors.
. "$(dirname "$0")/_lib.sh"
PAY="$PLUGIN/skills/review-pr/payload.py"

r="$tmp/repo"
new_repo "$r"
mkdir -p "$r/src" "$r/my dir"
seq 1 30 | sed 's/^/line /' >"$r/src/a.ts"
echo old >"$r/my dir/b c.ts"
echo gone >"$r/src/gone.ts"
commit_all "$r" base
mb=$(cd "$r" && git rev-parse HEAD)
sed -i.bak 's/^line 15$/line fifteen/' "$r/src/a.ts" && rm "$r/src/a.ts.bak"
printf 'new\nnewer\n' >"$r/my dir/b c.ts"
rm "$r/src/gone.ts"
commit_all "$r" change
sha=$(cd "$r" && git rev-parse HEAD)
(cd "$r" && git diff "$mb" HEAD) >"$tmp/diff.patch"

cat >"$tmp/drafts.json" <<'EOF'
[{"n":1,"path":"src/a.ts","line":15,"severity":"S2","body":"Off by one."},
 {"n":2,"path":"src/a.ts","line":12,"severity":"S3","body":"Context line, still in the hunk."},
 {"n":3,"path":"src/a.ts","line":2,"severity":"S2","body":"Outside every hunk."},
 {"n":4,"path":"my dir/b c.ts","line":2,"severity":"S4","body":"Spaces in path."},
 {"n":5,"path":"src/gone.ts","line":1,"severity":"S1","body":"Deleted file."},
 {"n":6,"path":"README.md","severity":"S3","body":"File-level note."}]
EOF

expect_rc check 0 python3 "$PAY" --check "$tmp/drafts.json" "$tmp/diff.patch"
want="1 inline src/a.ts:15
2 inline src/a.ts:12
3 body src/a.ts:2
4 inline my dir/b c.ts:2
5 body src/gone.ts:1
6 body README.md:-"
[ "$out" = "$want" ] || fail check "got: $out"
ok check

echo "Adds a clamp." >"$tmp/summary.md"
expect_rc select 0 python3 "$PAY" "$tmp/drafts.json" "$tmp/diff.patch" --sha "$sha" --select 1,3,6 --summary-file "$tmp/summary.md"
printf '%s' "$out" >"$tmp/p.json"
python3 - "$tmp/p.json" "$sha" <<'EOF' || fail select "$out"
import json, sys
p = json.load(open(sys.argv[1]))
assert p["event"] == "COMMENT" and p["commit_id"] == sys.argv[2], p
assert p["comments"] == [{"path": "src/a.ts", "line": 15, "side": "RIGHT", "body": "**Must fix:** Off by one."}], p["comments"]
assert p["body"].startswith("Adds a clamp."), p["body"]
assert "**src/a.ts:2** — **Must fix:** Outside every hunk." in p["body"], p["body"]
assert "**README.md** — **Suggestion:** File-level note." in p["body"], p["body"]
assert "Context line" not in json.dumps(p), "unselected draft leaked"
EOF
ok select

expect_rc all-body 0 python3 "$PAY" "$tmp/drafts.json" "$tmp/diff.patch" --sha "$sha" --select all --all-body
printf '%s' "$out" | python3 -c 'import json,sys; p=json.load(sys.stdin); assert p["comments"]==[] and p["body"].count("**")>=12, p' \
  || fail all-body "$out"
ok all-body

expect_rc select-missing 2 python3 "$PAY" "$tmp/drafts.json" "$tmp/diff.patch" --sha "$sha" --select 9; ok select-missing
expect_rc bad-sha 2 python3 "$PAY" "$tmp/drafts.json" "$tmp/diff.patch" --sha abc --select all; ok bad-sha
expect_rc no-select 2 python3 "$PAY" "$tmp/drafts.json" "$tmp/diff.patch" --sha "$sha"; ok no-select
echo '{"n":1}' >"$tmp/bad.json"
expect_rc bad-drafts 2 python3 "$PAY" --check "$tmp/bad.json" "$tmp/diff.patch"; ok bad-drafts
expect_rc help 0 python3 "$PAY" -h; ok help
echo "PASS test-review-pr-payload"
