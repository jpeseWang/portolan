#!/usr/bin/env bash
# PostToolUse(Edit|Write): end the QA design phase when sdw:qa writes complete cases.md (snapshot kept); format with the repo's own formatter only.
set -u
trap 'exit 0' EXIT
. "${0%/*}/lib.sh"
sdw_have_json || exit 0

sdw_read_input
FILE=$(sdw_jget .tool_input.file_path)
[ -n "$FILE" ] || exit 0
CWD=$(sdw_cwd)
AGENT=$(sdw_jget .agent_type)
SID=$(sdw_jget .session_id)
P=$(sdw_resolve "$CWD" "$FILE")
[ -f "$P" ] || exit 0

# Design ends only with a case per AC: at least one TC row, and every AC-n of plan.md in a Source cell.
cases_complete() {
  local d=$1 ac
  grep -Eq '^\|[[:space:]]*TC-[0-9]+' "$d/cases.md" || return 1
  [ -f "$d/plan.md" ] || return 0
  for ac in $(grep -Eo '^\|[[:space:]]*AC-[0-9]+' "$d/plan.md" | grep -Eo 'AC-[0-9]+' | sort -u); do
    awk -F'|' -v ac="$ac" '$2 ~ /TC-[0-9]+/ && $3 ~ ("(^|[^0-9A-Za-z-])" ac "([^0-9]|$)") { f = 1 } END { exit !f }' "$d/cases.md" || return 1
  done
}

case "$AGENT" in
  sdw:qa)
    PROJ=$(sdw_projdir "$CWD") || exit 0
    case "$P" in
      "$PROJ/.sdw/work/"*/cases.md)
        d=${P%/cases.md}
        [ "${d%/*}" = "$PROJ/.sdw/work" ] || exit 0
        [ "$(head -n 1 "$d/.qa-phase" 2>/dev/null)" = design ] || exit 0
        cases_complete "$d" || exit 0
        cp "$P" "$d/.cases.design.md" && printf 'execute\n' > "$d/.qa-phase" ;;
    esac
    exit 0 ;;
  sdw:*) exit 0 ;;
esac
case "$P" in */.sdw/*) exit 0 ;; esac

DIR=${P%/*}
TOP=$(cd "$DIR" && git rev-parse --show-toplevel 2>/dev/null) && TOP=$(cd "$TOP" && pwd -P) || exit 0
REL=${P#"$TOP"/}
PROJ=$(sdw_projdir "$CWD") || PROJ=""
sdw_source_env "$PROJ"

# Nearest dir from the file up to the git toplevel that satisfies test "$1".
up_find() {
  local d=$DIR
  while :; do
    if "$@" "$d"; then printf '%s\n' "$d"; return 0; fi
    [ "$d" = "$TOP" ] || [ "$d" = / ] && return 1
    d=${d%/*}; [ -n "$d" ] || d=/
  done
}
has_prettier() {
  local f
  for f in "$1"/.prettierrc "$1"/.prettierrc.* "$1"/prettier.config.*; do [ -f "$f" ] && return 0; done
  [ -f "$1/package.json" ] && grep -q '"prettier"[[:space:]]*:' "$1/package.json"
}
has_biome() { [ -f "$1/biome.json" ] || [ -f "$1/biome.jsonc" ]; }
has_py_fmt() { [ -f "$1/pyproject.toml" ] && grep -Eq '^\[tool\.(ruff|black)' "$1/pyproject.toml"; }
has_csharpier() { [ -f "$1/.config/dotnet-tools.json" ] && grep -qi csharpier "$1/.config/dotnet-tools.json"; }
node_bin() { local d=$DIR; while :; do [ -x "$d/node_modules/.bin/$1" ] && { printf '%s\n' "$d/node_modules/.bin/$1"; return 0; }; [ "$d" = "$TOP" ] || [ "$d" = / ] && return 1; d=${d%/*}; done; }
venv_bin() { local d=$DIR v; while :; do for v in .venv venv; do [ -x "$d/$v/bin/$1" ] && { printf '%s\n' "$d/$v/bin/$1"; return 0; }; done; [ "$d" = "$TOP" ] || [ "$d" = / ] && return 1; d=${d%/*}; done; }

TOOL="" BIN=""
case "$P" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.mts|*.cts|*.vue|*.css|*.scss|*.less|*.json|*.html|*.svelte|*.astro|*.yml|*.yaml)
    if up_find has_prettier >/dev/null && BIN=$(node_bin prettier); then TOOL=prettier
    elif up_find has_biome >/dev/null && BIN=$(node_bin biome); then TOOL=biome
    fi ;;
  *.py)
    if up_find has_py_fmt >/dev/null; then
      if grep -q '^\[tool\.ruff' "$(up_find has_py_fmt)/pyproject.toml" && BIN=$(venv_bin ruff); then TOOL=ruff
      elif BIN=$(venv_bin black); then TOOL=black
      fi
    fi ;;
  *.cs) up_find has_csharpier >/dev/null && command -v dotnet >/dev/null 2>&1 && TOOL=csharpier ;;
esac
[ -n "$TOOL" ] || exit 0

CACHE_DIR="${TMPDIR:-/tmp}"; CACHE_DIR="${CACHE_DIR%/}/sdw"
mkdir -p "$CACHE_DIR" 2>/dev/null
CACHE="$CACHE_DIR/fmt-${SID:-nosession}.txt"
TAB=$(printf '\t')

# HEAD's version must already be formatted, so legacy files never churn.
head_clean() {
  local tmp rc
  case "$TOOL" in
    prettier) git show "HEAD:$REL" | "$BIN" --check --stdin-filepath "$P" >/dev/null 2>&1 ;;
    biome) tmp=$(git show "HEAD:$REL") && [ "$(printf '%s\n' "$tmp" | "$BIN" format --stdin-file-path="$P" 2>/dev/null)" = "$tmp" ] ;;
    ruff) git show "HEAD:$REL" | "$BIN" format --check --stdin-filename "$P" - >/dev/null 2>&1 ;;
    black) git show "HEAD:$REL" | "$BIN" --check -q - >/dev/null 2>&1 ;;
    csharpier)
      tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdw-cs.XXXXXX") || return 1
      git show "HEAD:$REL" > "$tmp/${P##*/}" 2>/dev/null
      dotnet csharpier check "$tmp/${P##*/}" >/dev/null 2>&1 || dotnet csharpier --check "$tmp/${P##*/}" >/dev/null 2>&1
      rc=$?; rm -rf "$tmp"; return $rc ;;
  esac
}

verdict=$(awk -F'\t' -v p="$P" '$1 == p { v = $2 } END { print v }' "$CACHE" 2>/dev/null)
if [ -z "$verdict" ]; then
  if ! (cd "$TOP" && git cat-file -e "HEAD:$REL" 2>/dev/null); then verdict=ok
  elif (cd "$TOP" && head_clean); then verdict=ok
  else verdict=skip
  fi
  printf '%s%s%s\n' "$P" "$TAB" "$verdict" >> "$CACHE"
fi
[ "$verdict" = ok ] || exit 0

case "$TOOL" in
  prettier) (cd "$TOP" && "$BIN" --write "$P") >/dev/null 2>&1 ;;
  biome) (cd "$TOP" && "$BIN" format --write "$P") >/dev/null 2>&1 ;;
  ruff) (cd "$TOP" && "$BIN" format "$P") >/dev/null 2>&1 ;;
  black) (cd "$TOP" && "$BIN" -q "$P") >/dev/null 2>&1 ;;
  csharpier) (cd "$TOP" && { dotnet csharpier format "$P" || dotnet csharpier "$P"; }) >/dev/null 2>&1 ;;
esac
exit 0
