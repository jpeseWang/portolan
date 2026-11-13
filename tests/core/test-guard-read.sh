#!/usr/bin/env bash
# guard-read: no secret reads for anyone; sdw:qa design-phase read roots; sdw:qa tool allowlist; fail-closed.
. "$(dirname "$0")/_lib.sh"

WS="$tmp/ws space"
mkdir -p "$WS/.sdw/work/feat"
mkrepo "$WS/web" feat
WORK="$WS/.sdw/work/feat"
mkdir -p "$WS/web/docs"; echo spec > "$WS/web/docs/api.md"
printf '## qa\n- spec: web/docs\n' > "$WS/.sdw/run.md"

# run <agent> <tool> <key> <value>
run() {
  hook_json guard-read.sh "{\"cwd\":$(json_str "$WS/web"),\"agent_type\":$(json_str "$1"),\"tool_name\":\"$2\",\"tool_input\":{\"$3\":$(json_str "$4")}}"
}
deny() { run "$@"; [ "$RC" = 2 ] || fail "deny: $*" "exit $RC"; ok "deny: $*"; }
allow() { run "$@"; [ "$RC" = 0 ] || fail "allow: $*" "exit $RC err $ERR"; ok "allow: $*"; }

deny "" Read file_path .env
deny "" Read file_path apps/api/.ENV.local
deny "" Read file_path "$WS/.sdw/auth/admin.cookies"
deny sdw:qa Read file_path e2e/.auth/admin.json
deny "" Grep path .env.production
run "" Grep glob .env; [ "$RC" = 2 ] || fail "grep glob .env" "exit $RC"; ok "deny: grep glob .env"
allow "" Read file_path .env.example
allow "" Read file_path src/a.ts
allow "" Glob pattern '**/.env*'
for g in '.env*' '*.env*' '**/.env*'; do deny "" Grep glob "$g"; done
for g in '*.ts' '.env.example' '**/*.md'; do allow "" Grep glob "$g"; done
deny "" Read file_path playwright/.auth/user.json
deny "" Read file_path certs/k.pem
deny "" Read file_path .envrc
(cd "$WS/web" && printf 'VITE_API_URL=/api\n' > .env.development && git add .env.development && git commit -qm env) || fail setup env
allow "" Read file_path .env.development
echo 'API_KEY=x' >> "$WS/web/.env.development"
deny "" Read file_path .env.development

printf 'design\n' > "$WORK/.qa-phase"
deny sdw:qa Read file_path src/a.ts
deny sdw:qa Grep path .
deny sdw:qa Glob pattern 'src/**/*.ts'
deny sdw:qa Glob pattern "$WS/web/src/**"
allow sdw:qa Read file_path "$WORK/plan.md"
allow sdw:qa Read file_path docs/api.md
allow sdw:qa Read file_path "$PLUGIN/skills/qa/techniques.md"
allow sdw:reviewer Read file_path src/a.ts
allow "" Read file_path src/a.ts
printf 'execute\n' > "$WORK/.qa-phase"
allow sdw:qa Read file_path src/a.ts

deny sdw:qa WebFetch url https://forge.invalid/pr/1.diff
deny sdw:qa mcp__atlassian__createJiraIssue summary x
deny sdw:qa Agent prompt x
allow sdw:qa mcp__playwright__browser_navigate url http://localhost:3000/
allow "" WebFetch url https://docs.invalid/
allow "" mcp__atlassian__getJiraIssue key X-1

for bad in '' 'nope' '[]'; do
  printf '%s' "$bad" | "$PLUGIN/hooks/guard-read.sh" > /dev/null 2> "$tmp/.err"; rc=$?
  [ "$rc" = 2 ] && grep -q 'bad input' "$tmp/.err" || fail "bad input '$bad'" "exit $rc"
done
ok "unparseable input -> exit 2"
