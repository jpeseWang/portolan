# Portolan

Work with several AI coding agents without hitting a wall, and ship with proof that the work was checked.

A *portolan* is a medieval sea chart: it did not show the sea, it showed the routes. This toolkit does the same for your AI
tools. Two parts, usable alone or together:

| Part | What it does | Works with |
|---|---|---|
| **route** (`route/`) | Reads how much quota you have left on **Claude Code**, **Codex** and **Antigravity** in one command, and picks the right tool for the job from priority chains: strong model for hard work, cheap one for the rest, another vendor for a second opinion. Opens any tool in any folder or git worktree. | any of the three |
| **sdw** (`plugin/`) | A Claude Code plugin for working inside other people's repos: plan from the ticket, build, have an independent QA agent and reviewer check the work, ship with evidence that is still valid for the pushed commit. Hooks enforce what prose cannot. Leaves no tracked files in the repo. | Claude Code only |

Nothing runs in the background unless you turn on the optional DeepSeek proxy.

Requirements: `git`, `python3` 3.8+, and at least one of `claude`, `codex`, `agy`. route's `aim*` commands also want
`zsh` and `tmux`; sdw wants Claude Code and `jq`. Tested on macOS. CI runs the test suite on Linux too, but nothing here
has been used day to day on Linux or Windows (use WSL there).

## Set it up with your AI

Open Claude Code, Codex or Antigravity in any folder and paste this. It reads the repo first, shows you what it will
change, and asks before it does anything. Part B (the sdw plugin) is optional and only for Claude Code.

<!-- ai-setup-prompt:start -->
```text
You are setting up Portolan on my machine: https://github.com/jpeseWang/portolan (route checks my quota on Claude Code,
Codex and Antigravity and picks the right tool for a job; sdw is an optional workflow plugin for Claude Code).
Read first, act second.

Part A, route:
1. Clone it to ~/portolan (tell me if you want a different place) and read README.md, AGENTS.md, route/README.md,
   route/setup.sh, route/env.zsh, route/routing.json and route/providers.py before you run anything.
2. In at most 10 lines tell me what ./route/setup.sh will change on this machine, which of claude, codex, agy, zsh,
   tmux and git I already have, and what is missing.
3. Ask me which subscriptions I have (Claude Pro or Max, ChatGPT for Codex, Google AI for Antigravity) and which job
   I will use this for (for example QA). Then edit route/routing.json in my clone so the chains for that job list only
   tools I have, and show me the diff.
4. Run ./route/setup.sh --dry-run and show me the output. Only after I say yes, run ./route/setup.sh. Add --write-rc or
   --link only if I say yes to each. Do not run ./route/setup.sh --with-proxy unless I ask for DeepSeek.
5. Check it works: run tests/route/test_routing.py and tests/route/test_portable.py with python3, then
   `ai-quota --subs` and `ai-quota --pick qa-run` (use route/bin/ai-quota if the shell commands are not loaded yet).
   If a provider says the login expired, tell me which CLI to open and sign in to. Do not sign in for me and do not
   try to refresh tokens.
6. Finish with a cheat sheet of at most 8 lines for my setup: which command for which job, and which role to pick.

Part B, only if I use Claude Code and say yes: the sdw workflow plugin, from the same clone.
7. Check that claude, git and jq are installed. Read docs/sdw.md and bootstrap.sh, then run ./bootstrap.sh --dry-run and
   show me the output, including the settings diff it would apply to my Claude Code settings. If I use more than one
   Claude config directory, ask me which one first, because bootstrap follows CLAUDE_CONFIG_DIR.
8. Only after I say yes, run ./bootstrap.sh with no other option. Never run --uninstall, --update or --migrate, and
   add --with-qa-tools or --security-skill only if I ask. Afterwards tell me to run /reload-plugins in Claude Code and
   /sdw:onboard inside a project; do not onboard a project for me.

Rules:
- Never read, print or ask me for API keys, tokens or passwords. Do not open any CLI's credential or auth files, or
  Keychain items. The tools in this repo read what they need; you do not.
- Work without sudo. Change nothing outside the clone except what route/setup.sh does and the lines I approved in my
  shell profile and in ~/.local/bin; for Part B, only what bootstrap.sh does after I said yes.
- Do not commit or push anything.
- Ask me before you install anything, change a shell profile or edit a file I did not mention.
- If a step fails, stop and show me the error instead of working around it.
```
<!-- ai-setup-prompt:end -->

## Set it up yourself

```
git clone https://github.com/jpeseWang/portolan ~/portolan
cd ~/portolan

./route/setup.sh --dry-run     # route: shows every change, makes none
./route/setup.sh               # creates route/local.zsh and route/state/, runs the tests

./bootstrap.sh --dry-run       # sdw (Claude Code only): shows the settings diff, makes no change
./bootstrap.sh
```

sdw alone, without bootstrap's settings merge: in Claude Code, `/plugin install sdw --marketplace jpeseWang/portolan`.
That installs the plugin only (no settings, no verify skill); `./bootstrap.sh` is the path this repo tests.

Then, in a new terminal: `ai-quota --subs` and `aim-pick qa-run`. Details, options and what each command changes:
[route/README.md](route/README.md) and [docs/sdw.md](docs/sdw.md).

## Using the two together

sdw decides how much process a change needs (its lanes: trivial, standard, risky, bug); route decides which tool to
spend on it. Typical split: a trivial change on a cheap tool, a risky one on the strongest, and the review always from
a different vendor than the one that wrote it (`aim-pick reviewer --exclude <vendor>`). Inside sdw, sub-agents and the
QA agent run in Claude Code; Codex and Antigravity sessions follow the same files by hand and run without sdw's hooks.
QA specifically: [route/projects/qa.md](route/projects/qa.md).

## Layout

```
route/       quota reader, priority chains, shell commands, optional DeepSeek proxy   (README inside)
plugin/      the sdw Claude Code plugin: skills, agents, hooks, bin/sdw-*
bootstrap.sh installs sdw: release clone, plugin, user settings merge, optional skills
docs/        sdw.md (sdw manual), internals.md, and the rest of sdw's docs
tests/       run.sh [area]: areas bootstrap, core, lint, qa, review, route, team
```

## Tests

```
tests/run.sh            # everything (bash 3.2 compatible, no network)
tests/run.sh route      # only route
```

## Safety notes

- No keys are stored in this repo. route reads API keys from the macOS Keychain or the environment and passes them to
  child processes through the environment or stdin, not on a command line.
- sdw's guard hooks ask before force pushes, PR merges, container removal and similar. `SDW_RELAX=1` in your
  environment, or a file `~/.config/sdw/relax`, switches the softer asks off; see docs/internals.md. Hard denials (`rm -rf` outside the project, reading
  secrets, and so on) stay on either way.
- `AIM_AGY_AUTOAPPROVE=1` in `route/local.zsh` makes the `agy` wrapper skip Antigravity's permission prompts. It is off by default.
- Which code may be sent to which provider is your or your client's decision. route enforces nothing beyond the
  folders you list in `AIM_NO_DS_PATHS`.

MIT license.
