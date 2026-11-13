# route

The routing half of [Portolan](../README.md). It reads how much quota you have left on **Claude Code**, **Codex** and
**Antigravity** (`agy`) in one command, and tells you which tool to use for the job in front of you.

| You get | How |
|---|---|
| One quota view for Claude, Codex and Antigravity | `ai-quota` |
| A priority chain per job (lead, worker, reviewer, four QA steps) | `aim-pick <role>`, chains in `routing.json` |
| Open any tool in any folder, or in its own git worktree | `aim`, `aim-task`, `aim-lead` (zsh + tmux) |
| Optional: Claude Code on DeepSeek for cheap, easy work | `claude-ds` (needs the proxy, see below) |

Needs `python3` 3.8+ and at least one of `claude`, `codex`, `agy`. `zsh` and `tmux` are only needed for the `aim*`
commands; `bin/ai-quota` and `bin/aim-pick` run from any shell. Tested on macOS only; see the root README for the rest.

## Set up

The root README has a prompt that sets everything up with your AI. By hand, from the clone:

```
./route/setup.sh --dry-run     # shows every change, makes none
./route/setup.sh               # creates local.zsh and state/ in route/, runs the route tests
```

`setup.sh` is safe to re-run and changes only `route/` unless you pass an option:

| Option | Adds |
|---|---|
| `--write-rc` | one `source .../route/env.zsh` line in `~/.zshrc`, after a dated backup |
| `--link` | `ai-quota` and `aim-pick` symlinks in `~/.local/bin` (use them from bash or fish) |
| `--with-proxy` | the optional DeepSeek proxy: venv, LiteLLM, Postgres in Docker (see below) |
| `--no-test` | skips the test run |

Then, in a new terminal:

```
ai-quota --subs      # a line that says "login expired": open that CLI once and sign in
aim-pick qa-run      # which tool to use right now for running tests
```

Machine-specific settings go in `route/local.zsh` (not committed): project names for `aim-task -p`, directories where
DeepSeek must not be used, and whether `agy` may approve its own tool permissions. See `local.example.zsh`.

## Priority chains

`routing.json` has one ordered chain per role. `aim-pick <role>` reads the current quota and marks each entry `ok`,
`skip` (below its minimum, a denied folder, or the same vendor as the implementer) or `?` (quota unreadable). The first
`ok` wins; if none is `ok` the first `?` is offered and labelled unverified.

| Role | Order | For |
|---|---|---|
| `lead` | Opus, Sonnet, Sonnet on Antigravity, Codex, Gemini | planning and decisions |
| `worker` | Sonnet, Gemini, Codex, DeepSeek | implementation |
| `reviewer` | Codex, Gemini, Sonnet on Antigravity, Sonnet | second opinion; `--exclude <vendor>` drops the implementer's vendor |
| `qa-design` | Sonnet, Gemini, Codex | test cases and risk analysis |
| `qa-run` | Gemini Flash, Codex, Haiku, Sonnet | running tests, exploring, reading logs (the token-heavy part) |
| `qa-report` | Gemini Flash low, Haiku, Codex | bug reports and summaries |
| `qa-escalate` | Opus on Antigravity, Opus, Codex | a bug the cheaper tools could not reproduce |

QA roles never start with Opus. A plan that has only a 5-hour window (no weekly one) is judged on the window it has.
Thresholds are defaults (Opus needs 30% of the 5-hour and 15% of the weekly window left, others 10%); edit them in
`routing.json`. QA workflow, prompts and token-saving habits: [projects/qa.md](projects/qa.md).

```
aim-pick                              # every chain and the current choice
aim-pick qa-run --dir ~/work/app      # for a folder (matters when some tools are denied there)
aim-pick reviewer --exclude anthropic # reviewer from another vendor than the implementer
aim-lead [dir]                        # open the best lead tool in a tmux window
```

The lead does not switch mid-session. When its quota runs out, write a handoff (`handoff/TEMPLATE.md`), run
`aim-lead`, and start the new lead from that file.

## Daily use

```
aim claude [dir]                      # open a tool in any folder, no repo needed (claude, codex, agy, ds)
aim-task -p web TICKET-1 claude       # worktree + window for a project registered in local.zsh
aim-task TICKET-2 codex               # same, for the repo you are standing in
aim-tasks                             # list windows and worktrees
ai-quota                              # quota, DeepSeek balance, proxy spend
```

`aim-task` creates the worktree with `sdw-wt` when sdw is installed, otherwise with plain `git worktree add`.

## Where the numbers come from

`providers.py` reads Claude (Anthropic OAuth usage), Codex (ChatGPT usage) and Antigravity (`agy -p "/usage"`)
directly and caches the result for 5 minutes in `state/` (15 after a rate limit). Things that make a line read
"login expired" or `?`:

- Claude: the login is the one for your `CLAUDE_CONFIG_DIR` (each config dir is its own account, stored under its
  own Keychain item on macOS, or in `.credentials.json` on Linux). Run `ai-quota` from a shell that has the same
  `CLAUDE_CONFIG_DIR` as the `claude` you use.
- Tokens are never refreshed here. If a CLI has not run for a while its token expires; open it once.
- With no open 5-hour window, Claude counts as 100% left for that window.
- Windows differ by plan. Not every plan returns a weekly or per-model limit; a window that is absent is not checked.
  Only the author's plan was tested; behaviour on Claude Pro is untested.

Optional statusline: `statusline-snippet.sh` holds the two blocks that show `ds:$x.xx` and cache Claude's 5h/7d for `ai-quota`.

## Optional: DeepSeek proxy

`claude-ds` runs Claude Code on DeepSeek models through a local LiteLLM proxy. It is the cheapest option for easy work
and the only part that needs Docker and an API key. `./route/setup.sh --with-proxy` builds the pieces; you add your own key:

```
security add-generic-password -U -s deepseek-api -a "$USER" -w    # macOS, prompts for the key
export DEEPSEEK_API_KEY=...                                       # other systems, in your shell profile
```

Your prompts and code go to DeepSeek's API, so list client or private folders in `AIM_NO_DS_PATHS` (`local.zsh`);
`claude-ds` and the `worker` chain refuse to run there. `ai-quota` reads `local.zsh` itself, so the list also
applies when it is called from bash or an agent's shell that never loaded `env.zsh` (or export
`AIM_NO_DS_PATHS_STR="/path/a:/path/b"`). If `local.zsh` cannot be read, `claude-ds` is shown as unverified rather
than allowed. The proxy listens on `127.0.0.1` only. The `$5/day` cap in `litellm.yaml` is configured but its
enforcement has not been tested.

## Tests

```
tests/run.sh route
python3 -I -B tests/route/test_routing.py      # quota parsing, chains, fallbacks, deny list
python3 -I -B tests/route/test_portable.py     # nothing machine-specific, setup.sh, env.zsh, the README prompt
```

## Files

`setup.sh` installer, `env.zsh` shell commands, `bin/` portable commands, `ai-quota.py` + `providers.py` quota and
routing, `routing.json` chains, `local.example.zsh` machine settings template, `litellm.yaml` optional proxy,
`MATRIX.md` who does what, `projects/` profiles (`example.md`, `qa.md`), `handoff/TEMPLATE.md`.
