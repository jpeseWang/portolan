---
name: qa
description: "Independent QA pass: cases from ticket and ACs, run in browser/API, explore, file bug reports to disk, verdict by exit criteria."
argument-hint: "[quick | design | retest | --p2 | --yes | --api-fuzz] [acceptance criteria text]"
---

# QA

Arguments: `$ARGUMENTS`. Mode `quick`, `design` or `retest`, else full. Flags `--p2`,
`--yes`, `--api-fuzz`. Any other text is acceptance criteria the user typed. This session reads only
`${CLAUDE_SKILL_DIR}/tools.md` "Detect"; the agent reads techniques.md and the templates; sdw-evidence
applies exit-criteria.md.

## 0. Setup

```bash
sdw-workdir --no-create >/dev/null; echo "rc=$?"
wd=$(sdw-workdir) && echo "wd=$wd" && sdw-workdir --phase && ls -a "$wd"
BASE=$(sdw-cfg BASE_BRANCH); BASEREF=$(git rev-parse -q --verify "origin/$BASE" >/dev/null && echo "origin/$BASE" || echo "$BASE"); echo "baseref=$BASEREF"
```
rc 3 (no sdw project) → `quick` only, in chat, no files; say `/sdw:onboard` enables full QA.
rc 4 → cd into the repo or worktree under test. Read `$wd/plan.md` (`Lane:`, ACs, `## Surfaces`)
and `$(sdw-workdir --projdir)/.sdw/run.md`.

## quick (main session, no agent)

For TRIVIAL changes and mid-task checks. 3–5 checks from the plan.md ACs or the user's words.
1. Each check is one observable statement: status and body shape, text on screen, row written.
2. App per run.md (`start`, `port`, `ready`). `lsof -nP -iTCP:<port> -sTCP:LISTEN` first: this
   app from this worktree is reused; anything else listening is the finding. It will not start
   → report that and stop.
3. Observe with the cheapest tool: curl, the CLI, `sdw-ui-shot` (png and JSON into
   `$wd/shots/`). Unhappy paths too: empty and invalid input, no session 401, wrong role 403.
4. Report `Checked / Observed (pasted output) / Unhappy path / NOT RUN (why) / Console`.
   Never report what you did not observe. Stop only the servers you started.

## 1. Preflight (main session)

- No plan.md: with typed criteria, save them unedited to `$wd/ticket.md` (line 1
  `<!-- source: pasted fetched <iso> -->`) and write a minimal plan.md from
  `${CLAUDE_SKILL_DIR}/../plan/plan-template.md`: one AC row each, Source `agreed-in-chat`, lane
  RISKY when a risk trigger appears (roles, permissions, money, migration), else STANDARD. Show the
  rows; continue unless the user objects (`--yes` skips the wait). No criteria → `type /sdw:plan
  first`. Never invent ACs.
- Lane TRIVIAL → offer quick instead. BUG → STANDARD caps; `$wd/repro.md` is an input whenever present.
- Mode: fresh run → design, then execute. cases.md with phase `execute` and no Result → execute
  only. Mode `design` with a cases.md whose phase is past design → say so and ask before
  redesigning (it resets the snapshot); `--yes` does not imply it. `retest` needs cases.md and a finished run; without cases.md it runs as full and
  qa-env.md records `retest→full`.
- Tools per `${CLAUDE_SKILL_DIR}/tools.md` "Detect"; write `$wd/qa-env.md`.
- Execute, full and retest only (design runs no app):
  - Server freshness, per app in run.md:
    ```bash
    pid=$(lsof -nP -iTCP:<port> -sTCP:LISTEN -t | head -1); echo "pid=$pid"
    lsof -a -p "$pid" -d cwd -Fn | sed -n 's/^n//p'; git rev-parse --show-toplevel
    date -j -f '%a %b %d %T %Y' "$(ps -o lstart= -p "$pid")" +%s
    (cd "$(git rev-parse --show-toplevel)" && { git diff --name-only HEAD; git ls-files --others --exclude-standard; } \
      | while IFS= read -r f; do [ -e "$f" ] && stat -f '%m %N' "$f"; done | sort -n | tail -1)
    ```
    Server cwd in another worktree → that app's cases BLOCKED; never use it. Started before the
    newest change and not a watch server → restart it if QA started it, else ask the user. Not
    running → start per run.md in the background, record PID in qa-env.md, wait for `ready`.
    Next.js on RISKY: `next build && next start -p <spare port>`.
  - Roles are the keys under run.md `## users`; a key listing two names also has `<key>-2`
    (`- user: alice, bob` → `sdw-login user; sdw-login user-2`). Log in every role the cases
    name, and `<r>-2` whenever an idor row exists. Non-zero → record role and reason in
    qa-env.md; its cases go BLOCKED.
  - Base capture, RISKY or when Surfaces lists a UI route: `sdw-wt add base-$(date +%s) --detach
    <BASEREF>`, start it on a spare port as `(cd "<WT>" && …)`, then per route
    `sdw-ui-shot --url <base url> --out "$wd/shots/base-<route>.png" --axe > "$wd/shots/base-<route>.json"`.
    Stop it and `sdw-wt rm` after. A route missing on base is noted in qa-env.md.
  - `--api-fuzz`: run the tools.md fuzz command now (it reads a session jar, so never the agent).
  - Change marker, kept for step 3: `touch "$wd/.qa-start"`.
- `sdw-workdir --phase design` for a fresh run; `sdw-workdir --phase execute` for execute-only
  or retest.

## 2. Agent runs

Launch `sdw:qa` with the Agent tool in the **foreground** (a background agent's permission
prompts are auto-denied). The prompt carries only:
`wd=<wd> projdir=<projdir> checkout=<abs path, one per repo under test> skill_dir=${CLAUDE_SKILL_DIR}
mode=<…> lane=<…> caps=<…> roles=<ready roles> tools=<ready tools> api-fuzz=<yes|no> p2=<yes|no>`.
Never pass the diff, the changed files or how the change was built.

1. Mode `design` (every lane). Then check cases.md here: every AC-n in a Source cell, an authz
   row per Surfaces endpoint, an idor row per endpoint with an id, every Expected cites a
   source, within caps (STANDARD, BUG ≤12; RISKY ≤30). `sdw-workdir --phase` must now read
   `execute`; `design` means the hook found an AC without a case. Show the table and take
   changes unless `--yes`. `design` mode ends here: print `next: /sdw:test from-qa, implement,
   then /sdw:qa`.
2. Mode `execute` (or `retest`) with the lane's caps: STANDARD, BUG P1 only (P2 with `--p2`),
   1 charter of about 10 tool calls; RISKY P1 and P2, 2 charters of about 20 calls each.

## 3. Check (main session)

1. Changes outside `.sdw/` since QA started, in each repo under test:
   `find . \( -name node_modules -o -name .git -o -name .next -o -name .turbo -o -name .sdw \) -prune -o -type f -newer "$wd/.qa-start" -print`
   plus `git status --porcelain`. Anything → tell the user exactly what changed; never revert it.
2. Line 1 of `$wd/qa-report.md` must start with `<!-- sdw-stamp`; otherwise the run is incomplete.
3. Coverage: list the endpoints and UI routes the branch diff touches (route definitions in
   `git diff "$(git merge-base HEAD <BASEREF>)"`) and compare with plan.md Surfaces and the
   authz rows. Write a `## Coverage gaps` section in qa-report.md: one line per uncovered one, or
   `- none` (any reason after an em dash: `- none — <why>`).
4. `sdw-evidence qa-verdict --write` computes the verdict per
   `${CLAUDE_SKILL_DIR}/exit-criteria.md` and writes it; paste its output. Never judge it yourself.
5. plan.md AC table: Status (`PASS FAIL BLOCKED NOT RUN`) and Evidence (TC ids).
6. `sdw-workdir --phase done`. Stop servers QA started (PIDs in qa-env.md).
7. Print ≤10 summary lines, then what the user can type (never invoke these yourself):
   - each open bug: `/sdw:debug BUG-nn`, then `/sdw:qa retest`
   - a proven `pre-existing` bug (qa-verdict's `- pre-existing:` lines) does not block: report it
     to the user, out of this change's scope
   - an open S1/S2 the user decides not to fix: `Status: wontfix` plus `Decided-by: <who, where>`
   - Automate=yes cases with no Test name: `/sdw:test from-qa`
   - a bug for the tracker: `/sdw:create-ticket bug BUG-nn`
