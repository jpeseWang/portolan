#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit): no secret files; sdw's own QA files are not editable; sdw:qa and sdw:reviewer write only their own work-dir files.
set -u
rc=0
trap 'rc=$?; if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then echo "sdw: guard error ($rc)" >&2; exit 2; fi' EXIT
. "${0%/*}/lib.sh"
sdw_have_json || { echo "sdw: install jq" >&2; exit 2; }

sdw_read_input
sdw_valid_input || { echo "sdw: guard error (bad input)" >&2; exit 2; }
FILE=$(sdw_jget .tool_input.file_path)
[ -n "$FILE" ] || FILE=$(sdw_jget .tool_input.notebook_path)
[ -n "$FILE" ] || exit 0
CWD=$(sdw_cwd)
AGENT=$(sdw_jget .agent_type)

deny() { echo "sdw: blocked — $1; $2" >&2; exit 2; }

P=$(sdw_resolve "$CWD" "$FILE")

# Names compare case-insensitively: the default macOS volume is case-insensitive.
check_path() {
  local p=$1 b
  b=$(printf '%s' "${p##*/}" | tr 'A-Z' 'a-z')
  if sdw_secret_file "$p"; then
    case "$SDW_SK" in
      env) sdw_benign_env "$p" || deny "$FILE holds live credentials" "edit the .example file and tell the user which key to set" ;;
      key) deny "$FILE is key or credential material" "never write secrets; the user stores them in the Keychain" ;;
      session) deny "$FILE is a saved login session" "sessions are written only by sdw-login" ;;
    esac
  fi
  case "$(printf '%s' "$p/" | tr 'A-Z' 'a-z')" in
    */.sdw/state/qa-active/) deny "$FILE is set with the QA phase" "the /sdw:qa skill sets it" ;;
  esac
  case "$b" in
    .qa-phase|.cases.design.md|.qa-start) deny "$FILE is written only by sdw" "the phase and the design snapshot are set by /sdw:qa and the post-edit hook" ;;
    review-raw.md) [ "$AGENT" = sdw:reviewer ] || deny "$FILE holds the reviewer's own words" "only sdw:reviewer writes it; record decisions in review.md" ;;
  esac
}

check_path "$P"
if [ -L "$P" ]; then
  T=$P n=0
  while [ -L "$T" ] && [ $n -lt 20 ]; do
    l=$(readlink "$T"); case "$l" in /*) T=$l ;; *) T="${T%/*}/$l" ;; esac; n=$((n + 1))
  done
  T=$(sdw_resolve / "$T")
  check_path "$T"
  P=$T
fi

case "$AGENT" in
  sdw:qa|sdw:reviewer)
    PROJ=$(sdw_projdir "$CWD") || deny "$AGENT cannot write: project dir not resolvable" "run from an onboarded project"
    W="$PROJ/.sdw/work"
    case "$P" in "$W"/*/*) ;; *) deny "$AGENT may write only under $W/" "write findings there; the author changes the repo" ;; esac
    if [ "$AGENT" = sdw:reviewer ]; then
      case "$P" in "$W"/*/review-raw.md) ;; *) deny "sdw:reviewer writes only <workdir>/review-raw.md" "return findings; the main session writes review.md" ;; esac
      exit 0
    fi
    QWD=$(sdw_qa_wd "$PROJ" "$CWD")
    if [ -n "$QWD" ]; then
      case "$P" in "$QWD"/*) ;; *) deny "sdw:qa writes only in the work dir under QA ($QWD)" "use the wd from the prompt" ;; esac
      REL=${P#"$QWD"/}
    else
      REL=${P#"$W"/*/}
    fi
    case "$REL" in
      cases.md|qa-report.md|shots/*) ;;
      bugs/BUG-[0-9]*.md) ;;
      *) deny "sdw:qa writes only cases.md, qa-report.md, bugs/BUG-nn.md and shots/" "plan.md, ticket.md and run.md are the yardstick, not QA's to change" ;;
    esac
    if [ "$REL" = qa-report.md ]; then
      C=$(sdw_jget .tool_input.content)
      [ -n "$C" ] || C=$(sdw_jget .tool_input.new_string)
      if printf '%s\n' "$C" | grep -Eq '^[[:space:]]*Verdict:' && printf '%s\n' "$C" | grep -E '^[[:space:]]*Verdict:' | grep -Evq '^[[:space:]]*Verdict:[[:space:]]*PENDING[[:space:]]*$'; then
        deny "sdw:qa cannot set the verdict" "write Verdict: PENDING; sdw-evidence qa-verdict computes it"
      fi
    fi
    ;;
esac
exit 0
