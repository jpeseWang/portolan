#!/usr/bin/env bash
# sdw-jira against a local fake Jira: paths, auth scheme, ADF/wiki bodies, exit codes,
# and the token never reaching argv, stdout or stderr.
set -u
here=$(cd "$(dirname "$0")" && pwd -P)
PLUGIN=$(cd "$here/../../plugin" && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdw-tests-team.XXXXXX")
srv_pid=""
cleanup() {
  [ -n "$srv_pid" ] && kill "$srv_pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
mkdir -p "$HOME" "$tmp/stub" "$tmp/srv" "$tmp/bin"

fail() { echo "FAIL $1: $2"; exit 1; }
ok() { echo "ok $1"; }

TOKEN="tok-zq81-$$-NEVERPRINT"
printf '%s\n' "$TOKEN" > "$tmp/token"
B64=$(printf '%s' "me@example.test:$TOKEN" | base64 | tr -d '\n')

# --- stubs: Keychain, a logging curl wrapper, and sdw-cfg if A's is not there yet
cat > "$tmp/stub/security" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/security.log"
[ "\$1" = find-generic-password ] || exit 2
svc=""; w=0; shift
while [ \$# -gt 0 ]; do case \$1 in -s) svc=\$2; shift;; -w) w=1;; esac; shift; done
if [ "\$w" = 1 ] && [ "\$svc" = "\$(cat "$tmp/keychain-service")" ]; then cat "$tmp/token"; exit 0; fi
echo "security: The specified item could not be found in the keychain." >&2
exit 44
EOF
real_curl=$(command -v curl) || fail setup "curl not installed"
cat > "$tmp/stub/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/curl-argv.log"
exec "$real_curl" "\$@"
EOF
if [ -x "$PLUGIN/bin/sdw-cfg" ]; then
  BIN="$PLUGIN/bin"
else
  BIN="$tmp/bin"
  ln -s "$PLUGIN/bin/sdw-jira" "$BIN/sdw-jira"
  cat > "$BIN/sdw-cfg" <<'EOF'
#!/usr/bin/env bash
d=$PWD; f=""
while [ "$d" != / ] && [ "$d" != "$HOME" ]; do
  [ -f "$d/.sdw/config.env" ] && { f="$d/.sdw/config.env"; break; }
  d=$(dirname "$d")
done
if [ "$1" = --has ]; then [ -n "$f" ] && grep -q "^$2=" "$f"; exit; fi
v=""; [ -n "$f" ] && v=$(sed -n "s/^$1=//p" "$f" | tail -1)
v=${v#\"}; v=${v%\"}
[ -z "$v" ] && [ $# -ge 2 ] && v=$2
[ -z "$v" ] && [ "$1" = JIRA_FLAVOR ] && v=cloud
printf '%s\n' "$v"
EOF
  chmod +x "$BIN/sdw-cfg"
  echo "note: plugin/bin/sdw-cfg absent, using a test stand-in"
fi
chmod +x "$tmp/stub/security" "$tmp/stub/curl"
export PATH="$tmp/stub:$BIN:$PATH"

# --- fake Jira on a random port
STUB_TOKEN="$TOKEN" STUB_EMAIL="me@example.test" python3 "$here/_jira_stub.py" "$tmp/srv" &
srv_pid=$!
i=0
while [ ! -f "$tmp/srv/port" ]; do
  i=$((i + 1)); [ $i -gt 100 ] && fail setup "stub server did not start"
  sleep 0.1
done
PORT=$(cat "$tmp/srv/port")
BASE="http://127.0.0.1:$PORT"
printf '%s' "sdw:jira:$BASE" > "$tmp/keychain-service"

PROJ="$tmp/client work/web app"
mkdir -p "$PROJ/.sdw"
(cd "$PROJ" && git init -q . && git commit -q --allow-empty -m init) || fail setup "git init"

writecfg() { # writecfg <flavor> [extra KEY=value lines…]
  local fl=$1; shift
  {
    echo "TRACKER=jira"
    echo "JIRA_BASE_URL=\"$BASE/\""
    echo "JIRA_EMAIL=me@example.test"
    echo "JIRA_PROJECT=ABC"
    echo "JIRA_FLAVOR=$fl"
    echo "JIRA_AC_FIELD=customfield_10050"
    echo "JIRA_SPRINT_FIELD=customfield_10020"
    for l in "$@"; do echo "$l"; done
  } > "$PROJ/.sdw/config.env"
}

run() { # run <args…>; stdin from $STDIN (default /dev/null); sets rc
  (cd "$PROJ" && sdw-jira "$@") < "${STDIN:-/dev/null}" > "$tmp/out" 2> "$tmp/err"
  rc=$?
  cat "$tmp/out" "$tmp/err" >> "$tmp/all-output"
}
want_rc() { [ "$rc" = "$2" ] || fail "$1" "exit $rc, want $2; stderr: $(head -c 400 "$tmp/err")"; }
has_out() { grep -qF -- "$2" "$tmp/out" || fail "$1" "stdout lacks [$2]: $(head -c 400 "$tmp/out")"; }
has_err() { grep -qF -- "$2" "$tmp/err" || fail "$1" "stderr lacks [$2]: $(head -c 400 "$tmp/err")"; }
nreq() { if [ -f "$tmp/srv/requests.jsonl" ]; then wc -l < "$tmp/srv/requests.jsonl" | tr -d ' '; else echo 0; fi; }
req() { # req <python expr over r = last request (or r = all requests with -a)>
  python3 - "$tmp/srv/requests.jsonl" "$1" <<'PY'
import json, sys
rs = [json.loads(l) for l in open(sys.argv[1])]
r = rs[-1]
v = eval(sys.argv[2])
print(v if isinstance(v, str) else json.dumps(v))
PY
}
check() { # check <case> <python expr that must be True>
  [ "$(req "$2")" = true ] || fail "$1" "false: $2  (last request: $(req 'r'))"
}

# ---------- usage
run -h; want_rc usage-h 0; has_out usage-h "sdw-jira worklog add"
run; want_rc usage-none 2
run bogus; want_rc usage-unknown 2
run GET; want_rc usage-get-no-path 2
run issue "not a key"; want_rc usage-bad-key 2
run worklog add ABC-1 --started yesterday --duration 1h; want_rc usage-bad-started 2
run worklog add ABC-1 --started now --duration 25h; want_rc usage-bad-duration 2
run create --type Task --summary "$(printf 'a\nb')"; want_rc usage-multiline-summary 2
ok usage

# ---------- config and Keychain failures (no request may be sent)
n0=$(nreq)
run myself; want_rc no-config 4; has_err no-config "JIRA_BASE_URL not set"
writecfg cloud
sed -i.bak "s#^JIRA_BASE_URL=.*#JIRA_BASE_URL=http://jira.example.test#" "$PROJ/.sdw/config.env"
run myself; want_rc plain-http-remote 5; has_err plain-http-remote "plain http"
writecfg cloud
printf '%s' "sdw:jira:elsewhere" > "$tmp/keychain-service"
run myself; want_rc no-token 4
has_err no-token "security add-generic-password -U -s 'sdw:jira:$BASE' -a '<account>' -w"
printf '%s' "sdw:jira:$BASE" > "$tmp/keychain-service"
[ "$(nreq)" = "$n0" ] || fail no-request-on-failure "a request was sent"
grep -q -- "find-generic-password -s sdw:jira:$BASE -w" "$tmp/security.log" ||
  fail keychain-lookup "security not called with -s <service> -w"
ok config-failures

# ---------- cloud, basic auth
run myself; want_rc cloud-myself 0; has_out cloud-myself acc-1; has_err cloud-myself "HTTP 200"
check cloud-myself 'r["path"] == "/rest/api/3/myself" and r["auth_scheme"] == "Basic" and r["auth_ok"]'
ok cloud-myself

run GET /issue/ABC-1; want_rc raw-get 0
check raw-get 'r["path"] == "/rest/api/3/issue/ABC-1" and r["method"] == "GET"'
run GET "/rest/agile/1.0/board?projectKeyOrId=ABC"; want_rc raw-rest-path 0
check raw-rest-path 'r["path"] == "/rest/agile/1.0/board?projectKeyOrId=ABC"'
ok raw-paths

printf '{"fields":{"labels":["x y"]}}' > "$tmp/pay load.json"
run PUT /issue/ABC-1 "@$tmp/pay load.json"; want_rc raw-put 1; has_err raw-put "HTTP 404"
check raw-put 'r["method"] == "PUT" and r["content_type"] == "application/json" and r["body"] == {"fields": {"labels": ["x y"]}}'
printf 'not json' > "$tmp/bad.json"
run POST /issue "@$tmp/bad.json"; want_rc raw-bad-json 2
run POST /issue "@$tmp/missing.json"; want_rc raw-missing-file 4
STDIN="$tmp/pay load.json" run POST /issue @-; want_rc raw-stdin 0; has_out raw-stdin ABC-9
ok raw-payloads

run GET /issue/ABC-404; want_rc non-2xx 1; has_err non-2xx "HTTP 404"; has_out non-2xx "Issue does not exist"
ok non-2xx

run issue ABC-1 --text; want_rc issue-text 0
has_out issue-text "ABC-1 [Story] To Do — Export orders"
has_out issue-text "here (https://spec.example.test/x)"
has_out issue-text "- CSV only"
has_out issue-text "## Acceptance criteria (customfield_10050)"
has_out issue-text "Given orders When export Then CSV"
has_out issue-text "### PO 2026-10-15T10:00"
check issue-text '"customfield_10050" in r["path"] and "customfield_10020" in r["path"]'
has_out issue-text "Reporter: QA Lead"
has_out issue-text "[attachment: export-error.png]"
has_out issue-text "## Attachments (2)"
[ "$(grep '^- .*, id ' "$tmp/out")" = "- server.log (text/plain, 912 B, id 10003, 2026-10-16T11:30)
- export-error.png (image/png, 47.1 KB, id 10001, 2026-10-15T09:00)" ] || fail issue-attachments "$(cat "$tmp/out")"
check issue-text '"attachment" in r["path"] and "reporter" in r["path"]'
ok issue-text

# ---------- attachment download: metadata, then content through a redirect, written only inside
SHOT="$PROJ/.sdw/work/feat/shots/export error.png"
run attachment 10001 --out "$SHOT"; want_rc attachment 0; has_out attachment "$(printf 'shots/export error.png\timage/png\t47.1 KB')"
python3 -c 'import sys; assert open(sys.argv[1], "rb").read() == b"\x89PNG\r\n\x1a\nfixture-image"' "$SHOT" || fail attachment "wrong bytes"
[ "$(ls -A "$(dirname "$SHOT")")" = "export error.png" ] || fail attachment "temp file left: $(ls -A "$(dirname "$SHOT")")"
check attachment 'r["path"] == "/media/10001"'
check attachment '[x["path"] for x in rs[-3:-1]] == ["/rest/api/3/attachment/10001", "/rest/api/3/attachment/content/10001"] and all(x["auth_ok"] for x in rs[-3:-1])'
n0=$(nreq)
run attachment 10001 --out "$SHOT"; want_rc attachment-exists 5; has_err attachment-exists "refusing to overwrite"
run attachment 10001 --out /sdw-outside/x.png; want_rc attachment-outside 5
run attachment 10001 --out "$PROJ/.git/hooks/pre-commit"; want_rc attachment-git-dir 5
run attachment 10001 --out "$PROJ"; want_rc attachment-dir 2
run attachment 10001 --out "$PROJ/.sdw/work/feat/newdir/"; want_rc attachment-trailing-slash 2
[ -e "$PROJ/.sdw/work/feat/newdir" ] && fail attachment-trailing-slash "wrote a file named after the directory"
for o in "$PROJ/.claude/settings.local.json" "$PROJ/.github/workflows/x.yml" "$PROJ/.envrc" "$PROJ/src/x.png" \
  "$PROJ/.sdw/work/feat/.claude/x.json" "$tmp/scratch/.vscode/tasks.json" "$tmp/scratch/.mcp.json"; do
  run attachment 10001 --out "$o"; want_rc "attachment-outside-work-dir $o" 5
  [ -e "$o" ] && fail attachment-outside-work-dir "wrote $o"
done
run attachment abc --out "$tmp/a.png"; want_rc attachment-bad-id 2
run attachment 10001; want_rc attachment-no-out 2
[ "$(nreq)" = "$n0" ] || fail attachment-refused "a refused download sent a request"
[ -e /sdw-outside ] && fail attachment-outside "wrote outside"
run attachment 10002 --out "$tmp/b.png"; want_rc attachment-foreign-host 5; has_err attachment-foreign-host "outside JIRA_BASE_URL"
[ "$(nreq)" = $((n0 + 1)) ] && [ ! -e "$tmp/b.png" ] || fail attachment-foreign-host "content fetched from another host"
ok attachment

n0=$(nreq)
run transition ABC-1 21 --dry-run; want_rc transition-dry 0
has_out transition-dry "POST /rest/api/3/issue/ABC-1/transitions"
[ "$(nreq)" = "$n0" ] || fail transition-dry "dry run sent a request"
run transition ABC-1 21; want_rc transition 0; has_err transition "HTTP 204"
check transition 'r["method"] == "POST" and r["body"] == {"transition": {"id": "21"}}'
run transitions ABC-1; want_rc transitions 0; has_out transitions '"In Progress"'
ok transitions

run search 'assignee = currentUser() AND statusCategory = "In Progress"' --brief; want_rc search 0
has_out search "$(printf 'ABC-1\tIn Progress\tExport orders')"
check search 'r["path"].startswith("/rest/api/3/search/jql?jql=assignee+%3D+currentUser%28%29") and "maxResults=50" in r["path"]'
ok search-cloud

run sprint; want_rc sprint 0; has_out sprint "$(printf '42\tSprint 4\tboard 7 ABC board')"
check sprint 'r["path"] == "/rest/agile/1.0/board/7/sprint?state=active"'
ok sprint

n0=$(nreq)
run worklog add ABC-1 --started 2026-10-16T09:00+02:00 --duration 1h30m --comment "CSV endpoint and tests" --dry-run
want_rc worklog-dry 0; has_out worklog-dry '"timeSpentSeconds": 5400'
[ "$(nreq)" = "$n0" ] || fail worklog-dry "dry run sent a request"
run worklog add ABC-1 --started 2026-10-16T09:00+02:00 --duration 1h30m --comment "CSV endpoint and tests"
want_rc worklog-add 0; has_out worklog-add 10001
check worklog-add 'r["path"] == "/rest/api/3/issue/ABC-1/worklog" and r["body"]["started"] == "2026-10-16T09:00:00.000+0200" and r["body"]["timeSpentSeconds"] == 5400'
check worklog-add 'r["body"]["comment"] == {"type": "doc", "version": 1, "content": [{"type": "paragraph", "content": [{"type": "text", "text": "CSV endpoint and tests"}]}]}'
run worklog add ABC-1 --started 2026-10-16T07:00:00Z --duration 45m
want_rc worklog-utc 0
check worklog-utc 'r["body"] == {"started": "2026-10-16T07:00:00.000+0000", "timeSpentSeconds": 2700}'
ok worklog-add

run worklog list ABC-1 --since 2026-10-15 --mine; want_rc worklog-mine 0
[ "$(cut -f1 "$tmp/out" | tr '\n' ' ')" = "1 3 " ] || fail worklog-mine "want ids 1 3, got $(cat "$tmp/out")"
check worklog-mine '"startedAfter=" in r["path"]'
run worklog mine 2026-10-16; want_rc worklog-day 0
has_out worklog-day "$(printf 'ABC-1\t1\t2026-10-16T09:00:00.000+0200\t3600')"
has_out worklog-day "$(printf 'TOTAL\t3600\t1h00m')"
[ "$(wc -l < "$tmp/out" | tr -d ' ')" = 2 ] || fail worklog-day "unexpected lines: $(cat "$tmp/out")"
ok worklog-list

cat > "$tmp/desc file.md" <<'EOF'
## Steps
Open https://app.example.test/orders.
Click Export
- one
- two

1. first
2. second

```json
{"a": 1}
```
EOF
run create --type Task --summary "Export orders as CSV" --description-file "$tmp/desc file.md" \
  --assignee me --sprint 42 --label csv; want_rc create-cloud 0; has_out create-cloud ABC-9
check create-cloud 'r["path"] == "/rest/api/3/issue" and r["method"] == "POST"'
check create-cloud 'r["body"]["fields"]["project"] == {"key": "ABC"} and r["body"]["fields"]["issuetype"] == {"name": "Task"}'
check create-cloud 'r["body"]["fields"]["assignee"] == {"accountId": "acc-1"} and r["body"]["fields"]["customfield_10020"] == 42 and r["body"]["fields"]["labels"] == ["csv"]'
check create-cloud '(lambda d: d["type"] == "doc" and d["version"] == 1 and [c["type"] for c in d["content"]] == ["heading", "paragraph", "bulletList", "orderedList", "codeBlock"])(r["body"]["fields"]["description"])'
check create-cloud '(lambda c: c[0]["attrs"]["level"] == 2 and {"type": "hardBreak"} in c[1]["content"] and any(m["attrs"]["href"] == "https://app.example.test/orders" for n in c[1]["content"] for m in n.get("marks", [])) and c[4]["attrs"]["language"] == "json" and c[4]["content"][0]["text"] == "{\"a\": 1}")(r["body"]["fields"]["description"]["content"])'
check create-cloud '(lambda w: w(w, r["body"]["fields"]["description"]))(lambda w, n: (n.get("type") != "text" or bool(n.get("text"))) and all(w(w, k) for k in n.get("content", [])))'
n0=$(nreq)
run create --type Bug --summary "Totals round wrong" --dry-run; want_rc create-dry 0
[ "$(head -1 "$tmp/out")" = "POST /rest/api/3/issue" ] || fail create-dry "first line: $(head -1 "$tmp/out")"
[ "$(nreq)" = "$n0" ] || fail create-dry "dry run sent a request"
ok create-cloud

# ---------- data center, bearer auth, wiki markup
writecfg dc
run myself; want_rc dc-myself 0
check dc-myself 'r["path"] == "/rest/api/2/myself" and r["auth_scheme"] == "Bearer" and r["auth_ok"]'
run create --type Task --summary "Export orders as CSV" --description-file "$tmp/desc file.md" --assignee me
want_rc create-dc 0
check create-dc 'r["path"] == "/rest/api/2/issue" and r["body"]["fields"]["assignee"] == {"name": "me"}'
check create-dc '(lambda d: isinstance(d, str) and d.startswith("h2. Steps\n") and "* one\n* two" in d and "# first\n# second" in d and "{code:json}\n{\"a\": 1}\n{code}" in d)(r["body"]["fields"]["description"])'
run search 'project = ABC' --brief; want_rc search-dc 0
check search-dc 'r["path"].startswith("/rest/api/2/search?jql=project+%3D+ABC")'
run worklog mine 2026-10-16; want_rc worklog-day-dc 0; has_out worklog-day-dc "$(printf 'TOTAL\t3600\t1h00m')"
writecfg dc JIRA_AUTH=basic
run myself; want_rc dc-basic 0
check dc-basic 'r["auth_scheme"] == "Basic" and r["auth_ok"]'
ok data-center

# ---------- offline rendering needs no project and no token
printf '## Title\n- a\n' > "$tmp/r.md"
(cd "$tmp" && sdw-jira render --flavor cloud < "$tmp/r.md") > "$tmp/out" 2>&1 || fail render "cloud render failed"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["type"]=="doc" and d["content"][1]["type"]=="bulletList"' "$tmp/out" ||
  fail render "bad ADF: $(cat "$tmp/out")"
(cd "$tmp" && sdw-jira render --flavor dc < "$tmp/r.md") > "$tmp/out" 2>&1 || fail render "dc render failed"
[ "$(cat "$tmp/out")" = "$(printf 'h2. Title\n\n* a')" ] || fail render "bad wiki: $(cat "$tmp/out")"
ok render

# ---------- server gone: no response is exit 1, HTTP 000
writecfg cloud
kill "$srv_pid" 2>/dev/null; wait "$srv_pid" 2>/dev/null; srv_pid=""
run myself; want_rc no-response 1; has_err no-response "HTTP 000"
ok no-response

# ---------- the token never leaves the Keychain stub
for f in "$tmp/all-output" "$tmp/curl-argv.log"; do
  grep -qF -- "$TOKEN" "$f" && fail token-leak "token found in $(basename "$f")"
  grep -qF -- "$B64" "$f" && fail token-leak "basic credential found in $(basename "$f")"
done
grep -q -- "-K -" "$tmp/curl-argv.log" || fail token-leak "curl not fed a config on stdin"
grep -qi authorization "$tmp/curl-argv.log" && fail token-leak "Authorization header on curl argv"
[ -z "$(find "$PLUGIN" -name __pycache__)" ] || fail hygiene "__pycache__ left under plugin/"
ok token-never-printed

echo "PASS test-sdw-jira"
