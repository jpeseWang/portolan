#!/usr/bin/env bash
# Portolan route setup. Safe to re-run. Default changes only this clone (local.zsh, state/); everything else is opt-in.
# Exit: 0 ok, 1 a step failed, 2 usage, 4 python3 missing or too old.
set -u

HERE=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$HERE/.." && pwd -P)
DRY=0 WRITE_RC=0 LINK=0 PROXY=0 TEST=1 FAILED=0

usage() {
  cat <<'EOF'
usage: ./setup.sh [--dry-run] [--write-rc] [--link] [--with-proxy] [--no-test]

  (default)     check tools, create local.zsh and state/ in this clone, run the tests, print next steps
  --dry-run     print every action, change nothing
  --write-rc    append one `source .../env.zsh` line to ~/.zshrc (after copying it to a dated backup)
  --link        symlink bin/ai-quota and bin/aim-pick into ~/.local/bin (use them from bash or fish)
  --with-proxy  also set up the optional DeepSeek proxy: venv + LiteLLM, Prisma client, Postgres in Docker.
                Not needed for quota checks, routing or QA. API keys are never asked for or stored here.
  --no-test     skip the test run at the end
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dry-run) DRY=1 ;;
    --write-rc) WRITE_RC=1 ;;
    --link) LINK=1 ;;
    --with-proxy) PROXY=1 ;;
    --no-test) TEST=0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
fail() { say "  FAILED: $*" >&2; FAILED=1; }
# act <cmd...>: run it, or only print it with --dry-run
act() { if [ "$DRY" = 1 ]; then say "  would: $*"; else say "  do: $*"; "$@" || fail "$*"; fi; }

[ "$DRY" = 1 ] && say "dry run: nothing below is changed"

step "python3"
if ! command -v python3 >/dev/null 2>&1; then say "  python3 not found; install Python 3.8 or newer" >&2; exit 4; fi
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' ||
  { say "  python3 is older than 3.8: $(python3 -V 2>&1)" >&2; exit 4; }
say "  $(python3 -V 2>&1)"

step "tools on this machine"
tool() { # tool <name> <what it is for>
  if command -v "$1" >/dev/null 2>&1; then say "  have     $1"; else say "  missing  $1   ($2)"; fi
}
tool claude "Claude Code"
tool codex  "Codex CLI"
tool agy    "Antigravity CLI"
tool zsh    "env.zsh needs it; bin/ai-quota and bin/aim-pick do not"
tool tmux   "aim, aim-task and aim-lead open windows with it"
tool git    "worktrees"
if [ "$PROXY" = 1 ]; then tool docker "proxy database"; fi
say "  A missing tool only removes its own chain entries from use; nothing else breaks."

step "this clone"
act mkdir -p "$HERE/state"
if [ -f "$HERE/local.zsh" ]; then
  say "  local.zsh exists, left as it is"
else
  act cp "$HERE/local.example.zsh" "$HERE/local.zsh"
  say "  edit local.zsh to register projects, set a DeepSeek deny list or enable agy auto-approve"
fi

step "shell"
SRC_LINE="source \"$HERE/env.zsh\""
case "${SHELL:-}" in
  */zsh) RC="$HOME/.zshrc" ;;
  *) RC="" ;;
esac
if [ -z "$RC" ]; then
  say "  your login shell is not zsh. env.zsh is zsh-only; run ./setup.sh --link to use ai-quota and aim-pick from any shell."
elif [ -f "$RC" ] && grep -qF "$HERE/env.zsh" "$RC"; then
  say "  $RC already sources $HERE/env.zsh"
elif [ "$WRITE_RC" = 1 ]; then
  if [ "$DRY" = 1 ]; then
    say "  would: copy $RC to a dated backup, then append: $SRC_LINE"
  else
    [ -f "$RC" ] && cp "$RC" "$RC.portolan-backup-$(date +%Y%m%d-%H%M%S)"
    printf '\n# Portolan route\n%s\n' "$SRC_LINE" >> "$RC" && say "  appended to $RC: $SRC_LINE" || fail "write $RC"
  fi
else
  say "  not changed. To load the commands in new terminals add this line to $RC (or re-run with --write-rc):"
  say "    $SRC_LINE"
fi

if [ "$LINK" = 1 ]; then
  step "links in ~/.local/bin"
  act mkdir -p "$HOME/.local/bin"
  for f in ai-quota aim-pick; do
    dest="$HOME/.local/bin/$f"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$HERE/bin/$f" ]; then say "  $dest already points here"; continue; fi
      say "  $dest exists and is not ours; left alone"; continue
    fi
    act ln -s "$HERE/bin/$f" "$dest"
  done
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) say "  note: ~/.local/bin is not on PATH in this shell" ;; esac
fi

if [ "$PROXY" = 1 ]; then
  step "optional DeepSeek proxy (LiteLLM + Postgres)"
  VENV="${AIM_VENV:-$HOME/.local/share/ai-matrix/venv}"
  if [ "$DRY" = 1 ]; then
    say "  would: create $VENV and pip install 'litellm[proxy,extra_proxy]' (skipped when already importable)"
    say "  would: run prisma generate against litellm's schema.prisma"
    say "  would: start Postgres 16 as container aim-postgres on 127.0.0.1:5442 with a random password in $HERE/.dbpass"
    say "  would: print how to store your DeepSeek key (you do that yourself)"
  else
    [ -x "$VENV/bin/python" ] || act python3 -m venv "$VENV"
    if ! "$VENV/bin/python" -c 'import litellm, prisma' 2>/dev/null; then
      act "$VENV/bin/pip" install -q 'litellm[proxy,extra_proxy]'
    fi
    SCHEMA=$("$VENV/bin/python" -c 'import litellm,os;print(os.path.join(os.path.dirname(litellm.__file__),"proxy","schema.prisma"))' 2>/dev/null)
    if [ -n "$SCHEMA" ] && [ -f "$SCHEMA" ]; then
      ( cd "$(dirname "$SCHEMA")" && PATH="$VENV/bin:$PATH" prisma generate --schema "$SCHEMA" >/dev/null 2>&1 ) &&
        say "  prisma client generated" || fail "prisma generate"
    else
      fail "litellm schema.prisma not found"
    fi
    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
      say "  docker is not installed or not running; start Docker, then re-run with --with-proxy"
    elif docker ps -a --format '{{.Names}}' | grep -qx aim-postgres; then
      say "  container aim-postgres exists"; docker start aim-postgres >/dev/null 2>&1
    else
      if [ ! -s "$HERE/.dbpass" ]; then
        ( umask 077; python3 -c 'import secrets; print(secrets.token_hex(16))' > "$HERE/.dbpass" )
      fi
      envf=$(mktemp); chmod 600 "$envf"
      printf 'POSTGRES_USER=litellm\nPOSTGRES_DB=litellm\nPOSTGRES_PASSWORD=%s\n' "$(cat "$HERE/.dbpass")" > "$envf"
      act docker run -d --name aim-postgres --restart unless-stopped -p 127.0.0.1:5442:5432 --env-file "$envf" \
        -v aim-pgdata:/var/lib/postgresql/data postgres:16-alpine
      rm -f "$envf"
    fi
    say "  next, you add your own DeepSeek key (this script never asks for it):"
    say "    macOS:  security add-generic-password -U -s deepseek-api -a \"\$USER\" -w     (prompts for the key)"
    say "    other:  export DEEPSEEK_API_KEY=...   (in your shell profile)"
  fi
fi

if [ "$TEST" = 1 ] && [ "$DRY" = 0 ]; then
  step "tests"
  for t in test_routing test_portable; do
    if [ -f "$ROOT/tests/route/$t.py" ]; then
      out=$(python3 -I -B "$ROOT/tests/route/$t.py" 2>&1); rc=$?
      say "  $t: $(printf '%s\n' "$out" | tail -n 1)"
      [ "$rc" = 0 ] || { printf '%s\n' "$out" | tail -n 15 | sed 's/^/    /'; fail "$t"; }
    fi
  done
fi

step "next"
say "  1. Open a NEW terminal (or: $SRC_LINE)"
say "  2. ai-quota --subs     # a line that says login expired: open that CLI once (claude, codex or agy) and sign in"
say "  3. aim-pick qa-run     # shows which tool to use now; ai-quota --roles lists all roles"
say "  Docs: route/README.md, route/MATRIX.md, route/projects/qa.md"

[ "$FAILED" = 0 ] || exit 1
exit 0
