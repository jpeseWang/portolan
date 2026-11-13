# Shared hook helpers. Sourced, never run. JSON via jq, else python3.

SDW_ROOT=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}
SDW_BIN="$SDW_ROOT/bin"
SDW_INPUT=""

sdw_have_json() {
  command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1
}

sdw_read_input() { SDW_INPUT=$(cat); }

# True when the input is a JSON object; guards fail closed otherwise.
sdw_valid_input() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$SDW_INPUT" | jq -e 'type == "object"' >/dev/null 2>&1
  else
    printf '%s' "$SDW_INPUT" | python3 -c 'import json, sys; sys.exit(0 if isinstance(json.load(sys.stdin), dict) else 1)' >/dev/null 2>&1
  fi
}

# sdw_jget .a.b -> string value ("" when missing; booleans as true/false).
sdw_jget() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$SDW_INPUT" | jq -r "$1"' | if . == null then "" elif type == "string" then . else tojson end' 2>/dev/null
  else
    printf '%s' "$SDW_INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for k in sys.argv[1].strip(".").split("."):
    d = d.get(k) if isinstance(d, dict) else None
if d is None:
    sys.exit(0)
sys.stdout.write(d if isinstance(d, str) else json.dumps(d))' "$1" 2>/dev/null
  fi
}

# JSON string literal of stdin.
sdw_jstr() {
  if command -v jq >/dev/null 2>&1; then jq -Rs .
  else python3 -c 'import json, sys; sys.stdout.write(json.dumps(sys.stdin.read()))'
  fi
}

# The session's working dir: stdin .cwd, else $CLAUDE_PROJECT_DIR, else $PWD.
sdw_cwd() {
  local c
  c=$(sdw_jget .cwd)
  if [ -n "$c" ] && [ -d "$c" ]; then printf '%s\n' "$c"
  elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then printf '%s\n' "$CLAUDE_PROJECT_DIR"
  else pwd
  fi
}

sdw_projdir() { (cd "$1" 2>/dev/null && "$SDW_BIN/sdw-workdir" --projdir 2>/dev/null); }

sdw_source_env() {
  if [ -n "${1:-}" ] && [ -f "$1/.sdw/env.sh" ]; then
    set +u
    . "$1/.sdw/env.sh" >/dev/null 2>&1
    set -u
  fi
  return 0
}

# Lexical normalisation of $2 against base $1, then the longest existing ancestor made physical.
sdw_resolve() {
  local base=$1 p=$2 out="" seg rest existing tail
  case "$p" in /*) ;; *) p="$base/$p" ;; esac
  local IFS=/
  set -f
  for seg in $p; do
    case "$seg" in
      ''|.) ;;
      ..) out=${out%/*} ;;
      *) out="$out/$seg" ;;
    esac
  done
  set +f
  unset IFS
  [ -n "$out" ] || out=/
  existing=$out tail=""
  while [ "$existing" != / ] && [ ! -d "$existing" ]; do
    tail="/${existing##*/}$tail"
    existing=${existing%/*}
    [ -n "$existing" ] || existing=/
  done
  rest=$(cd "$existing" 2>/dev/null && pwd -P) || rest=$existing
  [ "$rest" = / ] && rest=""
  printf '%s\n' "${rest}${tail:-}" | sed 's#^$#/#'
}

# True when path $1 equals or lies under dir $2 (both already resolved).
sdw_under() {
  [ -n "$2" ] || return 1
  [ "$1" = "$2" ] && return 0
  case "$1" in "${2%/}"/*) return 0 ;; esac
  return 1
}

# Work dir under QA: .sdw/state/qa-active (set with the phase), else the branch of $2. Empty when unknown.
sdw_qa_wd() {
  local b=""
  [ -f "$1/.sdw/state/qa-active" ] && b=$(head -n 1 "$1/.sdw/state/qa-active")
  [ -n "$b" ] || b=$(cd "$2" 2>/dev/null && "$SDW_BIN/sdw-workdir" --branch 2>/dev/null)
  case "$b" in ''|*/*|.|..) return 0 ;; esac
  printf '%s\n' "$1/.sdw/work/$b"
}

# QA design phase for the work dir under QA; unknown work dir → any work dir in design.
sdw_qa_design() {
  local f
  if [ -n "$2" ]; then
    [ -f "$2/.qa-phase" ] && [ "$(head -n 1 "$2/.qa-phase")" = design ]
    return
  fi
  for f in "$1"/.sdw/work/*/.qa-phase; do
    [ -f "$f" ] && [ "$(head -n 1 "$f")" = design ] && return 0
  done
  return 1
}

# Paths sdw:qa may read in the design phase: .sdw/, the plugin, and run.md "## qa" "- spec:" entries.
sdw_design_roots() {
  printf '%s\n' "$1/.sdw" "$SDW_ROOT"
  [ -f "$1/.sdw/run.md" ] || return 0
  awk '/^## /{ s = ($0 ~ /^## qa[[:space:]]*$/) } s && /^- spec:/ { sub(/^- spec:[ \t]*/, ""); n = split($0, a, ","); for (i = 1; i <= n; i++) { gsub(/^[ \t]+|[ \t]+$/, "", a[i]); if (a[i] != "" && a[i] != "none") print a[i] } }' "$1/.sdw/run.md" |
    while IFS= read -r p; do
      case "$p" in /*) sdw_resolve / "$p" ;; *) sdw_resolve "$1" "$p" ;; esac
    done
}

# True when resolved path $1 lies in one of the newline-separated roots $2.
sdw_in_roots() {
  local r
  while IFS= read -r r; do
    [ -n "$r" ] && sdw_under "$1" "$r" && return 0
  done <<EOF
$2
EOF
  return 1
}

# A secret-bearing file name: .env or .env.* except templates (case-insensitive, no fork).
sdw_secret_name() {
  case "${1##*/}" in
    *.[eE][xX][aA][mM][pP][lL][eE]|*.[sS][aA][mM][pP][lL][eE]|*.[tT][eE][mM][pP][lL][aA][tT][eE]) return 1 ;;
    .[eE][nN][vV]|.[eE][nN][vV].*) return 0 ;;
  esac
  return 1
}

# Secret content that must stay out of the transcript: .env files, key material, saved logins.
# Sets SDW_SK to env, key or session.
sdw_secret_file() {
  local nc=0
  SDW_SK='env'
  sdw_secret_name "$1" && return 0
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  SDW_SK=""
  case "${1##*/}" in
    .envrc|*.pem|*.key|*.p12|*.pfx|*.jks|id_rsa*|id_ed25519*|.auth.json|*.auth.json) SDW_SK=key ;;
  esac
  case "/$1/" in */.sdw/auth/*|*/e2e/.auth/*|*/playwright/.auth/*) SDW_SK=session ;; esac
  [ "$nc" = 1 ] || shopt -u nocasematch
  [ -n "$SDW_SK" ]
}

# A tracked .env.* (never .env) whose committed and working copies name no secret-looking key.
sdw_benign_env() {
  local dir rel b=${1##*/}
  case "$b" in .[eE][nN][vV].*) ;; *) return 1 ;; esac
  dir=${1%/*}
  [ -d "$dir" ] || return 1
  rel=$(cd "$dir" && git ls-files --full-name --error-unmatch -- "$b" 2>/dev/null) || return 1
  [ -n "$rel" ] || return 1
  (cd "$dir" && git cat-file -e "HEAD:$rel" 2>/dev/null) || return 1
  ! { (cd "$dir" && git show "HEAD:$rel" 2>/dev/null); [ ! -f "$1" ] || cat "$1"; } |
    sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)=.*/\2/p' |
    grep -Eiq 'KEY|TOKEN|SECRET|PASSWORD'
}
