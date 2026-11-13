# Exit criteria (computed by `sdw-evidence qa-verdict`; nobody asserts the verdict)

Run id = the first 7 characters of the first `tree` in qa-report.md's stamp line.
A case counts as PASS only with Evidence filled and Run equal to the run id; otherwise NOT RUN.
A case whose Source, Steps or Expected differs from `.cases.design.md` (the snapshot taken when
design ended) counts as NOT RUN.

READY when all hold:
- cases.md has a Run column and a design snapshot exists;
- every P1 case PASS;
- every AC-n of plan.md has a PASS case naming it in Source;
- every plan.md Surfaces endpoint has a PASS **authz** case whose Steps name its method and path
  (`{id}` or `:id` matches any segment; a path with no method, `-X` or `-d` is a GET), and an
  **idor** case when the path takes an id;
- no bug S1/S2 with `Status: open`, `fixed` (not yet verified by a retest), or `wontfix` without
  a `Decided-by:` line, or with any other status. `Status: pre-existing` is listed apart and does
  not block only when Regression vs base starts `no` and names an existing `shots/base-*` file,
  and Source names no AC; otherwise it counts as open;
- no new console error, pageerror or 5xx: present in an unmocked `shots/*.json` capture and
  absent from `shots/base-*.json` of the same route (no base capture → all are new);
- qa-report.md has `## NOT RUN`, `## Test data created` and `## Questions for PO` (`none`
  allowed), and no question marked `blocks: yes` naming an AC;
- RISKY: at least one charter sheet (`### C1 …` under `## Charters` in cases.md), and
  `## Coverage gaps` is `none` (a reason may follow: `none — <why>`).

READY WITH KNOWN ISSUES: all of the above except P2 cases not PASS (FAIL, BLOCKED, NOT RUN or
carried, each listed), open S3/S4 bugs, or STANDARD/BUG coverage gaps (listed).

NOT READY: anything else. A BLOCKED P1 case is NOT READY, never PASS: name what unblocks it.

Test-side evidence (red on base, stability, suite vs baseline) is not part of this verdict;
/sdw:ship checks it.
