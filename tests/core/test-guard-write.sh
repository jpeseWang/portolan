#!/usr/bin/env bash
# guard-write: secret paths, tracked benign .env.*, agent confinement to the work dir, fail-closed.
. "$(dirname "$0")/_lib.sh"

WS="$tmp/ws space"
mkdir -p "$WS/.sdw/work/feat"
mkrepo "$WS/web" feat
WORK="$WS/.sdw/work/feat"
(
  cd "$WS/web" &&
  printf 'VITE_API_BASE_URL=/api\nVITE_BASE_PATH=/\n' > .env.development &&
  printf 'STRIPE_SECRET=sk_test_x\n' > .env.staging &&
  printf 'APP_ENV=prod\nDATABASE_URL=\n' > .env.dist &&
  git add .env.development .env.dist && git add -f .env.staging && git commit -qm envs
) || fail setup "tracked env files"

# run <agent> <path> [tool_input key]
run() {
  hook_json guard-write.sh "{\"cwd\":$(json_str "$WS/web"),\"agent_type\":$(json_str "$1"),\"tool_input\":{\"${3:-file_path}\":$(json_str "$2")}}"
}
deny() { run "${2:-}" "$1" "${3:-}"; [ "$RC" = 2 ] || fail "deny: $1 ${2:-}" "exit $RC"; ok "deny: $1 ${2:-}"; }
allow() { run "${2:-}" "$1" "${3:-}"; [ "$RC" = 0 ] || fail "allow: $1 ${2:-}" "exit $RC err $ERR"; ok "allow: $1 ${2:-}"; }

deny .env
deny apps/api/.env
deny .env.local
deny .env.production
deny .env.staging
deny .envrc
deny certs/server.pem
deny certs/server.key
deny keystore.p12
deny keystore.pfx
deny app.jks
deny "$HOME/.ssh/id_rsa"
deny id_ed25519.pub
deny .auth.json
deny e2e/.auth/admin.json
deny "$WS/.sdw/auth/admin.json"
deny playwright/.auth/user.json
deny .env notebook_path
deny src/../.env
allow .env.example
allow .env.local.sample
allow config/.env.template
allow .env.development
allow .env.dist
allow src/a.ts
allow README.md
allow "$WORK/notes.md"

for a in sdw:qa sdw:reviewer; do
  deny src/a.ts $a
  deny "$WS/.sdw/project.md" $a
  deny "$WORK/.qa-phase" $a
  deny "$WORK/../../work" $a
  deny "$WORK/../feat2/cases.md" $a
done
allow "$WORK/cases.md" sdw:qa
allow "$WORK/qa-report.md" sdw:qa
allow "$WORK/bugs/BUG-01.md" sdw:qa
allow "$WORK/shots/home.png" sdw:qa
allow "$WORK/shots/mock/orders-422.json" sdw:qa
deny "$WORK/plan.md" sdw:qa
deny "$WORK/ticket.md" sdw:qa
deny "$WORK/review.md" sdw:qa
deny "$WORK/.cases.design.md" sdw:qa
deny "$WORK/cases.md/../../../../web/src/a.ts" sdw:qa
allow "$WORK/review-raw.md" sdw:reviewer
deny "$WORK/cases.md" sdw:reviewer
deny "$WORK/review-raw.md"
deny "$WORK/.cases.design.md"
deny "$WS/.sdw/state/qa-active"

# The work dir under QA comes from .sdw/state/qa-active when the session is not on that branch.
mkdir -p "$WS/.sdw/state"; printf 'other\n' > "$WS/.sdw/state/qa-active"
deny "$WORK/cases.md" sdw:qa
allow "$WS/.sdw/work/other/cases.md" sdw:qa
rm "$WS/.sdw/state/qa-active"

# sdw:qa never writes a verdict other than PENDING.
verdict() {
  hook_json guard-write.sh "{\"cwd\":$(json_str "$WS/web"),\"agent_type\":\"sdw:qa\",\"tool_input\":{\"file_path\":$(json_str "$WORK/qa-report.md"),\"$1\":$(json_str "$2")}}"
}
verdict content "$(printf '<!-- sdw-stamp {} -->\nVerdict: READY\n')"; [ "$RC" = 2 ] || fail "qa verdict READY" "exit $RC"; ok "qa cannot write Verdict: READY"
verdict new_string 'Verdict: NOT READY'; [ "$RC" = 2 ] || fail "qa verdict via Edit" "exit $RC"; ok "qa cannot edit the verdict"
verdict content "$(printf '<!-- sdw-stamp {} -->\nVerdict: PENDING\n')"; [ "$RC" = 0 ] || fail "qa verdict PENDING" "exit $RC $ERR"; ok "qa writes Verdict: PENDING"

# Case-insensitive names and symlinks.
deny .ENV
deny apps/.Env.Local
deny certs/server.KEY
(cd "$WS/web" && echo s > .env && ln -s .env link.txt && mkdir -p "$WORK/shots" && ln -s "$WS/web/.env" "$WORK/shots/x.json") || fail setup symlinks
deny link.txt
deny "$WORK/shots/x.json" sdw:qa
allow .ENV.example

# Unparseable input fails closed.
for bad in '' 'not json' '{' '[]'; do
  printf '%s' "$bad" | "$PLUGIN/hooks/guard-write.sh" > /dev/null 2> "$tmp/.err"; rc=$?
  [ "$rc" = 2 ] && grep -q 'bad input' "$tmp/.err" || fail "bad input '$bad'" "exit $rc"
done
ok "unparseable input -> exit 2"

mkdir -p "$tmp/loose"
hook_json guard-write.sh "{\"cwd\":$(json_str "$tmp/loose"),\"agent_type\":\"sdw:qa\",\"tool_input\":{\"file_path\":$(json_str "$tmp/loose/x.md")}}"
[ "$RC" = 2 ] || fail "qa without projdir" "exit $RC"; ok "qa without projdir -> exit 2"

mkdir -p "$tmp/min"
for b in bash git sed grep cat; do ln -s "$(command -v $b)" "$tmp/min/$b"; done
printf '%s' '{"cwd":"/","tool_input":{"file_path":"/x/a.ts"}}' | PATH="$tmp/stub:$tmp/min" "$PLUGIN/hooks/guard-write.sh" > /dev/null 2> "$tmp/.err"
rc=$?
[ "$rc" = 2 ] && grep -q 'install jq' "$tmp/.err" || fail "no jq/python3" "exit $rc"
ok "no jq/python3 -> exit 2"

cp -R "$PLUGIN" "$tmp/broken"
echo 'exit 7' >> "$tmp/broken/hooks/lib.sh"
printf '%s' '{"cwd":"/","tool_input":{"file_path":"/x/a.ts"}}' | "$tmp/broken/hooks/guard-write.sh" > /dev/null 2> "$tmp/.err"
rc=$?
[ "$rc" = 2 ] && grep -q 'guard error' "$tmp/.err" || fail "internal error" "exit $rc"
ok "internal error -> exit 2"
