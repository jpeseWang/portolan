#!/usr/bin/env bash
# PreToolUse(Read|Grep|Glob|WebFetch|WebSearch|Agent|Task|mcp__*): no secret reads; sdw:qa reads only
# .sdw/, the plugin and spec paths during QA design, and uses no tool beyond Playwright MCP.
set -u
rc=0
trap 'rc=$?; if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then echo "sdw: guard error ($rc)" >&2; exit 2; fi' EXIT
. "${0%/*}/lib.sh"
sdw_have_json || { echo "sdw: install jq" >&2; exit 2; }

sdw_read_input
sdw_valid_input || { echo "sdw: guard error (bad input)" >&2; exit 2; }
TOOL=$(sdw_jget .tool_name)
AGENT=$(sdw_jget .agent_type)
CWD=$(sdw_cwd)

deny() { echo "sdw: blocked — $1; $2" >&2; exit 2; }

case "$TOOL" in
  Read|Grep|Glob) ;;
  *)
    if [ "$AGENT" = sdw:qa ]; then
      case "$TOOL" in
        mcp__playwright__*|mcp__plugin_playwright_playwright__*) ;;
        *) deny "sdw:qa cannot use $TOOL" "QA tests the app with curl, sdw-ui-shot, playwright-cli or Playwright MCP; it files nothing" ;;
      esac
    fi
    exit 0 ;;
esac

F=$(sdw_jget .tool_input.file_path)
[ -n "$F" ] || F=$(sdw_jget .tool_input.path)
if [ -z "$F" ] && [ "$TOOL" = Glob ]; then
  G=$(sdw_jget .tool_input.pattern)
  case "$G" in /*) F=${G%%[*?[{]*}; F=${F%/*} ;; esac
fi
[ -n "$F" ] || F=.
P=$(sdw_resolve "$CWD" "$F")

if sdw_secret_file "$P"; then
  case "$SDW_SK" in
    session) deny "$F is a saved login session" "use --role, sdw-login and curl -b <jar> without reading it" ;;
    env) [ "$TOOL" = Glob ] || sdw_benign_env "$P" || deny "reading $F would put secrets in the transcript" "read the .example file, or ask the user for the key name" ;;
    *) [ "$TOOL" = Glob ] || deny "reading $F would put secrets in the transcript" "ask the user; key material never enters the transcript" ;;
  esac
fi
G=$(sdw_jget .tool_input.glob)
if [ -n "$G" ] && [ "$TOOL" != Glob ]; then
  g=${G##*/}
  sdw_secret_name "$g" && deny "grepping $G would put secrets in the transcript" "grep the .example file"
  case "$g" in
    *.[eE][xX][aA][mM][pP][lL][eE]|*.[sS][aA][mM][pP][lL][eE]|*.[tT][eE][mM][pP][lL][aA][tT][eE]) ;;
    *[eE][nN][vV]*|.*)
      for n in .env .env.local .env.production .env.development.local; do
        # shellcheck disable=SC2254
        case "$n" in $g) deny "grepping $G would put secrets in the transcript" "grep the .example file" ;; esac
      done ;;
  esac
fi

if [ "$AGENT" = sdw:qa ]; then
  PROJ=$(sdw_projdir "$CWD") || exit 0
  QWD=$(sdw_qa_wd "$PROJ" "$CWD")
  if sdw_qa_design "$PROJ" "$QWD"; then
    sdw_in_roots "$P" "$(sdw_design_roots "$PROJ")" ||
      deny "QA is in the design phase; cases come from the ticket, ACs and spec, not the code ($F)" "read .sdw/, the plugin and the run.md spec paths until cases.md is written"
  fi
fi
exit 0
