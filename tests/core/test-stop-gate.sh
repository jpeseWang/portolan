#!/usr/bin/env bash
# stop-gate: doc-only skip, per-repo/prefix gates, fingerprint block/pass/retry-let-go, question-only turn on red.
. "$(dirname "$0")/_lib.sh"

W="$tmp/work space"
mkdir -p "$W/.sdw"
mkrepo "$W/web"
mkrepo "$W/api"
R="$tmp/ran"; mkdir -p "$R"
cat > "$W/.sdw/gates" <<EOF
web:src | fast: touch "$R/web"; test ! -f ../fail-web
api:. | fast: touch "$R/api"; test ! -f fail-api
EOF

stop() { # stop <cwd> <session> [active]
  hook_json stop-gate.sh "{\"cwd\":$(json_str "$1"),\"session_id\":\"$2\",\"stop_hook_active\":${3:-false}}"
}
ran() { ls "$R" | paste -sd' ' -; }
clear_ran() { rm -f "$R"/*; }

mkrepo "$tmp/plain"
echo x >> "$tmp/plain/src/a.ts"
stop "$tmp/plain" s0
[ "$RC" = 0 ] && [ -z "$OUT$ERR" ] || fail "not onboarded" "rc $RC out $OUT err $ERR"; ok "not onboarded: silent exit 0"

stop "$W/web" s1
[ "$RC" = 0 ] && [ -z "$(ran)" ] || fail "clean tree" "rc $RC ran $(ran)"; ok "clean tree: nothing runs"

echo doc >> "$W/web/README.md"; mkdir -p "$W/web/docs"; echo d > "$W/web/docs/a.ts"
stop "$W/web" s1
[ "$RC" = 0 ] && [ -z "$(ran)" ] || fail "doc-only" "rc $RC ran $(ran)"; ok "doc-only change: nothing runs"

echo 1 >> "$W/api/src/a.ts"
stop "$W/web" s1
[ "$RC" = 0 ] && [ "$(ran)" = api ] || fail "per-repo gate" "rc $RC ran $(ran)"; ok "change in api runs only api:."
clear_ran
stop "$W/web" s1
[ "$RC" = 0 ] && [ -z "$(ran)" ] || fail "unchanged fingerprint" "ran $(ran)"; ok "same fingerprint: no rerun"

touch "$W/web/fail-web"; echo 1 >> "$W/web/src/a.ts"
stop "$W" s1
[ "$RC" = 2 ] || fail "red blocks" "rc $RC err $ERR"
printf '%s' "$ERR" | grep -q 'The fast gate failed' && printf '%s' "$ERR" | grep -q -- '--- web:src' || fail "red message" "$ERR"
printf '%s' "$ERR" | grep -q -- '--- api:.' && fail "red message" "api listed though green"
ok "red fast gate from the non-git parent blocks with exit 2"
[ "$(ran)" = "api web" ] || fail "both gates ran" "$(ran)"
clear_ran

stop "$W" s1
[ "$RC" = 0 ] && [ -z "$(ran)" ] && [ -z "$OUT" ] || fail "question-only turn" "rc $RC ran $(ran)"; ok "question-only turn on a red tree passes"

stop "$W" s1 true
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'still red after a retry: web:src' || fail "retry same fp" "rc $RC out $OUT"
[ -z "$(ran)" ] || fail "retry same fp" "reran"
ok "stop_hook_active, same red fingerprint: lets go with a message"

echo 2 >> "$W/web/src/a.ts"
stop "$W/web" s1 true
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'still red' && [ -n "$(ran)" ] || fail "retry new fp" "rc $RC out $OUT"
ok "stop_hook_active, new red fingerprint: reruns, never blocks"
clear_ran

echo 3 >> "$W/web/src/a.ts"
stop "$W/web" s2
[ "$RC" = 2 ] || fail "new session blocks" "rc $RC"; ok "other session id has its own record"

echo 4 >> "$W/web/src/a.ts"
SDW_STOP_MODE=json stop "$W/web" s2
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '"decision":"block"' || fail "json stop mode" "rc $RC out $OUT"; ok "SDW_STOP_MODE=json blocks via stdout"

rm "$W/web/fail-web"; echo 5 >> "$W/web/src/a.ts"
stop "$W/web" s2
[ "$RC" = 0 ] && [ -z "$OUT$ERR" ] || fail "green" "rc $RC out $OUT err $ERR"
grep -q ' green ' "$W/.sdw/state/stop/s2" || fail "record" "$(cat "$W/.sdw/state/stop/s2")"
ok "green: exit 0 and recorded"

# A red stop fixed by reverting leaves a clean tree: the red record goes.
touch "$W/web/fail-web"; echo r > "$W/web/src/new.ts"
stop "$W/web" s6
[ "$RC" = 2 ] && grep -q ' red ' "$W/.sdw/state/stop/s6" || fail "revert: red first" "rc $RC"
rm "$W/web/fail-web" "$W/web/src/new.ts"
for r in web api; do (cd "$W/$r" && git checkout -q -- . && git clean -qfd) || fail "revert: reset $r" "git"; done
[ -z "$(cd "$W/web" && sdw-gate --fingerprint)" ] || fail "revert: clean tree" "fingerprint not empty"
stop "$W/web" s6 true
[ "$RC" = 0 ] && [ ! -f "$W/.sdw/state/stop/s6" ] || fail "revert: record gone" "rc $RC"
hook_json session-start.sh "{\"cwd\":$(json_str "$W/web"),\"session_id\":\"s6\",\"source\":\"resume\"}"
printf '%s' "$OUT" | grep -q 'gate red at last stop' && fail "revert: session-start" "still reports red"
ok "red then reverted: clean-tree stop drops the record; resume reports no red gate"

# Tamper hits on a green tree are a warning only.
cp -R "$PLUGIN" "$tmp/plug"
printf '#!/bin/sh\necho "skip-added src/a.test.ts:3 it.skip(\\"x\\")"\nexit 1\n' > "$tmp/plug/bin/sdw-tamper"
chmod +x "$tmp/plug/bin/sdw-tamper"
echo 6 >> "$W/web/src/a.ts"
CLAUDE_PLUGIN_ROOT="$tmp/plug" stop "$W/web" s3
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'test changes to justify' || fail "tamper warning" "rc $RC out $OUT"
ok "tamper hits on green: systemMessage, exit 0"

# A sibling worktree gates its own changes, in its own dir.
(cd "$W/web" && git worktree add -b wt "$W/web-wt" main >/dev/null 2>&1) || fail setup worktree
touch "$W/web-wt/fail-web"; echo 1 >> "$W/web-wt/src/a.ts"
stop "$W/web-wt" s4
[ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q "web:src ($W/web-wt/src)" || fail "worktree" "rc $RC err $ERR"
ok "sibling worktree: gate runs in the worktree"

rm "$W/.sdw/gates"
echo 7 >> "$W/web/src/a.ts"
stop "$W/web" s5
[ "$RC" = 0 ] || fail "no gates file" "rc $RC"; ok "no gates file: exit 0"
