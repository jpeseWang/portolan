---
name: commit
description: "Run gates for touched apps, scan for weakened tests, secrets and debug output, then make one focused commit."
argument-hint: "[--anyway]"
disable-model-invocation: true
---

# Commit
Arguments: $ARGUMENTS
## 0. Preflight
```bash
sdw-workdir --no-create >/dev/null; echo "rc=$?"; echo "team=$(sdw-cfg TEAM_SKILLS)"; git status --short; git diff --stat HEAD
```
- rc 3 → say `run /sdw:onboard first` and stop; rc 4 → ask to cd into the repo or worktree; base branch → stop, suggest /sdw:plan.
- TEAM_SKILLS has `commit` and the arguments lack `--anyway` → say `this repo has /commit, use it` and stop.

## 1. Stage by path
Read every changed file; stage only this change, by path, never `git add -A`. Files you did not touch
are reported, not staged or reverted. Two unrelated changes → offer two commits.

## 2. Gates
```bash
sdw-gate --check || sdw-gate --fast; sdw-gate --full; echo "full=$?"
```
Paste the summaries. Red → stop and fix the cause. Commit on red only after the user's explicit yes for
this commit; the body then names the failing gate. Gates run on the working tree: unstaged edits in a
gated app mean the result is not the commit's; say so. sdw-gate writes the evidence.

## 3. Scans (blocking)
```bash
sdw-tamper --staged; echo "tamper=$?"
git diff --cached --name-only --diff-filter=AM -z | xargs -0 grep -nEIi '(AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_|xox[baprs]-|sk_live_|(api[_-]?key|secret|passw(or)?d|token)["'\'' ]*[:=] *["'\''][^"'\'' ]{8,})' -- 2>/dev/null | cut -d: -f1,2
git diff --cached -U0 | grep -nE '^\+.*(\.only\(|\bfit\(|\bfdescribe\(|debugger;|console\.log\(|Console\.WriteLine\(|breakpoint\(\))'
```
- Each tamper hit: revert it, or the user gives the reason, which goes in the commit body in plain words.
- Secret hits print only `file:line`, never the value. A real secret, `.env*`, keys, large binaries or
  generated files the repo does not commit → unstage and tell the user.

## 4. Review and budgets
- `$(sdw-workdir --no-create)/review.md` has `Open:` S1 or S2 above 0 → stop: fix, then `/sdw:review` again.
- Repo-wide budgets (comment density, bundle size) → re-run; read the exit code, not the printed
  percentage. Already over on base → say whose it is; never trim someone else's text to fit.

## 5. Message
- Repo convention first: `git log --format=%s -20`, commitlint config, CONTRIBUTING, .sdw/project.md
  Conventions. Ticket prefix from the branch name (BRANCH_PATTERN). Else Conventional Commits:
  `type(scope): subject`, imperative, ≤72 chars; body says why when it is not obvious.
- No attribution trailers. Write it to `$(sdw-workdir)/commit-msg.txt`.

## 6. Commit
```bash
git commit -F "$(sdw-workdir)/commit-msg.txt" && git log --oneline -1 && git status --short
```
Never `--no-verify`; never `--amend` a pushed commit without a yes; a failing repo hook is a red gate.
Then update plan.md `## Progress` when plan.md exists: a Done line with the slice and sha7, Now and
Next rewritten, a Decision line (what — why) for each choice made since the last one. Keep it ≤12
lines: fold the oldest Done lines into one `- Done earlier: <slices>` and drop superseded Decisions.
Report sha, files (+/−), gates, scans, what is left for the user. Next: `/sdw:ship`.
