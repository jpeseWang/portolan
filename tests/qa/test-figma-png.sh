#!/usr/bin/env bash
# sdw-figma-png: meta + images only, token via curl -K stdin, cache keyed by lastModified,
# cache (unverified) fallback, exit codes.
. "$(dirname "$0")/_lib.sh"

TOKEN='figd_TESTTOKEN_123'
export STUB_MOD='2026-01-02T03:04:05Z'
python3 -c 'import sys; from PIL import Image; Image.new("RGB",(40,30),(1,2,3)).save(sys.argv[1])' "$tmp/render.png" \
  || { echo "SKIP figma-png: Pillow missing"; exit 0; }
export STUB_RENDER="$tmp/render.png"

cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG/curl.argv"
out="" url="" cfg=0
while [ $# -gt 0 ]; do
  case "$1" in
    -K) [ "$2" = "-" ] && cfg=1; shift 2 ;;
    -o) out=$2; shift 2 ;;
    -w|--max-time) shift 2 ;;
    http*) url=$1; shift ;;
    *) shift ;;
  esac
done
[ "$cfg" = 1 ] && cat >> "$STUB_LOG/curl.config"
case "$url" in
  */v1/files/*/meta)
    [ -n "${STUB_META_FAIL:-}" ] && { echo '{"status":429}' > "$out"; printf 429; exit 0; }
    printf '{"file":{"name":"x","last_touched_at":"%s"}}' "$STUB_MOD" > "$out"; printf 200 ;;
  */v1/images/*)
    echo "$url" >> "$STUB_LOG/images.calls"
    id=$(printf '%s' "$url" | sed 's/.*ids=\([^&]*\).*/\1/; s/%3A/:/g')
    printf '{"err":null,"images":{"%s":"https://render.example.invalid/r.png"}}' "$id" > "$out"; printf 200 ;;
  https://render.example.invalid/*)
    cp "$STUB_RENDER" "$out"; printf 200 ;;
  *) printf 404 ;;
esac
EOF
chmod +x "$STUB/curl"

run sdw-figma-png KEYabc 12:345
expect_rc token-missing 4
case "$err" in *"security add-generic-password -U -s 'sdw:figma'"*) ;; *) fail token-missing "$err" ;; esac
ok token-missing

keychain_put sdw:figma figma "$TOKEN"
want="$FAKE_PROJDIR/.sdw/design-refs/KEYabc/12-345@2x-2026-01-02T03-04-05Z.png"
run sdw-figma-png KEYabc 12:345
expect_rc fetch 0
[ "$out" = "$want" ] || fail fetch "path '$out', want '$want'"
[ -s "$want" ] || fail fetch "render not written"
grep -q "X-Figma-Token: $TOKEN" "$STUB_LOG/curl.config" || fail fetch "token not sent through -K stdin"
grep -q 'ids=12%3A345&scale=2&format=png' "$STUB_LOG/images.calls" || fail fetch "images query: $(cat "$STUB_LOG/images.calls")"
ok fetch

grep -qF "$TOKEN" "$STUB_LOG/curl.argv" && fail secret-off-argv "token on curl argv"
case "$out$err" in *"$TOKEN"*) fail secret-off-argv "token printed" ;; esac
grep 'render.example.invalid' "$STUB_LOG/curl.argv" | grep -q -- '-K' && fail secret-off-argv "token sent to the render host"
grep -q '/nodes' "$STUB_LOG/curl.argv" && fail no-nodes "called /nodes"
ok secret-off-argv

run sdw-figma-png KEYabc 12-345
expect_rc cache-hit 0
[ "$out" = "$want" ] || fail cache-hit "path '$out'"
[ "$(wc -l < "$STUB_LOG/images.calls" | tr -d ' ')" = 1 ] || fail cache-hit "images endpoint called again"
ok cache-hit

STUB_META_FAIL=1 run sdw-figma-png KEYabc 12:345
expect_rc cache-unverified 0
[ "$out" = "$want" ] || fail cache-unverified "path '$out'"
case "$err" in *"cache (unverified)"*) ;; *) fail cache-unverified "stderr: $err" ;; esac
ok cache-unverified

STUB_META_FAIL=1 run sdw-figma-png KEYabc 99:1
expect_rc api-error 1
case "$err" in *429*) ;; *) fail api-error "status not on stderr: $err" ;; esac
ok api-error

export STUB_MOD='2026-02-01T00:00:00Z'
run sdw-figma-png KEYabc 12:345 --scale 1
expect_rc new-version 0
[ "$out" = "$FAKE_PROJDIR/.sdw/design-refs/KEYabc/12-345@1x-2026-02-01T00-00-00Z.png" ] || fail new-version "path '$out'"
ok new-version

run sdw-figma-png KEYabc
expect_rc usage 2
run sdw-figma-png KEYabc 12:345 --format jpg
expect_rc usage 2
run sdw-figma-png -h
expect_rc usage 0
ok usage

FAKE_PROJDIR="" run sdw-figma-png KEYabc 12:345
expect_rc not-onboarded 3
ok not-onboarded
