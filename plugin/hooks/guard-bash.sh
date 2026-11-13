#!/usr/bin/env bash
# PreToolUse(Bash): DENY irreversible commands (exit 2), ASK on risky ones; DENY wins. docs/internals.md §4.3.
set -u
rc=0
trap 'rc=$?; if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then echo "sdw: guard error ($rc)" >&2; exit 2; fi' EXIT
. "${0%/*}/lib.sh"
sdw_have_json || { echo "sdw: install jq" >&2; exit 2; }

sdw_read_input
bad_input() { echo "sdw: guard error (bad input)" >&2; exit 2; }
if command -v jq >/dev/null 2>&1; then
  IN=$(printf '%s' "$SDW_INPUT" | jq -r 'if type == "object" then @sh "CMD=\(.tool_input.command // "" | tostring) CWD_IN=\(.cwd // "" | tostring) AGENT=\(.agent_type // "" | tostring)" else error end' 2>/dev/null) || bad_input
  case "$IN" in CMD=*) eval "$IN" ;; *) bad_input ;; esac
else
  sdw_valid_input || bad_input
  CMD=$(sdw_jget .tool_input.command) CWD_IN=$(sdw_jget .cwd) AGENT=$(sdw_jget .agent_type)
fi
[ -n "$CMD" ] || exit 0
if [ -n "$CWD_IN" ] && [ -d "$CWD_IN" ]; then CWD=$CWD_IN
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then CWD=$CLAUDE_PROJECT_DIR
else CWD=$(pwd)
fi
ASK_REASON=""
HOME_P=$(cd "$HOME" 2>/dev/null && pwd -P) || HOME_P=$HOME

deny() { echo "sdw: blocked — $1; $2" >&2; exit 2; }
ask() { [ -n "$ASK_REASON" ] || ASK_REASON=$1; }
# A soft ask: asks like ask(), but stays silent when SDW_RELAX=1 (unattended runs). Never used for a deny.
relaxed() { [ "${SDW_RELAX:-0}" = 1 ] || ask "$1"; }

CONF=0 SDWAG=0
case "$AGENT" in sdw:qa|sdw:reviewer) CONF=1 ;; esac
case "$AGENT" in sdw:*) SDWAG=1 ;; esac

PROJ_DONE=0 PROJ="" BOUND="" TOP=""
load_proj() {
  [ "$PROJ_DONE" = 1 ] && return 0
  PROJ_DONE=1
  PROJ=$(sdw_projdir "$CWD") || PROJ=""
  TOP=$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) && TOP=$(cd "$TOP" && pwd -P) || TOP=""
  BOUND=${PROJ:-${TOP:-$(cd "$CWD" && pwd -P)}}
}

TMPS=""
for t in "${TMPDIR:-}" /tmp /private/tmp; do
  [ -n "$t" ] || continue
  TMPS="$TMPS
${t%/}"
  [ -d "$t" ] && TMPS="$TMPS
$(cd "$t" && pwd -P)"
done

# Strictly under a temp root; the roots themselves hold every agent's scratch.
in_tmp() {
  local t
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    case "$1" in "${t%/}"/*) return 0 ;; esac
  done <<EOF
$TMPS
EOF
  return 1
}

is_tmp_root() {
  local t
  while IFS= read -r t; do
    [ -n "$t" ] && [ "$1" = "${t%/}" ] && return 0
  done <<EOF
$TMPS
EOF
  return 1
}

inside() { load_proj; sdw_under "$1" "$BOUND" || { [ -n "$TOP" ] && sdw_under "$1" "$TOP"; }; }

# $1 is a project, repo or temp root, or an ancestor of one.
root_or_above() {
  local b
  load_proj
  for b in "$BOUND" "$PROJ" "$TOP" "${PROJ:+$PROJ/.sdw}" "$HOME_P"; do
    [ -n "$b" ] && sdw_under "$b" "$1" && return 0
  done
  while IFS= read -r b; do
    [ -n "$b" ] && sdw_under "$b" "$1" && return 0
  done <<EOF
$TMPS
EOF
  return 1
}

unq() { UQ=$1; UQ=${UQ#\"}; UQ=${UQ%\"}; UQ=${UQ#\'}; UQ=${UQ%\'}; }

# Variables assigned earlier in this command: literal values and $(sdw-workdir [--projdir]).
VARS=""
var_get() {
  local l
  while IFS= read -r l; do
    case "$l" in "$1="*) VG=${l#*=}; return 0 ;; esac
  done <<EOF
$VARS
EOF
  return 1
}
var_del() { case "$VARS" in *"
$1="*) VARS=$(printf '%s\n' "$VARS" | grep -v "^$1=") ;; esac; }
var_set() { var_del "$1"; VARS="$VARS
$1=$2"; }

# Sets EX: ~, $HOME, $TMPDIR and tracked variables expanded; any other $ stays.
expand() {
  local u n rest
  unq "$1"; u=$UQ
  case "$u" in
    '${'[A-Za-z_]*'}"'*) n=${u%%\}*}; u="$n}${u#*\}\"}" ;;
    '$'[A-Za-z_]*'"'*) n=${u%%\"*}; case "${n#\$}" in *[!A-Za-z0-9_]*) ;; *) u="$n${u#*\"}" ;; esac ;;
  esac
  # shellcheck disable=SC2088
  case "$u" in
    '~') u=$HOME ;;
    '~/'*) u="$HOME/${u#'~/'}" ;;
    '$HOME'|'${HOME}') u=$HOME ;;
    '$HOME/'*) u="$HOME/${u#'$HOME/'}" ;;
    '${HOME}/'*) u="$HOME/${u#'${HOME}/'}" ;;
    '$TMPDIR'|'${TMPDIR}') u=${TMPDIR:-/tmp} ;;
    '$TMPDIR/'*) u="${TMPDIR:-/tmp}/${u#'$TMPDIR/'}" ;;
    '${TMPDIR}/'*) u="${TMPDIR:-/tmp}/${u#'${TMPDIR}/'}" ;;
    '${'[A-Za-z_]*'}'*)
      n=${u#'${'}; n=${n%%\}*}; rest=${u#'${'"$n"'}'}
      var_get "$n" && u="$VG$rest" ;;
    '$'[A-Za-z_]*)
      n=${u#'$'}; n=${n%%[!A-Za-z0-9_]*}; rest=${u#'$'"$n"}
      var_get "$n" && u="$VG$rest" ;;
  esac
  EX=$u
}

# Sets RP to $1 resolved against the effective cwd; fails when a cd made that unknown.
ECWD=$(cd "$CWD" 2>/dev/null && pwd -P) || ECWD=$CWD
res() {
  case "$1" in /*) RP=$(sdw_resolve / "$1"); return 0 ;; esac
  [ -n "$ECWD" ] || return 1
  RP=$(sdw_resolve "$ECWD" "$1")
}

BASES_DONE=0 BASES=""
load_bases() {
  [ "$BASES_DONE" = 1 ] && return 0
  BASES_DONE=1
  BASES=" main master develop $(cd "$CWD" && "$SDW_BIN/sdw-cfg" BASE_BRANCH 2>/dev/null) "
}
is_base() { [ -n "$1" ] || return 1; load_bases; case "$BASES" in *" $1 "*) return 0 ;; esac; return 1; }
GDIR="" TAB=$(printf '\t')
# Branches an earlier checkout/switch in this command moved to: "<toplevel><TAB><branch>", ? = unknown.
SWITCHED=""
gtop() { (cd "$GDIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || printf '%s\n' "$GDIR"; }
cur_branch() {
  [ -n "$GDIR" ] || return 0
  if [ -n "$SWITCHED" ]; then
    local top l b="" hit=0
    top=$(gtop)
    while IFS= read -r l; do case "$l" in "$top$TAB"*) b=${l#*"$TAB"}; hit=1 ;; esac; done <<EOF
$SWITCHED
EOF
    [ "$hit" = 1 ] && { printf '%s\n' "$b"; return 0; }
  fi
  (cd "$GDIR" 2>/dev/null && git symbolic-ref --short -q HEAD 2>/dev/null)
}
note_switch() {
  local sub=$1 a b="" n=0 new="" nx=0 det=0 v p
  shift
  [ -n "$GDIR" ] || return 0
  for a in "$@"; do
    if [ "$nx" = 1 ]; then new=$a; nx=0; continue; fi
    case "$a" in
      --) return 0 ;;
      -b|-B|-c|-C|--orphan|--create|--force-create) nx=1 ;;
      --orphan=*|--create=*|--force-create=*) new=${a#*=} ;;
      --detach|-d) det=1 ;;
      -) n=$((n + 1)); [ $n = 1 ] && b=- ;;
      -*|*'>'*|*'<'*) ;;
      *) n=$((n + 1)); [ $n = 1 ] && b=$a ;;
    esac
  done
  if [ -n "$new" ]; then v=$new
  elif [ "$det" = 1 ]; then v='?'
  elif [ $n = 0 ] || { [ "$sub" = checkout ] && [ $n -gt 1 ]; }; then return 0
  else v=$b
  fi
  if [ "$v" != '?' ]; then
    expand "$v"; v=$EX
    case "$v" in *'$'*|*'`'*|-|'') v='?' ;; esac
  fi
  if [ "$v" != '?' ] && [ -z "$new" ] && ! is_base "$v" &&
    ! (cd "$GDIR" 2>/dev/null && { git show-ref --verify -q "refs/heads/$v" || git for-each-ref --format=x "refs/remotes/*/$v" | grep -q .; }); then
    case "$v" in /*) p=$v ;; *) p=$GDIR/$v ;; esac
    [ "$sub" = checkout ] && [ -e "$p" ] && return 0
    v='?'
  fi
  SWITCHED="$SWITCHED
$(gtop)$TAB$v"
}
gdir_cd() {
  [ -n "$GDIR" ] || return 0
  expand "$1"
  case "$EX" in *'$'*|*'`'*|'') GDIR=""; return 0 ;; esac
  GDIR=$(sdw_resolve "$GDIR" "$EX")
  [ -d "$GDIR" ] || GDIR=""
}

QA_DONE=0 QA_WD="" WORK_DIR=""
load_qa() {
  [ "$QA_DONE" = 1 ] && return 0
  QA_DONE=1
  load_proj
  [ -n "$PROJ" ] || return 0
  WORK_DIR="$PROJ/.sdw/work"
  QA_WD=$(sdw_qa_wd "$PROJ" "$CWD")
}
QA_DESIGN=""
qa_design() {
  if [ -z "$QA_DESIGN" ]; then
    load_qa
    QA_DESIGN=no
    [ -n "$PROJ" ] && sdw_qa_design "$PROJ" "$QA_WD" && QA_DESIGN=yes
  fi
  [ "$QA_DESIGN" = yes ]
}

# Files only the hooks, the main session's sdw bins or one agent may write.
protected() {
  unq "$1"
  case "${UQ##*/}" in
    .qa-phase|.cases.design.md|.qa-start) return 0 ;;
    review-raw.md) [ "$AGENT" = sdw:reviewer ] && return 1; return 0 ;;
  esac
  return 1
}

# A write target an sdw agent may use: /dev/null, &N, or under the work dir (sdw:qa: its own work dir).
agent_target_ok() {
  local t
  unq "$1"; t=$UQ
  case "$t" in /dev/null|/dev/stdout|/dev/stderr|'&1'|'&2'|'&-'|-) return 0 ;; esac
  expand "$1"; t=$EX
  case "$t" in *'$'*|*'`'*|'') return 1 ;; esac
  load_qa
  [ -n "$WORK_DIR" ] || return 1
  res "$t" || return 1
  if [ "$AGENT" = sdw:qa ] && [ -n "$QA_WD" ]; then
    case "$RP" in "$QA_WD"/*) return 0 ;; esac
    return 1
  fi
  case "$RP" in "$WORK_DIR"/*/*) return 0 ;; esac
  return 1
}

check_target() {
  protected "$1" && deny "$1 is written only by sdw itself" "the phase, design snapshot and raw review are not editable"
  if confined; then
    agent_target_ok "$1" || deny "$AGENT may write only under <projdir>/.sdw/work/ (target: $1)" "write to the absolute work-dir path, or use the Write tool there"
  fi
  return 0
}

check_rm_target() {
  local t=$1 u
  unq "$t"; u=$UQ
  # shellcheck disable=SC2088
  case "$u" in
    /|'/*'|'~'|'~/'|'~/*'|'$HOME'|'${HOME}'|'$HOME/'|'${HOME}/'|'$HOME/*'|'${HOME}/*'|..|../|'*')
      deny "recursive delete of $t" "delete a specific path inside the project" ;;
  esac
  expand "$t"; u=$EX
  case "$u" in *'$'*|*'`'*) relaxed "rm -r on an unexpanded variable or command substitution: $t"; return 0 ;; esac
  case "$u" in
    .|''|*/*|*[*?[]*) ;;
    *)
      [ -n "$ECWD" ] || { relaxed "rm -r on a relative path after a cd: $t"; return 0; }
      RP="$ECWD/$u"
      in_tmp "$RP" || inside "$RP" || deny "recursive delete outside the project: $t" "delete paths inside the project, or use sdw-wt rm for worktrees"
      return 0 ;;
  esac
  res "$u" || { relaxed "rm -r on a relative path after a cd: $t"; return 0; }
  case "${RP##*/}" in
    *[*?[]*)
      local parent=${RP%/*}
      root_or_above "${parent:-/}" && deny "recursive delete of every file in a project, repo, home or temp root: $t" "delete specific paths inside it" ;;
  esac
  root_or_above "$RP" && deny "recursive delete of a project, repo, home or temp root: $t" "delete a specific path inside it"
  in_tmp "$RP" && return 0
  inside "$RP" || deny "recursive delete outside the project: $t" "delete paths inside the project, or use sdw-wt rm for worktrees"
}

# A word naming a .env file (other than a tracked, secret-free one), key material or a saved login.
secret_arg() {
  expand "$1"
  case "$EX" in *'$'*|*'`'*|'') return 1 ;; esac
  sdw_secret_file "$EX" || return 1
  [ "$SDW_SK" = env ] || return 0
  res "$EX" || return 0
  ! sdw_benign_env "$RP"
}

# Words that follow a redirect operator are not arguments.
args_only() {
  local skip=0 w
  for w in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$w" in
      *'>'|*'<') skip=1; continue ;;
      *'>'*|*'<'*) continue ;;
    esac
    printf '%s\n' "$w"
  done
}

redirect_targets() {
  local n=$# i=1 w t
  while [ $i -le $n ]; do
    eval "w=\${$i}"
    case "$w" in
      \"*|\'*) ;;
      *'>'*)
        t=${w#*>}; t=${t#>}; t=${t#|}
        if [ -z "$t" ] && [ $i -lt $n ]; then i=$((i + 1)); eval "t=\${$i}"; fi
        [ -n "$t" ] && printf '%s\n' "$t" ;;
    esac
    i=$((i + 1))
  done
}

check_git() {
  local sub="" a hooks=$HOOKSKIP
  GDIR=$ECWD
  [ -d "$GDIR" ] || GDIR=""
  [ $((GITENV + GITEXP)) = 0 ] || GDIR=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -c) case "${2:-}" in [cC][oO][rR][eE].[hH][oO][oO][kK][sS][pP][aA][tT][hH]=*) hooks=1 ;; esac; shift ;;
      -C) gdir_cd "${2:-}"; shift ;;
      --git-dir|--work-tree) GDIR=""; shift ;;
      --git-dir=*|--work-tree=*) GDIR="" ;;
      --namespace) shift ;;
      -*) ;;
      *) sub=$1; shift; break ;;
    esac
    shift
  done
  [ -n "$sub" ] || return 0
  if [ "$hooks" = 1 ]; then
    case "$sub" in commit|push|merge|rebase) deny "skipping the repo's hooks (core.hooksPath, HUSKY=0 and the like)" "fix what the hook reports" ;; esac
  fi
  case "$sub" in
    push) check_push "$@" ;;
    switch) note_switch switch "$@" ;;
    reset) for a in "$@"; do [ "$a" = --hard ] && deny "git reset --hard discards work" "commit to a throwaway branch first"; done ;;
    clean)
      for a in "$@"; do
        case "$a" in --force) deny "git clean -f deletes untracked files" "remove specific files by path" ;;
          --*) ;; -*f*) deny "git clean -f deletes untracked files" "remove specific files by path" ;; esac
      done ;;
    checkout)
      for a in "$@"; do
        case "$a" in .|./) deny "git checkout . discards every uncommitted change" "commit to a throwaway branch first" ;; esac
      done
      note_switch checkout "$@" ;;
    restore)
      local staged=0 wt=0
      for a in "$@"; do
        case "$a" in --staged) staged=1 ;; --worktree) wt=1 ;; --*) ;;
          -*) case "$a" in *S*) staged=1 ;; esac; case "$a" in *W*) wt=1 ;; esac ;; esac
      done
      [ "$staged" = 1 ] && [ "$wt" = 0 ] || deny "git restore discards work (and is not in git 2.15)" "commit to a throwaway branch first" ;;
    stash)
      case "${1:-}" in list|show) ;; *) deny "git stash is shared by every worktree and agent" "use a worktree or a throwaway commit" ;; esac ;;
    branch)
      local force=0 del=0 hard=0
      for a in "$@"; do
        case "$a" in
          -D|-*D*) hard=1 ;;
          -d|--delete) del=1 ;;
          -f|--force) force=1 ;;
          --*) ;;
          -*) case "$a" in *d*) del=1 ;; esac; case "$a" in *f*) force=1 ;; esac ;;
        esac
      done
      if [ "$hard" = 1 ] || { [ "$del" = 1 ] && [ "$force" = 1 ]; }; then
        for a in "$@"; do case "$a" in -*) ;; *) is_base "$a" && deny "deleting base branch $a" "leave base branches alone" ;; esac; done
      fi ;;
    commit)
      for a in "$@"; do
        case "$a" in --no-verify) deny "git commit --no-verify skips the repo's hooks" "fix what the hook reports" ;;
          --*) ;; -*n*) case "$a" in -*[!a-zA-Z]*) ;; *) deny "git commit -n skips the repo's hooks" "fix what the hook reports" ;; esac ;; esac
      done ;;
  esac
  if [ "$CONF" = 1 ]; then
    case "$sub" in add|commit|checkout|reset|apply|am|rebase|merge|cherry-pick|push|clean|restore|switch|mv|rm)
      deny "$AGENT cannot run git $sub" "report the finding; the author changes the repo" ;;
    esac
  fi
  return 0
}

check_push() {
  local a force=0 lease=0 all=0 del=0 dry=0 tags=0 skip=0 pos=() r dst cur i=0 plus colon
  for a in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$a" in
      --force) force=1 ;;
      --force-with-lease|--force-with-lease=*) lease=1 ;;
      --mirror|--all) all=1 ;;
      --delete) del=1 ;;
      --dry-run|-n) dry=1 ;;
      --tags) tags=1 ;;
      -o|--push-option|--repo|--receive-pack|--exec) skip=1 ;;
      --*) ;;
      -*) case "$a" in *f*) force=1 ;; esac; case "$a" in *d*) del=1 ;; esac ;;
      *'>'*|*'<'*) ;;
      *) pos+=("$a") ;;
    esac
  done
  cur=$(cur_branch)
  load_bases
  [ -n "$GDIR" ] && BASES="$BASES$(cd "$GDIR" 2>/dev/null && "$SDW_BIN/sdw-cfg" BASE_BRANCH 2>/dev/null) "
  [ "$cur" = '?' ] && GDIR="" cur=""
  if [ $((force + lease)) -gt 0 ] && [ "$all" = 1 ]; then deny "force push of every branch" "force-push one feature branch at a time"; fi
  [ "$dry" = 1 ] && [ $((force + lease)) = 0 ] && return 0
  [ "$all" = 1 ] && ask "push of every branch, base branches included"
  if [ ${#pos[@]} -le 1 ]; then
    if [ $((force + lease)) -gt 0 ]; then
      [ -n "$cur" ] && is_base "$cur" && deny "force push while on base branch $cur" "push to a feature branch and open a PR"
      [ "$force" = 1 ] && relaxed "force push of ${cur:-HEAD}; prefer --force-with-lease"
    fi
    [ "$tags" = 1 ] || push_dst "$cur"
    return 0
  fi
  for r in "${pos[@]}"; do
    i=$((i + 1))
    [ $i = 1 ] && continue
    unq "$r"; r=$UQ
    plus=0
    case "$r" in +*) plus=1; r=${r#+} ;; esac
    split_ref "$r"
    colon=$RCOLON
    if [ "$colon" = 1 ]; then expand "$RD"; else expand "$r"; fi
    dst=${EX#refs/heads/}
    if [ "$del" = 1 ] || { [ "$colon" = 1 ] && [ -z "$RS" ]; }; then
      is_base "$dst" && deny "deleting remote base branch $dst" "leave base branches alone"
      case "$dst" in *'$'*|*'`'*) relaxed "deleting a remote branch the guard cannot expand: $r" ;; esac
      continue
    fi
    case "$colon:$dst" in
      1:*'$'*|1:*'`'*) relaxed "push to a destination the guard cannot expand: $r"; continue ;;
      *:HEAD|*:@|0:*'$'*|0:*'`'*) dst=$cur; colon=cur ;;
    esac
    if [ $((force + lease + plus)) -gt 0 ]; then
      is_base "$dst" && deny "force push to base branch $dst" "push to a feature branch and open a PR"
      [ $((force + plus)) -gt 0 ] && relaxed "force push to ${dst:-HEAD}; prefer --force-with-lease"
    fi
    if [ "$colon" = cur ]; then push_dst "$dst"
    else is_base "$dst" && ask "push to base branch $dst; push a feature branch and open a PR"
    fi
  done
  return 0
}

# Sets RS and RD to the refspec's source and destination, split at the first ":" outside ${…}; RCOLON=1 when split.
split_ref() {
  local s=$1 n=${#1} i=0 d=0 c
  RS=$1 RD="" RCOLON=0
  while [ $i -lt $n ]; do
    c=${s:i:1}
    case "$c" in
      '{') [ $i -gt 0 ] && [ "${s:i-1:1}" = '$' ] && d=$((d + 1)) ;;
      '}') [ $d -gt 0 ] && d=$((d - 1)) ;;
      :) [ $d = 0 ] && { RS=${s:0:i}; RD=${s:i+1}; RCOLON=1; return 0; } ;;
    esac
    i=$((i + 1))
  done
}

push_dst() {
  if [ -z "$GDIR" ]; then relaxed "push from a directory the guard cannot resolve"
  elif is_base "$1"; then ask "push to base branch $1; push a feature branch and open a PR"
  fi
}

check_merge() {
  local tool=$1 w=() skip=0 a
  shift
  for a in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$a" in -R|--repo|--hostname) skip=1; continue ;; -*|*'>'*|*'<'*) continue ;; esac
    unq "$a"; w+=("$UQ")
    [ ${#w[@]} -ge 2 ] && break
  done
  case "$tool:${w[0]:-} ${w[1]:-}" in
    "gh:pr merge"|"glab:mr merge"|"glab:mr accept") relaxed "$tool ${w[0]} ${w[1]} merges into the base branch" ;;
  esac
  if [ "${w[0]:-}" = api ]; then
    for a in "$@"; do
      unq "$a"
      case "$UQ" in *mergePullRequest*|*mergeRequestAccept*) relaxed "$tool api merge mutation merges into the base branch"; return 0 ;; esac
      printf '%s\n' "$UQ" | grep -Eq '(^|/)(pulls|merge_requests)/[^/]+/merge([/?]|$)' && { relaxed "$tool api $UQ merges into the base branch"; return 0; }
    done
  fi
  return 0
}

check_docker() {
  local tool=$1 a w=() fl=" " skip=0 sub verb
  case "$tool" in docker-compose|podman-compose) w=(compose) ;; esac
  shift
  for a in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$a" in *'>'*|*'<'*) continue ;; esac
    unq "$a"; a=$UQ
    case "${#w[@]}:${w[0]:-}:$a" in
      0::-H|0::--host|0::-c|0::--context|0::--config|0::-l|0::--log-level|0::--connection|0::--url) skip=1; continue ;;
      1:compose:-f|1:compose:--file|1:compose:-p|1:compose:--project-name|1:compose:--env-file|1:compose:--profile|1:compose:--project-directory|1:compose:--ansi|1:compose:--progress|1:compose:--parallel) skip=1; continue ;;
    esac
    case "$a" in -*) fl="$fl$a " ;; *) w+=("$a") ;; esac
  done
  sub=${w[0]:-} verb=${w[1]:-}
  case "$sub:$verb" in
    system:prune)
      case "$fl" in *" --volumes "*|*" --volumes=true "*|*" --volumes=1 "*) deny "$tool system prune --volumes deletes data" "ask the user first" ;; esac
      relaxed "$tool system prune removes stopped containers and the data in them" ;;
    system:reset) deny "$tool system reset deletes every container, image and volume" "ask the user first" ;;
    container:prune) relaxed "$tool container prune removes stopped containers and the data in them" ;;
    image:prune) dflag a all "$fl" && relaxed "$tool image prune -a removes every unused image" ;;
    rm:*|container:rm|container:remove) relaxed "$tool rm deletes the data in the container's writable layer" ;;
    compose:rm) dflag v volumes "$fl" && relaxed "$tool compose rm -v removes containers and their anonymous volumes" ;;
    compose:down) case " $* " in *" --rmi all "*|*" --rmi=all "*) relaxed "$tool compose down --rmi all removes the images too" ;; esac ;;
  esac
  return 0
}

# dflag <short letter> <long name> <flags>: the flag alone, in a short cluster, or as --long[=…].
dflag() {
  local f
  set -f
  for f in $3; do
    case "$f" in "--$2"|"--$2="*) set +f; return 0 ;; --*) ;; -*"$1"*) set +f; return 0 ;; esac
  done
  set +f
  return 1
}

# Confined: sdw:qa/sdw:reviewer always; any other sdw agent when projdir is unknown.
confined() { [ "$CONF" = 1 ] || { [ "$SDWAG" = 1 ] && { load_proj; [ -z "$PROJ" ]; }; }; }

# sdw:qa in the design phase reads only ticket, plan, spec and run.md; everything else is denied.
ROOTS_DONE=0 ROOTS=""
design_path_ok() {
  local p
  if [ "$ROOTS_DONE" = 0 ]; then ROOTS_DONE=1; load_proj; ROOTS=$(sdw_design_roots "$PROJ"); fi
  expand "$1"; p=$EX
  case "$p" in
    *'`'*) return 1 ;;
    *'$'*)
      [ -n "$LOOPVAR" ] || return 1
      local q v x=${p//\$\{$LOOPVAR\}/}
      x=${x//\$$LOOPVAR/}
      case "$x" in *'$'*) return 1 ;; esac
      case "$p" in *"\$$LOOPVAR"[A-Za-z0-9_]*) return 1 ;; esac
      while IFS= read -r v; do
        [ -n "$v" ] || continue
        q=${p//\$\{$LOOPVAR\}/$v}; q=${q//\$$LOOPVAR/$v}
        res "$q" && sdw_in_roots "$RP" "$ROOTS" || return 1
      done <<EOF
$LOOPVALS
EOF
      return 0 ;;
  esac
  res "$p" || return 1
  sdw_in_roots "$RP" "$ROOTS"
}
check_design() {
  local cmd=$1 a skip1=0 seen=0 why="QA is in the design phase; cases come from the ticket, ACs and spec, not the code or diff"
  shift
  case "$cmd" in
    cd|sdw-workdir|sdw-cfg|sdw-evidence|sdw-figma-png|echo|printf|pwd|date|true|false|test|'['|']'|wc|sort|uniq|cut|tr|basename|dirname) return 0 ;;
    git)
      case "${1:-}" in
        rev-parse|symbolic-ref) return 0 ;;
        status) for a in "$@"; do case "$a" in -v|-vv|--verbose) deny "$why" "finish cases.md first" ;; esac; done; return 0 ;;
        branch) [ "${2:-}" = --show-current ] && return 0 ;;
      esac
      deny "$why" "finish cases.md first" ;;
    curl)
      for a in "$@"; do case "$a" in http://localhost*|http://127.0.0.1*|'"http://localhost'*|'"http://127.0.0.1'*) return 0 ;; esac; done
      deny "$why (curl only to the local app)" "finish cases.md first" ;;
    ls|cat|head|tail|less|more|mkdir) ;;
    grep|egrep|rg|sed|jq) skip1=1; for a in "$@"; do case "$a" in -e|-f|--regexp*|--file*) skip1=0 ;; esac; done ;;
    *) deny "$why ($cmd is not a reading command)" "finish cases.md first" ;;
  esac
  local skipn=0
  for a in "$@"; do
    if [ "$skipn" -gt 0 ]; then skipn=$((skipn - 1)); continue; fi
    case "$cmd:$a" in
      head:-[nc]|tail:-[nc]|grep:-[ABCme]|egrep:-[ABCme]|rg:-[ABCmegtT]|rg:--glob|rg:--type|rg:--regexp|sed:-e|jq:--indent) skipn=1; continue ;;
      jq:--arg|jq:--argjson) skipn=2; continue ;;
    esac
    case "$a" in -*|*'>'*|*'<'*|''|/dev/null|/dev/stdin|/dev/stdout|/dev/stderr) continue ;; esac
    case "$a" in *[!0-9]*) ;; *) continue ;; esac
    if [ "$skip1" = 1 ]; then skip1=0; continue; fi
    seen=1
    design_path_ok "$a" || deny "$why (path: $a)" "read only .sdw/, the plugin and run.md spec paths until cases.md is written"
  done
  if [ "$seen" = 0 ]; then
    case "$cmd" in ls|rg|grep|egrep) design_path_ok . || deny "$why ($cmd here reads the code)" "name a path under .sdw/ or a spec path" ;; esac
  fi
  return 0
}

DEPTH=0
# Re-check the script of `bash -c '…'`, `eval …` or `env -S '…'`.
nested() {
  local s save=$ECWD
  s=$(printf '%s' "$1" | tr '\002' '>')
  [ "$DEPTH" -lt 3 ] || deny "shell nested more than 3 levels" "run the command directly"
  case "$s" in \'*\') s=${s#\'}; s=${s%\'} ;; \"*\") s=${s#\"}; s=${s%\"} ;; esac
  DEPTH=$((DEPTH + 1))
  check_text "$s"
  DEPTH=$((DEPTH - 1))
  ECWD=$save
}

PENDING_VAR="" PENDING_CD="" HOOKSKIP=0 GITENV=0 GITEXP=0 LOOPVAR="" LOOPVALS=""
check_segment() {
  local seg=$1 W=() n ci=0 i wrap="" dur=0 cmd a args=() t last assigns=() pend=$PENDING_VAR pcd=$PENDING_CD
  PENDING_VAR="" PENDING_CD="" HOOKSKIP=0 GITENV=0
  case "$seg" in *[![:space:]]*) ;; *) PENDING_VAR=$pend PENDING_CD=$pcd; return 0 ;; esac
  set -f
  read -r -a W <<< "$seg"
  set +f
  n=${#W[@]}
  i=0
  # bash 3.2 substitution is quadratic, so long words go through tr.
  while [ $i -lt $n ]; do
    case "${W[i]}" in
      *$'\003'*) if [ ${#W[i]} -gt 512 ]; then W[i]=$(printf '%s' "${W[i]}" | tr '\003' ' '); else W[i]=${W[i]//$'\003'/ }; fi ;;
    esac
    i=$((i + 1))
  done
  while [ $ci -lt $n ]; do
    a=${W[ci]}
    case "$a" in
      [A-Za-z_]*=*)
        case "$a" in HUSKY=0|SKIP_SIMPLE_GIT_HOOKS=1|LEFTHOOK=0) HOOKSKIP=1 ;; GIT_DIR=*|GIT_WORK_TREE=*) GITENV=1 ;; esac
        [ -z "$wrap" ] && assigns+=("$a"); ci=$((ci + 1)); continue ;;
      done) LOOPVAR="" LOOPVALS=""; ci=$((ci + 1)); continue ;;
      if|then|else|elif|do|while|until|fi|'esac'|'!'|'{'|'}') ci=$((ci + 1)); continue ;;
      for|select)
        [ -z "$wrap" ] || break
        LOOPVAR="" LOOPVALS=""
        if [ "${W[ci + 2]:-}" = in ]; then
          LOOPVAR=${W[ci + 1]:-}
          i=$((ci + 3))
          while [ $i -lt $n ]; do
            unq "${W[i]}"
            case "$UQ" in *'$'*|*'`'*|*'"'*|*"'"*) LOOPVAR=""; break ;; esac
            LOOPVALS="$LOOPVALS$UQ
"
            i=$((i + 1))
          done
        fi
        return 0 ;;
      sudo|env|command|time|nohup|xargs|exec|nice|timeout|stdbuf|caffeinate)
        wrap=$a; [ "$a" = timeout ] && dur=1; ci=$((ci + 1)); continue ;;
      -*)
        if [ -n "$wrap" ]; then
          case "$wrap:$a" in
            env:-S) [ $((ci + 1)) -lt $n ] && nested "${W[ci + 1]}"; ci=$((ci + 2)) ;;
            sudo:-[ugChpDrtUT]|env:-[uC]|nice:-n|xargs:-[nIPLsdEa]|timeout:-[sk]|stdbuf:-[ioe]) ci=$((ci + 2)) ;;
            *) ci=$((ci + 1)) ;;
          esac
          continue
        fi ;;
    esac
    if [ "$dur" = 1 ]; then dur=0; ci=$((ci + 1)); continue; fi
    break
  done
  if [ $ci -ge $n ]; then
    for a in "${assigns[@]+"${assigns[@]}"}"; do
      t=${a#*=}; a=${a%%=*}
      case "$t" in
        '$'|'"$') PENDING_VAR=$a ;;
        *'`'*|*'$('*) var_del "$a" ;;
        *) expand "$t"; case "$EX" in *'$'*) var_del "$a" ;; *) var_set "$a" "$EX" ;; esac ;;
      esac
    done
    return 0
  fi
  cmd=${W[ci]}; cmd=${cmd#\\}; unq "$cmd"; cmd=${UQ##*/}
  args=("${W[@]:$((ci + 1))}")
  local rest=$cmd
  [ ${#args[@]} -gt 0 ] && rest="$cmd ${args[*]}"

  if [ -n "$pend" ]; then
    case "$rest" in
      "sdw-workdir"|"sdw-workdir --no-create") var_set "$pend" "$(cd "${ECWD:-$CWD}" 2>/dev/null && "$SDW_BIN/sdw-workdir" --no-create 2>/dev/null)" ;;
      "sdw-workdir --projdir") var_set "$pend" "$(cd "${ECWD:-$CWD}" 2>/dev/null && "$SDW_BIN/sdw-workdir" --projdir 2>/dev/null)" ;;
      *) var_del "$pend" ;;
    esac
  fi
  if [ -n "$pcd" ]; then
    case "$rest" in
      "sdw-workdir"|"sdw-workdir --no-create") ECWD=$(cd "$CWD" 2>/dev/null && t=$("$SDW_BIN/sdw-workdir" --no-create 2>/dev/null) && cd "$t" 2>/dev/null && pwd -P) || ECWD="" ;;
      "sdw-workdir --projdir") ECWD=$(cd "$CWD" 2>/dev/null && t=$("$SDW_BIN/sdw-workdir" --projdir 2>/dev/null) && cd "$t" 2>/dev/null && pwd -P) || ECWD="" ;;
    esac
  fi

  # Input redirection from a secret file, for every command.
  i=0
  for a in "${args[@]+"${args[@]}"}"; do
    i=$((i + 1))
    case "$a" in
      '<'|[0-9]'<') [ $i -lt ${#args[@]} ] && { secret_arg "${args[i]}" && deny "reading ${args[i]} would print secrets" "read the .example file, or ask the user for the key name"; } ;;
      '<'*|[0-9]'<'*) secret_arg "${a#*<}" && deny "reading $a would print secrets" "read the .example file, or ask the user for the key name" ;;
    esac
  done
  if [ "$cmd" = security ]; then
    case " ${args[*]:-} " in
      *" find-generic-password "*" -w "*|*" find-generic-password "*" -g "*|*" find-internet-password "*" -w "*|*" find-internet-password "*" -g "*)
        deny "printing a Keychain secret" "sdw bins read secrets; never print them" ;;
    esac
  fi

  if [ "$SDWAG" = 1 ]; then
    case "$seg" in *.sdw/auth*|*.auth/*)
      case "$cmd" in curl|sdw-ui-shot|sdw-login|ls|playwright-cli) ;;
        *) deny "$AGENT cannot read saved sessions" "use --role, sdw-login, curl -b <jar> or curl -H @<header file>" ;;
      esac ;;
    esac
    case "$seg" in
      *.[eE][nN][vV]*)
        t=$(printf '%s' "$seg" | tr '\003\047"(),;:=[]{}' '              ')
        set -f
        for a in $t; do sdw_secret_name "$a" && { set +f; deny "$AGENT cannot read $a" "secrets stay out of the transcript"; }; done
        set +f ;;
    esac
    case "$cmd" in cat|head|tail|ls|grep|rg|wc|diff|cmp|sdw-workdir|sdw-evidence) ;;
      *)
        for t in .qa-phase .cases.design.md .qa-start review-raw.md qa-active; do
          case "$seg" in *"$t"*) { protected "$t" || [ "$t" = qa-active ]; } && deny "sdw agents cannot change $t" "the phase, design snapshot and raw review are written by sdw" ;; esac
        done ;;
    esac
    i=0
    for a in "${W[@]}"; do
      i=$((i + 1))
      if [ "$a" = --phase ] && [ $i -lt $n ]; then
        case "${W[i]}" in *'>'*|*'<'*|'') ;; *) deny "sdw agents cannot set the QA phase" "the /sdw:qa skill and the post-edit hook set it" ;; esac
      fi
    done
  fi
  if [ "$AGENT" = sdw:qa ] && qa_design; then
    check_design "$cmd" "${args[@]+"${args[@]}"}"
  fi

  case "$seg" in *'>'*)
    while IFS= read -r t; do [ -n "$t" ] && check_target "$t"; done <<EOF
$(redirect_targets "${W[@]}")
EOF
  ;; esac

  case "$cmd" in
    cd|pushd)
      t=""
      for a in "${args[@]+"${args[@]}"}"; do case "$a" in -*) ;; *) t=$a; break ;; esac; done
      if [ -z "$t" ]; then ECWD=$HOME_P
      else
        expand "$t"
        case "$EX" in
          '$'|'"$') ECWD="" PENDING_CD=1 ;;
          *'$'*|*'`'*|-) ECWD="" ;;
          *) if res "$EX"; then ECWD=$RP; else ECWD=""; fi ;;
        esac
      fi ;;
    popd) ECWD="" ;;
    export) case " ${args[*]:-}" in *" GIT_DIR="*|*" GIT_WORK_TREE="*) GITEXP=1 ;; esac ;;
    bash|sh|zsh|dash|ksh)
      i=0
      for a in "${args[@]+"${args[@]}"}"; do
        i=$((i + 1))
        case "$a" in -c|-[a-zA-Z]*c|-[a-zA-Z]*c[a-zA-Z]*) [ $i -lt ${#args[@]} ] && nested "${args[i]}"; break ;; -*) ;; *) break ;; esac
      done ;;
    eval) [ ${#args[@]} -gt 0 ] && nested "${args[*]}" ;;
    tee|touch|mkdir)
      if [ "$SDWAG" = 1 ] || [ "$cmd" = tee ]; then
        while IFS= read -r t; do case "$t" in -*|'') ;; *) check_target "$t" ;; esac; done <<EOF
$(args_only "${args[@]+"${args[@]}"}")
EOF
      fi ;;
    curl|wget)
      local nx=""
      for a in "${args[@]+"${args[@]}"}"; do
        if [ -n "$nx" ]; then check_target "$a"; nx=""; continue; fi
        case "$cmd:$a" in
          curl:-o|curl:--output|curl:-[a-zA-Z]*o|wget:-O|wget:--output-document|wget:-[a-zA-Z]*O|wget:-P|wget:--directory-prefix) nx=1 ;;
          curl:--output=*|wget:--output-document=*|wget:--directory-prefix=*) check_target "${a#*=}" ;;
          curl:-o?*) check_target "${a#-o}" ;;
          wget:-O?*) check_target "${a#-O}" ;;
          curl:--remote-name*|curl:-O|curl:-[a-zA-Z]*O*) check_target "./curl-remote-name" ;;
        esac
      done ;;
    dd) for a in "${args[@]+"${args[@]}"}"; do case "$a" in of=*) check_target "${a#of=}" ;; esac; done ;;
    sdw-jira)
      i=0
      for a in "${args[@]+"${args[@]}"}"; do
        i=$((i + 1))
        [ "$a" = --out ] && [ $i -lt ${#args[@]} ] && check_target "${args[i]}"
      done ;;
    ln)
      if [ "$SDWAG" = 1 ]; then
        last=""
        for a in "${args[@]+"${args[@]}"}"; do case "$a" in -*) ;; *) last=$a ;; esac; done
        [ -n "$last" ] && check_target "$last"
      fi ;;
    rm)
      local rec=0 dd=0
      [ "$CONF" = 1 ] && deny "$AGENT cannot delete files" "report it; the author cleans up"
      while IFS= read -r a; do
        [ -n "$a" ] || continue
        if [ "$dd" = 0 ]; then
          case "$a" in
            --) dd=1; continue ;;
            --recursive) rec=1; continue ;;
            --*) continue ;;
            -*) case "$a" in *[rR]*) rec=1 ;; esac; continue ;;
          esac
        fi
        printf '%s\n' "$a"
      done > "$SDW_T/rm" <<EOF
$(args_only "${args[@]+"${args[@]}"}")
EOF
      while IFS= read -r t; do protected "$t" && deny "$t is written only by sdw itself" "leave it in place"; done < "$SDW_T/rm"
      if [ "$rec" = 1 ]; then
        while IFS= read -r t; do check_rm_target "$t"; done < "$SDW_T/rm"
      fi ;;
    mv)
      [ "$CONF" = 1 ] && deny "$AGENT cannot move files" "report it; the author changes the repo"
      for a in "${args[@]+"${args[@]}"}"; do protected "$a" && deny "$a is written only by sdw itself" "leave it in place"; done ;;
    cp)
      last=""
      while IFS= read -r a; do case "$a" in -*|'') ;; *) last=$a ;; esac; done <<EOF
$(args_only "${args[@]+"${args[@]}"}")
EOF
      [ -n "$last" ] && check_target "$last" ;;
    sed|perl)
      if confined; then
        for a in "${args[@]+"${args[@]}"}"; do
          t=${a#-}
          case "$a" in
            --in-place*|-i*) deny "$AGENT cannot edit files in place" "write findings to the work dir" ;;
            --*|-|-[Mm]*|-I*) ;;
            -*i*)
              if [ "$cmd" = perl ] || [ -z "${t//[a-zA-Z]/}" ]; then
                deny "$AGENT cannot edit files in place" "write findings to the work dir"
              fi ;;
          esac
        done
      fi ;;
    find)
      local roots=() del=0 prev="" seen_opt=0 filt=0
      for a in "${args[@]+"${args[@]}"}"; do
        case "$a" in -*|'('|'\('|'!') seen_opt=1 ;; esac
        case "$a" in -name|-iname|-path|-ipath|-regex|-iregex|-newer*|-mtime|-mmin|-size|-empty|-user|-perm) filt=1 ;; esac
        [ "$seen_opt" = 0 ] && case "$a" in *'>'*|*'<'*) ;; *) roots+=("$a") ;; esac
        [ "$a" = -delete ] && del=1
        case "$prev" in -exec|-execdir|-ok|-okdir) [ "${a##*/}" = rm ] && del=1 ;; esac
        prev=$a
      done
      if [ "$del" = 1 ]; then
        [ ${#roots[@]} -gt 0 ] || roots=(.)
        for t in "${roots[@]}"; do
          expand "$t"
          case "$EX" in *'$'*|*'`'*) ask "find -delete on an unexpanded variable: $t"; continue ;; esac
          res "$EX" || { ask "find -delete on a relative root after a cd: $t"; continue; }
          [ "$filt" = 0 ] && root_or_above "$RP" && deny "find -delete with no filter over a project, repo, home or temp root: $t" "add -name/-path, or narrow the root"
          in_tmp "$RP" || inside "$RP" || { [ "$filt" = 1 ] && is_tmp_root "$RP"; } || deny "find -delete outside the project: $t" "narrow the root to a path inside the project"
        done
      fi ;;
    git) check_git "${args[@]+"${args[@]}"}" ;;
    gh|glab) check_merge "$cmd" "${args[@]+"${args[@]}"}" ;;
    docker|podman|docker-compose|podman-compose) check_docker "$cmd" "${args[@]+"${args[@]}"}" ;;
  esac

  case "$cmd" in
    cat|head|tail|less|more|grep|egrep|rg|bat|sed|awk|gawk|sort|uniq|cut|diff|comm|nl|tac|rev|paste|column|fold|xxd|od|hexdump|strings|base64|jq|yq|view)
      while IFS= read -r a; do
        secret_arg "$a" && deny "reading $a would print secrets" "read the .example file, or ask the user for the key name"
      done <<EOF
$(args_only "${args[@]+"${args[@]}"}")
EOF
      ;;
  esac

  if [ "$CONF" = 1 ]; then
    case "$cmd" in
      npx|npm|pnpm|pnpx|yarn|bun|bunx|uvx|pipx|jest|vitest|playwright|dotnet|eslint|prettier|biome|stylelint|ruff|black)
        local tool=$cmd fmt="$AGENT cannot rewrite files with a formatter or autofix"
        case "$cmd" in npx|pnpx|bunx|uvx|pipx) for a in "${args[@]+"${args[@]}"}"; do case "$a" in -*) ;; *) tool=${a##*/}; break ;; esac; done ;; esac
        for a in "${args[@]+"${args[@]}"}"; do
          case "$a" in
            -u|--update|--update-snapshots|--update-snapshots=*|--updateSnapshot)
              deny "$AGENT cannot update snapshots or baselines" "report the visual or snapshot change as a finding" ;;
            --fix|--fix-type*|--write|--apply|--apply-unsafe) deny "$fmt" "report the finding; the author changes the repo" ;;
            -w) case "$tool" in prettier|biome) deny "$fmt" "report the finding; the author changes the repo" ;; esac ;;
          esac
        done
        case "$tool:: $rest " in
          dotnet::*" format "*) case " $rest " in *" --verify-no-changes "*) ;; *) deny "$fmt" "use dotnet format --verify-no-changes" ;; esac ;;
          ruff::*" format "*|black::*) case " $rest " in *" --check "*) ;; *) deny "$fmt" "add --check" ;; esac ;;
        esac ;;
    esac
  fi

  case "$cmd" in
    prisma|npx|pnpm|yarn|bunx|bun|npm|typeorm|ts-node|dotnet|rails|bundle|docker|docker-compose|podman|podman-compose|rake)
      case "$rest" in *'prisma migrate reset'*) deny "prisma migrate reset wipes the database" "run it yourself after checking which database this is" ;; esac
      case "$rest" in *'prisma db push'*) case "$rest" in *--force-reset*|*--accept-data-loss*) deny "prisma db push with data loss" "write a migration instead" ;; esac ;; esac
      case "$rest" in *schema:drop*|*schema:sync*) deny "typeorm schema drop/sync" "write a migration instead" ;; esac
      case "$rest" in *'ef database drop'*) deny "dotnet ef database drop" "run it yourself after checking which database this is" ;; esac
      case "$rest " in *'ef database update 0 '*) deny "dotnet ef database update 0 reverts every migration" "revert to a named migration, after asking" ;; esac
      case " $rest " in *' db:drop '*) deny "rails db:drop" "run it yourself after checking which database this is" ;; esac
      case "$rest " in *compose*' down '*) case "$rest " in *' -v '*|*' --volumes'*) deny "docker compose down -v deletes volumes" "docker compose down (keeps the data)" ;; esac ;; esac
      case "$rest" in *'volume rm'*|*'volume prune'*) deny "docker volume rm/prune deletes data" "ask the user first" ;; esac
      case "$rest" in *'ef migrations remove'*) ask "dotnet ef migrations remove" ;; esac
      case "$rest" in *'ef database update'*|*'prisma migrate deploy'*|*migration:run*)
        [ "$(cd "$CWD" && "$SDW_BIN/sdw-cfg" DB_LOCAL 2>/dev/null)" = 1 ] || ask "migration against a database not declared local (DB_LOCAL=1)" ;;
      esac ;;
  esac
  return 0
}

# Splits a command into segments, one per line. Quotes are tracked across lines; inside quotes,
# blanks become \003 and ">" becomes \002 (one word, never a redirect); "$(" and backticks end
# the segment with a "$" word; heredoc bodies are dropped unless a shell reads them.
split_cmd() {
  printf '%s\n' "$1" | awk '
    function top() { return substr(st, length(st), 1) }
    function push(c) { st = st c }
    function pop() { st = substr(st, 1, length(st) - 1) }
    function nl() { out = out "\n"; seg = "" }
    function emit(c) { out = out c; seg = seg c }
    BEGIN { st = ""; nterm = 0; skip = 0 }
    {
      if (skip) {
        line = $0
        if (strip[cur]) sub(/^\t+/, "", line)
        if (line == term[cur]) { cur++; if (cur > nterm) { skip = 0; nterm = 0 } }
        next
      }
      s = $0; out = ""; n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1); t = top()
        if (t == "S") {
          if (c == "\047") { pop(); emit(c) }
          else if (c == " " || c == "\t") emit("\003")
          else if (c == ">") emit("\002")
          else emit(c)
          continue
        }
        if (c == "\\" && i < n) { emit(c substr(s, i + 1, 1)); i++; continue }
        if (t == "D") {
          if (c == "\"") { pop(); emit(c) }
          else if (c == "$" && substr(s, i + 1, 1) == "(") { emit("$"); nl(); push("P"); i++ }
          else if (c == "`") { emit("$"); nl(); push("B") }
          else if (c == " " || c == "\t") emit("\003")
          else if (c == ">") emit("\002")
          else emit(c)
          continue
        }
        if (c == "\047") { push("S"); emit(c); continue }
        if (c == "\"") { push("D"); emit(c); continue }
        if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t;&|(]/)) break
        if (c == "$" && substr(s, i + 1, 1) == "(") { emit("$"); nl(); push("P"); i++; continue }
        if (c == "`") { if (t == "B") { pop(); nl() } else { emit("$"); nl(); push("B") }; continue }
        if (c == "(") { push("p"); nl(); continue }
        if (c == ")") { if (t == "P" || t == "p") pop(); nl(); continue }
        if (c == "|" && substr(s, i - 1, 1) == ">") continue
        if (c == "&" && (substr(s, i - 1, 1) == ">" || substr(s, i + 1, 1) == ">")) { emit(c); continue }
        if (c == ";" || c == "&" || c == "|") { nl(); continue }
        if (c == "<" && substr(s, i + 1, 1) == "<" && substr(s, i + 2, 1) != "<" && substr(s, i - 1, 1) != "<") {
          j = i + 2; sp = 0
          if (substr(s, j, 1) == "-") { sp = 1; j++ }
          while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
          q = substr(s, j, 1); if (q == "\047" || q == "\"") j++; else q = ""
          w = ""
          while (j <= n && substr(s, j, 1) ~ /[A-Za-z0-9_.-]/) { w = w substr(s, j, 1); j++ }
          if (w ~ /^[A-Za-z_]/ && seg !~ /(^|[ \t\/])(bash|sh|zsh|dash|ksh|eval)([ \t]|$)/) { nterm++; term[nterm] = w; strip[nterm] = sp }
          emit("<<"); i++; continue
        }
        emit(c)
      }
      t = top()
      if (t == "S" || t == "D") { out = out "\003"; printf "%s", out }
      else { printf "%s\n", out; seg = "" }
      if (nterm > 0) { skip = 1; cur = 1 }
    }
    END { if (top() == "S" || top() == "D") printf "\n" }'
}

# Segments of one command text, with a pre-filter for very large commands.
check_text() {
  local segs seg cnt
  segs=$(split_cmd "$1")
  cnt=0
  [ "${#segs}" -gt 16384 ] && cnt=$(printf '%s\n' "$segs" | grep -c .)
  if [ "${#segs}" -gt 65536 ] || [ "$cnt" -gt 2000 ]; then
    segs=$(printf '%s\n' "$segs" | grep -E "(^|[[:space:]\\\\/])(rm|git|find|cp|mv|sed|perl|tee|bash|sh|zsh|eval|env|cd|pushd|curl|wget|dd|ln|touch|mkdir|security|sudo|xargs|npx|npm|pnpm|yarn|bun|bunx|dotnet|prisma|docker|docker-compose|podman|podman-compose|gh|glab|rails|rake|typeorm|cat|head|tail|less|more|grep|egrep|rg|bat|jest|vitest|playwright|sdw-workdir|sdw-jira|[A-Za-z_][A-Za-z0-9_]*=)([[:space:]]|$)|[<>]|\\.sdw/auth|\\.[eE][nN][vV]")
  fi
  while IFS= read -r seg; do
    check_segment "$seg"
  done <<EOF
$segs
EOF
}

SDW_T=$(mktemp -d "${TMPDIR:-/tmp}/sdw-guard.XXXXXX") || exit 2
trap 'rc=$?; rm -rf "$SDW_T"; if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then echo "sdw: guard error ($rc)" >&2; exit 2; fi' EXIT

FLAT=${CMD//\\$'\n'/ }

# Whole-command patterns.
if printf '%s\n' "$FLAT" | grep -Eq '(^|[^[:alnum:]_.-])(curl|wget)([[:space:]][^;&|]*)?\|[[:space:]]*(sudo[[:space:]]+(-[^[:space:]]+[[:space:]]+)*)?(env[[:space:]]+)?(sh|bash|zsh)([[:space:]]|$)'; then
  deny "piping a download into a shell" "download it, read it, then run it"
fi
if printf '%s\n' "$FLAT" | grep -Eq '(^|[^[:alnum:]_.-])(sh|bash|zsh|source|\.)[[:space:]]+<\([[:space:]]*(curl|wget)'; then
  deny "running a downloaded script" "download it, read it, then run it"
fi
if [ "$AGENT" = sdw:qa ] && printf '%s\n' "$FLAT" | grep -Eq '(^|[^[:alnum:]])Verdict:[[:space:]]*(READY|NOT READY)'; then
  deny "sdw:qa cannot write a verdict" "leave Verdict: PENDING; sdw-evidence qa-verdict computes it"
fi

check_text "$FLAT"

# SQL is scanned only where a database client runs it; commit messages, PR bodies and file writes are prose.
case "$FLAT" in *[Dd][Rr][Oo][Pp]*|*[Tt][Rr][Uu][Nn][Cc][Aa][Tt][Ee]*|*[Dd][Ee][Ll][Ee][Tt][Ee]*|*[Uu][Pp][Dd][Aa][Tt][Ee]*)
  if printf '%s\n' "$FLAT" | grep -Eq '(^|[^[:alnum:]_-])(psql|mysql|mariadb|sqlite3|sqlcmd|mongosh|mongo|duckdb|clickhouse-client|cockroach|bq|snowsql)([[:space:]]|$)|prisma[[:space:]]+db[[:space:]]+execute|supabase[[:space:]]+db'; then
    if printf '%s\n' "$FLAT" | grep -Eiq '(^|[^[:alnum:]_])DROP[[:space:]]+(TABLE|DATABASE|SCHEMA|INDEX|VIEW|COLUMN|CONSTRAINT|USER|ROLE|PROCEDURE|FUNCTION|TRIGGER)([[:space:]]|$)'; then ask "SQL DROP"; fi
    if printf '%s\n' "$FLAT" | grep -Eiq '(^|[^[:alnum:]_])TRUNCATE[[:space:]]+(TABLE[[:space:]]+)?[[:alnum:]_"`[]'; then ask "SQL TRUNCATE"; fi
    if printf '%s\n' "$FLAT" | grep -Eiq '(^|[^[:alnum:]_])DELETE[[:space:]]+FROM([[:space:]]|$)' && ! printf '%s\n' "$FLAT" | grep -Eiq '(^|[^[:alnum:]_])WHERE([[:space:]]|$)'; then ask "SQL DELETE without WHERE"; fi
    if printf '%s\n' "$FLAT" | grep -Eiq '(^|[^[:alnum:]_])UPDATE[[:space:]]+[^[:space:]]+[[:space:]]+SET([[:space:]]|$)' && ! printf '%s\n' "$FLAT" | grep -Eiq '(^|[^[:alnum:]_])WHERE([[:space:]]|$)'; then ask "SQL UPDATE without WHERE"; fi
  fi ;;
esac

if [ -n "$ASK_REASON" ]; then
  if [ "${SDW_ASK_MODE:-json}" = deny ]; then deny "$ASK_REASON" "run it yourself if intended"; fi
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' \
    "$(printf 'sdw: %s' "$ASK_REASON" | sdw_jstr)"
fi
exit 0
