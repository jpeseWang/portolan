#!/usr/bin/env bash
# session-start: valid JSON, core.md always, project.md cut, state lines, size cap, env-file line, compact extras.
. "$(dirname "$0")/_lib.sh"

ctx() { # ctx <json on stdin> -> prints additionalContext, fails on invalid JSON
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["hookSpecificOutput"]["additionalContext"])'
}
start() { # start <cwd> [source] [session]
  hook_json session-start.sh "{\"cwd\":$(json_str "$1"),\"session_id\":\"${3:-s1}\",\"source\":\"${2:-startup}\"}"
  [ "$RC" = 0 ] || fail "session-start exit" "$RC $ERR"
  CTX=$(printf '%s' "$OUT" | ctx) || fail "session-start JSON" "$OUT"
  LEN=$(printf '%s' "$CTX" | python3 -c 'import sys; print(len(sys.stdin.read()))')
}
CORE=$(cat "$PLUGIN/rules/core.md")

mkrepo "$tmp/plain"
start "$tmp/plain"
[ "$CTX" = "$CORE" ] || fail "not onboarded" "context is not core.md alone"
ok "not onboarded: core.md only, valid JSON, CLAUDE_PROJECT_DIR unset"

printf '' | "$PLUGIN/hooks/session-start.sh" > "$tmp/o.json" 2>/dev/null
ctx < "$tmp/o.json" > /dev/null || fail "empty stdin" "$(cat "$tmp/o.json")"
ok "empty stdin: valid JSON"

P="$tmp/it's proj"
mkdir -p "$P/.sdw/state/stop"
mkrepo "$P/app" feat
printf 'export PATH="$HOME/bin:$PATH"\n' > "$P/.sdw/env.sh"
{ echo '## Apps'; i=0; while [ $i -lt 100 ]; do echo "line $i — $(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60)"; i=$((i + 1)); done; } > "$P/.sdw/project.md"
W="$P/.sdw/work/feat"; mkdir -p "$W/bugs"
printf '# Plan: x\nLane: RISKY — authz\n| ID | Given/When/Then | Source | Status | Evidence |\n| AC-1 | a | ticket AC | PASS | |\n| AC-2 | b | ticket AC | TODO | |\n' > "$W/plan.md"
printf 'Title: t\nSeverity: S1\nStatus: open\n' > "$W/bugs/BUG-01.md"
printf 'Title: t\nSeverity: S2\nStatus: fixed\n' > "$W/bugs/BUG-02.md"
printf '<!-- sdw-stamp {} -->\nOpen: S1 0, S2 2, S3 1, S4 0\n' > "$W/review.md"
printf '<!-- sdw-stamp {} -->\nVerdict: NOT READY\n' > "$W/qa-report.md"
echo old > "$P/.sdw/state/stop/old-session"; touch -t 202001010000 "$P/.sdw/state/stop/old-session"
echo "abc red web:src" > "$P/.sdw/state/stop/s9"
export CLAUDE_ENV_FILE="$tmp/envfile"; : > "$CLAUDE_ENV_FILE"

start "$P/app/src" startup s9
case "$CTX" in "$CORE"*) ok "core.md first and verbatim" ;; *) fail "core first" "missing" ;; esac
proj=$(printf '%s\n' "$CTX" | sed -n '/^## Project (.sdw\/project.md)$/,/^## State$/p' | sed '1d;$d')
plen=$(printf '%s' "$proj" | python3 -c 'import sys; print(len(sys.stdin.read().strip()))')
[ "$plen" -le 2500 ] && [ "$(printf '%s\n' "$proj" | grep -c .)" -le 40 ] || fail "project.md cut" "$plen chars"
ok "project.md cut to <=2,500 chars and 40 lines ($plen)"
for want in 'branch feat (app) · dirty 0' 'lane RISKY · AC 1/2' 'QA NOT READY (stale)' 'open bugs S1 1 S2 0' 'review open S1 0 S2 2' 'gate red at last stop'; do
  printf '%s\n' "$CTX" | grep -qxF "$want" || fail "state line" "missing '$want' in: $(printf '%s\n' "$CTX" | sed -n '/^## State/,$p')"
  ok "state: $want"
done
[ "$LEN" -le 9000 ] || fail "size cap" "$LEN"; ok "total $LEN <= 9000"
q=$(printf '%s' "$P/.sdw/env.sh" | sed "s/'/'\\\\''/g")
[ "$(cat "$CLAUDE_ENV_FILE")" = "source '$q'" ] || fail "env file" "$(cat "$CLAUDE_ENV_FILE")"
( . "$CLAUDE_ENV_FILE" ) || fail "env file sources" "error"
ok "env file gets one quoted source line"
[ ! -f "$P/.sdw/state/stop/old-session" ] && [ -f "$P/.sdw/state/stop/s9" ] || fail "stop cleanup" "old record kept"
ok "state/stop older than 7 days deleted"
printf '%s' "$CTX" | grep -q '^Modified:' && fail "startup extras" "Modified on startup"

P2="$tmp/p2"; mkdir -p "$P2/.sdw"; mkrepo "$P2/app"
python3 -c 'print("\n".join("- fact %d %s" % (i, "x" * 60) for i in range(40)))' > "$P2/.sdw/project.md"
start "$P2/app"
proj=$(printf '%s\n' "$CTX" | awk '/^## /{ s = ($0 ~ /^## Project/); next } s && NF')
[ "$(printf '%s\n' "$proj" | tail -n 1)" = '(project.md truncated; see .sdw/project.md)' ] || fail "truncation note" "$(printf '%s\n' "$proj" | tail -n 2)"
printf '%s\n' "$proj" | sed '$d' | grep -qvE '^- fact [0-9]+ x{60}$' && fail "partial line" "$(printf '%s\n' "$proj" | tail -n 2)"
ok "project.md over 2,500 bytes: whole lines plus a truncation note"

i=0; while [ $i -lt 30 ]; do echo x > "$P/app/src/f$i.ts"; i=$((i + 1)); done
printf 'app:src | fast: true\n' > "$P/.sdw/gates"
start "$P/app" compact
n=$(printf '%s\n' "$CTX" | sed -n '/^Modified:$/,/^Gates:$/p' | grep -c '^app:')
[ "$n" = 20 ] || fail "compact Modified" "$n lines"
printf '%s\n' "$CTX" | grep -q '^Gates:' || fail "compact Gates" "missing"
[ "$LEN" -le 9000 ] || fail "compact size" "$LEN"
ok "compact: Modified <=20, Gates, total $LEN"

unset CLAUDE_ENV_FILE
cp -R "$PLUGIN" "$tmp/plug"
python3 -c 'print("# big core\n" + ("rule line that is long enough to matter. " * 150))' > "$tmp/plug/rules/core.md"
BIG=$(cat "$tmp/plug/rules/core.md")
CLAUDE_PLUGIN_ROOT="$tmp/plug" start "$P/app" compact s9
[ "$LEN" -le 9000 ] || fail "over budget" "$LEN"
case "$CTX" in "$BIG"*) ;; *) fail "over budget" "core.md truncated" ;; esac
printf '%s' "$CTX" | grep -q '^Modified:' && fail "over budget" "compact extras kept"
printf '%s\n' "$CTX" | grep -qxF 'lane RISKY · AC 1/2' || fail "over budget" "state dropped"
ok "over budget: extras dropped, project cut, core intact, state kept ($LEN)"
