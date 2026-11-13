#!/usr/bin/env bash
# SessionStart: inject core rules, project facts and a few state lines (≤9,000 chars); export env.sh to the Bash tool.
set -u
rc=0
trap 'rc=$?; if [ "$rc" != 0 ]; then echo "sdw: session-start error ($rc)" >&2; exit 0; fi' EXIT
. "${0%/*}/lib.sh"
sdw_have_json || { echo "sdw: session-start needs jq or python3" >&2; exit 0; }

MAX=9000
sdw_read_input
CWD=$(sdw_cwd)
SID=$(sdw_jget .session_id)
SRC=$(sdw_jget .source)
SRC=${SRC:-startup}
case "$SID" in */*|.*) SID=$(printf '%s' "$SID" | tr '/.' '__') ;; esac

CORE=$(cat "$SDW_ROOT/rules/core.md" 2>/dev/null)
PROJ=$(sdw_projdir "$CWD") || PROJ=""

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$(printf '%s' "$1" | sdw_jstr)"
  exit 0
}
blen() { printf '%s' "$1" | LC_ALL=C wc -c | tr -d ' '; }
# Byte-capped cut that never leaves a broken UTF-8 sequence.
cut_bytes() { printf '%s' "$1" | head -c "$2" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null; }
# Whole lines within $2 bytes, plus a note when anything was dropped ($3 set: lines were dropped already).
cut_lines() {
  local note="(project.md truncated; see .sdw/project.md)" out
  if [ "$(blen "$1")" -le "$2" ] && [ -z "${3:-}" ]; then printf '%s' "$1"; return; fi
  [ "$2" -gt $((${#note} + 1)) ] || return 0
  out=$(cut_bytes "$1" $(($2 - ${#note} - 1)))
  case "$1" in "$out"|"$out"$'\n'*) ;; *) out=$(printf '%s\n' "$out" | sed '$d') ;; esac
  printf '%s%s' "${out:+$out
}" "$note"
}

[ -n "$PROJ" ] || emit "$CORE"

SDW="$PROJ/.sdw"
sdw_source_env "$PROJ"
if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -f "$SDW/env.sh" ]; then
  q=$(printf '%s' "$SDW/env.sh" | sed "s/'/'\\\\''/g")
  printf "source '%s'\n" "$q" >> "$CLAUDE_ENV_FILE"
fi
[ -d "$SDW/state/stop" ] && find "$SDW/state/stop" -type f -mtime +7 -delete 2>/dev/null

bin() { b=$1; shift; (cd "$CWD" && "$SDW_BIN/$b" "$@") 2>/dev/null; }

PROJECT=""
if [ -f "$SDW/project.md" ]; then
  if [ "$(grep -c '' "$SDW/project.md")" -gt 40 ]; then
    PROJECT=$(cut_lines "$(head -n 39 "$SDW/project.md")" 2500 more)
  else
    PROJECT=$(cut_lines "$(cat "$SDW/project.md")" 2500)
  fi
  PROJECT="## Project (.sdw/project.md)
$PROJECT"
fi

# ---- state lines ----
STATE=""
add() { [ -n "$1" ] && STATE="${STATE:+$STATE
}$1"; }
BASE=$(bin sdw-cfg BASE_BRANCH); BASE=${BASE:-main}
checkouts() {
  local top common r
  if top=$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null); then
    common=$(cd "$top" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
    if [ "${common##*/}" = .git ]; then r=${common%/.git}; r=${r##*/}; else r=${top##*/}; fi
    printf '%s\t%s\n' "$(cd "$top" && pwd -P)" "$r"
  fi
  bin sdw-workdir --repos | while IFS= read -r r; do printf '%s\t%s\n' "$r" "${r##*/}"; done
}
n=0
while IFS="$(printf '\t')" read -r co repo; do
  [ -n "$co" ] && [ $n -lt 3 ] || continue
  br=$(cd "$co" && git symbolic-ref --short -q HEAD 2>/dev/null) || br=""
  dirty=$(cd "$co" && git status --porcelain 2>/dev/null | grep -c . | tr -d ' ')
  [ -n "$br" ] && [ "$br" = "$BASE" ] && [ "$dirty" = 0 ] && continue
  line="branch ${br:-detached} ($repo) · dirty $dirty"
  if (cd "$co" && git rev-parse -q --verify "origin/$BASE" >/dev/null 2>&1); then
    line="$line · ahead $(cd "$co" && git rev-list --count "origin/$BASE..HEAD" 2>/dev/null)"
  fi
  add "$line"; n=$((n + 1))
done <<EOF
$(checkouts)
EOF
STATE=$(printf '%s\n' "$STATE" | awk '!seen[$0]++' | head -n 3)

WD=$(bin sdw-workdir --no-create) || WD=""
if [ -n "$WD" ] && [ -d "$WD" ]; then
  if [ -f "$WD/plan.md" ]; then
    lane=$(sed -n 's/^Lane:[[:space:]]*\([A-Z]*\).*/\1/p' "$WD/plan.md" | head -n 1)
    total=$(grep -Ec '^\|[[:space:]]*AC-[0-9]+' "$WD/plan.md")
    pass=$(grep -E '^\|[[:space:]]*AC-[0-9]+' "$WD/plan.md" | grep -Ec '\|[[:space:]]*PASS[[:space:]]*\|')
    add "lane ${lane:-?} · AC $pass/$total"
  fi
  if [ -f "$WD/qa-report.md" ]; then
    verdict=$(sed -n 's/^Verdict:[[:space:]]*//p' "$WD/qa-report.md" | head -n 1)
    st=$(bin sdw-evidence list --kind qa --valid-for WORKTREE | head -n 1)
    [ -n "$st" ] && v=valid || v=stale
    add "QA ${verdict:-PENDING} ($v)"
  fi
  if [ -d "$WD/bugs" ]; then
    s1=0 s2=0
    for f in "$WD"/bugs/BUG-*.md; do
      [ -f "$f" ] || continue
      grep -Eiq '^Status:[[:space:]]*open' "$f" || continue
      grep -Eq '^Severity:[[:space:]]*S1' "$f" && s1=$((s1 + 1))
      grep -Eq '^Severity:[[:space:]]*S2' "$f" && s2=$((s2 + 1))
    done
    [ $((s1 + s2)) -gt 0 ] && add "open bugs S1 $s1 S2 $s2"
  fi
  if [ -f "$WD/review.md" ]; then
    o=$(sed -n 's/^Open:[[:space:]]*//p' "$WD/review.md" | head -n 1)
    r1=$(printf '%s' "$o" | sed -n 's/.*S1[[:space:]]*\([0-9]*\).*/\1/p')
    r2=$(printf '%s' "$o" | sed -n 's/.*S2[[:space:]]*\([0-9]*\).*/\1/p')
    [ -n "$o" ] && add "review open S1 ${r1:-?} S2 ${r2:-?}"
  fi
fi
if [ -n "$SID" ] && [ -f "$SDW/state/stop/$SID" ]; then
  res=$(awk '{ print $2; exit }' "$SDW/state/stop/$SID")
  [ -n "$res" ] && add "gate $res at last stop"
fi
STATE=$(printf '%s\n' "$STATE" | grep -v '^$' | head -n 8)
[ -n "$STATE" ] && STATE="## State
$STATE"

# ---- only when something is wrong ----
WARN=""
tc=$(cd "$PROJ" && "$SDW_BIN/sdw-toolchain" --brief 2>/dev/null | head -n 3)
[ -n "$tc" ] && WARN=$tc
DOCS=$(bin sdw-cfg DOCS_DIR)
if [ -n "$DOCS" ] && [ -d "$PROJ/$DOCS" ]; then
  df=$(cd "$PROJ" && "$SDW_BIN/sdw-docs-freshness" --docs "$PROJ/$DOCS" --brief 2>/dev/null | head -n 2)
  [ -n "$df" ] && WARN="${WARN:+$WARN
}$df"
fi

EXTRA=""
if [ "$SRC" = compact ]; then
  mod=$(bin sdw-gate --changes | awk -F'\t' '{ print $2 ":" $3 }' | head -n 20)
  gates=$(bin sdw-gate --dry-run | head -n 5)
  [ -n "$mod" ] && EXTRA="Modified:
$mod"
  [ -n "$gates" ] && EXTRA="${EXTRA:+$EXTRA
}Gates:
$gates"
fi

join() {
  local out="" part
  for part in "$@"; do [ -n "$part" ] && out="${out:+$out

}$part"; done
  printf '%s' "$out"
}

TEXT=$(join "$CORE" "$PROJECT" "$STATE" "$WARN" "$EXTRA")
[ "$(blen "$TEXT")" -le $MAX ] || TEXT=$(join "$CORE" "$PROJECT" "$STATE" "$WARN")
[ "$(blen "$TEXT")" -le $MAX ] || TEXT=$(join "$CORE" "$PROJECT" "$STATE")
if [ "$(blen "$TEXT")" -gt $MAX ]; then
  room=$((MAX - $(blen "$(join "$CORE" "x" "$STATE")") + 1))
  [ "$room" -gt 0 ] || room=0
  PROJECT=$(cut_lines "$PROJECT" "$room")
  TEXT=$(join "$CORE" "$PROJECT" "$STATE")
fi
[ "$(blen "$TEXT")" -le $MAX ] || TEXT=$(cut_bytes "$TEXT" $MAX)
emit "$TEXT"
