---
name: daily-report
description: Standup text for a working day from commits, PRs, tickets and QA outcomes, with hours labelled as estimates.
argument-hint: "[date]"
---

# Daily report

Read-only: standup text for the user to paste; posts nothing anywhere.

## 1. Guard and working day

```bash
sdw-cfg TEAM_SKILLS | tr ' ' '\n' | grep -qx daily-report && echo "TEAM daily-report"
python3 - "$ARGUMENTS" <<'PY'
import re, sys
from datetime import datetime, timedelta as t
a = re.search(r"\d{4}-\d{2}-\d{2}", sys.argv[1])
d = datetime.strptime(a.group(), "%Y-%m-%d").date() if a else (datetime.now() - t(hours=5)).date()
p = d - t(days={0: 3, 6: 2}.get(d.weekday(), 1))
print("DAY=%s PREV=%s NEXT=%s" % (d, p, d + t(days=1)))
PY
```
`TEAM` and no `--anyway` in `$ARGUMENTS` → say "this repo has /daily-report, use it" and stop.
Working days run 05:00–05:00 local; PREV skips weekends. Not onboarded: current repo only.

## 2. Gather (set DAY, PREV, NEXT from step 1)

```bash
DAY=…; PREV=…; NEXT=…; PD=$(sdw-workdir --projdir 2>/dev/null) || PD=""
{ { [ -n "$PD" ] && sdw-workdir --repos; } || git rev-parse --show-toplevel; } | while IFS= read -r r; do (
  cd "$r" || exit; ME=$(git config user.email); F='%h %ad %s%d'; D='format:%a %H:%M'
  echo "== ${r##*/} $PREV"; git log --all --author="$ME" --since="${PREV}T05:00" --until="${DAY}T05:00" --format="$F" --date="$D"
  echo "== ${r##*/} $DAY"; git log --all --author="$ME" --since="${DAY}T05:00" --until="${NEXT}T05:00" --format="$F" --date="$D"
  gh pr list --author @me --state all --search "updated:>=$PREV" --json number,title,state,headRefName,url ); done
```

- `$PD/.sdw/state/sync-$DAY.md` or `sync-$PREV.md` present → reuse its PR and ticket lines.
- `sdw-cfg TRACKER`: jira → `sdw-jira search 'assignee = currentUser() AND updated >= "<PREV>"' --brief`
  and `sdw-jira worklog mine <PREV>`; github → `gh issue list --assignee @me --state open`;
  none → `$PD/TASKS.md` if present.
- QA: each `$PD/.sdw/work/*/qa-report.md` and `work/_done/*/qa-report.md` changed since PREV →
  its `Verdict:` and `## Summary` counts.
- Anything not set up (no `gh`, not GitHub, no tracker): "skipped: <reason>" in your reply.

## 3. Group and estimate

- Group by ticket key from branch, commit and PR title (`ABC-123`, `#123`, branch `123-slug`);
  no key → a short plain label. Summarise outcomes ("CSV export merged"), not commit subjects.
- QA as plain words ("QA passed", "QA: ready, two known issues"). Never BUG ids, case ids,
  severities, lanes or file paths.
- Hours per task in Yesterday: Jira worklogs when present, marked `(logged)`; otherwise an
  estimate of human effort marked `(est.)`. The total stays ≤8h, and less when the evidence
  covers less. Commit timestamps are not time spent.

## 4. Output
```
Daily report — Fri 2026-10-16

Yesterday (Thu 2026-10-15)
- ABC-123 CSV export — endpoint and tests, PR #128 open, QA passed (~3h est.)
Total: ~3h (estimates)

Today
- ABC-123 address review on #128

Blockers
- Waiting on the API contract for ABC-130 (asked <who>, <when>)
```
Empty section → `- none`. English only. Only what the evidence shows; no filler tasks.
