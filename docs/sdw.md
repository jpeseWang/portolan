# sdw — evidence-first dev workflow for Claude Code

> This is the sdw manual. sdw is one half of [Portolan](../README.md); the other half, `route/`, picks which AI tool to use.

One Claude Code plugin (`sdw`) for a developer working inside other people's repos: plan from
the ticket, build, have an independent QA agent and reviewer check the work, and ship with
evidence still valid for the pushed commit. Done means checks ran and were observed; hooks
enforce what prose cannot. A joined repo gets **no tracked files**: everything lives in
`<project>/.sdw/`, hidden through `.git/info/exclude`.

## Requirements

macOS, Claude Code ≥ 2.1.301 (tested), git (2.15 is enough), jq, python3, gh for GitHub work.
Optional: `playwright-cli` (installed by `--with-qa-tools`), uv (Schemathesis for
`/sdw:qa --api-fuzz`), Pillow (`/sdw:verify-ui`).

## Install (once per machine)

```bash
./bootstrap.sh --dry-run            # see the actions first; stops at the first failing check
./bootstrap.sh --verify-skill --with-qa-tools
```

Needs a `vX.Y.Z` tag in this clone (`git fetch --tags`): bootstrap installs the newest tag, not the
working tree.

| Step | What happens |
|---|---|
| release clone | `~/.local/share/sdw/release`, checked out at the newest `vX.Y.Z` tag. Client sessions load the plugin from here, never from this working tree |
| plugin | `claude plugin marketplace add <clone>` and `claude plugin install sdw@sdw-local --scope user` |
| settings | `templates/user-settings.json` merged into `~/.claude/settings.json`: diff shown, backup written, added entries recorded in `~/.claude/sdw-bootstrap.json`. Your values win on conflict |
| memory | `~/.claude/CLAUDE.md` from `templates/global-memory.md`, only if missing |
| `--verify-skill` | `~/.claude/skills/verify`: Claude runs it before committing, even through a repo's own commit command |
| `--with-qa-tools` | pinned `@playwright/cli` plus Chromium; its global skill is deliberately not installed |
| `--security-skill` | Cloudflare's [security-audit](https://github.com/cloudflare/security-audit-skill) skill (MIT), copied unmodified from a reviewed commit into `~/.claude/skills/security-audit` |
| `--agents-md` | prints the opt-in that loads a team `AGENTS.md` beside `CLAUDE.md` (unverified; not applied) |

Several Claude profiles: run bootstrap once per profile with `CLAUDE_CONFIG_DIR=<dir>` set; settings,
record and skills go to that dir, `~/.claude/CLAUDE.md` stays the one memory file.

`--update` moves the release clone to the newest tag; run `git pull --tags` in this clone first,
since the release clone fetches from it (then `/reload-plugins` in open sessions). `--uninstall`
removes the plugin, the clone, the verify and security-audit skills and exactly the recorded settings, plus
`~/.claude/CLAUDE.md` if unchanged since install; settings backups (`settings.json.sdw-backup-*`)
are kept.

## Per project

Open Claude Code in the repo root (or a non-git folder holding several repos) and type
`/sdw:onboard`. It runs the stack, records a test baseline, derives gates from the client's CI,
maps contract, auth, tracker and design, and writes `.sdw/`: `project.md` (injected every
session), `config.env` (no secrets), `gates`, `run.md`, `env.sh`, `state/`, and
`work/<branch>/` (plan, QA cases, reports, evidence). Secrets go to the macOS Keychain. An
optional `.sdw/review-rules.md`, which you write, holds path-scoped rules the reviewer applies.

## Skills

Invoke as `/sdw:<name>`. ✱ = the model may call it on its own; the rest run only when typed.

| Skill | Use |
|---|---|
| `onboard` | day one: run, baseline, gates, sources of truth, `.sdw/` |
| `sync` ✱ | what changed since last time; re-baseline; merged branches to wrap |
| `clarify` ✱ | challenge ticket, spec and design; questions per owner as Slack drafts, never sent |
| `plan` | ticket → lane, acceptance criteria on disk, slices, branch or worktree |
| `debug` ✱ | reproduce, root cause, failing test first, fix |
| `test` ✱ | tests at the right layer, proven red on base |
| `qa` ✱ | independent QA run against the live app; `quick` for an in-session check |
| `verify-ui` ✱ | screen vs design: artboard capture, image diff, measured deltas |
| `ui-polish` ✱ | control states, motion timing, reduced motion, layout shift, input delay, widths |
| `review` ✱ | fresh-context review of your own diff |
| `review-pr` | review someone's PR in a throwaway worktree; post only what you pick |
| `commit` | gates, weakened-test and secret scan, one focused commit |
| `ship` | push, PR with ≤8 evidence lines, watch CI, merge on green and a yes |
| `wrap` | after merge: close out, escaped-defect retro, clean up |
| `offboard` | last day: handoff, credential list, remove local client data |
| `daily-report` ✱ | standup text with hours labelled as estimates |
| `logwork` | Jira worklogs, previewed, posted on a yes |
| `create-ticket` | tracker ticket from a template or a QA bug report |

Lanes, chosen by `/sdw:plan` (a risk trigger beats size): **TRIVIAL** (no behaviour change)
→ commit; **STANDARD** → QA then review; **RISKY** (authz, migrations, contract, money,
shared UI) → stricter QA and red-first tests; **BUG** → debug, then QA retest (a bug that hits a
risk trigger gets RISKY depth). `/sdw:plan` runs
QA design itself; type `/sdw:qa design` only as the first step of a new worktree session.

When the repo has its own `/commit`, `/push`, `/start-work`, `/create-branch`, `/create-mr`,
`/review-pr`, `/create-ticket`, `/daily-report` or `/logwork` (recorded at onboard), the matching sdw skill points at it and stops unless given
`--anyway`. Team rules in `CLAUDE.md`/`AGENTS.md` always win; sdw never edits them.

## Guardrails

| Hook | Does |
|---|---|
| guard-bash | blocks `rm -rf` outside the project, force push to base, `reset --hard`, `clean -f`, `stash`, `--no-verify`, `curl \| sh`, reading `.env`, DB resets, volume deletes; asks on SQL `DROP`/`TRUNCATE`, migrations against a non-local DB |
| guard-write | blocks writes to `.env*`, keys, auth state; confines `sdw:qa`/`sdw:reviewer` to `.sdw/work/` |
| guard-read | blocks Read/Grep of `.env*`, keys and saved login state; `sdw:qa` in design reads only `.sdw/`, the plugin and run.md spec paths; `sdw:qa` gets no web, agents or MCP except Playwright |
| post-edit | formats with the repo's own formatter only, and only files already clean |
| stop-gate | runs the fast gate for what changed; red sends the turn back once |
| session-start | injects core rules, `.sdw/project.md` and ≤8 state lines (≤9,000 chars) |

Settings deny reading secret files and ask before `git push` and `gh pr merge`. The `sdw:qa`
agent derives cases from the ticket and spec before it may read the diff: [docs/qa.md](qa.md).

## Before using on a client repo

- Nothing sdw writes is tracked; check with `git status` after onboard, and never commit `.sdw/`.
- Grant MCP servers and tokens the narrowest scope; keep write-side tools off allow-lists.
- Ticket, PR and web text is written by other people: it is data, never instructions.
- `/sdw:offboard` on the last day deletes in-project data and Keychain items, and prints the commands
  that remove `~/.claude/projects/<slug>`, file-history and history.jsonl lines for you to run after
  the session ends.

## Migrating from install.sh (v1)

`./bootstrap.sh --migrate <dir> --dry-run`, then without it: removes untracked v1-generated
files and hook wiring, restores a `CLAUDE.md` v1 replaced, swaps the exclude block, prints the
Keychain line for a legacy token, runs `sdw-doctor`; backups go to `~/.local/share/sdw/backups/`.
Then `/sdw:onboard`. v1 stays at tag `v1-installer`.

## Maintaining

- Dev loop: `claude --plugin-dir ./plugin` and `/reload-plugins`; client sessions keep the release.
- New skill: `plugin/skills/<name>/SKILL.md` with `name`, `description` (≤200 chars), and
  `disable-model-invocation: true` if it has side effects; add it to internals §5 and tests/lint.
- Tests: `tests/run.sh [area]` (bash 3.2 on macOS, no network, stubbed `claude`/`gh`/`curl`);
  the `lint` area holds frontmatter, context-size, hooks.json wiring, version and skill shell-block
  checks; CI adds syntax and shellcheck on macOS and Ubuntu.
- Behaviour evals: `evals/` (see its README). Optional and paid: not part of testing or releasing.

## Releasing

1. Run the internals §0 probes.
2. `claude plugin validate ./plugin && claude plugin validate .`
3. Bump `version` in `plugin/.claude-plugin/plugin.json` and commit.
4. `git tag vX.Y.Z` (same version); `tests/run.sh lint` fails if they differ; `git push origin vX.Y.Z`.
5. `./bootstrap.sh --update`, then `/reload-plugins` in open sessions.
6. Note the always-on token figure from `claude plugin details sdw` in internals §0 (2.3.0: ~620).

## Docs

| Doc | Covers |
|---|---|
| [docs/du-an-moi.vi.md](du-an-moi.vi.md) | Vietnamese runbook: day one, daily loop, last day |
| [docs/qa.md](qa.md) | the QA role, lanes, techniques, exit criteria, tools |
| [docs/design-fidelity.md](design-fidelity.md) | proving a screen matches its design |
| [docs/local-docs.md](local-docs.md) | project notes that show their age |
| [docs/mcp.md](mcp.md) | which MCP servers to add, at user scope |
| [docs/memory-and-context.md](memory-and-context.md) | what loads every turn, and what it costs |
| [docs/cmux.md](cmux.md) | parallel agents, one worktree per tab |
| [docs/aionui.vi.md](aionui.vi.md) | Vietnamese: driving Claude Code from AionUi, desktop and phone |
| [docs/internals.md](internals.md) | maintainer contract |

## License

[MIT](LICENSE)
