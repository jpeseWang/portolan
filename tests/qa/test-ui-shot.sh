#!/usr/bin/env bash
# sdw-ui-shot and the sdw-login form recipe against a local static page: capture, route mocking,
# axe, motion styles, vitals, --role storage state, navigation failure, prerequisite exits.
# Needs node >= 18 and a dir whose node_modules holds Playwright (SDW_QA_PW_APP); without them it prints SKIP and exits 0. Playwright's own
# browsers need not be installed: system Chrome is the fallback.
REAL_HOME=$HOME
. "$(dirname "$0")/_lib.sh"

node_ok() { [ -x "$1/node" ] && "$1/node" -e 'process.exit(+process.versions.node.split(".")[0] >= 18 ? 0 : 1)' 2>/dev/null; }
NODE_BIN=""
for d in ${SDW_QA_NODE_BIN:+"$SDW_QA_NODE_BIN"} $(ls -d "$REAL_HOME"/.nvm/versions/node/v*/bin 2>/dev/null | sort -r) \
  "$(dirname "$(command -v node 2>/dev/null || echo /none/node)")"; do
  node_ok "$d" && { NODE_BIN=$d; break; }
done
[ -n "$NODE_BIN" ] || { echo "SKIP ui-shot: no node >= 18"; exit 0; }
PW_APP=${SDW_QA_PW_APP:-}
[ -n "$PW_APP" ] && [ -d "$PW_APP/node_modules/playwright-core" ] \
  || { echo "SKIP ui-shot: set SDW_QA_PW_APP to a dir with node_modules/playwright-core"; exit 0; }
export PATH="$NODE_BIN:$PATH"

site="$tmp/site root"
mkdir -p "$site/api"
echo '{"v":1}' > "$site/api/data"
cat > "$site/index.html" <<'EOF'
<html><head><title>probe</title></head><body><h1>Probe</h1><div id="out">loading</div><div id="ck"></div>
<script>
document.getElementById('ck').textContent = document.cookie || 'none'
fetch('/api/data').then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json() })
  .then(function (d) { document.getElementById('out').textContent = 'ok ' + d.v })
  .catch(function (e) { console.error('load failed: ' + e.message); document.getElementById('out').textContent = 'error' })
  .then(function () { document.getElementById('out').setAttribute('data-done', '1') })
</script></body></html>
EOF
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
(cd "$site" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) &
server_pid=$!
url="http://127.0.0.1:$port/"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  python3 -c 'import sys, urllib.request; urllib.request.urlopen(sys.argv[1], timeout=1)' "$url" 2>/dev/null && break
  sleep 0.3
done

check() {
  python3 -c 'import json, sys; d = json.loads(sys.stdin.read()); sys.exit(0 if eval(sys.argv[1]) else 1)' "$2" <<< "$out" \
    || fail "$1" "$2 is false; stdout: $out; stderr: $err"
}
shots="$tmp/shots dir"
cd "$PW_APP" || fail setup "cannot cd to $PW_APP"

run sdw-ui-shot --url "$url" --out "$shots/plain.png" --wait '#out[data-done]' --measure '#out' --viewport 800x600
expect_rc capture 0
[ "$(head -c 8 "$shots/plain.png" | od -An -tx1 | tr -d ' \n')" = 89504e470d0a1a0a ] || fail capture "not a PNG"
check capture 'd["status"] == 200 and d["error"] is None and d["axe"] is None and d["requests"] == []'
check capture 'd["measure"]["#out"][0]["text"] == "ok 1" and d["viewport"] == "800x600@1x"'
case "$err" in *"trying system Chrome"*) echo "  (browser: system Chrome fallback)" ;; esac
ok capture

run sdw-ui-shot --url "$url" --out "$shots/500.png" --wait '#out[data-done]' --measure '#out' --route '**/api/data=500'
expect_rc route-500 0
check route-500 'any(r["url"].endswith("/api/data") and r.get("status") == 500 for r in d["requests"])'
check route-500 'any("load failed: HTTP 500" in c["text"] and c["type"] == "error" for c in d["console"])'
check route-500 'd["measure"]["#out"][0]["text"] == "error"'
ok route-500

run sdw-ui-shot --url "$url" --out "$shots/off.png" --wait '#out[data-done]' --measure '#out' --route '**/api/data=offline'
expect_rc route-offline 0
check route-offline 'any(r["url"].endswith("/api/data") and "failure" in r for r in d["requests"])'
check route-offline 'd["measure"]["#out"][0]["text"] == "error"'
ok route-offline

run sdw-ui-shot --url "$url" --out "$shots/empty.png" --wait '#out[data-done]' --measure '#out' --route '**/api/data=empty'
expect_rc route-empty 0
check route-empty 'd["measure"]["#out"][0]["text"] == "ok undefined" and d["requests"] == []'
ok route-empty

printf '{"items":[],"total":0}' > "$tmp/body.json"
run sdw-ui-shot --url "$url" --out "$shots/body.png" --wait '#out[data-done]' --measure '#out' --route "**/api/data=200:@$tmp/body.json"
expect_rc route-body 0
check route-body 'd["measure"]["#out"][0]["text"] == "ok undefined" and d["requests"] == []'
ok route-body

cat > "$site/form.html" <<'EOF2'
<html><body><input id="n"><button id="go">Save</button><div id="msg"></div>
<div id="tz"></div><script>
document.getElementById('tz').textContent = Intl.DateTimeFormat().resolvedOptions().timeZone + ' ' + navigator.language
document.getElementById('go').onclick = function () {
  fetch('/api/save', { method: 'POST', body: document.getElementById('n').value })
    .then(function (r) { document.getElementById('msg').textContent = r.status + ' ' + document.getElementById('n').value })
}
</script></body></html>
EOF2
run sdw-ui-shot --url "${url}form.html" --out "$shots/form.png" --fill '#n=Probe 1' --click '#go' \
  --route '**/api/save=422' --timezone Asia/Ho_Chi_Minh --locale fr-FR --measure '#msg' --measure '#tz'
expect_rc steps 0
check steps 'd["measure"]["#msg"][0]["text"] == "422 Probe 1" and d["steps"] == 2'
check steps 'd["measure"]["#tz"][0]["text"] in ("Asia/Ho_Chi_Minh fr-FR", "Asia/Saigon fr-FR") and d["timezone"] == "Asia/Ho_Chi_Minh"'
ok steps-timezone-locale

run sdw-ui-shot --url "$url" --out "$shots/axe.png" --axe
expect_rc axe 0
if printf '%s' "$out" | grep -q '"notRun"'; then
  check axe 'd["axe"]["violations"] == [] and "axe-core" in d["axe"]["notRun"]'
  echo "  (axe NOT RUN: no axe-core resolvable)"
else
  check axe 'any(v["id"] == "html-has-lang" and v["nodes"] == 1 for v in d["axe"]["violations"])'
fi
ok axe

cat > "$site/motion.html" <<'EOF2'
<html><head><style>
#b { transition: transform 150ms cubic-bezier(0.23, 1, 0.32, 1), opacity 150ms }
@media (prefers-reduced-motion: reduce) { #b { transition: none } }
</style></head><body><button id="b">Go</button><div id="slot"></div><p id="p">Probe text</p>
<script>
setTimeout(function () { var d = document.createElement('div'); d.style.height = '200px'; document.getElementById('slot').appendChild(d) }, 200)
document.getElementById('b').onclick = function () { var t = Date.now(); while (Date.now() - t < 120) {} document.getElementById('p').textContent = 'clicked' }
</script></body></html>
EOF2
run sdw-ui-shot --url "${url}motion.html" --out "$shots/motion-reduce.png" --motion '#b'
expect_rc motion-reduce 0
check motion-reduce 'd["reducedMotion"] == "reduce" and d["motion"]["#b"][0]["style"]["transitionDuration"] == "0s" and d["vitals"] is None'
run sdw-ui-shot --url "${url}motion.html" --out "$shots/motion.png" --motion '#b' --reduced-motion no-preference
expect_rc motion 0
check motion 'd["motion"]["#b"][0]["style"]["transitionProperty"] == "transform, opacity" and d["motion"]["#b"][0]["style"]["transitionDuration"] == "0.15s, 0.15s"'
run sdw-ui-shot --url "${url}motion.html" --out "$shots/x.png" --reduced-motion slow
expect_rc motion-usage 2
ok motion

run sdw-ui-shot --url "${url}motion.html" --out "$shots/vitals.png" --vitals --settle 800
expect_rc vitals 0
check vitals 'd["vitals"]["cls"] > 0 and d["vitals"]["shifts"][0]["sources"] and d["vitals"]["inpMs"] is None'
run sdw-ui-shot --url "${url}motion.html" --out "$shots/vitals-click.png" --vitals --click '#b' --measure '#p'
expect_rc vitals-click 0
check vitals-click 'd["vitals"]["inpMs"] is not None and d["vitals"]["inpMs"] >= 100 and d["measure"]["#p"][0]["text"] == "clicked"'
check vitals-click 'd["vitals"]["longTasks"]["count"] >= 1'
ok vitals

mkdir -p "$FAKE_PROJDIR/.sdw/auth"
printf '{"cookies":[{"name":"sid","value":"abc","domain":"127.0.0.1","path":"/","expires":-1,"httpOnly":false,"secure":false,"sameSite":"Lax"}],"origins":[]}' \
  > "$FAKE_PROJDIR/.sdw/auth/viewer.json"
run sdw-ui-shot --url "$url" --out "$shots/role.png" --role viewer --measure '#ck'
expect_rc role 0
check role 'd["measure"]["#ck"][0]["text"] == "sid=abc"'
run sdw-ui-shot --url "$url" --out "$shots/role.png" --role admin
expect_rc role-missing 4
printf 'X-User: hdr-user\n' > "$FAKE_PROJDIR/.sdw/auth/api.header"
run sdw-ui-shot --url "$url" --out "$shots/hdr.png" --role api --wait '#out[data-done]'
expect_rc role-header 0
FAKE_PROJDIR="" run sdw-ui-shot --url "$url" --out "$shots/role.png" --role viewer
expect_rc role-not-onboarded 3
ok role

cat > "$site/login.html" <<'EOF'
<html><body><input name="email"><input type="password" id="pw"><button id="go">Sign in</button>
<script>
document.getElementById('go').onclick = function () {
  if (document.getElementById('pw').value !== 'pw "ok"') return
  document.cookie = 'sid=xyz; path=/'
  location.href = '/dashboard.html'
}
</script></body></html>
EOF
echo '<html><body><h1 id="dash">Dashboard</h1></body></html>' > "$site/dashboard.html"
cat > "$FAKE_PROJDIR/.sdw/run.md" <<EOF
## app: web
- port: $port
## login
- kind: form
- url: /login.html
- user-field: input[name=email]
- pass-field: #pw
- submit: #go
- success: #dash
## users
- editor: erin@example.invalid
- viewer: vic@example.invalid
EOF
keychain_put sdw:proj:editor erin@example.invalid 'pw "ok"'
keychain_put sdw:proj:viewer vic@example.invalid 'wrong'
run sdw-login editor
expect_rc form-login-real 0
[ "$out" = "ok editor" ] || fail form-login-real "stdout '$out'"
grep -q 'sid' "$FAKE_PROJDIR/.sdw/auth/editor.cookies" || fail form-login-real "jar has no sid"
run sdw-login viewer
expect_rc form-login-rejected 1
case "$err" in *"success marker not seen"*) ;; *) fail form-login-rejected "$err" ;; esac
ok form-login-real

closed=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
run sdw-ui-shot --url "http://127.0.0.1:$closed/" --out "$shots/fail.png"
expect_rc nav-failed 1
check nav-failed 'd["error"] and "ERR_CONNECTION_REFUSED" in d["error"]'
ok nav-failed

run sdw-ui-shot --url "$url" --out "$shots/x.png" --route '**/api=teapot'
expect_rc usage 2
run sdw-ui-shot --url "$url"
expect_rc usage 2
run sdw-ui-shot -h
expect_rc usage 0
ok usage

cd "$tmp" || fail setup "cd $tmp"
# PATH without a global playwright-cli, which would otherwise supply Playwright.
out=$(PATH="$STUB:$FBIN:$NODE_BIN:/usr/bin:/bin" SDW_OFFLINE=1 "$FBIN/sdw-ui-shot" --url "$url" --out "$shots/np.png" 2>"$tmp/stderr")
rc=$?; err=$(cat "$tmp/stderr")
expect_rc no-playwright 4
ok no-playwright

out=$(PATH="$FBIN:/usr/bin:/bin" "$FBIN/sdw-ui-shot" --url "$url" --out "$shots/nn.png" 2>&1)
rc=$?
if [ -x /usr/bin/node ]; then echo "  (skipped no-node: /usr/bin/node exists)"; else expect_rc no-node 4; fi
ok no-node
