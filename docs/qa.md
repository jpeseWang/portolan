# QA — an independent tester inside the workflow

A tester who did not write the code checks the change against what was **asked** (the raw
ticket as well as the planned acceptance criteria), runs it against a server proven to serve
this branch, and signs off only against explicit exit criteria, with evidence on disk.

## Independence, enforced by hooks

- `/sdw:qa` runs the `sdw:qa` agent in the foreground (a background subagent's permission
  prompts are auto-denied).
- **Design phase** (`.qa-phase` = `design`): inputs are `ticket.md`, the ACs and out-of-scope
  list in `plan.md`, design refs, `run.md` and `qa-env.md`, plus the spec only when run.md lists it
  under `## qa` as `- spec: <path>` (onboard fills it). guard-read and guard-bash allow reads under
  `.sdw/`, the plugin and those spec paths only, so `git diff/log/show/blame` and app source are
  blocked. Writing `cases.md` flips the phase to `execute`.
- **Execute phase**: routes and markup may be read only to find URLs and selectors.
- `sdw:qa` and `sdw:reviewer` can write only under `.sdw/work/`; no `sed -i`, no snapshot
  updates (`-u`, `--update-snapshots`), no git writes, and they cannot change `.qa-phase`.
- A gap between `ticket.md` and the planned ACs is itself a finding.

## Lanes and caps

`/sdw:plan` runs QA design for STANDARD, RISKY and BUG; type `/sdw:qa design` only as the first step
of a new worktree session. Caps per lane (cases, P2, charters) and the techniques are in
[techniques.md](../plugin/skills/qa/techniques.md); TRIVIAL gets `/sdw:qa quick` when visible.

## Where cases come from

Each case names its technique and its **source**: ticket, AC-n, spec §, design node, a named
standard (e.g. WCAG 1.4.3), or "consistent with <sibling route>". A value observed in the app
is never an expected value; unspecified behaviour goes to one "Questions for PO" list.

- Boundaries and partitions for numbers, lengths, dates and counts, plus a short injection set.
- Decision tables for interacting conditions; state transitions for anything with a status
  (invalid transition, double submit, refresh mid-flow, back button).
- Authz: STANDARD checks anonymous → 401 and wrong role → 403. RISKY adds the other user's or
  tenant's id, own object, over-posting (`role`, `ownerId`, `tenantId`), and method/path swaps,
  which needs two users per role. Cookie-auth mutations get a CSRF row.
- Error paths forced with `sdw-ui-shot --route '<glob>=<status>|offline|empty|delay:MS'` (any
  3-digit status; `empty` is 200 with `[]`); UI states
  (loading, empty, error, long text, least-privileged role, 375 px, keyboard only).
- Stack-triggered rows only when the diff shows them: uploads, background jobs, websockets,
  feature flags, new `NEXT_PUBLIC_*`/`VITE_*` values in the built bundle.
- Error guessing: time zones and DST, locale formatting, concurrent edits, stale cache after a
  mutation, pagination edges, duplicate names.
- Charters: "Explore <area> with <heuristic> to discover <risk>", each with a session sheet.

## Results, bugs and the verdict

`cases.md` columns are exactly `| ID | Source | Technique | Pri | Preconditions & data | Steps |
Expected (with source) | Layer | Automate | Test name | Result | Evidence | Run |`. Bugs follow
[bug-template.md](../plugin/skills/qa/bug-template.md); QA never files tickets
(`/sdw:create-ticket bug BUG-nn` converts one when you ask). `sdw-evidence qa-verdict` computes
the verdict from the files by [exit-criteria.md](../plugin/skills/qa/exit-criteria.md), never from
what anyone wrote.

## Login, users and test data

`run.md` names two users per role and a login recipe (form selectors, an API endpoint with a
cookie or a token, a caller-asserted header, or `oauth-manual`); a multi-app project uses `## login: <app>` and `sdw-login <role> --app <app>`,
and a relative login URL is completed from that app's port. Passwords live in Keychain, service
`sdw:<PROJ_SLUG>:<role>`, account = the user name:
`security add-generic-password -U -s 'sdw:<slug>:<role>' -a '<user>' -w` (it prompts for the
value). `sdw-login <role>` writes Playwright storage state and a cookie jar, or
`.sdw/auth/<role>.header` for token and header recipes, to `.sdw/auth/` without printing anything.
OAuth-only apps: `sdw-ui-shot --save-auth <role> --headed` once. Test data is named
`Probe <unix-ts>` and listed per environment; with `QA_WRITE_ENV=shared-ask` QA asks before
creating anything, and nothing is ever deleted.

## Tools and fallbacks

Browser order, axe sources, `SDW_OFFLINE`/`SDW_CACHE_DIR` and `--api-fuzz` are in
[tools.md](../plugin/skills/qa/tools.md). No browser → UI cases BLOCKED, API cases still run; a
missing axe shows as NOT RUN, not as clean.

**Playwright Test Agents** (`npx playwright init-agents --loop=claude`) need Playwright ≥ 1.56
and the client's yes: they write `.claude/agents` and overwrite `.mcp.json`. A healer diff that
changes an assertion, a locator target or adds a skip is a review finding.

## Later

Mutation testing (StrykerJS needs client devDependencies; Stryker.NET is a global tool, so ask
and list what it installs), pairwise selection (hand-pick an all-pairs set), property tests and
Lighthouse budgets are not part of QA yet.
