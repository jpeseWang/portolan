---
name: test
description: "Write tests at the right layer, prove them red on base, check stability, run the suite against the baseline."
argument-hint: "[path | behaviour | from-qa | migration | characterize <path>]"
---

# Test

Target: $ARGUMENTS (empty → the current diff and the ACs in plan.md)

## 0. Preflight
```bash
WD=$(sdw-workdir) || echo "rc=$?"; echo "wd=$WD"; ls "$WD" 2>/dev/null
```
rc 3 (no sdw project) → steps 1–4 and run the new tests with the repo's runner; skip red-on-base,
evidence and baseline, and say so. rc 4 → ask the user to cd into the repo or worktree.

## 1. Runner (the app's own; a new framework needs a yes)
| Stack | Look for | One file |
|---|---|---|
| JS/TS | vitest/jest/mocha in package.json | `npx vitest run <f>` · `npx jest <f>` |
| Browser e2e | `playwright.config.*`, `cypress.config.*` | `npx playwright test <f>` |
| .NET | `*.Tests.csproj` (xUnit/NUnit/MSTest) | `dotnet test --filter "FullyQualifiedName~<Class>"` |
| Python | pytest | `pytest <f> -q` |
| Go / JVM | `*_test.go` / `src/test/` | `go test ./<pkg> -run <N>` · `./gradlew test --tests <C>` |
Copy the nearest sibling test: file name, folder, fixtures, builders, assertion style. Reuse the
existing integration setup (WebApplicationFactory, supertest, TestClient, testcontainers, SQLite).

## 2. Layer
- Pure logic (mapping, validation, calculation, reducers) → unit.
- Endpoint, authz, persistence, query, migration → integration through the real pipeline and a same-dialect
  DB. Mocking the DB or auth tests the mock. Name a dialect gap (SQLite vs SQL Server/Postgres) when it matters.
- A flow across pages that must never break → e2e: few, stable, against the running stack.

## 3. Sources
- One test per AC-n in `$WD/plan.md` where the layer allows.
- `from-qa`: every `Automate=yes` row in `$WD/cases.md` becomes a test whose assertions copy the row's
  Expected verbatim. Fill that row's `Test name` column.
- Bug fix: the regression test from the repro. Then edges (empty, zero, boundary, duplicate, missing
  optional), failure paths (dependency throws, validation, 404), authz (allowed role, denied 403, other
  tenant/owner cannot see it).
- Test names describe behaviour, never `TC-nn`, lanes or bug ids.

## 4. Writing rules
- One behaviour per test; arrange/act/assert; mock only true external boundaries (third-party HTTP,
  clock, email).
- Expected values are written by hand from their source (AC, case row, spec; in `characterize`,
  the unchanged code's observed output), never copied from what the changed code returns.
- Test data is named `Probe <unix-ts>`. A test cleans up only what it created in a local or test DB
  (`DB_LOCAL=1` or run.md `test-db`); on a shared DB it is reported, never deleted.
- e2e: role/test-id locators, web-first assertions, no `waitForTimeout`, no floating promises.
  No Playwright setup yet: offer `${CLAUDE_SKILL_DIR}/e2e/` (see its README.md) and copy only after a yes.
- New e2e specs: `--repeat-each=3` (RISKY: 5); any flake is fixed, never retried away.
- Never weaken a test, assertion, snapshot or threshold to get green (the tamper scan flags it).

## 5. Red on base
```bash
BASE=$(sdw-cfg BASE_BRANCH); BASEREF=$(git rev-parse -q --verify "origin/$BASE" >/dev/null && echo "origin/$BASE" || echo "$BASE")
sdw-redcheck "$(git merge-base HEAD "$BASEREF")" --test <file> [--test <file>] [--app <dir>] -- <one-file cmd>
```
- `RESULT: RED(assertion)` proves the test. `RED(setup)`, `GREEN` → fix the test or report NOT PROVEN
  with the class. `RED(build/import)` → try the mutation check below, else report NOT PROVEN.
  sdw-redcheck writes its own evidence.
- .NET: a test that references types the change adds cannot compile on base. Assert through existing
  APIs where possible; otherwise try the mutation check, else report NOT PROVEN (build) and say why.
- Mutation check, when red on base cannot apply (the test needs code the change adds): write a minimal
  patch that breaks the new code (no test path) to `$(sdw-workdir)/mutation.patch`, run
  `sdw-redcheck --mutate "$(sdw-workdir)/mutation.patch" --test <file> -- <one-file cmd>`; `RED(mutation)` proves it.
- DB-touching tests need run.md `test-db` (testcontainers, in-memory, sqlite, database-url); `none` →
  exit 5, report NOT PROVEN (no test DB).

## 6. Migration mode (`migration`, RISKY lane, `sdw-cfg DB_LOCAL` = 1 only)
- Scratch DB only. DB_LOCAL=1 is not enough when the DB is the one the app or another worktree uses,
  or holds production data (run.md `QA_WRITE_ENV: shared-ask`, project.md Migrations): run the cycle
  on a fresh DB or container (new DB name, migrated from empty), or report NOT RUN with the reason.
  Never down-migrate a shared or production-copy DB.
- apply → revert → apply: EF `dotnet ef database update <previous>` then latest; TypeORM
  `migration:revert` then `migration:run`; Prisma has no down migration, so say so.
- Then the base code's smoke against the new schema: `sdw-wt add base-$(date +%s) --detach <BASEREF>`
  (last line WT, BASEREF as in step 5), run its smoke on a spare port as `(cd "<WT>" && …)` (the Bash cwd resets after every
  call), `sdw-wt rm` it.
- DB_LOCAL≠1 → refuse and say why.

## 6b. Characterize mode (`characterize <path>`)
When a refactor or speed-up touches code no test covers, first pin its current behaviour:
- Run the current code on literal inputs: one per branch, plus empty, zero and max. Write each
  expected value by hand from what it returned; a result that contradicts a spec is reported, not
  fixed here.
- These pass on base by design, so step 5's red on base does not apply: prove each with a mutation
  patch that breaks the code under test and `sdw-redcheck --mutate` → `RED(mutation)`.
- Performance rewrite: add an old-vs-new equivalence test over the same inputs while both exist.
- Then refactor; the characterization tests stay green, unchanged.

## 7. Full suite
```bash
sdw-gate --full
```
It writes the evidence. Compare counts with `.sdw/state/baseline.md`; name pre-existing failures,
never claim them, never hide new ones.

## 8. Report
```
TESTS — <target>
Layer:        integration (WebApplicationFactory + SQLite)
Added:        4 in Orders/OrderAccessTests.cs (AC-1, AC-2, AC-3, authz)
Red-on-base:  3 RED(assertion) · 1 NOT PROVEN (build: new type OrderExport)
Stable:       e2e export.spec.ts 3/3
Suite:        api 416/416 (baseline 412 + 4) · web 230/230
NOT PROVEN:   OrderExportTests — references a type added by this change
```
Paste failures verbatim. A test that fails because the code is wrong is a finding; report it.
