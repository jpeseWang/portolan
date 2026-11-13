# Copy to local.zsh (setup.sh does this). local.zsh is not committed; env.zsh sources it.

# Let agy approve every tool permission itself. Without it a headless `agy -p` cannot run commands.
# It removes a safety prompt, so enable it only if you accept that.
# AIM_AGY_AUTOAPPROVE=1

# Directories where claude-ds (DeepSeek) must not run, for example client code or data.
# AIM_NO_DS_PATHS=("$HOME/work/client-a" "$HOME/work/client-b")

# Short names for aim-task -p <name>: the main git repo of each project (not a worktree).
# AIM_PROJECTS=(
#   web  "$HOME/work/client-a/web-app"
#   api  "$HOME/work/client-a/api"
# )
