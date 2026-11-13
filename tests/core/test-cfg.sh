#!/usr/bin/env bash
# sdw-cfg: parsing, defaults, --has, secret refusal, the onboard template, not onboarded.
. "$(dirname "$0")/_lib.sh"

P="$tmp/My Proj_1"
mkdir -p "$P/.sdw"
mkrepo "$P/app"
cat > "$P/.sdw/config.env" <<'EOF'
# comment
BASE_BRANCH=develop
export TRACKER=jira
JIRA_FLAVOR="dc"
BRANCH_PATTERN='{key}/{slug}'
DOCS_DIR=local-docs   # trailing comment
TEAM_SKILLS="commit push"
WORKLOG=0
WORKLOG=1
EMPTY=
EOF
cd "$P/app" || exit 1
c() { expect_rc "$1" "$2" sdw-cfg "${@:3}"; [ -z "${WANT+x}" ] || [ "$OUT" = "$WANT" ] || fail "$2" "got '$OUT', want '$WANT'"; unset WANT; }

WANT=develop c 0 "plain key" BASE_BRANCH
WANT=jira c 0 "export line" TRACKER
WANT=dc c 0 "double-quoted" JIRA_FLAVOR
WANT='{key}/{slug}' c 0 "single-quoted" BRANCH_PATTERN
WANT=local-docs c 0 "trailing comment stripped" DOCS_DIR
WANT='commit push' c 0 "quoted value with space" TEAM_SKILLS
WANT=1 c 0 "last occurrence wins" WORKLOG
WANT=bearer c 0 "JIRA_AUTH default follows flavor" JIRA_AUTH
WANT=github c 0 "built-in default" VCS_HOST
WANT=fallback c 0 "explicit default" EMPTY fallback
WANT=my-proj-1 c 0 "PROJ_SLUG default" PROJ_SLUG
WANT='' c 0 "unknown key is empty" FIGMA_FILE_KEY
c 0 "--has set" --has TRACKER
c 1 "--has empty" --has EMPTY
c 1 "--has unset" --has FIGMA_FILE_KEY
for k in JIRA_TOKEN DB_PASSWORD CLIENT_SECRET APIKEY AWS_CREDENTIALS FIGMA_TOKEN; do
  c 5 "secret refused $k" "$k"
  c 5 "secret refused --has $k" --has "$k"
done
c 2 "lowercase key" base_branch
c 2 "key with dash" BASE-BRANCH
c 2 "no args"
c 0 "help" -h
sed 's/^JIRA_FLAVOR=cloud$/JIRA_FLAVOR=dc/' "$PLUGIN/skills/onboard/config.example.env" > "$P/.sdw/config.env"
WANT=bearer c 0 "rendered template on dc defaults to bearer" JIRA_AUTH

mkrepo "$tmp/plain"
cd "$tmp/plain" || exit 1
WANT=main c 0 "not onboarded prints default" BASE_BRANCH
c 1 "not onboarded --has" --has BASE_BRANCH
c 5 "not onboarded secret" JIRA_TOKEN
