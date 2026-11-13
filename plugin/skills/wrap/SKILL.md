---
name: wrap
description: "After merge: close the task, escaped-defect retro, remove worktree, archive the work dir."
argument-hint: "[branch]"
disable-model-invocation: true
---

# Wrap
Branch: $ARGUMENTS (empty → the current branch)

## 1. Merged?
```bash
sdw-workdir --projdir; echo "rc=$?"; HOST=$(sdw-cfg VCS_HOST); echo "host=$HOST tracker=$(sdw-cfg TRACKER) worklog=$(sdw-cfg WORKLOG)"
```
- rc 3 → say `run /sdw:onboard first` and stop.
- VCS_HOST=github with `gh`: `gh pr view "<branch>" --json number,state,mergedAt,url,headRefOid`. Otherwise (or no
  `gh`): `BASE=$(sdw-cfg BASE_BRANCH); [ "$HOST" = none ] || git fetch origin --quiet; git branch -r --merged
  "origin/$BASE" | grep -qx "  origin/<branch>"`; no → ask the user `merged? (y/n)`, since a squash merge
  does not show.
- Merged: every commit on the branch must be in what merged. GitHub: `git fetch origin --quiet`, then
  `git log --oneline <headRefOid>..<tip>` for each of `<branch>` and `origin/<branch>` that exists (oid
  unknown locally → `git fetch origin pull/<n>/head` first). Otherwise: `git log --oneline
  origin/<branch>..<branch>` (never pushed). Any line → list them as `commits not in the merged PR`; run
  steps 2–4 but not 5, and the user decides on a follow-up PR.
- Not merged → stop. With the user's yes, append `Status: parked <iso>` to its plan.md instead
  (/sdw:sync then skips it).

## 2. Bookkeeping (TRACKER=none only)
Move the task to Done in `<repo>/TASKS.md` with the finish date; add a line to CHANGELOG.md only when a
Keep-a-Changelog file already exists (user-facing outcome, under `[Unreleased]`). Leave both uncommitted
and tell the user they go into the next branch with `/sdw:commit`. TRACKER≠none: no bookkeeping commits.

## 3. Escaped-defect retro
For each defect found after the AC stage (QA FAIL, reviewer S1/S2, CI red, PR review comments, bugs
reported after merge): name the gate that should have caught it and propose one fix, preferring in order
a test, a `.sdw/gates` line, a `.sdw/review-rules.md` rule (a mistake the reviewer could have caught,
seen before: `## <glob>` and `- <rule> — why: <what happened>`), a hook rule, a `## Traps` line. Apply
only with a yes. None → say so.

## 4. Time
WORKLOG=1 → tell the user `/sdw:logwork` can log this task.

## 5. Clean up
- `sdw-wt list`: the row for this branch → `cd` out of it if the session is inside, then `sdw-wt rm <slug>`
  (dirty → show `git status`, `--force` only with a yes).
- Archive: `mv "<projdir>/.sdw/work/<bslug>" "<projdir>/.sdw/work/_done/<bslug>"` (`mkdir -p _done`
  first; an existing target gets a `-<date>` suffix).
- Main checkout still on this branch and clean → offer `git checkout <BASE> && git pull --ff-only`.

Report: PR, retro items (applied or proposed), worktree deleted, work dir archived.
