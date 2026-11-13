---
name: ship
description: "Push, open or update the PR with evidence valid for this commit, watch CI, merge only on green and a yes."
argument-hint: "[--draft] [--anyway]"
disable-model-invocation: true
---

# Ship
Arguments: $ARGUMENTS (every Bash block re-derives its variables)

## 0. Preflight
```bash
sdw-workdir --no-create >/dev/null; echo "rc=$?"; HOST=$(sdw-cfg VCS_HOST); echo "team=$(sdw-cfg TEAM_SKILLS) host=$HOST tracker=$(sdw-cfg TRACKER)"
BR=$(git symbolic-ref --short -q HEAD); BASE=$(sdw-cfg BASE_BRANCH); echo "branch=$BR base=$BASE"
git status --porcelain; [ "$HOST" = none ] || git fetch origin --quiet
BASEREF=$(git rev-parse -q --verify "origin/$BASE" >/dev/null && echo "origin/$BASE" || echo "$BASE"); git log --oneline "$BASEREF..HEAD"
```
- rc 3 → say `run /sdw:onboard first` and stop. rc 4 → ask the user to cd into the repo or worktree.
- TEAM_SKILLS has `push` or `create-mr`, arguments lack `--anyway` → say `this repo has /push, use it` (or /create-mr), stop.
- VCS_HOST=none → run step 1's `sdw-evidence check`, show its FAIL lines, then stop: no remote, so
  nothing to push to.
- Stop on: detached HEAD, the base branch, a dirty tree, no commits ahead. `gh` missing or logged out with VCS_HOST=github → push only, and
  say the PR step was skipped.

## 1. Evidence for this commit
```bash
sdw-evidence check; echo "check=$?"; sdw-evidence list --valid-for HEAD
```
- Stop until `RESULT: ok`. `FAIL gate <key>` → `sdw-gate --full --keys <key>`, then check again.
- `FAIL qa` → the user types the command the line names (`/sdw:qa`, or `/sdw:qa retest` after a run
  with failures); `FAIL review` → `/sdw:review`; open bug → `/sdw:debug BUG-nn`.
- `WARN NOT PROVEN` lines are listed to the user; pr-lines puts them under Not covered.
- Suite vs `.sdw/state/baseline.md`: paste the runner's summary line from this branch's `sdw-gate --full`
  output beside the baseline line; fewer passing → stop and ask. No summary line → say NOT VERIFIED.
- Only the user's explicit "ship anyway" passes a blocked check; each FAIL then goes in Not covered, in plain words.

## 2. Push
```bash
BR=$(git symbolic-ref --short -q HEAD); git push -u origin "$BR"
```
Rejected because the remote moved → `git pull --rebase origin "$BR"` with a yes, then step 1 again.
Force only with a yes and only as `--force-with-lease`; never to the base branch.

## 3. Body
- The client's template wins: `ls -d .github/* docs/* * 2>/dev/null | grep -i pull_request_template`
  (a `PULL_REQUEST_TEMPLATE/` dir with several → ask which). None → `${CLAUDE_SKILL_DIR}/pr-body.md`.
- Fill every section from the commits, plan.md and the diff in plain words. Tick a checklist box only
  for a check that ran and was seen to pass. No lanes, case or bug ids, severities, hashes or tool names.
- Notes (the template's notes section, else `## Notes`): plan.md `## Progress` Decision lines as
  `<what> — <why>`, duplicates merged, at most 5, no slice or step names. None → no section.
- Append the evidence block, at most 8 lines:
  `<details><summary>Verification</summary>` + blank line + `sdw-evidence pr-lines` output + `</details>`.
- TRACKER=github: add `Closes #<n>`. Write the body to `$(sdw-workdir)/pr-body.md`.

## 4. Title, create or update
- Title from `sdw-cfg PR_TITLE_PATTERN` (`{key}`/`{n}` from the branch, `{summary}` from plan title or main
  commit); a title-check workflow in `.github/workflows/` wins. Write it to `$(sdw-workdir)/pr-title.txt`.
```bash
BR=$(git symbolic-ref --short -q HEAD); BASE=$(sdw-cfg BASE_BRANCH); WD=$(sdw-workdir); DRAFT=  # DRAFT=1 when the arguments contain --draft
if gh pr view "$BR" --json number >/dev/null 2>&1; then gh pr edit "$BR" --title "$(cat "$WD/pr-title.txt")" --body-file "$WD/pr-body.md"
else gh pr create --base "$BASE" --head "$BR" --title "$(cat "$WD/pr-title.txt")" --body-file "$WD/pr-body.md" ${DRAFT:+--draft}; fi
[ "$(gh pr view "$BR" --json headRefOid -q .headRefOid)" = "$(git rev-parse HEAD)" ] && echo "head ok" || echo "HEAD MISMATCH"
```
HEAD MISMATCH → push again and re-check; never continue while the PR lacks the local tip.

## 5. CI
- VCS_HOST≠github: print the PR/MR link from the push output (or the host's new-PR page for this
  branch), paste the body for the user, say plainly that CI is watched manually, and stop.
- GitHub: run with `run_in_background: true` and wait for the completion notice (never a foreground wait):
```bash
BR=$(git symbolic-ref --short -q HEAD); gh pr checks "$BR" --watch --fail-fast --interval 30; echo "checks exit: $?"
```
- Exit 0 → green. "no checks reported" is not green: say so. Red → `gh run view <run id> --log-failed | tail -60`,
  report the failing check and stop (fix → `/sdw:commit` → `/sdw:ship`).

## 6. Tracker (preview, then only after a yes)
- Jira: `sdw-jira transitions <KEY>`; TRANSITION_IN_REVIEW not offered → say which are and stop. Else
  `sdw-jira transition <KEY> <id> --dry-run`, then without `--dry-run`.
- GitHub project: GH_STATUS_IN_REVIEW_ID via `gh project item-edit` (`${CLAUDE_SKILL_DIR}/../../reference/tracker-github.md`).

## 7. Merge (green and an explicit yes only)
Method: the team's convention (.sdw/project.md Conventions) among those
`gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed` allows; else ask.
Re-check checks and headRefOid, then
`gh pr merge "<branch>" --<squash|merge|rebase> --match-head-commit "$(git rev-parse HEAD)"` (`--delete-branch`
only when asked). Never merge on red, on no checks, or without a yes. Next: `/sdw:wrap`.

## Output
Wherever the run ends after the push, when plan.md exists, first rewrite its `## Progress` Now and Next: the PR link,
the CI or merge state, and what is left.
```
SHIP  KEY-123-export-orders-as-csv → main (3 commits)
Evidence: gates pass · QA ready · review 0 open · 1 test not proven (listed)
PR:       <url> (head a1b2c3d matches local)
CI:       build ✓ · test ✓ · e2e ✗ login.spec.ts:22 timeout → not merged
Next:     fix e2e → /sdw:commit → /sdw:ship
```
