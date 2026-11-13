#!/usr/bin/env bash
# Stop: a turn that changed code cannot end on a red fast gate. Unchanged fingerprint since the last stop
# passes (question-only turns), and stop_hook_active never blocks. docs/internals.md §4.6.
set -u
BLOCKING=0
rc=0
trap 'rc=$?; if [ "$BLOCKING" != 1 ] && [ "$rc" != 0 ]; then echo "sdw: stop-gate error ($rc)" >&2; exit 0; fi' EXIT
. "${0%/*}/lib.sh"
sdw_have_json || { echo "sdw: stop-gate needs jq or python3" >&2; exit 0; }

sdw_read_input
CWD=$(sdw_cwd)
SID=$(sdw_jget .session_id)
ACTIVE=$(sdw_jget .stop_hook_active)
SID=${SID:-nosession}
case "$SID" in */*|.*) SID=$(printf '%s' "$SID" | tr '/.' '__') ;; esac

PROJ=$(sdw_projdir "$CWD") || exit 0
[ -f "$PROJ/.sdw/gates" ] || exit 0
sdw_source_env "$PROJ"

gate() { (cd "$CWD" && "$SDW_BIN/sdw-gate" "$@"); }
sysmsg() { printf '{"systemMessage":%s}\n' "$(printf '%s' "$1" | sdw_jstr)"; }

FP=$(gate --fingerprint 2>/dev/null) || exit 0
REC="$PROJ/.sdw/state/stop/$SID"
if [ -z "$FP" ]; then rm -f "$REC"; exit 0; fi
LAST_FP="" LAST_RES="" LAST_KEYS=""
[ -f "$REC" ] && read -r LAST_FP LAST_RES LAST_KEYS < "$REC"

if [ "$FP" = "$LAST_FP" ]; then
  if [ "$ACTIVE" = true ] && [ "$LAST_RES" = red ]; then sysmsg "sdw: still red after a retry: $LAST_KEYS"; fi
  exit 0
fi

OUT=$(gate --fast 2>&1); RC=$?
if [ "$RC" -ne 0 ] && [ "$RC" -ne 1 ]; then
  sysmsg "sdw: fast gate could not run (exit $RC): $(printf '%s' "$OUT" | tail -n 3)"
  exit 0
fi
if [ "$RC" = 0 ]; then
  RES=green KEYS=$(printf '%s\n' "$OUT" | sed -n 's/^green //p' | tail -n 1)
else
  RES=red KEYS=$(printf '%s\n' "$OUT" | sed -n 's/^--- \([^ ]*\) (.*/\1/p' | paste -sd, -)
fi
mkdir -p "$PROJ/.sdw/state/stop"
printf '%s %s %s\n' "$FP" "$RES" "$KEYS" > "$REC"

if [ "$ACTIVE" = true ]; then
  [ "$RES" = red ] && sysmsg "sdw: still red after a retry: $KEYS"
  exit 0
fi

TAMPER=""
if [ -x "$SDW_BIN/sdw-tamper" ]; then
  while IFS= read -r co; do
    [ -n "$co" ] || continue
    TAMPER="$TAMPER$(cd "$co" && "$SDW_BIN/sdw-tamper" 2>/dev/null | sed "s#^#$(basename "$co"): #")
"
  done <<EOF
$(gate --changes 2>/dev/null | cut -f1 | LC_ALL=C sort -u)
EOF
  TAMPER=$(printf '%s' "$TAMPER" | grep -v '^$' | head -n 10)
fi

if [ "$RES" = green ]; then
  [ -n "$TAMPER" ] && sysmsg "sdw: test changes to justify:
$TAMPER"
  exit 0
fi

MSG="The fast gate failed; fix the cause (never the test, lint rule or type) or say plainly it is still red.
$(printf '%s\n' "$OUT" | grep -v '^red ' | head -c 4000)"
[ -n "$TAMPER" ] && MSG="$MSG
Also (not blocking):
$TAMPER"
if [ "${SDW_STOP_MODE:-exit2}" = json ]; then
  printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$MSG" | sdw_jstr)"
  exit 0
fi
printf '%s\n' "$MSG" >&2
BLOCKING=1
exit 2
