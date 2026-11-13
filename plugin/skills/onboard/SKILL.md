---
name: onboard
description: "Day one on a client repo: run it, baseline it, derive CI-mirroring gates, map sources of truth, write untracked .sdw/ state."
argument-hint: "[hints: board, design file, spec path]"
disable-model-invocation: true
---

# Onboard
Hints: $ARGUMENTS

Read-only to shared systems (tracker, design, shared DBs, cloud). Fix your environment, never their code;
pre-existing failures are recorded, not patched. Record only commands you saw work; `none` beats a guess.
Ask only what the repo cannot answer. Templates: `${CLAUDE_SKILL_DIR}/`; read `notes.md` there before step 5.

## 0. Locate
- Run from the repo root or from the non-git workspace parent that holds the repos; in a subdir or a
  linked worktree, say where to `cd` and stop. `sdw-workdir --projdir` already finds an ancestor → ask
  whether to refresh that one instead.
- v1 install present (`solo-dev-workflow:generated` under any repo's `.claude/`, or a symlinked
  CLAUDE.md with a `.bak` beside it): tell the user to run
  `~/.local/share/sdw/release/bootstrap.sh --migrate <dir> --dry-run`, then stop.
- `.sdw/` already exists → refresh mode: show a diff before replacing any file; never drop Traps lines.
```bash
mkdir -p .sdw/state .sdw/work && sdw-exclude && sdw-workdir --repos
```

## 1. Inventory (each repo)
- Read the team's CLAUDE.md, AGENTS.md, CONTRIBUTING, PR template and CI config (`.github/workflows/`,
  `azure-pipelines.yml`, `bitbucket-pipelines.yml`, `.gitlab-ci.yml`): the project's rules, and the
  honest record of how it builds and tests.
- Apps: `git ls-files | grep -E '(^|/)(package\.json|[^/]+\.(csproj|sln)|pyproject\.toml|go\.mod|pom\.xml|build\.gradle(\.kts)?)$' | grep -v node_modules`.
  Per app: path, kind, stack, package manager (the lockfile decides), scripts. Nx/Turbo/pnpm workspace?
- Team skills: names in `.claude/commands/` and `.claude/skills/`, mapped by name or obvious purpose to
  `commit push start-work create-branch create-mr review-pr create-ticket daily-report logwork` → TEAM_SKILLS.
- An AGENTS.md hidden by a CLAUDE.md in its dir or an ancestor: note it; `bootstrap.sh --agents-md` fixes it.
- VCS_HOST from `git remote get-url origin`: github, gitlab, bitbucket or azure; no origin → `none`.

## 2. Toolchain
```bash
sdw-workdir --repos | while IFS= read -r r; do sdw-toolchain "$r"; done
```
- Fix each mismatch for this machine (nvm, mise, the SDK `global.json` asks for). Pinned
  `packageManager`: `corepack enable --install-directory "$PWD/.sdw/state/corepack-bin"`.
- Write `.sdw/env.sh` from `sdw-toolchain "<repo>" --emit-env` for every repo, unique lines only (format:
  `${CLAUDE_SKILL_DIR}/env.sh.example`). Start every later Bash block of this session with
  `source .sdw/env.sh &&`; from the next session on the SessionStart hook does it.

## 3. Run each app (DB → API → web)
- DB: `DB_LOCAL=1` only when the connection host is localhost, 127.0.0.1 or a local container. A shared
  DB or a production copy: no migrate, seed or destructive statement, and `QA_WRITE_ENV: shared-ask`.
- Before starting: `lsof -nP -iTCP:<port> -sTCP:LISTEN`. A listener you did not start (another agent, a
  system service) is a finding: use it or report it, never kill it.
- Start detached and record what you started, so step 9b can stop exactly that:
  `nohup <start> > .sdw/state/<app>.log 2>&1 & echo "$! <app> <port>" >> .sdw/state/onboard-pids`.
  Wait for the ready signal, hit one real route. Every failure: exact error text → cause → fix (these
  become `## Traps`).

## 4. Baseline (clean base only)
- BASEREF is `origin/<BASE>` when it exists, else `<BASE>` (no remote).
- Dirty or off base → `sdw-wt add base-$(date +%s) --detach <BASEREF> --no-deps` (last line WT); the
  Bash cwd resets after every call, so run each step as `(cd "<WT>" && …)`; `sdw-wt rm` after. Deps:
  lockfile at BASEREF equal to the checkout's → symlink each app's `node_modules`/`.venv` from the
  checkout; else install in WT only, and say so.
- Run each app's tests. Write `.sdw/state/baseline.md`: base sha, date, one pasted summary line per app
  (pre-existing failures named), and the latest green CI run if any:
  `gh run list --branch <BASE> --status success --limit 1 --json databaseId,headSha`.
- Write `.sdw/state/last-sync`: line 1 ISO time, line 2 base sha.

## 5. Gates → `.sdw/gates` (grammar and examples: `${CLAUDE_SKILL_DIR}/gates.example`)
- Fast per app: typecheck + lint, about a minute, never a build that rewrites a running dev server's output.
- Full per app: every CI check step that runs locally (never an install: `npm ci`, `pnpm install`,
  `dotnet restore` rewrite dependencies under running servers): format check, commitlint, build, tests, codegen drift
  (`<generate> && git diff --exit-code <dir>`), EF `migrations has-pending-model-changes` or
  `prisma migrate diff --exit-code` when present.
- Turbo/Nx: one `.` line with the affected command. Otherwise `deps:` lines from shared packages.
- Run every candidate on the clean base. Red there → narrow it, or keep it and run
  `sdw-gate --write-baseline <key> [--full]` from the clean base checkout so only new diagnostics fail.
- `sdw-gate --list` and `sdw-gate --dry-run --full` must succeed. List the CI steps that cannot run locally.

## 6. Sources of truth
- Contract (path; spec or code wins), auth (cookie or token, where roles are enforced, tenancy),
  FE↔BE origin (same origin, proxy, CORS), data (migration tool and folder, seed, production copy?),
  deploy (environments, what deploys on merge).
- Jira: put JIRA_BASE_URL/EMAIL/PROJECT in config.env and have the user store the token (step 8).
  JIRA_FLAVOR: `*.atlassian.net` → cloud, else dc (dc without PATs → JIRA_AUTH=basic); `sdw-jira myself` confirms (401 auth, 404 flavour); `sdw-jira GET /field` gives JIRA_AC_FIELD and
  JIRA_SPRINT_FIELD; one ticket's `/issue/<KEY>/transitions` gives the transition ids.
  Details: `${CLAUDE_SKILL_DIR}/../../reference/tracker-jira.md`.
- GitHub: `gh auth status` must list the `project` scope; `gh project field-list` gives GH_STATUS_* ids
  (`${CLAUDE_SKILL_DIR}/../../reference/tracker-github.md`).
- Design: FIGMA_FILE_KEY; seat → FIGMA_MCP_BUDGET (View seat ≈ 6 MCP calls/month: use 0); token `sdw:figma`?
- People: who decides scope, design, the contract, environments and test data, and the channel where
  decisions go. Read it from CODEOWNERS, recent PR reviewers (`gh pr list --state merged --limit 30
  --json author,reviews`), and the Jira project lead and components. Ask the user for the rest. Never
  guess a name: an unknown owner stays empty and goes under `## Unknown`.

## 7. QA prerequisites → `.sdw/run.md` (format: `${CLAUDE_SKILL_DIR}/run.md`)
- Per app: start, port, ready, seed, test-db for red-on-base runs, OpenAPI URL or `none`.
- Login recipe: form URL + selectors; an API endpoint (cookie, or a token with `- token-path:`); a
  `header` recipe for caller-asserted headers (`- header: x-user: {user}`); or `oauth-manual`.
- Two named test users per role (`<role>`, `<role>-2`); names only. Spec paths for QA design: `## qa`
  `- spec: <projdir-relative path>[, …]`.
- Seed or fixtures that reach empty, error and long-text states. QA_WRITE_ENV. Design artboard sizes.

## 8. Write (all untracked)
- `.sdw/project.md` from `${CLAUDE_SKILL_DIR}/project.md`: ≤40 lines, ≤2,500 chars, Traps from today's
  failures with exact error text.
- `.sdw/people.md` from `${CLAUDE_SKILL_DIR}/people.md`: names and chat handles only, no emails or phone numbers.
- `.sdw/config.env` from `${CLAUDE_SKILL_DIR}/config.example.env` (no secrets), `.sdw/gates`, `.sdw/run.md`;
  then `sdw-exclude --check`.
- Keychain one-liners for the user to run in their own terminal, one per missing item:
  `security add-generic-password -U -s '<service>' -a '<account>' -w`
  (`sdw:jira:<JIRA_BASE_URL>`, `sdw:figma`; per test user `-s 'sdw:<PROJ_SLUG>:<role>' -a '<user name>'`,
  the second user of a role under the same service). A `header` recipe without `{pass}` needs none.
- Local docs: default yes for a workspace parent (`DOCS_DIR=local-docs`), otherwise ask
  (`DOCS_DIR=.sdw/docs`, so nothing appears in `git status`). Copy, keeping existing files (exit 1 = some kept):
  `mkdir -p "<DOCS_DIR>" && cp -Rn "${CLAUDE_SKILL_DIR}/local-docs/." "<DOCS_DIR>/"`. Fill overview.md,
  tech/troubleshooting.md and the STATUS baseline; stamp `<!-- reviewed: <today> | against: <sha> | status: current -->`.
- Ask once: is this client under NDA? Yes → merge `"autoMemoryEnabled": false` into
  `<projdir>/.claude/settings.local.json` (one permission prompt). The sdw exclude block keeps it out
  of `git status`; confirm with `git check-ignore -q .claude/settings.local.json` in a repo-root projdir.

## 9. Doctor
`sdw-doctor`. Report every FAIL and WARN with its fix.

## 9b. Stop what onboard started
Each PID in `.sdw/state/onboard-pids`: `kill <pid>`, confirm the port is free, then delete the file.
Never stop a listener you did not start.

## 10. Output
```
ONBOARD — <projdir>
Apps:       web (Next 15, pnpm, :3000) · api (.NET 8, :8080)
Toolchain:  node 22.12 ✓ dotnet 8.0.4 ✓ (env.sh written)
Running:    db ✓ api ✓ web ✓ (stopped after) · 2 traps recorded
Baseline:   api 412/412 · web typecheck 3 pre-existing (gate baseline stored)
Gates:      2 fast · 2 full · not runnable locally: e2e (needs cloud secrets)
Team:       /commit, /push → sdw defers
QA ready:   users 2/2 roles · login form ✓ · seed ✓ · browser playwright-cli · OpenAPI none
People:     PO ✓ Designer ✓ BE lead ✓ · unknown: DevOps (.sdw/people.md)
Needs:      <access to request> · then ≤5 questions the repo could not answer
```
