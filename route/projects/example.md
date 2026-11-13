# Project profile (template)

Copy this to `projects/local/<name>.md` (that folder is not committed) and fill it in. Keep client names,
ticket prefixes, paths and identities out of any file that is committed.

## Where to run
- Main git repo: `<path>`; register it in `local.zsh` as `AIM_PROJECTS=(name "<path>")`.
- Start a worktree and a tool: `aim-task -p <name> <ticket-slug> <claude|codex|agy>`.

## Who does what
Pick the role with `aim-pick <role>`; the chains live in `routing.json`.

## Rules the project sets (they outrank this repo)
- Source of truth for requirements:
- Branch, commit and PR conventions:
- What an agent must never touch (data, secrets, environments):
- Whether code or data may be sent to third-party model providers (DeepSeek in particular). If not, add
  the folder to `AIM_NO_DS_PATHS`.
- How to run the project's own checks:

## Handoff
Use `handoff/TEMPLATE.md` between tools; keep project facts in the project's own docs.
