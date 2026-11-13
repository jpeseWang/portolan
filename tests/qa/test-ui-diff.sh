#!/usr/bin/env bash
# sdw-ui-diff: region report, written images, evidence entry, scaling, exit codes.
. "$(dirname "$0")/_lib.sh"

python3 -c 'import PIL' 2>/dev/null || { echo "SKIP ui-diff: Pillow missing"; exit 0; }
img="$tmp/imgs dir"
mkdir -p "$img"
python3 - "$img" <<'EOF'
import sys
from PIL import Image, ImageDraw
d = sys.argv[1]
def frame(x, scale=1):
    im = Image.new("RGB", (320 * scale, 200 * scale), "white")
    ImageDraw.Draw(im).rectangle((x * scale, 64 * scale, (x + 63) * scale, 127 * scale), fill="black")
    return im
frame(0).save(f"{d}/design.png")
frame(0).save(f"{d}/same.png")
frame(128).save(f"{d}/app.png")
frame(0, 2).save(f"{d}/design@2x.png")
EOF

run sdw-ui-diff "$img/design.png" "$img/app.png" --out "$tmp/out/settings" --key /settings --path apps/web
expect_rc regions 0
case "$out" in *"mismatch: 12.8% of pixels"*) ;; *) fail regions "mismatch line: $out" ;; esac
printf '%s\n' "$out" | grep -Eq '^  x +0-64 +y +64-128 +100%' || fail regions "design-only block not reported: $out"
printf '%s\n' "$out" | grep -Eq '^  x +128-192 +y +64-128 +100%' || fail regions "app-only block not reported: $out"
for k in side-by-side overlay heatmap; do
  [ -s "$tmp/out/settings.$k.png" ] || fail regions "missing $k image"
done
ok regions

ev=$(cat "$EVID_LOG")
for want in add "--kind" ui-diff "--key" /settings "--result" info "--detail" "mismatch=12.8%" "--path" apps/web \
  "$tmp/out/settings.heatmap.png"; do
  printf '%s\n' "$ev" | grep -qxF -- "$want" || fail evidence "missing '$want' in: $ev"
done
[ "$(printf '%s\n' "$ev" | grep -c -- '^--artifact$')" = 3 ] || fail evidence "expected 3 artifacts"
ok evidence

rm -f "$EVID_LOG"
run sdw-ui-diff "$img/design.png" "$img/same.png" --out "$tmp/out/same"
expect_rc identical 0
case "$out" in *"mismatch: 0.0%"*"no region above the reporting floor"*) ;; *) fail identical "$out" ;; esac
grep -qxF -- same.png "$EVID_LOG" && grep -qxF -- . "$EVID_LOG" || fail identical "default key/path not used: $(cat "$EVID_LOG")"
ok identical

run sdw-ui-diff "$img/design@2x.png" "$img/same.png" --out "$tmp/out/scaled" --no-evidence
expect_rc scaled 0
case "$out" in *"mismatch: 0."*|*"mismatch: 1."*) ;; *) fail scaled "2x design not scaled to app width: $out" ;; esac
ok scaled

rm -f "$EVID_LOG"
run sdw-ui-diff "$img/design.png" "$img/app.png" --out "$tmp/out/ne" --no-evidence
[ ! -e "$EVID_LOG" ] || fail no-evidence "evidence written"
ok no-evidence

EVID_RC=3 run sdw-ui-diff "$img/design.png" "$img/app.png" --out "$tmp/out/ev3"
expect_rc evidence-unavailable 0
case "$err" in *"evidence not recorded (3)"*) ;; *) fail evidence-unavailable "$err" ;; esac
ok evidence-unavailable

run sdw-ui-diff "$img/nope.png" "$img/app.png" --out "$tmp/out/x"
expect_rc missing-input 4
printf 'not an image' > "$img/bad.png"
run sdw-ui-diff "$img/bad.png" "$img/app.png" --out "$tmp/out/x"
expect_rc missing-input 4
ok missing-input

run sdw-ui-diff "$img/design.png"
expect_rc usage 2
run sdw-ui-diff "$img/design.png" "$img/app.png" --out "$tmp/out/x" --bogus
expect_rc usage 2
run sdw-ui-diff --help
expect_rc usage 0
ok usage
