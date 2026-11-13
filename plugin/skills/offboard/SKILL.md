---
name: offboard
description: "Leave a project: open-work handoff, names-only credential list, remove every local copy of client data after one confirmation."
disable-model-invocation: true
---

# Offboard

Never print a credential's value: names and locations only. Revoking is not deleting: a token lives on
the server until it is revoked there. Nothing client-specific leaves with you. The sdw plugin stays installed.

## 0. Preflight
```bash
P=$(sdw-workdir --projdir); echo "rc=$?"; echo "projdir=$P"; sdw-workdir --repos
echo "slug=$(sdw-cfg PROJ_SLUG) jira=$(sdw-cfg JIRA_BASE_URL) docs=$(sdw-cfg DOCS_DIR)"; sdw-wt list
```
rc 3 → no sdw state here: ask for the project dir and stop.

## 1. Open work
For every repo: `git status --short`, `git stash list`, `git worktree list`,
`git log --branches --not --remotes --oneline | head -20` (commits only on this machine),
`git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads`. Plus
`gh pr list --author @me --state open`, tickets assigned to the user in progress (MCP, `sdw-jira`, or
`gh issue list --assignee @me`), each `.sdw/work/*/plan.md` with ACs not PASS, and unanswered
questions in `.sdw/work/*/questions.md` and `.sdw/state/clarify-*.md`.
For each item the user decides: push and hand over, close, or discard. Work that exists only here is
never deleted before that decision.

## 2. Handoff note and credentials
- Handoff: open PRs and their state, unmerged branches, half-done tasks and where they stopped, open
  bugs, traps from `.sdw/project.md`, pending decisions and their owners. Plain words, no secrets, no
  workflow ids. Show it and save it where the user says, never under `.sdw/` (deleted below). Do not post it.
- Credential inventory, names only:
  - Keychain: `security dump-keychain 2>/dev/null | sed -n 's/.*"svce"<blob>="\(sdw:[^"]*\)".*/\1/p' | sort -u`
    (attributes only; never `-d`, never `-w`).
  - `gh auth status` accounts; MCP server names in `.mcp.json` and for this project in `~/.claude.json`;
    `.env*` file names (never contents); `.sdw/auth/` and `e2e/.auth/` sessions; registries in `~/.npmrc`
    and `~/.docker/config.json`; SSH or deploy keys made for this client; cloud CLI profiles.
  - Table: credential · stored where · revoke where. The user revokes; mark each ⏳ until they confirm.

## 3. QA test data
From every `## Test data created` section in `.sdw/work/*/qa-report.md` and `.sdw/work/_done/*/qa-report.md`:
list per environment. Delete only with a separate yes per environment; shared environments need the
team's yes first. `setting` lines are not data to delete: show the `NOT restored` ones for the user to
put back, skip the rest.

## 4. Removal list (show it all with sizes, then ask ONCE)
- Every registered worktree: `sdw-wt rm <slug>` (dirty ones only with `--force`, after step 1).
- The exclude block: `sdw-exclude --remove` (before `.sdw/` goes).
- Keychain: `sdw:<PROJ_SLUG>:<role>` items and `sdw:jira:<JIRA_BASE_URL>`; `sdw:figma` only if no other
  project uses it (ask). Delete with `security delete-generic-password -s '<service>'`, repeated until
  it reports not found.
- `e2e/.auth/` and `playwright/.auth/` in every repo; untracked `test-results/`, `playwright-report/`.
- Claude Code data for projdir, every repo and every worktree path (outside the project: the guard
  blocks deleting it by design, so these go to the user, see After exit). Slug per path (both `pwd`
  and `pwd -P` forms): `python3 -c 'import re,sys;print(re.sub(r"[^A-Za-z0-9]","-",sys.argv[1]))' "<path>"`.
  - `~/.claude/projects/<slug>/` (auto-memory, `*.jsonl` transcripts);
  - `~/.claude/file-history/<id>` and `~/.claude/todos/<id>*` for each transcript's session id;
  - lines of `~/.claude/history.jsonl` whose `project` is one of those paths.
- Plugin state: `.sdw/` (plans, evidence, shots, design refs, auth, people.md with team names and handles), `${TMPDIR%/}/sdw/<repo>-*`
  throwaways, `~/.cache/sdw` files named for this project's design file.
- Client data elsewhere: DB containers and volumes (`docker ps -a`, `docker volume ls`; `docker volume rm`
  is blocked by the guard, so these go to the user), backups (`*.bak`, `*.dump`, `*.sql`), downloaded
  documents, symlinks into shared drives, an untracked DOCS_DIR, security-audit runs in
  `~/security-audit-skill/<repo>/` (they hold the client's vulnerabilities; outside the project, so the user's).
- `.claude/settings.local.json` keys onboard added (only if the user wants them gone). If the file stays,
  it shows in git status once the exclude block is gone: offer to delete it (when onboard created it),
  or to add `.claude/settings.local.json` alone to `.git/info/exclude`, outside the sdw block.

Before deleting memory: offer to copy genuinely generic lessons to `~/.claude/CLAUDE.md`, rewritten
without client names, URLs, ids, code or data.

Order on yes: worktrees → exclude block → Keychain → auth dirs and reports → client data inside the
project → `.sdw/` last. Never work around a guard block (python, find, a script): what it blocks goes
to the user. Print, under After exit, one command per remaining item for the user to run in their own
terminal after this session ends: every `rm -rf ~/.claude/projects/<slug>` (this session's included,
it keeps writing its transcript), `~/.claude/file-history/<id>` and `~/.claude/todos/<id>*`, the
`history.jsonl` filter, `docker rm`/`docker volume rm` per item, and data outside the project.

## 5. Report
```
OFFBOARD — <project>
Work:         2 PRs handed over (handoff saved to <path>) · 1 branch pushed · 0 stashes
Credentials:  5 found — Jira token ⏳ revoke · Figma token ⏳ · gh PAT ⏳ · 2 Keychain test users ✅ deleted
Test data:    23 "Probe …" rows on staging — team asked ⏳
Removed:      .sdw/ · exclude block · 2 worktrees · e2e/.auth · 3 backups
After exit:   14 transcript dirs · DB volume (2.1 GB): the commands printed above
```
`⏳` lines are the user's to finish; say so.
