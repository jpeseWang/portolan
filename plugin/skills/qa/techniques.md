# Case derivation

Each technique has a trigger, read from plan.md `## Surfaces` (endpoints, UI routes, entities
with a status, roles, new strings, dates) and the ACs; use it only when the trigger is present.
Every row records the technique that produced it, by the name in bold below.

## Caps by lane

| Lane | Cases | Priority | Charters |
|---|---|---|---|
| STANDARD, BUG | ≤12 | P1 only (P2 with `--p2`) | 1, about 10 tool calls |
| RISKY | ≤30 | P1 and P2 | 2, about 20 tool calls each |

P1: covers an AC, an **authz** or **idor** row, a **contract** row, a triggered **dates** or
**i18n** row, or a primary user flow. P2: everything else. Every AC has at least one case;
every Surfaces endpoint its authz row (Steps name the path). Over the cap → drop P2 first, then
merge cases, never drop an AC.

## Techniques

**partition** (equivalence partitions and boundaries). Trigger: numeric, length, date or count
input. Rows: min-1, min, max, max+1, empty, whitespace only, unicode/emoji/RTL, very long text,
one injection set (`<script>alert(1)</script>`, `' OR 1=1--`, `{{7*7}}`, `../`).

**decision** (decision table). Trigger: an AC with two or more interacting conditions. One row per
meaningful combination; collapse rows whose outcome cannot differ.

**state** (state transition). Trigger: an entity with a status. Every valid transition, one
invalid transition per state, refresh mid-flow, back button after submit. Every status value has
a screen or label and a way out (no dead-end state).

**idempotency**. Trigger: a UI action that POSTs, PUTs, PATCHes or DELETEs. Double-click → one
request and one record (count via the API); the button is disabled while pending; retry after
a forced 500 → still one record.

**authz**. Trigger: every Surfaces endpoint (server actions and route handlers count).
- All lanes: anonymous → 401; wrong role → 403.
- RISKY adds: own object 2xx, over-posting (`role`, `ownerId`, `tenantId` ignored or rejected),
  method/path swap (BFLA). Cookie auth and a state-changing endpoint: one CSRF row (cross-site
  form post rejected). Tenant id in a query or header ignored; signed URL expires, one object only.
- RISKY, list and search endpoints (leak scan): note the ids and emails `<r>-2` or another tenant
  owns in a file, save each list response as `<r>` to `shots/`, then
  `grep -c -F -f <file> shots/<list>*.json`: any hit is an S1 bug. No second user → BLOCKED.

**idor**. Trigger: any Surfaces endpoint or route that takes an object id, every lane. Sign in
as `<r>-2`, request `<r>`'s object: not 2xx and no field of it (OWASP ASVS V4.2.1; the exact
code per spec, else a PO question). No second user → BLOCKED `QA readiness: no second <r> user`.

**contract**. Trigger: every Surfaces endpoint. One api row: the spec section's status codes,
top-level keys and types, and the error body (e.g. RFC 7807 keys), checked with
`curl … | jq 'keys'` against the spec's list. An endpoint with no spec section is a finding and
a PO question. One ui row: the client reads the field names the spec defines (network JSON).

**dates**. Trigger: a date or time shown, entered, filtered or stored. Browser TZ ≠ server TZ
(`sdw-ui-shot --timezone Asia/Ho_Chi_Minh` against a UTC server), a 23:30 local day-boundary
row, and one DST-date row (e.g. America/New_York on the change date).

**i18n**. Trigger: a new user-facing string. The key exists in every locale file (`jq` on
each), and no raw key or fallback language shows with each locale active (`--locale`).

**errors** (error paths). Trigger: the UI calls an API. 400/401/403/404/409/422/500, timeout,
offline. On load: `sdw-ui-shot --route '<glob>=<status>|offline|delay:5000'`. On submit:
`--route '<glob>=422:@shots/mock-422.json' --fill '<sel>=<v>' --click '<submit>'` with a
spec-shaped body, or playwright-cli. Neither available → BLOCKED `no interactive mock`, never
PASS from a load-time capture. Expected: an error the user can act on, a way out, loading that
always clears.

**states** (UI states). Trigger: a Surfaces UI route. Loading, empty (`--route
'<glob>=200:@shots/empty.json'` shaped like the real response; `empty` only for a bare array),
error, long text, missing optional fields, least-privileged role, 375px viewport, keyboard only
with visible focus and no trap. One `--vitals` load capture per route: `cls` over 0.1 is a
finding. A dark-scheme capture (`--color-scheme dark`) when the app ships a dark theme. A picker,
select or autocomplete case uses unmocked data and needs a real choice that is not disabled.

**a11y**. Trigger: a Surfaces UI route with a form or dialog. Every control has an accessible
name (WCAG 4.1.2); a validation error is programmatically associated, `aria-describedby` or
`role=alert` (3.3.1); focus moves into a dialog and returns on close (2.4.3). axe serious and
critical violations not in the base capture are findings; a route missing on base has no
baseline, so all of them are.

**impact**. Trigger: a Surfaces endpoint or shared component (execute phase). `grep -rl` its
consumers in the checkout; smoke each sibling route with the default checks on the change and
compare with its base capture. Source `base behaviour (shots/base-*.json)`.

**stack** (only when the stack or ticket shows them): file upload size and type; background
jobs, emails and eventual consistency (poll with a timeout); websocket or SignalR reconnect
after a server restart or going offline; feature flag on and off; a new
`NEXT_PUBLIC_*`/`VITE_*` variable checked in the built bundle for secrets.

**guess** (error guessing, fixed list, P2): decimal and locale formatting, concurrent edit,
stale cache after a mutation, pagination edges, duplicate names.

## Writing rows

- Steps and Expected are numbered, imperative, and runnable by someone else:
  `1. Sign in as viewer 2. Open /reports 3. Click "Export"` → `1. 403 page with a link home
  (AC-3)`.
- Preconditions & data name the role, the seed and any `Probe <unix-ts>` data to create.
- Layer: the cheapest layer that observes the behaviour (api before ui).
- Automate `yes` when the case guards a regression an automated test can hold.
- Test name stays empty; `/sdw:test from-qa` fills it with a behaviour name, never `TC-nn`.
- Run stays empty in design; execute writes the run id.

## Charters

Form: `Explore <area> with <heuristic> to discover <risk>`. Heuristics: CRUD each field,
interrupt (refresh, back, second tab), starve (empty, offline, slow), flood (long, many,
fast), wrong user. Pick the area the cases cover least. Session sheet under `## Charters`:

```
### C1 Explore <area> with <heuristic> to discover <risk>
Covered: … · Sources: … · Bugs: BUG-nn … · Questions: Qn …
```
