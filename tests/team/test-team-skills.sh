#!/usr/bin/env bash
# Team skills and tracker references: argument hints, line budgets, sdw-jira commands that exist,
# no hand-written authenticated curl. Frontmatter, git 2.15 and shell parsing: tests/lint.
set -u
here=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN=$(cd "$here/../../plugin" && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdw-tests-team.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"

fail() { echo "FAIL $1: $2"; exit 1; }
ok() { echo "ok $1"; }

# skill | max lines | argument-hint
specs="daily-report|70|[date]
logwork|80|[date]
create-ticket|55|[story|task|bug BUG-nn] <summary>"

printf '%s\n' "$specs" | while IFS='|' read -r name max hint rest; do
  [ -n "$rest" ] && hint="$hint|$rest"
  f="$PLUGIN/skills/$name/SKILL.md"
  [ -f "$f" ] || fail "$name" "missing $f"
  python3 - "$f" "$name" "$max" "$hint" <<'PY' || exit 1
import re, sys
f, name, mx, hint = sys.argv[1:]
t = open(f).read()
m = re.match(r"^---\n(.*?)\n---\n", t, re.S)
if not m:
    sys.exit("FAIL %s: no frontmatter" % name)
fm = dict(l.split(": ", 1) for l in m.group(1).splitlines())
def bad(why):
    print("FAIL %s: %s" % (name, why)); sys.exit(1)
fm["argument-hint"] = fm.get("argument-hint", "").strip('"')
if fm["argument-hint"] != hint: bad("argument-hint %r, want %r" % (fm["argument-hint"], hint))
if len(t.splitlines()) > int(mx): bad("%d lines, budget %s" % (len(t.splitlines()), mx))
PY
  echo "ok hint-and-budget-$name"
done || exit 1

# Every sdw-jira subcommand the docs name exists in the bin's usage.
usage=$("$PLUGIN/bin/sdw-jira" -h) || fail jira-usage "sdw-jira -h failed"
for sub in $(grep -ohE 'sdw-jira (GET|POST|PUT|[a-z]+( (list|mine|add))?)' \
    "$PLUGIN"/skills/*/SKILL.md "$PLUGIN"/reference/*.md | sed 's/^sdw-jira //' | sort -u | tr ' ' '_'); do
  s=$(printf '%s' "$sub" | tr '_' ' ')
  case "$s" in GET|POST|PUT) s="GET|POST|PUT" ;; esac
  printf '%s\n' "$usage" | grep -qF "sdw-jira $s" || fail jira-subcommands "docs use 'sdw-jira $s', not in usage"
done
ok jira-subcommands

# References resolve from a skill dir; no secret-bearing curl.
for f in "$PLUGIN"/skills/{daily-report,logwork,create-ticket}/SKILL.md; do
  for r in $(grep -oE 'reference/tracker-[a-z]+\.md' "$f" | sort -u); do
    [ -f "$(dirname "$f")/../../$r" ] || fail references "$f names missing $r"
  done
done
if grep -nE 'curl .*(-u |Authorization|--user)' "$PLUGIN"/skills/{daily-report,logwork,create-ticket}/SKILL.md "$PLUGIN"/reference/tracker-*.md; then
  fail no-raw-curl "hand-written authenticated curl in team docs"
fi
ok references-and-hygiene

echo "PASS test-team-skills"
