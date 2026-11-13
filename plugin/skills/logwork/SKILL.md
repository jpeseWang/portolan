---
name: logwork
description: Log Jira worklogs from recorded start times and commits; preview each, post only on a yes.
argument-hint: "[date]"
disable-model-invocation: true
---

# Log work

A worklog states what the user did. Record real effort; never invent time to fill a day.
`$ARGUMENTS` may hold a date, a ticket key, a duration (`1h30m`, `45m`) and `--anyway`.
Details: `${CLAUDE_SKILL_DIR}/../../reference/tracker-jira.md`.

## 1. Gate

```bash
sdw-workdir --projdir >/dev/null; echo "projdir=$?"
echo "team=[$(sdw-cfg TEAM_SKILLS)] tracker=$(sdw-cfg TRACKER) worklog=$(sdw-cfg WORKLOG)"
```

Stop with the message when the first matching line applies:
- projdir=3 → "run /sdw:onboard first".
- team lists `logwork` and no `--anyway` → "this repo has /logwork, use it".
- tracker github → "N/A: GitHub Issues has no worklogs"; none → "N/A: no tracker configured".
- worklog not 1 → "Worklogs are off (WORKLOG=0 in .sdw/config.env)".

## 2. Day and candidates

DAY = the date in `$ARGUMENTS`, else today (before 05:00 local: yesterday). Candidates are the
key in `$ARGUMENTS`, else every task file plus branches with the user's commits that day:

```bash
DAY=…; PD=$(sdw-workdir --projdir)
NEXT=$(python3 -c 'import sys, datetime as d; print(d.date.fromisoformat(sys.argv[1]) + d.timedelta(1))' "$DAY")
find "$PD/.sdw/state" -name 'task-*' -type f | while IFS= read -r f; do printf '%s\t%s\t%s\n' "${f##*/task-}" "$(sed -n 1p "$f")" "$(sed -n 2p "$f")"; done
sdw-workdir --repos | while IFS= read -r r; do (cd "$r" && git log --all --author="$(git config user.email)" \
  --since="${DAY}T05:00" --until="${NEXT}T05:00" --format="${r##*/} %aI %h %s %d"); done
```

Task file columns: key, start time, branch. Map commits to keys by branch name and subject.

## 3. Duration, in order of trust

1. Stated in `$ARGUMENTS` → use it.
2. Computed: from = the later of the task start and the end of the user's last worklog on the
   key (`sdw-jira worklog list KEY --since <start date> --mine` → `id started seconds`);
   to = the last commit that day on the branch. Wall-clock is not effort: over 4h, across
   midnight, or commit gaps over 1h → show the evidence and ask for the real figure.
3. Neither → ask.

Round to the nearest 15 minutes, minimum 15m. Never round up to the hour. `started` = `from`,
or (last commit − duration) when the user stated only a duration; local offset, never hard-coded.

## 4. Duplicates and the day total

- `sdw-jira worklog list KEY --since DAY --mine`: an overlapping interval or the same duration
  that day → show it and ask whether this is a duplicate.
- `sdw-jira worklog mine DAY` → `TOTAL`. Total plus this entry over 8h → warn. The cap flags a
  likely mistake; it is not a target.

## 5. Preview one entry, post on a yes

The comment is one line from the branch's commits: what was done, not how long it took.
```bash
sdw-jira worklog add KEY --started '<YYYY-MM-DDTHH:MM>' --duration <1h30m> --comment '<one line>' --dry-run
```
```
ABC-123 · started Fri 2026-10-16 09:00 +0200 · 1h30m
Comment: CSV export endpoint and tests (3 commits)
Your day after this: 5h15m (warning above 8h)
Log it? (yes / edit / no)
```

Say the date out loud for a past day or a weekend. Anything but an explicit yes is a no.
On yes: the same command without `--dry-run`. Report the worklog `id` and the new day total
(`sdw-jira worklog mine DAY`). Exit 1 → show Jira's message, fix what it names, preview again;
never retry blind. The user may ask for the Jira MCP instead; same preview, same yes.

Never pad: no "fill to 8h", no spreading idle time over tickets; under-logging is the smaller
error. One worklog per yes. Only the user's own worklogs; never edit or delete anyone's.
