# source from ~/.zshrc:  source <path to this clone>/env.zsh
# Machine-specific settings (projects, DeepSeek deny list, agy auto-approve) live in local.zsh, which is not committed.
export AIM_HOME="${${(%):-%x}:A:h}"
export AIM_PORT="${AIM_PORT:-4000}"
export AIM_VENV="${AIM_VENV:-$HOME/.local/share/ai-matrix/venv}"

typeset -gA AIM_PROJECTS     # name -> main git repo, used by: aim-task -p <name>
typeset -ga AIM_NO_DS_PATHS  # directories where claude-ds must not run
AIM_AGY_AUTOAPPROVE="${AIM_AGY_AUTOAPPROVE:-0}"
[ -f "$AIM_HOME/local.zsh" ] && source "$AIM_HOME/local.zsh"
export AIM_NO_DS_PATHS_STR="${(j.:.)AIM_NO_DS_PATHS}"   # read by ai-quota.py

# _aim_secret <keychain-service> <ENV_VAR>: macOS Keychain first, then the environment. Never printed.
_aim_secret() {
  local v=""
  command -v security >/dev/null 2>&1 && v=$(security find-generic-password -s "$1" -w 2>/dev/null)
  [ -n "$v" ] || v="${(P)2:-}"
  printf '%s' "$v"
}

_aim_master() {
  [ -s "$AIM_HOME/.master" ] || (umask 077; echo "sk-$(openssl rand -hex 24)" > "$AIM_HOME/.master")
  cat "$AIM_HOME/.master"
}

# Postgres password for the proxy database: .dbpass when setup.sh created one, else the old local default.
_aim_dbpass() { [ -s "$AIM_HOME/.dbpass" ] && cat "$AIM_HOME/.dbpass" || printf 'litellm-local'; }

ai-proxy-up() {
  lsof -nP -iTCP:$AIM_PORT -sTCP:LISTEN >/dev/null 2>&1 && { echo "proxy already on :$AIM_PORT"; return; }
  local ds gem
  ds=$(_aim_secret deepseek-api DEEPSEEK_API_KEY)
  [ -n "$ds" ] || { echo "no DeepSeek key: add Keychain item deepseek-api or export DEEPSEEK_API_KEY"; return 1; }
  gem=$(_aim_secret gemini-api GEMINI_API_KEY)
  docker start aim-postgres >/dev/null 2>&1
  DATABASE_URL="postgresql://litellm:$(_aim_dbpass)@127.0.0.1:5442/litellm" \
  LITELLM_MASTER_KEY="$(_aim_master)" DEEPSEEK_API_KEY="$ds" GEMINI_API_KEY="$gem" \
    nohup "$AIM_VENV/bin/litellm" \
    --config "$AIM_HOME/litellm.yaml" --host 127.0.0.1 --port $AIM_PORT >"$AIM_HOME/proxy.log" 2>&1 &
  echo "proxy starting, log: $AIM_HOME/proxy.log"
}
ai-proxy-down() { lsof -tiTCP:$AIM_PORT -sTCP:LISTEN | xargs -r kill && echo stopped; }
ai-spend() {
  curl -s -H "Authorization: Bearer $(_aim_master)" "http://127.0.0.1:$AIM_PORT/spend/logs?summarize=true" | head -c 1500; echo
}

ai-quota() { python3 -I -B "$AIM_HOME/ai-quota.py" "$@"; }

# agy approves every tool permission only when AIM_AGY_AUTOAPPROVE=1 (set it in local.zsh). Without it a
# headless agy cannot run commands, so a review can come back empty. Also applies to windows opened by
# aim, aim-lead and aim-task, which start their tool through an interactive zsh.
agy() {
  if [ "${AIM_AGY_AUTOAPPROVE:-0}" = 1 ]; then
    case " $* " in
      *" --dangerously-skip-permissions "*) command agy "$@";;
      *) command agy --dangerously-skip-permissions "$@";;
    esac
  else
    command agy "$@"
  fi
}

# Easy tasks: Claude Code UI + DeepSeek. Keeps the active CLAUDE_CONFIG_DIR so sdw rules and hooks still apply.
claude-ds() {
  _aim_ds_ok || return 1
  ai-proxy-up >/dev/null 2>&1
  for _ in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$AIM_PORT/health/liveliness" && break; sleep 1; done
  ANTHROPIC_BASE_URL="http://127.0.0.1:$AIM_PORT" ANTHROPIC_AUTH_TOKEN="$(_aim_master)" \
  ANTHROPIC_MODEL="ds-chat" ANTHROPIC_SMALL_FAST_MODEL="ds-chat" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="ds-chat" ANTHROPIC_DEFAULT_HAIKU_MODEL="ds-chat" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="ds-think" claude "$@"
}

# Refuse claude-ds under AIM_NO_DS_PATHS (client code or data that must not go to DeepSeek).
_aim_ds_ok() {
  local d="${1:-$PWD}" p; d="${d:A}"
  for p in "${AIM_NO_DS_PATHS[@]}"; do
    [ -n "$p" ] || continue
    p="${p/#\~/$HOME}"; p="${p:A}"
    case "$d/" in "$p"/*) echo "claude-ds is disabled under $p (use claude, codex or agy)"; return 1;; esac
  done
}

# Open a tool in a tmux window (session "aim"); attach/switch when run from a terminal.
_aim_open() {
  local name="$1" dir="$2" m="$3" cmd id
  command -v tmux >/dev/null 2>&1 || { echo "tmux is not installed; run it yourself: cd $dir && $m"; return 1; }
  case "$m" in ds) cmd=claude-ds;; *) cmd="$m";; esac
  tmux has-session -t aim 2>/dev/null || tmux new-session -d -s aim -n main
  id=$(tmux new-window -P -F '#{window_id}' -t aim -n "$name:$m" -c "$dir" "zsh -ic '$cmd'") || return 1
  tmux select-window -t "$id"
  if [ -t 1 ]; then
    if [ -n "${TMUX:-}" ]; then tmux switch-client -t aim; else tmux attach -t aim; fi
  else
    echo "opened window $name:$m in $dir (tmux attach -t aim)"
  fi
}

# aim <claude|codex|agy|ds> [dir]  - open a tool in any directory, no git repo needed
aim() {
  local m="${1:-claude}" d="${2:-$PWD}"
  d="${d/#\~/$HOME}"; [ -d "$d" ] || { echo "no such directory: $d"; return 1; }
  d="${d:A}"
  [ "$m" = ds ] && { _aim_ds_ok "$d" || return 1; }
  _aim_open "${d:t}" "$d" "$m"
}

# aim-lead [dir]  open the best lead tool the current quota allows (chain in routing.json)
# aim-pick [role] [--exclude <vendor>] [--dir <path>]   show the chain and the choice (ai-quota --roles lists roles)
aim-lead() {
  local d="${1:-$PWD}" cmd; d="${d/#\~/$HOME}"; [ -d "$d" ] || { echo "no such directory: $d"; return 1; }
  d="${d:A}"; cmd=$(ai-quota --pick lead --cmd --dir "$d") || return 1
  echo "lead: $cmd"; _aim_open "${d:t}" "$d" "$cmd"
}
aim-pick() { ai-quota --pick "$@"; }

# One tmux window per task in its own worktree, from any directory:
#   aim-task [-p project|path] <slug> <claude|codex|agy|ds> [branch]
# -p takes a name from AIM_PROJECTS (local.zsh) or a repo path; without it the current directory's repo is used.
# Worktree = sibling <main-repo>-<slug>, created with sdw-wt when available.
aim-task() {
  local proj=""; [ "${1:-}" = -p ] && { proj="${2:-}"; shift 2; }
  local t="${1:-}" m="${2:-claude}" br="${3:-}" repo root wt
  [ -n "$t" ] || { echo "usage: aim-task [-p project|path] <slug> <claude|codex|agy|ds> [branch]"; return 1; }
  if [ -n "$proj" ]; then repo="${AIM_PROJECTS[$proj]:-$proj}"; repo="${repo/#\~/$HOME}"; else repo="$PWD"; fi
  root=$(git -C "$repo" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
  [ -n "$root" ] || {
    echo "not a git repo: $repo"
    echo "registered projects: ${(kj:, :)AIM_PROJECTS}"
    echo "use 'aim-task -p <project> ...', or 'aim <tool> [dir]' for a plain window"; return 1; }
  wt="$root-$t"
  [ "$m" = ds ] && { _aim_ds_ok "$wt" || return 1; }
  if [ ! -d "$wt" ]; then
    if command -v sdw-wt >/dev/null 2>&1; then (cd "$root" && sdw-wt add "$t" ${br:+--branch "$br"}) || return 1
    else git -C "$root" worktree add "$wt" -b "${br:-$t}" || return 1; fi
  fi
  _aim_open "$t" "$wt" "$m"
}
aim-tasks() { tmux list-windows -t aim -F '#{window_name}  #{pane_current_path}' 2>/dev/null; git worktree list 2>/dev/null; }
