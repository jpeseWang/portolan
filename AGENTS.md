# AGENTS.md

Instructions for an AI agent working in this repo or setting it up for a user.

## What this is
Portolan has two parts. `route/` reads quota for Claude Code, Codex and Antigravity and chooses a tool by priority chain
(`route/routing.json`). `plugin/` is sdw, a Claude Code plugin (skills, agents, hooks, `bin/sdw-*`), installed by
`bootstrap.sh`. Layout and commands: `README.md`, `route/README.md`, `docs/sdw.md`, `docs/internals.md`.
The setup prompt in `README.md` is the supported way to set it up with an agent.

## Setting it up for a user
Follow the prompt in README.md ("Set it up with your AI"). In short: read first, run `./route/setup.sh --dry-run`, get a
yes, run `./route/setup.sh`, run the route tests, show `ai-quota --subs`. For sdw only if the user uses Claude Code and
agrees: `./bootstrap.sh --dry-run`, show the settings diff, get a yes, `./bootstrap.sh`. Never run `--with-proxy`,
`--write-rc`, `--link`, `--uninstall`, `--update` or `--migrate` unless the user asked for exactly that.

## Rules
- Never read, print or request API keys, tokens or passwords. Do not open credential or auth files of any CLI, or Keychain items.
- Do not commit or push unless asked. No `sudo`.
- No machine- or client-specific text in committed files: no home paths, account names, client or project names, ticket
  keys. That goes in `route/local.zsh` or `route/projects/local/` (both ignored). `tests/route/test_portable.py` fails when it leaks.
- Do not weaken a test to make it pass. A change in behaviour gets a test that fails without it.
- Never run a script that installs, uninstalls or rewrites user settings with your own `CLAUDE_CONFIG_DIR` or `HOME` still
  pointing at the real ones. Tests isolate both; a hand-run experiment must too.

## Changing things
- route chains and thresholds: `route/routing.json`. Pools are built in `quota_pools()` in `route/ai-quota.py`; add a test in `tests/route/test_routing.py`.
- route shell commands: `route/env.zsh` (zsh only). Anything a non-zsh user needs goes through `route/bin/`.
- `route/setup.sh` must stay idempotent, and `--dry-run` must change nothing. `tests/route/test_portable.py` checks both.
- sdw: skills in `plugin/skills/<name>/SKILL.md`, hooks in `plugin/hooks/`, tools in `plugin/bin/`. A guard rule that asks
  or denies gets a case in `tests/core/test-guard-bash.sh`. The plugin version lives in `plugin/.claude-plugin/plugin.json`;
  `tests/run.sh lint` fails if a `vX.Y.Z` tag and that version differ.
- If you change the README prompt, keep its markers and safety rules; a test checks every file it names exists.
- Run `tests/run.sh` before you report anything as done, and paste the result line.
