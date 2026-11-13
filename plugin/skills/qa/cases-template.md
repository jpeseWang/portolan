# Cases: <KEY or slug>
Lane: <LANE> · Sources read: ticket.md, plan.md, <spec §…>, <design node …>, run.md

| ID | Source | Technique | Pri | Preconditions & data | Steps | Expected (with source) | Layer | Automate | Test name | Result | Evidence | Run |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| TC-01 | AC-1 | state | P1 | role editor; one draft order `Probe <unix-ts>` | 1. Open /orders/<id> 2. Click "Submit" | 1. Status shows "Submitted" (AC-1) 2. GET /api/orders/<id> → 200, `status: submitted` (spec §4.2) | ui | yes | | | | |
| TC-02 | AC-1 | authz | P1 | anonymous | 1. POST /api/orders/{id}/submit without a session | 1. 401, RFC 7807 body (spec §2.3) | api | yes | | | | |
| TC-03 | AC-1 | idor | P1 | role editor-2; editor's order | 1. As editor-2, POST /api/orders/{id}/submit with editor's id | 1. not 2xx, no field of the order (OWASP ASVS V4.2.1; code is Q1) | api | yes | | | | |

Rules: ID `TC-nn` · Pri `P1|P2` · Layer `ui|api|unit|integration|e2e` · Automate `yes|no` ·
Result `PASS|FAIL|BLOCKED|NOT RUN`, empty until executed · Evidence: observed line or
`shots/<file>` · Run: run id of the execution (empty in design) · a `|` inside a cell is `\|`.

## Questions for PO
- Q1 <what is unspecified> — affects <AC-n or area> — blocks: <yes if the AC cannot be judged without it | no> — ask: <owner from .sdw/people.md, else PO>

## Charters
