<line 1: the exact output of `sdw-evidence stamp`, nothing else>
Verdict: PENDING

## Summary
Cases: <n> · PASS <n> · FAIL <n> · BLOCKED <n> · NOT RUN <n> · Lane <LANE> · Tools: <from qa-env.md>
Server: <app> pid <pid>, cwd <path>, started <time> (fresh|stale)

## Bugs
| ID | Severity | Status | Title |
|---|---|---|---|

## Pre-existing
- BUG-nn <severity> — <title> — pre-existing, not in scope (`none` when empty)

## Default checks
Per touched route: console errors <n> (new <n>) · pageerror <n> · failed/4xx/5xx requests
<list> · axe <n violations, information | new vs base: ids> · evidence `shots/<file>.json`

## Charters
<C1 one line: area, heuristic, result, bugs>

## Coverage gaps
<written by the main session: touched endpoints or routes with no case; or `- none — <why>`>

## Carried from <old run id>
<retest only: TC-nn not re-run, with their old Result; omit otherwise>

## NOT RUN
- TC-nn / check — reason (never omitted; write `none` when empty)

## BLOCKED
- TC-nn — reason (missing app, browser, role, credential, approval)

## Test data created
- <environment>: `Probe <unix-ts>` <entity, id> (write `none` when empty)
- <environment>: setting <name> was <old value> (restored | NOT restored)

## Questions for PO
- Q1 … — affects AC-n — blocks: yes|no (copied from cases.md; `none` when empty)
