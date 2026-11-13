#!/usr/bin/env bash
# sdw-login: run.md parsing, api and form recipes, r-2 users, Keychain lookup, secrets kept off
# argv and output, exit codes.
. "$(dirname "$0")/_lib.sh"
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

PASS1='s3cret "PASS" \ one'
PASS2='second-pass'
export STUB_PASS="$PASS1"

cat > "$FAKE_PROJDIR/.sdw/run.md" <<'EOF'
# Run and QA
Notes in prose are ignored.

## app: web
- path: web:apps/web
- port: 5173
- ready: http://localhost:5173/

## login
- kind: api
- api: POST /api/login
- api-body: {"email":"{user}","password":"{pass}"}

## login: admin-ui
- kind: form
- url: /login
- user-field: input[name=email]
- pass-field: input[type=password]
- submit: button:has-text("Sign in")
- success: url:**/dashboard

## login: sso
- kind: oauth-manual
- url: https://idp.example.invalid/start

## users
- admin: alice@example.invalid, bob@example.invalid
- viewer: carol@example.invalid
- editor: dave@example.invalid
EOF

cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG/curl.argv"
jar="" out="" w="" url="" body=0
while [ $# -gt 0 ]; do
  case "$1" in
    -c) jar=$2; shift 2 ;;
    -o) out=$2; shift 2 ;;
    -w) w=$2; shift 2 ;;
    -X|-H|--max-time) shift 2 ;;
    --data-binary) [ "$2" = "@-" ] && body=1; shift 2 ;;
    http*) url=$1; shift ;;
    *) shift ;;
  esac
done
[ "$body" = 1 ] && cat > "$STUB_LOG/curl.body"
printf '%s\n' "$url" >> "$STUB_LOG/curl.urls"
if python3 -c 'import json,os,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("password")==os.environ["STUB_PASS"] else 1)' "$STUB_LOG/curl.body" 2>/dev/null; then
  printf '# Netscape HTTP Cookie File\n#HttpOnly_localhost\tFALSE\t/\tFALSE\t0\tsid\tabc123\n' > "$jar"
  printf '200'
else
  printf '401'
fi
EOF
cat > "$STUB/node" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG/node.argv"
cat > "$STUB_LOG/node.stdin"
outf=""
while [ $# -gt 0 ]; do case "$1" in --out) outf=$2; shift 2 ;; *) shift ;; esac; done
printf '{"cookies":[{"name":"auth","value":"tok1","domain":"localhost","path":"/","expires":-1,"httpOnly":true,"secure":false,"sameSite":"Lax"}],"origins":[]}' > "$outf"
EOF
chmod +x "$STUB/curl" "$STUB/node"

auth="$FAKE_PROJDIR/.sdw/auth"
keychain_put sdw:proj:admin alice@example.invalid "$PASS1"
keychain_put sdw:proj:admin bob@example.invalid "$PASS2"
keychain_put sdw:proj:editor dave@example.invalid "wrong-pass"

run sdw-login admin
expect_rc api-login 0
[ "$out" = "ok admin" ] || fail api-login "stdout '$out'"
python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["cookies"]; assert c[0]["name"]=="sid" and c[0]["httpOnly"]' "$auth/admin.json" \
  || fail api-login "storage state has no sid cookie"
grep -q 'sid' "$auth/admin.cookies" || fail api-login "cookie jar missing"
[ "$(mode "$auth/admin.json")" = 600 ] && [ "$(mode "$auth/admin.cookies")" = 600 ] \
  || fail api-login "auth files not mode 600"
grep -q 'http://localhost:5173/api/login' "$STUB_LOG/curl.urls" || fail api-login "relative api url not resolved with the app port"
grep -q -- '-s sdw:proj:admin -a alice@example.invalid -w' "$STUB_LOG/security.argv" || fail api-login "wrong Keychain lookup"
ok api-login

for f in curl.argv security.argv; do
  grep -qF 'PASS' "$STUB_LOG/$f" && fail secret-off-argv "password seen in $f"
done
case "$out$err" in *PASS*) fail secret-off-argv "password printed" ;; esac
ok secret-off-argv

export STUB_PASS="$PASS2"
run sdw-login admin-2
expect_rc second-user 0
[ "$out" = "ok admin-2" ] && [ -f "$auth/admin-2.json" ] || fail second-user "stdout '$out'"
tail -n 2 "$STUB_LOG/security.argv" | grep -q -- '-s sdw:proj:admin -a bob@example.invalid' || fail second-user "r-2 did not use the second user"
ok second-user

run sdw-login viewer
expect_rc keychain-missing 4
case "$err" in *"security add-generic-password -U -s 'sdw:proj:viewer' -a 'carol@example.invalid' -w"*) ;; *) fail keychain-missing "no store one-liner: $err" ;; esac
ok keychain-missing

run sdw-login editor
expect_rc rejected 1
[ -z "$out" ] || fail rejected "stdout not empty: $out"
ok rejected

run sdw-login ghost
expect_rc unknown-role 4
run sdw-login viewer-2
expect_rc unknown-second-user 4
ok unknown-role

run sdw-login admin --app sso
expect_rc oauth-manual 4
case "$err" in *"sdw-ui-shot --save-auth admin --url 'https://idp.example.invalid/start' --headed"*) ;; *) fail oauth-manual "$err" ;; esac
ok oauth-manual

export STUB_PASS="$PASS1"
rm -f "$STUB_LOG/node.argv"
run sdw-login admin --app admin-ui
expect_rc form-login 0
[ "$out" = "ok admin" ] || fail form-login "stdout '$out'"
grep -q -- '--url http://localhost:5173/login' "$STUB_LOG/node.argv" || fail form-login "node args: $(cat "$STUB_LOG/node.argv")"
grep -q -- '--success url:\*\*/dashboard' "$STUB_LOG/node.argv" || fail form-login "success marker not passed"
grep -qF 'PASS' "$STUB_LOG/node.argv" && fail form-login "password on node argv"
[ "$(cat "$STUB_LOG/node.stdin")" = "$PASS1" ] || fail form-login "password not on node stdin"
grep -q "$(printf '#HttpOnly_localhost\tFALSE\t/\tFALSE\t0\tauth\ttok1')" "$auth/admin.cookies" || fail form-login "jar not converted: $(cat "$auth/admin.cookies")"
ok form-login

run sdw-login
expect_rc usage 2
run sdw-login Admin
expect_rc usage 2
run sdw-login -h
expect_rc usage 0
ok usage

FAKE_PROJDIR="" run sdw-login admin
expect_rc not-onboarded 3
ok not-onboarded

mkdir -p "$tmp/nopy"
for b in bash awk grep sed cat mkdir rm chmod dirname tr head tail; do ln -s "$(command -v $b)" "$tmp/nopy/$b"; done
rm -f "$STUB_LOG/curl.argv"
out=$(PATH="$STUB:$tmp/nopy" "$FBIN/sdw-login" admin 2>"$tmp/stderr"); rc=$?; err=$(cat "$tmp/stderr")
expect_rc no-python3 4
[ ! -f "$STUB_LOG/curl.argv" ] || fail no-python3 "login request sent without python3"
ok no-python3

cp "$FAKE_PROJDIR/.sdw/run.md" "$tmp/run.md.orig"
cat >> "$FAKE_PROJDIR/.sdw/run.md" <<'EOF'
## login: hdr
- kind: header
- header: x-user: {user}
## login: jwt
- kind: api
- api: POST /api/token
- api-body: {"u":"{user}","p":"{pass}"}
- token-path: data.access_token
EOF
rm -f "$STUB_LOG/security.argv"
run sdw-login viewer --app hdr
expect_rc header-login 0
[ "$(cat "$auth/viewer.header")" = "x-user: carol@example.invalid" ] || fail header-login "header file: $(cat "$auth/viewer.header")"
[ "$(mode "$auth/viewer.header")" = 600 ] || fail header-login "not mode 600"
[ ! -s "$STUB_LOG/security.argv" ] || fail header-login "Keychain read for a header without {pass}"
ok header-login

printf '%s\n' '#!/usr/bin/env bash' 'out=""' \
  'while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift 2 ;; --data-binary) cat > /dev/null; shift 2 ;; *) shift ;; esac; done' \
  'printf %s "{\"data\":{\"access_token\":\"tok-SECRET-1\"}}" > "$out"' 'printf 200' > "$STUB/curl"
chmod +x "$STUB/curl"
run sdw-login admin --app jwt
expect_rc token-login 0
[ "$(cat "$auth/admin.header")" = "Authorization: Bearer tok-SECRET-1" ] || fail token-login "header file: $(cat "$auth/admin.header")"
case "$out$err" in *tok-SECRET*) fail token-login "token printed" ;; esac
ls -a "$auth" | grep -q 'body$' && fail token-login "response body left behind"
ok token-login
cp "$tmp/run.md.orig" "$FAKE_PROJDIR/.sdw/run.md"

mv "$FAKE_PROJDIR/.sdw/run.md" "$tmp/run.md.bak"
run sdw-login admin
expect_rc no-run-md 4
ok no-run-md
