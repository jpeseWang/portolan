# sdw internals

Maintainer contract for v2. Never loaded at runtime. Interface changes go through this file first.

Conventions used below: `<projdir>` is the resolved project dir (§2.1), `<wd>` the work dir
(`sdw-workdir`), `<repo>` the basename of a repo's main checkout, `<bslug>` the branch name
with every `/` replaced by `__` (detached HEAD: `detached-<sha7>`).

## 0. Mechanism status

Load-bearing behaviour uses only what was verified on Claude Code 2.1.301. Anything else is
optional or has a one-line fallback switch.

| Mechanism | Status | Use |
|---|---|---|
| SessionStart `hookSpecificOutput.additionalContext` | verified | core.md + project.md + state |
| plugin `bin/` on the Bash tool PATH | verified | bins called by bare name from skills |
| `$CLAUDE_PLUGIN_ROOT` in hooks, not in Bash tool | verified | hooks use it; bins locate siblings via `$0` |
| `$CLAUDE_PROJECT_DIR` in hooks | verified | projdir fallback only |
| `$CLAUDE_ENV_FILE` in SessionStart | verified | append `source <projdir>/.sdw/env.sh` |
| hook input `session_id cwd tool_name tool_input agent_type agent_id stop_hook_active` | verified | §4 |
| `agent_type` = `sdw:qa` / `sdw:reviewer` | verified (`<plugin>:<agent>`) | confinement |
| PreToolUse exit 2 blocks (also in subagents), stderr shown | verified | every DENY |
| `${CLAUDE_SKILL_DIR}`, `$ARGUMENTS` in SKILL.md | verified | supporting files |
| a skill named `verify` auto-runs before Claude commits | verified | bootstrap `--verify-skill` |
| PreToolUse JSON `permissionDecision: "ask"` | verified (2.1.301) | ASK class; switch `SDW_ASK_MODE=deny` in guard-bash.sh turns every ASK into exit 2 |
| Stop exit 2 + stderr continues the turn | verified (2.1.301) | stop-gate block; fallback stdout `{"decision":"block","reason":…}` exit 0, switch `SDW_STOP_MODE=json` |
| Stop `systemMessage` shown to the user | verified (2.1.301) | non-blocking warnings; fallback stderr + exit 0 |
| `disable-model-invocation: true` stops the model calling the skill | documented, unverified | side-effect skills; backstop is `permissions.ask` on `git push`/`gh pr merge` |
| SessionStart input `source` | verified (2.1.301): `startup`, `resume`, `compact` | compact extras; absent → treated as `startup` |
| agent frontmatter `disallowedTools effort maxTurns permissionMode` | unverified | optional; hooks enforce |
| pluginConfigs AGENTS.md opt-in | unverified | bootstrap `--agents-md` only, asks first |

Observed on 2.1.301 with `claude -p --plugin-dir ./plugin`:
- `ask` in `-p` denies the call (`permission_denied`, decision reason type `hook`) under manual,
  acceptEdits, auto and bypassPermissions, so `SDW_ASK_MODE` stays `json`; interactive sessions prompt.
  Every ASK is therefore a DENY under `-p`: a headless push to a base branch, a PR/MR merge or a
  docker prune is refused, and the user runs it from an interactive session.
- Stop exit 2 and `SDW_STOP_MODE=json` both continue the turn; both also show a "Stop hook error" notice.
- `systemMessage` appears only as a stream-json `system` message (`Stop says: …`), not in `-p` text output.
- Hook `.cwd` follows a persistent `cd` inside the project; a subagent inherits the parent's current
  cwd; a `cd` outside the project is reset.
- Tool names: `Read Grep Glob WebFetch WebSearch Agent mcp__<server>__<tool>`; `Task` stays in the
  guard-read matcher only for older versions.

Release checklist (manual `claude -p --plugin-dir ./plugin` probes): P1 JSON ask, P2 Stop exit 2,
P3 Stop systemMessage, P4 model cannot call a `disable-model-invocation` skill (not yet probed),
P5 subagent hook `.cwd`, P6 hook `ask` still prompts in an interactive bypassPermissions session
(`git -C . push origin main`). Flip the switches above if a probe fails.

Release steps: README "Releasing". `tests/lint/test-release.sh` checks that plugin.json's version
is semver, that a marketplace entry agrees, and that a `vX.Y.Z` tag at HEAD equals the committed
version. Always-on cost, from `claude plugin details sdw` after `marketplace add` of this repo and
`install sdw@sdw-local` in a throwaway HOME: 2.3.0 ~620 tok (2.2.1 ~580) (skill and agent descriptions; hooks
cost none). The SessionStart injection (core.md, project.md, state) comes on top.

Eval phase 1 (2.1.306, 2026-10-21), optional and paid, never a release step: from the repo root, with git ≥2.31 first on PATH (the runner
refuses 2.15), `claude plugin eval . --case commit-via-skill --runs 3 --scaffold --allow-tools Bash
--max-cost-usd 3 --no-publish`. With-without ablation: with 3/3 (score 1.00), without 0/3 (0.00, ran
`git commit`), Δ +1.00, $0.59, 77 s. Cases live in `evals/` (§1); local only, never CI.

## 1. Repo layout

```
.claude-plugin/marketplace.json   {"name":"sdw-local","owner":{…},"plugins":[{"name":"sdw","source":"./plugin",…}]}
plugin/.claude-plugin/plugin.json {"name":"sdw","version":"X.Y.Z","description":…,"author":{"name":…}}
plugin/rules/core.md              always-loaded rules, ≤60 lines and ≤4,500 chars
plugin/hooks/hooks.json           hook wiring (§4.1), top-level "hooks" wrapper (and an optional "description")
plugin/hooks/lib.sh               shared hook helpers: JSON field read (jq→python3), projdir, env.sh source
plugin/hooks/session-start.sh     SessionStart: inject context, env file
plugin/hooks/guard-bash.sh        PreToolUse Bash: deny/ask
plugin/hooks/guard-write.sh       PreToolUse Edit|Write|NotebookEdit: secret paths, agent confinement
plugin/hooks/guard-read.sh        PreToolUse Read|Grep|Glob|Web*|Agent|Task|mcp__*: secret reads, QA design reads, QA tools
plugin/hooks/post-edit.sh         PostToolUse Edit|Write: formatter, QA phase flip
plugin/hooks/stop-gate.sh         Stop: fingerprinted fast gate + tamper warning
plugin/bin/sdw-cfg                read one config key
plugin/bin/sdw-workdir            projdir / repos / work dir / QA phase
plugin/bin/sdw-exclude            .git/info/exclude block
plugin/bin/sdw-gate               gates: fingerprint, fast, full, check, baseline
plugin/bin/sdw-evidence           evidence stamp/add/list/check/qa-verdict/pr-lines
plugin/bin/sdw-wt                 sibling and throwaway worktrees
plugin/bin/sdw-toolchain          pinned vs actual toolchain, env.sh lines (python3)
plugin/bin/sdw-docs-freshness     local-docs staleness (python3)
plugin/bin/sdw-doctor             PASS/FAIL self-test
plugin/bin/sdw-tamper             weakened-test scanner; test-path classifier
plugin/bin/sdw-redcheck           prove a test is red on base
plugin/bin/sdw-ui-shot            bash wrapper → plugin/libexec/ui-shot.mjs
plugin/bin/sdw-ui-diff            design vs capture diff (python3, Pillow)
plugin/bin/sdw-login              scripted test login → .sdw/auth/ (bash; form recipes via libexec/login.mjs)
plugin/bin/sdw-figma-png          Figma REST /images render with cache
plugin/bin/sdw-jira               Jira REST with Keychain token
plugin/libexec/ui-shot.mjs        Playwright capture (node ≥18, ESM)
plugin/libexec/login.mjs          Playwright form login → storage state
plugin/agents/qa.md               sdw:qa
plugin/agents/reviewer.md         sdw:reviewer
plugin/skills/<18>/SKILL.md       + supporting files (§5)
plugin/reference/tracker-jira.md  Jira flavours, fields, ADF/wiki, transitions, worklog paths
plugin/reference/tracker-github.md gh issue/project commands, status field edit
bootstrap.sh                      user-level install/update/uninstall/migrate (§3.17)
templates/global-memory.md        → ~/.claude/CLAUDE.md if missing (≤35 lines)
templates/user-settings.json      merged into ~/.claude/settings.json
templates/verify-skill/SKILL.md   → ~/.claude/skills/verify/SKILL.md (--verify-skill)
tests/run.sh                      runs every tests/*/test-*.sh
tests/{core,qa,review,team,bootstrap,lint}/test-*.sh   area tests (§8)
evals/<case>/case.yaml            behaviour evals for `claude plugin eval` (§0); results/ ignored; not in CI
docs/internals.md                 this file
docs/{du-an-moi.vi.md,qa.md,design-fidelity.md,local-docs.md,mcp.md,memory-and-context.md,cmux.md}
README.md, LICENSE, .gitignore, .github/workflows/ci.yml
```

v1 (install.sh, variants/, factory/ and the rest) lives at tag `v1-installer`.

## 2. Per-project layout

### 2.1 projdir resolution (`sdw-workdir --projdir`, from `$PWD`)

1. If `$PWD` is in a git work tree: `top=$(git rev-parse --show-toplevel)`;
   `common=$(cd "$top" && cd "$(git rev-parse --git-common-dir)" && pwd -P)` (run from `top`:
   git 2.15 returns a relative path, and wrong ones from subdirs).
   `main` = `dirname "$common"` when `basename "$common"` is `.git`, else `top`.
   Walk up from `main` (inclusive) to, but excluding, `$HOME` and `/`; the first dir containing
   a `.sdw/` directory is projdir.
2. Else walk up from `$PWD` the same way.
3. Else, if `$CLAUDE_PROJECT_DIR` is set and contains `.sdw/`, use it.
4. Else exit 3 (`sdw: not onboarded (run /sdw:onboard)`).

This covers: session at repo root (`.sdw/` in the repo); non-git workspace parent holding one or
more repos (`.sdw/` in the parent); sibling worktrees and `$TMPDIR` throwaway worktrees (their
common dir points at the main checkout, which walks up to the same projdir). `/sdw:onboard` is
run from the repo root or the workspace parent and creates `<cwd>/.sdw/` first.

`--repos`: absolute paths of main checkouts under projdir: projdir itself if it is a work-tree
top, plus every `<projdir>/*/.git` and `<projdir>/*/*/.git` that is a **directory** (a `.git`
file is a worktree or submodule), skipping `node_modules`. Sorted, one per line.

Branch for the work dir: the `$PWD` repo's `git symbolic-ref --short -q HEAD`. If `$PWD` is not
in a repo and `--repos` yields exactly one repo with no linked worktree, that repo's branch;
otherwise exit 4 (`sdw: ambiguous repo, cd into a repo or worktree`, or `sdw: ambiguous checkout`
when the one repo has linked worktrees: the parent cannot tell which checkout is meant).
`sdw-gate` run from outside every checkout still gates only main checkouts and names each repo
whose linked worktrees it skipped on stderr.

Git rules everywhere: git 2.15. Use `(cd "$d" && git …)`, never `git switch`, `git restore`,
`branch --show-current`, `diff --merge-base`, `worktree remove`, `--path-format`, `git stash`.

### 2.2 Tree

```
<projdir>/.sdw/
  project.md        facts injected every session (§2.3)
  config.env        keys (§2.4), no secrets
  gates             fast/full gates (§2.5)
  run.md            run, login, users, QA settings (§2.6)
  people.md         who owns which area, chat handles, decision channel; written by /sdw:onboard, read by /sdw:clarify
  env.sh            toolchain exports (§2.7)
  review-rules.md   optional project review rules by path glob (§2.9)
  design-refs/      Figma renders: <fileKey>/<nodeId with : → ->@<scale>x-<lastModified>.png
  auth/             <role>.json (Playwright storage state), <role>.cookies (curl jar), <role>.header ("Name: value"); written only by sdw-login
  state/
    baseline.md             base sha, date, per-app test summary lines, latest green CI run id
    last-sync               line 1 ISO time, line 2 base sha
    sync-YYYY-MM-DD.md      /sdw:sync report
    gate-baseline/<gslug>.txt  normalised pre-existing diagnostics (§2.5)
    gate-stamps             "<fingerprint> <iso>" per green fast run, last 50 kept
    stop/<session_id>       "<fingerprint> <green|red> <keys,comma>" at the last Stop
    worktrees               TSV: slug repo path branch|detached iso
    task-<KEY>              line 1 ISO start time, line 2 branch
    qa-active               bslug of the work dir under QA; written with every `sdw-workdir --phase <value>`
    clarify-<slug>.md       /sdw:clarify output made on the base branch; /sdw:plan moves it to work/<bslug>/questions.md
    onboard-pids            "<pid> <app> <port>" of servers /sdw:onboard started; it stops them and deletes the file
    corepack-bin/           corepack shims (onboard, optional)
  work/<bslug>/             one per branch (§2.8)
  work/_done/<bslug>/       moved here by /sdw:wrap
  work/_pr/<n>/             /sdw:review-pr scratch (pr.json meta diff.patch acs.md drafts.json summary.md payload.json), removed by the skill
  docs/                     local docs when DOCS_DIR=.sdw/docs (repo-root projdir); a workspace parent uses local-docs/
```

`.git/info/exclude` block (written only by `sdw-exclude`, in `<common-dir>/info/exclude` of every
repo from `--repos`):

```
# >>> sdw >>>
.sdw/
e2e/.auth/
playwright/.auth/
.claude/settings.local.json
# <<< sdw <<<
```

### 2.3 project.md

Rendered from `plugin/skills/onboard/project.md`. Hard caps: ≤40 lines, ≤2,500 chars (CI checks
the template; session-start truncates the file). Sections, in order, each `## <name>` with 1–3
lines; unknown values are `<not onboarded>` or `none`, never guessed:
`Apps` (repo:prefix, port; gates live in .sdw/gates) · `Toolchain` (→ .sdw/env.sh) · `Contract` ·
`Migrations` · `Auth` · `Design` · `Tracker` · `Base branch` · `Team skills` · `Conventions` ·
`Run and QA` (→ .sdw/run.md) · `Traps` (≤10 lines, each with the exact error text).

### 2.4 config.env

Lines `KEY=value` or `export KEY=value`; `#` comments; values may be single- or double-quoted;
no expansion; last occurrence wins. Keys match `^[A-Z][A-Z0-9_]*$`. Any key matching
`TOKEN|SECRET|PASSWORD|PASSWD|APIKEY|CREDENTIAL` is invalid (secrets live in Keychain).

| Key | Default | Values |
|---|---|---|
| BASE_BRANCH | main | branch name |
| VCS_HOST | github | github, gitlab, bitbucket, azure, none (no remote) |
| TRACKER | none | none, jira, github |
| TEAM_SKILLS | (empty) | space-separated names of the repo's own skills: commit push start-work create-branch create-mr review-pr create-ticket daily-report logwork |
| PROJ_SLUG | basename of projdir, lowercased, `[^a-z0-9-]`→`-` | Keychain namespace |
| BRANCH_PATTERN | `{key}-{slug}` | placeholders `{key}` `{n}` `{slug}` |
| PR_TITLE_PATTERN | `{key}: {summary}` | placeholders `{key}` `{n}` `{summary}` |
| JIRA_BASE_URL, JIRA_EMAIL, JIRA_PROJECT | | |
| JIRA_FLAVOR | cloud | cloud (REST v3, basic), dc (REST v2, bearer) |
| JIRA_AUTH | basic if cloud, bearer if dc | basic, bearer |
| JIRA_AC_FIELD, JIRA_SPRINT_FIELD | | customfield ids |
| TRANSITION_IN_PROGRESS, TRANSITION_IN_REVIEW | | transition ids |
| GH_PROJECT | | `<owner>/<number>` |
| GH_STATUS_FIELD_ID, GH_STATUS_IN_PROGRESS_ID, GH_STATUS_IN_REVIEW_ID | | project field/option ids |
| WORKLOG | 0 | 0, 1 |
| DOCS_DIR | (empty) | projdir-relative path |
| DB_LOCAL | 0 | 1 only when the DB host is local |
| FIGMA_FILE_KEY | | |
| FIGMA_MCP_BUDGET | 0 | calls/month allowed via MCP |

### 2.5 gates

```
# comment
<repo>:<prefix> | fast: <cmd> | full: <cmd>
deps: <repo>:<prefix> -> <repo>:<prefix> [<repo>:<prefix>…]
```

- `<prefix>` is a repo-relative dir without leading/trailing `/`, or `.` (whole repo; use it for
  single-app repos and for affected-only commands such as `turbo run … --filter=...[HEAD]`).
- ` | fast: ` and ` | full: ` are literal separators, in that order, each optional. A command runs
  to the next separator or end of line, so it may contain `|`, but not the separator text.
- A changed path `p` (repo-relative) matches a key when prefix is `.`, `p == prefix`, or `p`
  starts with `prefix/`. Literal comparison, never regex. Every matching line runs.
- `deps:` one level, not transitive: a change matching the left key also selects every right key.
- Commands run as `bash -c "<cmd>"` with cwd `<checkout>/<prefix>`, where checkout is the worktree
  in which the change was found, after sourcing env.sh. Missing dir → result
  `gate dir missing: <dir>` (red).
- Doc filter (ignored for gate selection and fingerprints, and never invalidates evidence):
  paths ending `.md .mdx .txt`, or starting `docs/` or `local-docs/`.
- Baseline file `state/gate-baseline/<gslug>.txt`, gslug = key with `:`→`--`, `/`→`__`, prefix
  `.`→`_all`. Lines are normalised diagnostics: output lines matching
  `(error|warning) (TS|CS|MSB|NU|CA|IDE|BC)[0-9]+` or eslint unix format
  `^[^:]+:[0-9]+:[0-9]+: .*\[(Error|Warning)/`, with the checkout root prefix removed, any other
  absolute `…/node_modules/` prefix cut to `node_modules/` (a symlinked node_modules prints its
  real path), and
  `(\d+,\d+)` / `:\d+:\d+` removed. A gate passes when it exits 0, or when a baseline exists, at
  least one diagnostic line was recognised, and every recognised line is in the baseline.
- Parse error (line not matching the grammar) → `sdw-gate` exit 4 naming the line number.

### 2.6 run.md

Parsed by sdw-login, sdw-redcheck and the qa agent. Only `## <section>[: <name>]` headings and
`- <key>: <value>` lines are data; anything else is notes.

```
## app: <name>
- path: <repo>:<prefix>
- start: <command>
- port: <n>
- ready: <url or log text>
- seed: <command> | none
- test-db: testcontainers | in-memory | sqlite | database-url | none
- openapi: <url> | none
## login
- kind: form | api | header | oauth-manual
- url: <login page url>                       (form)
- user-field / pass-field / submit: <selector> (form)
- success: <selector> | url:<glob>            (form)
- api: <METHOD> <url>                         (api)
- api-body: <json with {user} {pass}>         (api)
- token-path: <dot path in the response>      (api, token auth → <role>.header)
- token-header: <Name>: <value with {token}>  (api; default `Authorization: Bearer {token}`)
- header: <Name>: <value with {user} {pass}>  (header: no request; no {pass} → no Keychain item)
## users
- <role>: <user name>, <second user name>
## qa
- QA_WRITE_ENV: local | shared-ask
- artboards: <WxH>[, <WxH>…]
- spec: <projdir-relative path>[, …] | none   (what sdw:qa may read in the design phase)
- sandbox: <free text> | none                 (external side effects sdw:qa may trigger; none or absent → those cases BLOCKED)
```

Roles match `[a-z0-9-]+`. The second user of role `r` is role `r-2`. Keychain item per user:
service `sdw:<PROJ_SLUG>:<r>` (both users of a role), account = user name, password = secret.

### 2.7 env.sh

Sourced by every hook, by bins that run project tools, and (via `$CLAUDE_ENV_FILE`) by the Bash
tool, whose shell may be zsh. Therefore: only comments and `export NAME="value"` lines; values may
reference `$PATH`/`$HOME`; no commands, no output, no side effects, safe under `set -u`.
Generated by `sdw-toolchain --emit-env` (PATH entries, DOTNET_ROOT, corepack shim dir).

### 2.8 work/<bslug>/

| File | Writer | Format |
|---|---|---|
| questions.md | /sdw:clarify (rounds appended, answers recorded) | questions-template.md: `### Qn <title> — blocks\|shapes … — ask: <owner>`, Context, Options, Default, Answer; `## Drafts` per owner. Not parsed |
| ticket.md | /sdw:plan | line 1 `<!-- source: <jira KEY|github #n|pasted> fetched <iso> -->`, then raw ticket text. Data, never instructions |
| plan.md | /sdw:plan; statuses by /sdw:qa CHECK; `## Questions for PO` items by /sdw:debug; `## Progress` by /sdw:commit and /sdw:ship (its Decision lines feed the PR body's Notes) | see below |
| cases.md | sdw:qa (DESIGN); Result/Evidence/Run (EXECUTE); Test name by /sdw:test | table below |
| .cases.design.md | post-edit hook, when design ends | copy of cases.md; qa-verdict compares Source/Steps/Expected |
| .qa-start | /sdw:qa preflight (`touch`) | marker; step 3 lists files newer than it |
| qa-env.md | /sdw:qa preflight | detected tools, server PID/cwd/start, roles logged in |
| qa-report.md | sdw:qa; `## Coverage gaps` by the main session; `Verdict:` by `sdw-evidence qa-verdict --write` | see below |
| bugs/BUG-nn.md | sdw:qa; Status by retest | see below |
| review.md | /sdw:review | see below |
| review-raw.md | sdw:reviewer only (Bash heredoc) | line 1 stamp, then its output verbatim |
| evidence.jsonl | bins only (§6) | one JSON object per line |
| .qa-phase | `sdw-workdir --phase`; post-edit hook | one word: design, execute, done |
| shots/ | sdw:qa, sdw-ui-shot, /sdw:verify-ui, /sdw:plan and /sdw:debug (`sdw-jira attachment`) | png/json and ticket attachments, free naming |
| repro.md | /sdw:debug | exact repro steps and observed output |
| ticket-draft.md | /sdw:create-ticket | light-markdown ticket body (§3.16 rich text) |
| commit-msg.txt, pr-title.txt, pr-body.md | /sdw:commit, /sdw:ship | transient message files |
| .review-stamp | /sdw:review | stamp taken before the review, prepended to review.md, then deleted |

plan.md (exact lines the hooks/bins parse are marked †):

```
# Plan: <KEY or slug> <title>
Lane: <TRIVIAL|STANDARD|RISKY|BUG> — <reason>        †
Ticket: ticket.md
## Acceptance criteria
| ID | Given/When/Then | Source | Status | Evidence |    †
| AC-1 | … | ticket AC | TODO | |
## Out of scope
## Questions for PO
## Surfaces                                              † lines `- <METHOD> </path>` ({id} for ids)
## Slices
## Risks
## Progress
- Done: <slice> <sha7>
- Now: <step>
- Next: <step>
- Decision: <what> — <why>
```

Parsers read only the first word after `Lane:`. A BUG that hits a risk trigger is
`Lane: RISKY — bug: <trigger>`: RISKY caps and gates, the BUG path in /sdw:plan (repro AC-1,
/sdw:debug first). `## Progress` is not parsed: one line per item, written by /sdw:plan as Now and
Next only, updated in place after each commit and ship (Done and Decision lines are added, Now and
Next replaced; /sdw:commit keeps it ≤12 lines by folding old Done lines into `- Done earlier:` and
dropping superseded Decisions), and read first when work resumes.

`Status: parked <iso>` (appended by /sdw:wrap for an unmerged branch the user sets aside) makes
/sdw:sync skip the dir. AC Status ∈ `TODO PASS FAIL BLOCKED NOT RUN`. Source ∈ `ticket AC | AC field | comment | spec §x | design <node> | agreed-in-chat`.

cases.md columns, exactly:
`ID | Source | Technique | Pri | Preconditions & data | Steps | Expected (with source) | Layer | Automate | Test name | Result | Evidence | Run`
ID `TC-nn`; Pri `P1|P2`; Technique one of techniques.md's bold names; Layer
`ui|api|unit|integration|e2e`; Automate `yes|no`; Result `PASS|FAIL|BLOCKED|NOT RUN` (empty until
executed); Run = first 7 chars of the first `tree` in the execute run's stamp. Charter session
sheets go below the table under `## Charters` (`### C<n> …`).

qa-report.md: line 1 is the `sdw-evidence stamp` line (§6). Then:
`Verdict: PENDING|READY|READY WITH KNOWN ISSUES|NOT READY` † (sdw:qa writes PENDING; only
`sdw-evidence qa-verdict --write` replaces it), `## Summary` (counts by Result), `## Bugs` (table
ID|Severity|Status|Title), `## Pre-existing` (proven `pre-existing` bugs, not in scope),
`## Default checks` (console, pageerror, failed/4xx/5xx requests, axe), `## Charters`,
`## Coverage gaps` †, `## Carried from <run id>` (retest), `## NOT RUN` †, `## BLOCKED`,
`## Test data created` † (`- <env>: Probe <ts> <entity, id>` data lines; `- <env>: setting
<name> was <old> (restored | NOT restored)` lines, which /sdw:offboard never deletes),
`## Questions for PO` † (lines may carry `blocks: yes`, and `ask: <owner>`, which is not parsed).

bugs/BUG-nn.md: lines `Title: ` (≤60 chars), `Severity: S1|S2|S3|S4` †,
`Status: open|fixed|verified|wontfix|pre-existing` †, `Decided-by:` † (wontfix only), `Source:` †,
then sections Environment (with timestamp, TZ, locale), Preconditions, Steps, Request (api: curl
with the jar path), Expected (with source), Actual (verbatim), Evidence, Repro rate, Regression vs
base † (`yes|no|unknown — <how checked>`), Server log (optional), Suspected area (guess).
`pre-existing`: shows on base, untouched by the change, no AC in Source; Regression vs base
`no — shots/base-<…>` (base capture or saved base-run output). Proven, it never blocks (§6.3).

review.md: line 1 stamp; `Open: S1 <n>, S2 <n>, S3 <n>, S4 <n>` †; sections `## Spec compliance`,
`## Code quality` (items `- [S2] path:line — consequence (open|fixed|justified: <user's words>)` †),
`## Pre-existing` (untagged), `## Test weakened`, `## Not reviewed`. Every review-raw.md item
`- [S1]`/`- [S2]` † is counted by the ship check, under `## Pre-existing` too.

### 2.9 review-rules.md

Optional and untracked; onboard never creates it. The user writes it, or /sdw:wrap's retro appends
a rule after a yes when a mistake the reviewer could have caught recurs. Not parsed by any bin.

```
## <glob>                 repo-relative, `*` within a segment, `**` across segments
- <rule> — why: <what went wrong before>
```

/sdw:review and /sdw:review-pr pass its path to sdw:reviewer when it exists; the reviewer applies
the bullets under every glob that matches a changed path and cites `rule <glob>` in the finding.
Severity still comes from the reviewer's scale, never from the rule.

## 3. Bins

Common to every bin: `#!/usr/bin/env bash` (or python3); executable; bash 3.2 safe (no
`declare -A`, `mapfile`, `${x,,}`, `&>>`; empty arrays as `${a[@]+"${a[@]}"}`); siblings via
`here=$(cd "$(dirname "$0")" && pwd -P)`; never read `$CLAUDE_PLUGIN_ROOT`; resolve everything
from `$PWD` (callers `cd` first, no `--from`); `-h`/`--help` prints usage and exits 0; quote
every path; never print or put a secret on argv; diagnostics to stderr prefixed `<bin>: `.
Secrets are read only as `security find-generic-password -s <service> [-a <account>] -w` and handed
to curl via `-K -` on stdin. Timeouts use perl (macOS has no `timeout`): sdw-gate forks, calls
`setpgrp` and kills the process group (TERM, KILL after 2 s, exit 124); sdw-redcheck uses `alarm`
(exit 142, direct child only); sdw-jira uses curl's `--connect-timeout 10 --max-time 60`.

Exit codes, all bins: **0** ok · **1** negative result (gate red, check failed, hits found,
API non-2xx) · **2** usage · **3** not onboarded · **4** missing prerequisite (tool, file,
Keychain item, ambiguous repo) · **5** refused for safety. Bin-specific meanings are noted.

### 3.1 sdw-cfg
`sdw-cfg KEY [default]` → value or default (§2.4 defaults apply when no default is passed).
`sdw-cfg --has KEY` → exit 0 set, 1 unset, no output.
Not onboarded: prints the default, exit 0 (`--has`: exit 1). Secret-looking key → exit 5.

### 3.2 sdw-workdir
`sdw-workdir` → `<projdir>/.sdw/work/<bslug>` (created). `--no-create`. `--projdir`. `--repos`.
`--branch` → bslug. `--phase` → prints `.qa-phase` (or `none`); `--phase design|execute|done`
writes it. Exit 3 not onboarded, 4 ambiguous repo.

### 3.3 sdw-exclude
`sdw-exclude [--remove|--check|--legacy] [repo-dir…]` (default: every `--repos` entry).
Writes/replaces/removes the §2.2 block idempotently; creates `info/`. `--check` exit 1 if any
repo lacks it. `--legacy` also removes the v1 block: the line `# Solo Dev Workflow — never commit
these` and the following lines that belong to v1's pattern list (install.sh at tag
`v1-installer`), up to the first blank or foreign line. Prints `<action> <file>` per repo.

### 3.4 sdw-gate
```
sdw-gate --fingerprint            print fingerprint of current changes ("" when none)
sdw-gate --dry-run [--full]       print "<key>\t<dir>\t<cmd>" that would run
sdw-gate --fast                   run fast gates for working-tree changes vs HEAD
sdw-gate --full [--keys k1,k2]    run full gates for branch changes (vs merge-base) + working tree
sdw-gate --check                  exit 0 "fresh <fp>" if fingerprint is in state/gate-stamps, else 1 "stale"
sdw-gate --write-baseline KEY [--full]   run KEY's command, store normalised diagnostics
sdw-gate --list                   parse .sdw/gates, print keys; exit 4 on parse error
sdw-gate --changes [--full]       print "<checkout>\t<repo>\t<path>" of the change set
```
Change set: every repo in `--repos` plus the `$PWD` work tree, deduped by repo name with the `$PWD`
checkout winning, so an agent in a sibling worktree never gates another agent's main-checkout edits. Per repo:
`git diff --name-only HEAD` ∪ `git ls-files --others --exclude-standard` (unborn HEAD:
`git ls-files` ∪ others), minus the doc filter; mapped to `<repo>:<path>`, repo = main checkout
basename. `--full` base: `git merge-base HEAD origin/<BASE_BRANCH>`, else local `<BASE_BRANCH>`,
else HEAD with a warning.

Fingerprint: lines `<repo> HEAD <sha>` per repo with changes, then `<repo>:<path> <blob>` per
changed path (`git hash-object -- <path>`, or `deleted`), `LC_ALL=C sort`, piped to
`git hash-object --stdin`. No changes → empty output.

`--fast`: green (including nothing to run) → append stamp, exit 0, print `green <keys>`; red → exit 1, print
`red <keys>`, then per failing key `--- <key> (<dir>): <cmd>` and its last 40 lines; nothing to run → exit 0. Whole run budget
`SDW_GATE_TIMEOUT` (default 280 s); a timed-out key is red with `timeout`.
`--full`: per key run, one evidence entry (`sdw-evidence add --kind gate:full`), covered paths =
the key's prefix plus every `deps:` left-hand prefix that selects it; prints `pass|fail|timeout <key> (<dir>)`
per key. Exit 1 if any key red. Internal env `SDW_WD` (set by `--full` for sdw-evidence) records into the
`$PWD` branch's work dir when the key's checkout is another repo. `--write-baseline KEY` runs in `$PWD`'s
checkout when its repo name matches the key (a `--detach` throwaway of the base qualifies), else the first
matching repo. Fingerprint extras: `dir` for an untracked nested repo or dir, `unborn` as HEAD sha; the doc
filter also drops `.sdw/` paths.
Exit 4: gates file missing or unparsable.

### 3.5 sdw-evidence
```
sdw-evidence stamp [--path P]…           print stamp line (default paths ".")
sdw-evidence add --kind K --key KEY --result R [--path P]… [--detail TEXT] [--artifact F]…
sdw-evidence list [--valid-for REF|WORKTREE] [--kind K]
sdw-evidence check [--lane L]            ship policy (§6.3); exit 1 when blocked
sdw-evidence qa-verdict [--lane L] [--write]   QA verdict computed from the files (§6.4); exit 1 NOT READY
sdw-evidence pr-lines                    ≤8 jargon-free lines for the PR <details>
```
`add` is called only by sdw-gate, sdw-redcheck and sdw-ui-diff; it prints the JSON line it
appended. `list` prints `<valid|invalid:<reason>> <kind> <key> <result> <ts>` per entry, newest
first, plus the qa-report.md and review.md stamps as kinds `qa` and `review`. `--valid-for` prints
only valid entries; `WORKTREE` validates against the current working-tree hash (session-start uses it
so QA run on uncommitted work is not shown stale).

### 3.6 sdw-wt
```
sdw-wt add <slug> [--branch NAME] [--base REF] [--no-deps]
sdw-wt add <slug> --detach <ref> [--no-deps]
sdw-wt rm <slug> [--force]
sdw-wt list
```
Sibling: path `<dirname main>/<repo>-<slug>`; `git worktree add -b NAME <path> <base>` when the
branch is new, else `git worktree add <path> NAME` (NAME defaults to slug). Detached: path
`${TMPDIR%/}/sdw/<repo>-<slug>`; an existing registered throwaway with that slug is removed first.
Both: copy untracked `.env*` files (depth ≤3, no node_modules) from the main checkout to the same
relative paths; install deps offline unless `--no-deps` (`pnpm install --offline
--frozen-lockfile` | `npm ci --prefer-offline --no-audit --no-fund` | `yarn install
--frozen-lockfile --offline` | `dotnet restore`), failure is a warning; register in
`state/worktrees` when onboarded. Last stdout line: the absolute path.
`rm`: path must be in `state/worktrees` (or under `${TMPDIR%/}/sdw/` when not onboarded) **and** in
`git worktree list --porcelain` **and** not the first (main) entry, else exit 5. A sibling with
`git status --porcelain` output needs `--force` (exit 5 otherwise). Then `rm -rf -- <path>`,
`git worktree prune`, drop the registry line. `list`: registry rows plus a `missing` flag.

### 3.7 sdw-toolchain (python3)
`sdw-toolchain [root] [--brief] [--emit-env]`. Handles an empty .python-version, global.json
rollForward and non-numeric dotnet output; also checks
packageManager/corepack, git (info only), jq, gh, playwright-cli, uv. `--brief`: mismatches only,
≤3 lines. `--emit-env`: env.sh lines on stdout. Exit 0 all match, 1 mismatch.

### 3.8 sdw-docs-freshness (python3)
`sdw-docs-freshness [--docs DIR] [--brief|--stale]`; "behind" counts the current repo against
`origin/<BASE_BRANCH>`; unparseable date or missing ttl → `unknown`; skip dirs exactly `daily` and
`.git`. Exit 0 all fresh, 1 something stale/unknown, 4 docs dir missing.

### 3.9 sdw-doctor
`sdw-doctor`. One line per check, `PASS|WARN|FAIL <check>: <detail>`; exit 1 if any FAIL.
Checks: jq or python3 present (FAIL); session-start with fake stdin emits valid JSON (FAIL);
guard-bash exits exactly 2 on `rm -rf /`, guard-write on `.env` and guard-read on a Read of `.env` (FAIL);
`.sdw/project.md` over 40 lines or 2,500 bytes (WARN); `sdw-gate --list` and
`--dry-run` (FAIL); `sdw-exclude --check` (FAIL); `env.sh` sources cleanly in `bash -u` (FAIL);
AGENTS.md shadowed by a CLAUDE.md in projdir or an ancestor (WARN); v1 marker
`solo-dev-workflow:generated` under any repo's `.claude/` (WARN); Keychain items expected by
config/run.md exist, names only, looked up as sdw-login reads them (service per role, account per
user; none for a `header` recipe without `{pass}`) (WARN); `~/.claude/settings.json` attribution `commit` and `pr`
are `""`, or the repo's last 50 commits carry a `Co-Authored-By: Claude` trailer (WARN); plaintext secrets in Claude config (python3; WARN `secrets: <file>: <json path>, …`,
names only, never a value or its length; no python3 → WARN not scanned): `~/.claude.json`
`mcpServers` and `projects.*.mcpServers`, `<dir>/.mcp.json` `mcpServers` (their `headers`, `env`,
`args` and `url`),
`~/.claude/settings*.json` and `<dir>/.claude/settings*.json` `env`, where `<dir>` is projdir and each
repo (not onboarded: the git toplevel, else `$PWD`). A value counts when it is a non-empty string
with no `$VAR`/`${VAR}` reference and either its key names a secret (`authoriz`, `bearer`, `token`,
`secret`, `passw`, `api-key`/`api_key`, `private-key`, `access-key`, `credential`, `cookie`, a key
ending `key`; value ≥6 chars, not `true`/`false`/`null` or a bare URL) or it is token-shaped: starts
`Bearer|Basic|Token <x>` or holds one (`<x>` ≥8 chars with a digit), or one word with a digit, not a
path or URL (`/ ~ . http`), of ≥12 chars mixing upper and lower case or ≥32 chars. An all-digit value
counts only under a `passw`/`secret`/`passcode` key (token limits and TTLs are numbers). An `args`
element counts as `--<name>=<v>` or `<NAME>=<v>` by that rule, as the element after a `--<flag>`
whose name names a secret, or when token-shaped; reported as `args[<i>]`. A `url` counts with a
password in its userinfo, a token-shaped user, or a query parameter that counts. Hooks are found at `$here/../hooks/`. Not
onboarded: runs only json, session-start, the guards and the secrets scan.

### 3.10 sdw-tamper (python3)
`sdw-tamper [--staged | --range A..B]` (default `git diff HEAD` plus untracked test files). Arguments
are checked before the repo, so a usage error is exit 2 anywhere.
`sdw-tamper --test-paths` filters repo-relative paths on stdin to test paths.
Test path: basename `*.test.*`, `*.spec.*`, `*_test.*`, `test_*.py`, `*Test.cs`, `*Tests.cs`,
`*.snap`, or a path segment `test`, `tests`, `__tests__`, `__snapshots__`, `e2e`, `spec`,
`*.Tests`, `*.Test`, `__screenshots__`, `*-snapshots`; `*.verified.*` counts as a snapshot. Doc files
(`.md .mdx .txt`) are never test paths. `.sdw/` always skipped. Default mode also scans untracked files
(≤512 KB, not binary).
Output `<kind> <path>:<line> <snippet ≤120>`, kinds: `assert-removed`, `skip-added`
(skip/only/fixme/xit/xdescribe/`[Fact(Skip`/`[Ignore`/`pytest.mark.skip`), `test-deleted`,
`snapshot-changed` (`*.snap`, baseline PNGs under test paths), `threshold-loosened` (larger
numbers in timeout/threshold/maxDiffPixels/retries lines), `suppression-added` (eslint-disable,
ts-ignore/expect-error/nocheck, `type: ignore`, noqa, pylint disable, `#pragma warning disable`,
SuppressMessage, NOSONAR, istanbul/c8/v8 ignore, `<NoWarn>`, TreatWarningsAsErrors false; any changed
code file except generated ones: `*.Designer.cs`, `*.g.cs`, `*ModelSnapshot.cs`, `*.generated.*`,
`*.min.js`, `Migrations/`). A loosened assertion (strong matcher → weak) is `assert-removed`. Line 0 =
the whole file. Exit 0 none, 1 hits, 4 not a repo; 127 (no python3) must never be read as hits.

### 3.11 sdw-redcheck
`sdw-redcheck <base> --test <file> [--test <file>]… [--app <dir>] -- <cmd> [args…]`.
`sdw-wt add red-<epoch>-<pid> --detach <base> --no-deps`, copy the test files (repo-relative), install
deps (pnpm workspace → `pnpm install --offline --frozen-lockfile`; npm/yarn `workspaces` →
`npm ci --prefer-offline --no-audit --no-fund` / `yarn install --frozen-lockfile --offline`; otherwise
symlink the app's node_modules and `.venv`/`venv`; dotnet → `dotnet restore`; sources env.sh), run `<cmd>` in
`<wt>/<app dir>` (default: `$PWD` relative to repo root) with `SDW_REDCHECK=1`, then `sdw-wt rm`.
Refuses (exit 5) when the test files or cmd match
`DbContext|DATABASE_URL|prisma|typeorm|knex|sequelize|mongoose|SqlConnection|WebApplicationFactory`
and run.md `test-db` is `none` or missing. Classification of a non-zero run, first match wins:
`RED(build/import)` on `TS2307|TS2305|CS0246|CS0103|CS1061|Cannot find module|ModuleNotFoundError|ImportError|SyntaxError|Build FAILED`;
`RED(setup)` on `ECONNREFUSED|EADDRINUSE|beforeAll.*[Tt]imeout|Cannot (GET|POST|PUT|DELETE) /`;
`RED(assertion)` on `AssertionError|expect\(|Expected|Assert\.|assert `; else `RED(unknown)`.
Zero exit → `GREEN`. Last line `RESULT: <class>`; writes evidence kind `redcheck`, key = first
test file, paths = test files, detail `base <sha7> exit <rc>: <cmd>`. Budget `SDW_REDCHECK_TIMEOUT`
(default 600 s; a timeout is RED(unknown)). run.md `test-db` comes from the `## app` whose `path` matches
the repo and the longest prefix containing the app dir (one test-db line overall → that one). Exit 0
only for RED(assertion), 1 other classes, 2 usage or a test file outside the repo, 4 unknown base,
missing test file, app dir missing on base, worktree or deps setup failed, 5 refused.

`sdw-redcheck --mutate <patch> --test <file>… [--app <dir>] -- <cmd>` proves a test of new code, where
red on base can only be RED(build/import). The worktree is detached at HEAD and gets the working
tree's changed and untracked files (`git diff --name-only HEAD`, `ls-files --others --exclude-standard`;
deleted ones removed), then `git apply <patch>`. Refused (exit 5) when the patch touches a test path
(`sdw-tamper --test-paths` on the `git apply --numstat -z` paths, so a non-ASCII name is not
quoted past it), a `--test` file, `.sdw/`, or renames or copies a file; exit 4 when it does not
parse or apply. Classified as above; RED(assertion) becomes `RED(mutation)` (exit 0), every other
class keeps its name (exit 1), so a mutation that breaks the build proves nothing. Evidence kind
`redcheck`, result `RED(mutation)`, detail `mutation <sha7> exit <rc>: <patched paths>: <first
changed lines>` (≤200 chars).

### 3.12 sdw-ui-shot
Bash wrapper: node ≥18 on PATH (else exit 4), `exec node "$here/../libexec/ui-shot.mjs" "$@"`.
```
sdw-ui-shot --url U --out F.png [--viewport WxH] [--dpr N] [--wait SEL] [--networkidle]
  [--settle MS] [--full-page] [--storage FILE | --role R] [--measure SEL]…
  [--color-scheme light|dark] [--channel chrome] [--headed] [--axe]
  [--motion SEL]… [--reduced-motion reduce|no-preference] [--vitals]
  [--timezone IANA] [--locale LL-CC] [--fill SEL=VALUE]… [--click SEL]…   (steps run in order after load)
  [--route GLOB=<3-digit status>|<status>:@FILE|offline|empty|delay:MS]…  (split on the last '='; empty = 200 [])
sdw-ui-shot --save-auth R --url LOGIN_URL --headed
```
Playwright: app `node_modules` from `$PWD` up, else playwright-core inside the global
playwright-cli, else `npm install --prefix ~/.cache/sdw/pw playwright-core@1.55.0` (`SDW_OFFLINE=1`
forbids it → exit 4; `SDW_CACHE_DIR` replaces `~/.cache/sdw`). Default wait
`load` + `--wait`. `--role R` = `<projdir>/.sdw/auth/R.json` and/or `R.header` (extraHTTPHeaders). axe tags wcag2a, wcag2aa, wcag21a,
wcag21aa, wcag22aa; source `@axe-core/playwright` or `axe-core` from `$PWD` or Playwright's tree, else
`~/.cache/sdw/axe` (bootstrap `--with-qa-tools` fills it; never downloaded here). `bypassCSP` only with `--axe`.
stdout JSON: `{url,out,viewport,status,timezone,locale,steps,mocked,reducedMotion,console[],pageerror[],requests[{method,url,status|failure}],measure{},motion{},vitals:null|{cls,shifts[≤3]{value,at,sources[≤3]},lcpMs,lcpElement,longTasks{count,totalMs},inpMs,interactions[≤3]},axe:null|{violations[{id,impact,nodes:<count>,targets[≤3]}],notRun?:<reason>},error:null|string}`.
Context emulates `prefers-reduced-motion: reduce` unless `--reduced-motion no-preference`; screenshots
always use `animations: 'disabled'`. `--motion SEL` reports transition and animation computed styles
(and `willChange`) for up to 5 matches. `--vitals` adds an init script with PerformanceObserver for
layout-shift (no `hadRecentInput`), largest-contentful-paint, longtask and event (`durationThreshold:
16`, entries with an `interactionId`); `inpMs` is null when no interaction reached 16 ms.
Exit 0 captured, 1 navigation failed (JSON still printed) or `--save-auth` captured no cookie, 3 `--role`
or `--save-auth` when not onboarded, 4 no Playwright/browser/node.
`--save-auth` writes `.sdw/auth/R.json` after the user closes the headed window.

### 3.13 sdw-ui-diff (python3)
`sdw-ui-diff <design.png> <app.png> --out <prefix> [--threshold N] [--cell N] [--min-ratio F]
[--top N] [--key ROUTE] [--path P]… [--no-evidence]`. Appends evidence kind
`ui-diff`, key = `--key` (default app.png basename), result `info`, detail `mismatch=<pct>`,
artifacts = written images, paths default `.`. Exit 0, 4 Pillow or input missing.

### 3.14 sdw-login
`sdw-login <role> [--app NAME]`. Reads run.md `## login: NAME` (else `## login`, else the first login
section) and `## users`; a relative url/api URL is completed as `http://localhost:<port>` from
`## app: NAME` (else the first app). Credential: `security find-generic-password -s sdw:<PROJ_SLUG>:<role
without -2> -a <user> -w`. Unreachable app → exit 1 `app not reachable?`. `form` → libexec/login.mjs with the
secret on stdin; `api` → curl with body on stdin (`--data-binary @-`) and `-c` jar, then converts
the jar to storage state, or with `token-path` writes `<role>.header` from the response (token never
on argv or stdout); `header` → `<role>.header` from the template, no request, Keychain only for
`{pass}`; `oauth-manual` → prints the `sdw-ui-shot --save-auth` command, exit 4. python3 missing → exit 4
before any request. Writes `.sdw/auth/<role>.json`, `.cookies` and/or `.header` (mode 600). stdout only
`ok <role>`. Exit 1 login rejected or success marker not seen, 4 recipe/Keychain/tool missing.

### 3.15 sdw-figma-png
`sdw-figma-png <fileKey> <nodeId> [--scale N] [--format png|svg]`. Token from Keychain
`sdw:figma`, sent as `X-Figma-Token` via `-K -`. Only `GET /v1/files/<key>/meta` (last modified)
and `GET /v1/images/<key>`; never `/nodes`. If meta fails, an existing cached render is used and
stderr says `cache (unverified)`. Cache path per §2.2. stdout: absolute image path.
Exit 1 API error (status on stderr), 4 token missing.

### 3.16 sdw-jira
`sdw-jira GET|POST|PUT <path> [@payload.json | @-]` (payload must be JSON, else exit 2), plus
subcommands: `myself`, `issue KEY [--fields] [--text]`, `transitions KEY`, `transition KEY ID [--dry-run]`,
`search JQL [--fields] [--max N] [--brief]`, `sprint [--project P]`, `worklog list KEY [--since] [--mine]`,
`worklog mine DATE`, `worklog add KEY --started --duration [--comment|--comment-file] [--dry-run]`,
`create --type --summary [--project] [--description-file] [--assignee me|ID] [--sprint] [--label]… [--dry-run]`,
`render [--flavor cloud|dc]` (offline), `attachment ID --out FILE`. `issue` fetches `reporter` and
`attachment` too; `--text` prints `Reporter:` under `Assignee:` and, after the description and ACs,
`## Attachments (n)` with one `- <filename> (<mimeType>, <size>, id <id>, <created>)` per file,
newest first; an ADF media node reads `[attachment: <alt>]`. `attachment` reads the metadata
(`/attachment/<id>`), then GETs its `content` URL with the same `-K -` auth, following redirects
(curl drops the header on a host change), ≤50 MB, written via a temp file; prints the path. Refused
(exit 5): a `content` URL outside JIRA_BASE_URL (no token sent), an existing FILE, or a FILE whose
resolved path is neither under `<projdir>/.sdw/work/` nor under the temp dir outside projdir and the
git toplevel, or has a `.git .claude .github .gitlab .vscode .idea .husky` segment or the basename
`.envrc`/`.mcp.json` (whoever can attach a file to the issue picks the bytes). A FILE ending `/` or
naming a directory is a usage error (exit 2).
Text inputs are light markdown, sent as ADF (cloud) or wiki
(dc). python3. Paths starting `/rest/` are used as is; otherwise
prefixed `/rest/api/3` (cloud) or `/rest/api/2` (dc). Auth from config: basic
`JIRA_EMAIL:<token>` or bearer; token from Keychain `sdw:jira:<JIRA_BASE_URL without trailing />`.
Body to stdout; `HTTP <code>` to stderr. Exit 0 2xx, 1 non-2xx or no response, 2 usage, 4 config/token
missing (or a token containing `"`, `\` or a newline), 5 token over plain http to a non-local host.
Read-only subcommands are allowed in templates/user-settings.json; POST/PUT, `create`, `transition`,
`worklog add` and `attachment` (it writes a file) always prompt.

### 3.17 bootstrap.sh
`./bootstrap.sh [--with-qa-tools] [--agents-md] [--verify-skill] [--security-skill] | --update | --uninstall |
--migrate <dir> [--dry-run]`. Release clone `~/.local/share/sdw/release` at the highest
`vX.Y.Z` tag (numeric field compare, no `sort -V`); `claude plugin marketplace add <clone>`;
`claude plugin install sdw@sdw-local --scope user`; diff + backup + merge of
templates/user-settings.json, added keys recorded in `~/.claude/sdw-bootstrap.json`;
`~/.claude/CLAUDE.md` only if missing. `CLAUDE_CONFIG_DIR` replaces `~/.claude` for settings, the
record and skills (sdw-doctor reads the same dir); CLAUDE.md is never created there, since Claude
Code 2.1.312 still loads `~/.claude/CLAUDE.md` with it set. `--verify-skill` copies templates/verify-skill/ to
`~/.claude/skills/verify/` (skips an existing non-sdw one). `--security-skill` clones
cloudflare/security-audit-skill, checks out the pinned `SEC_REF`, copies `skills/security-audit/*` and `LICENSE`
unmodified to `~/.claude/skills/security-audit/`, records the ref as `.security_skill`; `--update` refreshes it when
the pin moves, `--uninstall` removes it; an existing unrecorded copy is skipped. Bump the pin only after reading the
upstream diff. `--with-qa-tools`: `@playwright/cli@0.1.22`,
its Chromium, `axe-core@4.10.3` into `~/.cache/sdw/axe`. `--migrate` follows the plan's six steps and uses
`sdw-exclude --legacy`; it also restores or removes a v1 AGENTS.md, cleans v1's other-tool dirs, defers the
exclude swap (exit 1) while config.env/.mcp.json/.auth.json exist, and backs up to
`~/.local/share/sdw/backups/`. Exit 0, 1 a step failed, 2 usage, 4 claude/git/jq missing.

Keychain store one-liner printed by onboard/bootstrap, always ending in a bare `-w`:
`security add-generic-password -U -s '<service>' -a '<account>' -w`.

## 4. Hooks

### 4.1 hooks.json

| Event | Matcher | Command | Timeout |
|---|---|---|---|
| SessionStart | (omitted) | `"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"` | 15 |
| PreToolUse | `Bash` | `…/guard-bash.sh` | 10 |
| PreToolUse | `Edit\|Write\|NotebookEdit` | `…/guard-write.sh` | 10 |
| PreToolUse | `Read\|Grep\|Glob\|WebFetch\|WebSearch\|Agent\|Task\|mcp__.*` | `…/guard-read.sh` | 10 |
| PostToolUse | `Edit\|Write` | `…/post-edit.sh` | 30 |
| Stop | (omitted) | `…/stop-gate.sh` | 300 |

Hooks call bins as `"${CLAUDE_PLUGIN_ROOT}/bin/sdw-x"`, run them in a subshell `cd` to stdin
`.cwd` (falling back to `$CLAUDE_PROJECT_DIR` when `.cwd` is missing or gone), and source
`<projdir>/.sdw/env.sh` when present. JSON fields are read with jq, else python3; output JSON is
built with jq, else python3 `json.dumps`.

### 4.2 Failure behaviour

- Guards: `set -u`; an EXIT trap maps every status other than 0 and 2 to 2 with
  `sdw: guard error (<rc>)` on stderr. No jq and no python3 → `sdw: install jq`, exit 2. Stdin
  that is not a JSON object → `sdw: guard error (bad input)`, exit 2; exit 0 only for a valid
  object with no command or path.
- stop-gate and session-start: an EXIT trap maps any unintended non-zero to 0 with a stderr
  warning; stop-gate sets `BLOCKING=1` immediately before its one intentional `exit 2`.
- post-edit: always exit 0.

### 4.3 guard-bash.sh

Input: `.tool_input.command`, `.cwd`, `.agent_type` (one jq call). Segments: split outside quotes on `;`, `&&`,
`||`, `|`, `&`, newline, `(`, `)`; `$(…)` and backticks (also inside double quotes) end the segment
with a `$` word and their content is its own segment. Quote state spans lines; quoted blanks and `>`
are masked, so a quoted string is one word and `echo "a > b"` is no redirect. `>|` is `>`. Comments
(`#` at a word start) are dropped. Heredoc bodies are dropped unless a shell (`bash sh zsh dash ksh
eval`) reads them; the whole-command SQL and verdict scans still see them. Command word = first
word after `VAR=val`, shell keywords (`if then else elif do while until fi done esac ! { }`), and the
wrappers `sudo env command time nohup xargs exec nice timeout stdbuf caffeinate` with their value
options (`sudo -u/-g/-C/-h/-p/-D/-r/-t/-U/-T`, `env -u/-C`, `nice -n`, `xargs -n/-I/-P/-L/-s/-d/-E/-a`,
`timeout -s/-k` and its duration, `stdbuf -i/-o/-e`). `bash|sh|zsh|dash|ksh -c <script>`, `eval …`
and `env -S <script>` are re-checked as commands (3 levels). A `for`/`select` header is no command;
its loop variable over literal words is expanded to each word in QA design path checks. A
`cd`/`pushd` with a literal target, `"$(sdw-workdir)"` or `"$(sdw-workdir --projdir)"` moves the
effective cwd for later segments; any other target makes it unknown. Variables assigned a literal,
a value built only from tracked variables, `$(sdw-workdir)` or `$(sdw-workdir --projdir)` earlier
in the command are expanded in targets, also when only the variable is quoted (`"$WD"/run.log`). Over 64 KB or 2,000 segments, only segments naming a guarded command, a redirect, an
assignment, `.sdw/auth` or `.env` are checked. Boundary = projdir ∪ `.cwd`'s git toplevel (a
sibling worktree sits outside a repo-root projdir), else `.cwd`. Temp roots = `${TMPDIR%/}`,
`/tmp`, `/private/tmp` (and their physical paths); "in temp" means strictly under one. Base
branches = main, master, develop, `sdw-cfg BASE_BRANCH` (read in `.cwd` and in a `git -C` dir);
current branch from the effective cwd after every `git -C <dir>` (a `$` value or a missing dir makes
it unknown; so do `--git-dir`, `--work-tree` and a `GIT_DIR=`/`GIT_WORK_TREE=` assignment or export).
An earlier `git checkout|switch` in the command sets it per repo: `-b/-B/-c/-C/--orphan <b>` → `<b>`;
a base branch or an existing local or remote branch → that branch; a path checkout (`-- <path>`,
`<tree> <path>`, an existing path) leaves it; `-`, `--detach` or any other name makes it unknown. The work dir
under QA = `.sdw/state/qa-active`, else `.cwd`'s branch (§2.1), else unknown (then any work dir).

DENY is evaluated before ASK and wins.

DENY (exit 2, stderr `sdw: blocked — <reason>; <safer alternative>`):
- `rm` with `-r`/`-R`/`-rf`/`-fr` on `/`, `~`, `~/`, `$HOME`, `"$HOME"`, `..`, a bare `*`; on a target
  equal to, or an ancestor of, the boundary, projdir, `.cwd`'s toplevel, `<projdir>/.sdw`, `$HOME` or a
  temp root, or a glob over one (`./*`, `src/../*`, `./.[!.]*`); or on a target outside the boundary
  and not in temp
- `find … -delete` or `-exec rm` with a root outside the boundary and not in temp (with a filter, a
  temp root itself is allowed), or, without a filter (`-name -iname -path -ipath -regex -iregex
  -newer* -mtime -mmin -size -empty -user -perm`; `-type` alone is not one), a root that is a
  project, home or temp root
- any redirect, `tee`, `cp`, `mv`, `rm`, download target, or (sdw agents) any non-reading command
  naming `.qa-phase`, `.cases.design.md`, `.qa-start`, `.sdw/state/qa-active`, or `review-raw.md`
  (except sdw:reviewer)
- force push (`-f`, `--force`, `--force-with-lease`, `+<ref>`) whose target is a base branch
  (`<base>`, `HEAD:<base>`, `+<base>`), or any refspec-less force push while on a base branch;
  deleting a remote base branch (`git push --delete|-d <remote> <base>`, `:<base>`, `:refs/heads/<base>`)
- `git reset --hard`; `git clean -f…`; `git checkout .` / `git checkout -- .`; `git restore` (except
  `--staged`/`-S` without `--worktree`/`-W`); `git stash` (except `list`, `show`); `git branch -D <base>`
  or `-d -f <base>`; `git commit … --no-verify`/`-n`; `git commit|push|merge|rebase` with
  `-c core.hooksPath=…` or the assignment `HUSKY=0`, `SKIP_SIMPLE_GIT_HOOKS=1` or `LEFTHOOK=0`
- `curl`/`wget` segment piped into `sh|bash|zsh` (word boundary); `bash <(curl …)`
- a reader (`cat head tail less more grep egrep rg bat sed awk gawk sort uniq cut diff comm nl tac rev
  paste column fold xxd od hexdump strings base64 jq yq view`) on a secret file, and `< <secret file>`
  for any command: `.env`/`.env.*` except `.example|.sample|.template` and a tracked `.env.*` whose
  committed and working copies name no `KEY|TOKEN|SECRET|PASSWORD` key; `.envrc`, `*.pem`, `*.key`,
  `*.p12`, `*.pfx`, `*.jks`, `id_rsa*`, `id_ed25519*`, `*.auth.json`; a path segment `.sdw/auth/`,
  `e2e/.auth/` or `playwright/.auth/` (`lib.sh` `sdw_secret_file`, case-insensitive). `source`/`.` of
  a `.env` loads values without printing them and is allowed
- `security find-generic-password|find-internet-password … -w|-g` (prints a secret)
- `prisma migrate reset`; `prisma db push` with `--force-reset` or `--accept-data-loss`;
  `typeorm schema:drop|schema:sync`; `dotnet ef database drop`; `dotnet ef database update 0`;
  `rails db:drop`; `docker compose down -v`; `docker volume rm|prune`; `docker|podman system prune
  --volumes`; `podman system reset`
- agent_type `^sdw:(qa|reviewer)$` additionally: `sed -i`, `perl -i`; `-u`, `--update`,
  `--update-snapshots`, `--updateSnapshot` in a segment whose command word is npx, npm, pnpm, yarn,
  bun, bunx, jest, vitest, playwright or dotnet; formatters and autofix (`--fix`, `--fix-type*`,
  `--write`, `--apply`, `--apply-unsafe`; `-w` for prettier/biome; `dotnet format` without
  `--verify-no-changes`; `ruff format`/`black` without `--check`; `--fix-dry-run` is fine); write targets (`>`, `>>`, `>|`, `tee`, the last `cp`
  or `ln` argument, `touch`, `mkdir`, `curl -o/--output/-O`, `wget -O/-P`, `dd of=`, `sdw-jira --out`) outside
  `<projdir>/.sdw/work/<b>/` (sdw:qa: the work dir under QA when known), except `/dev/null`, `-`,
  `&1`, `&2`; an unexpanded `$` target; `rm`, `mv`; git
  `add commit checkout reset apply am rebase merge cherry-pick push clean restore switch mv rm`
- agent_type `sdw:qa` while the work dir under QA has `.qa-phase` `design` (unknown work dir: any):
  an allowlist. Allowed: `cd sdw-workdir sdw-cfg sdw-evidence sdw-figma-png echo printf pwd date true
  false test [ wc sort uniq cut tr basename dirname`; `git rev-parse|symbolic-ref|status` (no `-v`)
  `|branch --show-current`; `curl` to localhost; `for` loops over literal words; `ls cat head tail
  less more mkdir grep egrep rg sed jq`
  when every path argument (not the pattern, script or filter; `ls`/`grep`/`rg` without one = cwd)
  resolves under `<projdir>/.sdw`, the plugin root, or a run.md `## qa` `spec:` path. Everything
  else is denied, which covers diff plumbing, aliases, nested shells, interpreters and `xargs`.
  Any `Verdict: READY…`/`NOT READY` text in an sdw:qa command is denied.
- any sdw agent when projdir cannot be resolved: every write target above, `sed -i`, `perl -i`
  (fail closed)
- any sdw agent: `--phase` followed by any word (`sdw-workdir --phase <value>`, however invoked);
  a segment naming `.sdw/auth` or a `.auth/` dir unless its command is curl, sdw-ui-shot, sdw-login,
  ls or playwright-cli; any word whose basename is `.env`/`.env.*` (non-template)

ASK (`SDW_ASK_MODE=json`: stdout
`{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"sdw: <reason>"}}`, exit 0):

Soft asks, marked **(soft)** below, ask by default. Two switches turn exactly these off, for unattended runs where
a confirmation stalls the work: `SDW_RELAX=1` in the environment of the session, or, when `SDW_RELAX` is unset, a
file `~/.config/sdw/relax` (`mkdir -p ~/.config/sdw && touch ~/.config/sdw/relax`; `SDW_CONFIG_DIR` or
`XDG_CONFIG_HOME` move the folder). The file also reaches sessions that are already running, whose environment
cannot change, and sessions started from an app that does not read your shell profile. `SDW_RELAX=0` forces the ask
whatever the file says. Every DENY and every unmarked ASK stays on either way. `relaxed()` in guard-bash.sh
implements it; `tests/core/test-guard-bash.sh` checks each soft case in both modes (`relaxed`) and the file.
- **(soft)** force push not covered above (`--force-with-lease` to a non-base branch is allowed silently)
- any other push to a base branch, whatever the form (`git -C <dir>`, `/usr/bin/git`, wrappers,
  nested shells): a refspec whose destination is `<base>`, `HEAD:<base>`, `refs/heads/<base>` or
  `<src>:<base>`; `HEAD`/`@`, a refspec-less push or an unexpanded refspec with no colon while the
  current branch is a base branch, or while it is unknown; `--all`/`--mirror`. **(soft)** a
  `<src>:<dst>` or `:<dst>` whose destination stays unexpanded, and a push from a directory or
  branch the guard cannot resolve. Literal variables are expanded first, in the part
  after the colon too (the split ignores a colon inside `${…}`)
- **(soft)** a PR/MR merge: `gh … pr merge` (global `-R`/`--repo` skipped), `glab … mr merge|accept`, any flags;
  `gh|glab api` on `…/pulls/<n>/merge` or `…/merge_requests/<n>/merge` (any method) or with a
  `mergePullRequest`/`mergeRequestAccept` GraphQL mutation
- **(soft)** `docker`/`podman` (also `docker-compose`, `podman-compose`; global `-H --host -c --context
  --config -l --log-level --connection --url` values skipped): `system prune` without `--volumes`; `container prune`;
  `image prune` with `-a`/`--all`; `rm` or `container rm|remove` (a removed container takes the data
  in its writable layer); `compose rm` with `-v`/`--volumes`; `compose down --rmi all`
- in a command that names a database client (`psql mysql mariadb sqlite3 sqlcmd mongosh mongo duckdb
  clickhouse-client cockroach bq snowsql`, `prisma db execute`, `supabase db`; also via
  `docker|kubectl exec`), anywhere in it, case-insensitive: `DROP` followed by TABLE, DATABASE,
  SCHEMA, INDEX, VIEW, COLUMN, CONSTRAINT, USER, ROLE, PROCEDURE, FUNCTION or TRIGGER;
  `TRUNCATE <identifier>`; `DELETE FROM` without `WHERE`, `UPDATE <t> SET` without `WHERE`. Commit
  messages, PR bodies and file writes are not scanned
- `ef migrations remove`; `ef database update`, `prisma migrate deploy`, `typeorm migration:run`
  unless `DB_LOCAL=1`
- **(soft)** `rm -r` target with an unexpanded variable (other than `$HOME`, `$TMPDIR` and tracked ones), a
  command substitution, or a relative path after a `cd` the guard cannot follow

### 4.4 guard-write.sh

Input `.tool_input.file_path` (Write/Edit) or `.tool_input.notebook_path`, `.tool_input.content` /
`.new_string`, `.cwd`, `.agent_type`. Path resolved against `.cwd`, normalised lexically (`..`
removed), then its existing parent made physical with `cd … && pwd -P`; a symlink is followed and
both the link and its target are checked. Names compare case-insensitively. DENY (exit 2):
- a secret file as in §4.3 (`sdw_secret_file`): `.env`/`.env.*` except templates and a tracked
  `.env.*` whose HEAD and working copies have no key matching `KEY|TOKEN|SECRET|PASSWORD`
  (`sdw_benign_env`; this covers `.env.development`, `.env.dist`, `.env.defaults`);
  `.envrc`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `id_rsa*`, `id_ed25519*`, `.auth.json`,
  any path with segment `e2e/.auth/`, `playwright/.auth/` or `.sdw/auth/`
- for everyone: `.qa-phase`, `.cases.design.md`, `.qa-start`, `.sdw/state/qa-active`; `review-raw.md`
  unless agent_type is `sdw:reviewer`
- agent_type `sdw:qa`: anything but `cases.md`, `qa-report.md`, `bugs/BUG-<n>.md`, `shots/**` in the
  work dir under QA (unknown: any work dir); a qa-report.md whose content or new_string has a
  `Verdict:` line other than `PENDING`
- agent_type `sdw:reviewer`: anything but `<projdir>/.sdw/work/<b>/review-raw.md`
- either agent with projdir unresolvable

### 4.4b guard-read.sh

Input `.tool_name`, `.tool_input.file_path|path|pattern|glob`, `.cwd`, `.agent_type`. DENY (exit 2):
- for everyone: Read/Grep of a secret file as in §4.4 (same tracked benign `.env.*` exception);
  any Read/Grep/Glob under `.sdw/auth/`, `e2e/.auth/` or `playwright/.auth/`; a Grep `glob` that is a
  secret name or whose last segment (containing `env` or starting with `.`) matches `.env`,
  `.env.local`, `.env.production` or `.env.development.local`, unless it ends in a template suffix
- agent_type `sdw:qa` while the work dir under QA is in `design`: a Read/Grep/Glob path (default
  `.cwd`) outside `<projdir>/.sdw`, the plugin root and the run.md `spec:` paths
- agent_type `sdw:qa`: every WebFetch, WebSearch, Agent, Task and MCP tool except
  `mcp__playwright__*`

### 4.5 post-edit.sh

Input `.tool_input.file_path`, `.cwd`, `.agent_type`, `.session_id`.
- agent_type `sdw:qa`, the path is `<projdir>/.sdw/work/<b>/cases.md`, `<b>/.qa-phase` reads
  `design`, cases.md has a `| TC-n` row and every `AC-n` of `<b>/plan.md` appears in a TC row's
  Source cell → copy it to `<b>/.cases.design.md` and write `execute` to `<b>/.qa-phase`. Otherwise
  the phase stays. No formatting for sdw agents or paths under `.sdw/`.
- Format only when the repo declares the formatter: prettier (config file or `prettier` key in
  package.json) for `.js .jsx .ts .tsx .mjs .cjs .mts .cts .vue .css .scss .less .json .html
  .svelte .astro .yml .yaml`; `biome.json`; ruff/black via `[tool.ruff]`/`[tool.black]` in
  pyproject for `.py`; csharpier in `.config/dotnet-tools.json` for `.cs`. Never `.md/.mdx`,
  never eslint --fix, never a global ruff/black. Binary from `node_modules/.bin` walking up to the
  git toplevel.
- Only if the file is untracked, or its HEAD blob passes the formatter's check (e.g.
  `git show HEAD:<p> | prettier --check --stdin-filepath <p>`); result cached in
  `${TMPDIR%/}/sdw/fmt-<session_id>.txt` as `<abs path>\t<ok|skip>`.

### 4.6 stop-gate.sh

Input `.cwd`, `.session_id`, `.stop_hook_active`.
1. Resolve projdir from `.cwd`; none → exit 0. Gates file missing → exit 0.
2. `fp=$(sdw-gate --fingerprint)`; empty (a clean tree) → delete `state/stop/<session_id>`, exit 0.
   `last` = that record.
3. `stop_hook_active` true: `fp` equals last fp → exit 0 (systemMessage
   `sdw: still red after a retry: <keys>` when last was red); otherwise run `sdw-gate --fast`,
   record, systemMessage if red, exit 0. Never block.
4. `fp` equals last fp → exit 0 (question-only turns pass on a red tree).
5. Run `sdw-gate --fast`, record `<fp> <green|red> <keys>`. Run `sdw-tamper` in each checkout of
   `sdw-gate --changes`; only its stdout counts as hits (any other exit prints none).
6. Green: tamper hits → systemMessage `sdw: test changes to justify: …` (≤10 lines); exit 0.
7. Red: stderr = `The fast gate failed; fix the cause (never the test, lint rule or type) or
   say plainly it is still red.` + gate output (≤4,000 chars) + tamper hits as `Also (not
   blocking): …`; `BLOCKING=1; exit 2` (or the JSON form under `SDW_STOP_MODE=json`).
Claude Code caps Stop continuations; nothing here loops.

### 4.7 session-start.sh

Input `.cwd`, `.session_id`, `.source`. Output on stdout:
`{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<text>"}}`.
Text, in order, joined by blank lines; total ≤9,000 chars:
1. `${CLAUDE_PLUGIN_ROOT}/rules/core.md` verbatim (never truncated; CI keeps it ≤4,500).
2. `## Project (.sdw/project.md)` + the file in whole lines within 2,500 bytes and 40 lines; when
   anything is dropped the last line is `(project.md truncated; see .sdw/project.md)`. Absent → omitted.
3. `## State`, ≤8 lines, each omitted when it has no data:
   `branch <b> (<repo>) · dirty <n> · ahead <n>` (ahead only if `origin/<base>` exists; one line per
   repo with a non-base branch or dirty files, ≤3) · `lane <LANE> · AC <pass>/<total>` ·
   `QA <verdict> (<valid|stale>)` · `open bugs S1 <n> S2 <n>` · `review open S1 <n> S2 <n>` ·
   `gate <green|red> at last stop` (from `state/stop/<session_id>`, so only on resume/compact).
4. Only when non-empty: `sdw-toolchain --brief` (≤3 lines) and, when DOCS_DIR exists,
   `sdw-docs-freshness --brief` (≤2 lines).
5. `source=compact` only: `Modified:` ≤20 paths and `Gates:` ≤5 lines of `sdw-gate --dry-run`.
Over budget → drop 5, then 4, then cut 2 the same way. Side effects: append `source '<projdir>/.sdw/env.sh'`
(single-quoted, `'` escaped as `'\''`) to `$CLAUDE_ENV_FILE` when both exist; delete
`state/stop/*` older than 7 days. Not onboarded → core.md only.

## 5. Skills

Frontmatter keys: `name`, `description` (≤200 chars), `argument-hint` (when it takes args),
`disable-model-invocation: true` (side-effect set only). Every SKILL.md preflights with
`sdw-workdir --no-create >/dev/null; echo rc=$?` (3 not onboarded, 4 ambiguous repo; `--projdir`
never returns 4). On rc 3 the DMI skills refuse with `run /sdw:onboard first` (except onboard,
daily-report); the model-invocable ones fall back to the plain behaviour without work-dir files
(test: write and run tests; review: reviewer on the diff, nothing written; qa: `quick` in chat;
debug: repro in chat; ui-polish: captures under `${TMPDIR}/sdw-polish`; clarify: questions and
drafts in chat) or say in their description
that they need an sdw project (sync, verify-ui).
When `TEAM_SKILLS` lists the matching team skill it says `this repo has /<x>, use it` and stops
unless `$ARGUMENTS` contains `--anyway`; re-derives shell variables in every Bash block; prints
cross-skill steps for the user to type (a skill never invokes a side-effect skill). Supporting
files are read as `${CLAUDE_SKILL_DIR}/<file>`; reference files as
`${CLAUDE_SKILL_DIR}/../../reference/<file>`.

The Bash tool resets its cwd to the session dir whenever a call ends outside it. So a skill never
`cd`s into a worktree "for the rest of the task": a throwaway worktree is used as
`(cd "$WT" && …)` inside each call (bisect: start, run and reset in one call), and a sibling
worktree for the task itself gets a new session started there (`cd <path> && claude`).

DMI = `disable-model-invocation: true`; `\|` in the table is a literal `|`.

| Skill | DMI | argument-hint | description |
|---|---|---|---|
| onboard | yes | `[hints: board, design file, spec path]` | Day one on a client repo: run it, baseline it, derive CI-mirroring gates, map sources of truth, write untracked .sdw/ state. |
| sync | no | `[contract\|tickets\|design\|all]` | sdw project: what changed since last sync: commits, PRs, contract diff, tickets, design; re-baseline when base moved; find merged branches to wrap. |
| clarify | no | `[plan \| <ticket \| spec path \| design link \| pasted text>]` | Challenge a ticket, spec or design before code: gaps, contradictions, missing states, UX problems. Questions go to the right owner as Slack-ready drafts; nothing is sent. |
| plan | yes | `<task \| KEY-123 \| #123 \| URL \| pasted ticket>` | Plan a task or ticket: lane, acceptance criteria on disk, slices, risks, branch or worktree, tracker transition. |
| debug | no | `<symptom \| error \| BUG-nn \| ticket key>` | Something is broken: reproduce, isolate, root cause, failing test first, fix; or report NOT REPRODUCED with hypotheses. |
| test | no | `[path \| behaviour \| from-qa \| migration \| characterize <path>]` | Write tests at the right layer, prove them red on base, check stability, run the suite against the baseline. |
| qa | no | `[quick \| design \| retest \| --p2 \| --yes \| --api-fuzz] [acceptance criteria text]` | Independent QA pass: cases from ticket and ACs, run in browser/API, explore, file bug reports to disk, verdict by exit criteria. |
| verify-ui | no | `<route> <figma-url \| node-id \| png>` | sdw project: prove a screen matches its design: artboard-size capture, image diff against the reference, measured deltas. |
| ui-polish | no | `<route> [control selectors]` | Interaction polish on a UI change: each control's states, motion timing, reduced motion, layout shift, input delay, widths, dark mode. Rules, then measured. |
| review | no | | Independent review of your own diff against the ACs, QA report and quality bar, by a fresh-context reviewer agent. |
| review-pr | yes | `<PR number \| URL>` | Review someone's PR in a throwaway worktree; draft comments; post only the ones you select. |
| commit | yes | `[--anyway]` | Run gates for touched apps, scan for weakened tests, secrets and debug output, then make one focused commit. |
| ship | yes | `[--draft] [--anyway]` | Push, open or update the PR with evidence valid for this commit, watch CI, merge only on green and a yes. |
| wrap | yes | `[branch]` | After merge: close the task, escaped-defect retro, remove worktree, archive the work dir. |
| offboard | yes | | Leave a project: open-work handoff, names-only credential list, remove every local copy of client data after one confirmation. |
| daily-report | no | `[date]` | Standup text for a working day from commits, PRs, tickets and QA outcomes, with hours labelled as estimates. |
| logwork | yes | `[date]` | Log Jira worklogs from recorded start times and commits; preview each, post only on a yes. |
| create-ticket | yes | `[story\|task\|bug BUG-nn] <summary>` | Create a tracker ticket from a template or a QA bug report; show the exact payload, post only on a yes. |

Supporting files and dependencies:

| Skill | Files beside SKILL.md | Bins / agents used |
|---|---|---|
| onboard | project.md, people.md, run.md, config.example.env, gates.example, env.sh.example, notes.md, local-docs/** | sdw-toolchain, sdw-exclude, sdw-gate (--write-baseline, --list), sdw-jira, sdw-doctor, sdw-cfg |
| sync | — | sdw-cfg, sdw-jira search, sdw-figma-png, sdw-docs-freshness, sdw-workdir, sdw-wt, sdw-gate --write-baseline |
| clarify | checklist.md, questions-template.md, message-template.md | sdw-workdir, sdw-cfg, sdw-figma-png; ux-heuristics and web-design-guidelines when installed; Slack MCP search only |
| plan | plan-template.md, TASKS.md | sdw-cfg, sdw-workdir, sdw-jira, sdw-wt (add, list), gh pr list; sdw:clarify (step 5); Explore agent |
| debug | — | sdw-wt, sdw-redcheck, sdw-workdir, sdw-jira |
| test | e2e/{playwright.config.ts, fixtures.ts, a11y.ts, auth.setup.ts, smoke.spec.ts, test-data.ts, visual.spec.ts, README.md} | sdw-redcheck, sdw-gate --full, sdw-workdir |
| qa | techniques.md, tools.md, cases-template.md, report-template.md, bug-template.md, exit-criteria.md | sdw-workdir (--phase), sdw-login, sdw-ui-shot, sdw-figma-png, sdw-wt, sdw-evidence (stamp, qa-verdict); sdw:qa (foreground) |
| verify-ui | — | sdw-figma-png, sdw-ui-shot, sdw-ui-diff |
| ui-polish | motion.md (sourced defaults) | sdw-ui-shot (--motion, --reduced-motion, --vitals), sdw-workdir; playwright-cli for hover and focus |
| review | — | sdw-tamper, sdw-evidence stamp, sdw-workdir; sdw:reviewer |
| review-pr | payload.py (tested gh-api payload builder) | sdw-wt, sdw-cfg, sdw-jira issue, gh; sdw:reviewer |
| commit | — | sdw-gate (--check, --full), sdw-tamper --staged, sdw-workdir |
| ship | pr-body.md | sdw-evidence (check, pr-lines), sdw-gate --full --keys, sdw-cfg, sdw-jira |
| wrap | — | sdw-wt rm, sdw-cfg, sdw-workdir |
| offboard | — | sdw-wt, sdw-exclude --remove, sdw-workdir --repos |
| daily-report | — | sdw-cfg, sdw-workdir, sdw-jira search, sdw-jira worklog mine |
| logwork | — | sdw-jira worklog (list, mine, add), sdw-cfg, sdw-workdir; reference/tracker-jira.md |
| create-ticket | — | sdw-jira, gh; reference/tracker-*.md |

Agents: `qa.md` frontmatter `name: qa`, `description` (≤200 chars), `model: inherit`; optional
`disallowedTools: Edit, NotebookEdit, Agent`, `effort: high`, `maxTurns: 60`; `tools` omitted
(guard-read denies it every MCP but Playwright, web and agent tools). Its prompt carries
`checkout=<path>` per repo under test.
`reviewer.md`: `name: reviewer`, `tools: Read, Grep, Glob, Bash`, `model: inherit`; optional
`disallowedTools: Edit, Write, NotebookEdit, Agent`, `maxTurns: 40`. Neither relies on the
optional keys: §4.3/§4.4 enforce confinement. The QA agent always runs in the foreground.

templates/verify-skill/SKILL.md: `name: verify`, model-invocable, description about checking
before a commit; body runs `sdw-workdir --projdir` (exit 3 → say "no sdw project, nothing to
verify" and stop), then `sdw-gate --check || sdw-gate --fast`, then `sdw-tamper --staged`, and
reports; it never commits.

## 6. Evidence

### 6.1 evidence.jsonl entry

```json
{"v":1,"ts":"2026-01-01T00:00:00Z","kind":"gate:full","key":"web:apps/web","repo":"web",
 "head":"<40-hex>","tree":"<40-hex>","paths":["apps/web","packages/shared"],
 "result":"pass","detail":"≤200 chars","artifacts":[]}
```
`kind` ∈ `gate:full`, `redcheck`, `ui-diff`. `result`: gate `pass|fail|timeout`; redcheck the
class (`RED(assertion)`, `RED(mutation)` …, `GREEN`); ui-diff `info`. `paths` are repo-relative prefixes; `.` =
whole repo. Appended to `<wd>/evidence.jsonl` with one `printf` (no partial lines).

Working-tree hash: copy `$(git rev-parse --git-path index)` to a temp file (none → empty),
`GIT_INDEX_FILE=<tmp> git add -A`, `GIT_INDEX_FILE=<tmp> git write-tree`, delete the temp file;
run at the repo toplevel. It equals `HEAD^{tree}` once exactly that state is committed.

### 6.2 Stamp line (qa-report.md, review.md)

Line 1: `<!-- sdw-stamp {"repos":[{"repo":…,"head":…,"tree":…}],"paths":["."],"ts":…} -->` from
`sdw-evidence stamp`, one `repos` element per repo in the `sdw-gate --full` change set (a
fullstack change stamps every repo it touched). The QA agent writes it first in qa-report.md; /sdw:review in review.md.

### 6.3 Validity and the ship check

An entry or stamp is valid for HEAD when `git diff --name-only <tree> HEAD^{tree}` (in its repo),
minus doc-filter paths, contains no path equal to or under any of its `paths`; a stamp must be
valid in every repo it lists. A missing tree object makes it invalid (`invalid:tree-missing`).

`sdw-evidence check [--lane L]` (lane from plan.md `Lane:`; no plan.md → TRIVIAL). Branch change
set = `sdw-gate --full` change set. Output `PASS|FAIL|WARN <what>: <detail>`, last line
`RESULT: ok|blocked`; exit 1 when any FAIL:
- every gate key selected by the branch change set: newest valid `gate:full` with `pass`, else
  FAIL `gate <key>` (ship re-runs `sdw-gate --full --keys <key>`).
- every changed test file (`sdw-tamper --test-paths`): any valid `redcheck` with `RED(assertion)` or
  `RED(mutation)` → PASS (a later surviving or build-breaking mutation does not undo it); else the newest
  valid class → WARN `NOT PROVEN <file>: <class>`; none → WARN `NOT PROVEN <file>: no redcheck`.
- STANDARD, RISKY, BUG: qa-report.md stamp valid and the computed verdict (§6.4, never the written
  line) READY or READY WITH KNOWN ISSUES, else FAIL `qa` naming the first blocking reason and the
  command: `/sdw:qa retest` only after a run with FAIL/BLOCKED rows or open bugs, else `/sdw:qa`.
  A written verdict that differs is a WARN. review.md and review-raw.md stamps valid, and open
  S1/S2 = max(review.md `Open:`, raw `[S1]`/`[S2]` items minus review.md items marked
  `(justified`) both 0, else FAIL `review` (user types `/sdw:review`); neither file → `FAIL
  review: no review yet; type /sdw:review`.
- a bugs/BUG-nn.md is cleared only by `Status: verified`, `wontfix` with `Decided-by:`, or a
  proven `pre-existing`: `## Regression vs base` starts with `no` and names a `shots/base-*` file
  that exists, and `Source:` names no AC (`AC-1`, `ac 1`, `AC1`). Any other S1/S2 → FAIL `bug
  <file>: <status> <sev>`: `open`, `fixed` (not verified by a retest), `no status`, `wontfix`,
  `pre-existing unproven`, or `<status> (unknown status)` for a typo. A proven S1/S2 → `WARN bug
  <file>: pre-existing <sev> (not blocking)`; pr-lines omits it.

`sdw-evidence pr-lines`: ≤8 lines from valid entries only, no hashes, lanes, BUG ids or S-levels:
`Tests added: <n> (<m> proven failing before the change[, <k> by breaking the new code])`, `Checks run: <gate commands>`,
`UI compared: <keys>`, `QA: <n> cases, <verdict in plain words>`, `Not covered: …` (NOT PROVEN,
NOT RUN counts).

### 6.4 QA verdict

`sdw-evidence qa-verdict [--lane L] [--write]` applies plugin/skills/qa/exit-criteria.md to
cases.md, `.cases.design.md`, plan.md (ACs, `## Surfaces`), bugs/, qa-report.md (stamp, sections,
`blocks: yes` questions, `## Coverage gaps`) and `shots/*.json` vs `shots/base-*.json` (unmocked
captures: `mocked` and `steps` 0). A Surfaces endpoint counts as covered only by a case whose Steps
name its method and its path (`{id}`/`:id` match one segment; a path with no other method, `-X` or
`-d` is a GET). A `## Coverage gaps` line `none`, `none — <why>` or `none: <why>` is no gap. Prints `Verdict: <v>` then `- blocks: …` and `- known: …`
lines, then `- pre-existing: bug <file> <sev>` for each proven pre-existing bug (no effect on the
verdict); `--write` replaces qa-report.md's `Verdict:` line. Exit 0 READY or READY WITH KNOWN
ISSUES, 1 NOT READY.

## 7. Changes

Interface changes go through this file first.

## 8. Tests

- `tests/<area>/test-*.sh`: plain bash, `#!/usr/bin/env bash`, executable, exit non-zero on the
  first failure with `FAIL <case>: <why>`, print `ok <case>` per case. Files starting `_` are
  helpers, sourced, never run directly.
- Each test makes `tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdw-tests-<area>.XXXXXX")`, removes it in an
  EXIT trap, and isolates git: `HOME=$tmp/home`, `GIT_CONFIG_NOSYSTEM=1`, `GIT_AUTHOR_NAME`,
  `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL` exported.
- Plugin path: `PLUGIN=$(cd "$(dirname "$0")/../../plugin" && pwd -P)`; bins via
  `PATH="$PLUGIN/bin:$PATH"`; hooks with `CLAUDE_PLUGIN_ROOT=$PLUGIN` and JSON on stdin.
- No network, no Docker, no Claude session, no real Keychain: stub `security`, `curl`, `gh`,
  `claude`, `npx`, `node` by putting fake scripts first on PATH in `$tmp/stub`.
- Fixtures cover: repo root; non-git workspace parent with two repos; sibling worktree; `$TMPDIR`
  throwaway worktree; paths with spaces.
- Assert exit codes exactly (guards: `2`, not "non-zero"); "no jq and no python3" is simulated
  with a PATH holding only `$tmp/stub` plus symlinks to bash, git, sed, grep, cat.
- `tests/lint/test-static.sh` holds the static checks (always-loaded caps, frontmatter, git 2.15,
  removed v1 paths, `git fetch origin` guarded for `VCS_HOST=none`, every bash block in skills,
  agents and references parsing with `<placeholders>` as `x`); CI runs it through `tests/run.sh`.
  `test-hooks-json.sh` parses the §4.1 table and requires hooks.json to mount exactly those rows
  with executable commands; mutated copies prove a dropped matcher fails. `test-release.sh` is the
  version check of the §0 release steps. `evals/` costs money and stays out of `tests/run.sh`.
- `tests/run.sh [area…]`: runs every `tests/*/test-*.sh` (or the named areas), each in its own
  process; on macOS it prepends a dir whose `bash` links to `/bin/bash` (3.2) so `env bash`
  resolves there; prints `PASS|FAIL <file>` and a total; exit 1 if any failed.
- Minimum per area: core — §4.3 true/false positives incl. the audit list, guard fail-closed,
  agent confinement, projdir resolution in all fixtures, gate grammar and matching, fingerprint
  no-op, stop_hook_active never blocks, evidence validity, session-start JSON with
  `CLAUDE_PROJECT_DIR` unset; qa — run.md parsing, login with stubbed security/curl, ui-diff
  evidence; review — tamper kinds, test-path classifier, redcheck classification (stub cmd);
  team — sdw-jira path/auth building without printing the token; bootstrap — `--migrate
  --dry-run` changes nothing, settings merge and uninstall round-trip on a fake HOME.
