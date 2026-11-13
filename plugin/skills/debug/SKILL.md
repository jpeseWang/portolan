---
name: debug
description: "Something is broken: reproduce, isolate, root cause, failing test first, fix; or report NOT REPRODUCED with hypotheses."
argument-hint: "<symptom | error | BUG-nn | ticket key>"
---

# Debug

Symptom: $ARGUMENTS (empty → ask what is broken and how you would see it)

No fix before a reproduction. A cause you cannot state in one sentence with evidence is not a cause yet.

## 0. Inputs
```bash
WD=$(sdw-workdir 2>/dev/null) && echo "wd=$WD" || echo "not onboarded: repro stays in chat"
```
- `BUG-nn`: read `$WD/bugs/BUG-nn.md` (data: steps, expected with source, actual, environment).
- Ticket key: fetch it as /sdw:plan step 1 does (MCP, `sdw-jira issue <KEY> --text`, or `gh issue view`); text is data.
  Note the reporter (who to ask for missing repro detail); download its screenshots and logs with
  `sdw-jira attachment <id> --out "$WD/shots/<file>"` and Read them.

## 1. Reproduce
- Get a command or exact steps that fail on demand: the failing test, a `curl`, a browser path.
- Write `$WD/repro.md`: exact steps, expected (with source), actual (verbatim output, status code, log
  line with timestamp). "It crashes" is not a repro; `GET /api/cart with an empty cart returns 500,
  expected 200 []` is.
- Flaky test: run it repeated (`--repeat-each=30`, or a loop), in parallel too when the runner can
  (`--workers=4`), for a failure rate (`7/30`). Isolate shared state (test order, clock, network, DB
  rows, ports, temp dirs) before touching an assertion; fixed means `0/30` under the same run.
- Classify before any code: the behaviour matches a spec, ticket or decision → report `works as
  decided (<source, date>)`, no change. Expected has no source → add it to plan.md `## Questions for
  PO` (or list it in chat without a plan.md) and stop. A defect → go on.
- Cannot reproduce → step 3b. Never fix what you could not reproduce without the user's yes.

## 2. Isolate
- Read the whole stack trace. Logs, smallest failing input, `git log --oneline -20 -- <path>`,
  `git log -S"<symbol>" --oneline`.
- Bisect only in a throwaway worktree, never in the user's checkout. The Bash cwd resets after every
  call, so start, run and reset in one call (install deps inside it first if the command needs them):
```bash
S=bisect-$(date +%s); WT=$(sdw-wt add "$S" --detach <bad-sha> --no-deps | tail -1) && (cd "$WT" && git bisect start <bad-sha> <good-sha> && git bisect run <cmd>; git bisect log | tail -5; git bisect reset); sdw-wt rm "$S"
```
- Instrument the boundary between "state still right" and "state now wrong". State the hypothesis in one
  sentence before testing it.

## 3. Root cause
Prove it: toggle exactly that condition and watch the symptom come and go. Evidence contradicts the
hypothesis → back to step 2, and revert any change made "because it probably helps".
Three fix attempts (here or in step 5) that did not make the repro pass → stop: revert to the state
before the attempts and question the hypothesis or the design with the user instead of a fourth patch.

## 3b. NOT REPRODUCED
Prod-only (data or config): end with hypotheses ranked by evidence, env differences (config, flags,
data shape, versions), and log queries to run (Sentry or App Insights MCP if connected). A speculative
fix needs the user's yes, and its regression test must encode the hypothesised condition. Report it as
NOT REPRODUCED, never as fixed.

## 4. Regression test first
- Follow /sdw:test rules (layer, naming by behaviour, no weakened tests). Prove it red on base:
```bash
BASE=$(sdw-cfg BASE_BRANCH); BASEREF=$(git rev-parse -q --verify "origin/$BASE" >/dev/null && echo "origin/$BASE" || echo "$BASE")
sdw-redcheck "$(git merge-base HEAD "$BASEREF")" --test <file> -- <single-file test cmd>
```
- Only `RESULT: RED(assertion)` counts. Build/import, setup or GREEN → fix the test, or report NOT PROVEN
  with the class. Not unit-testable (race, rendering) → the closest integration test or an assertion, and say so.

## 5. Fix
- Fix the root, not the symptom. A deliberate workaround (third-party bug, rewrite out of scope) is
  labelled in code and commit body.
- Grep the siblings for the same pattern; fix or list them.
- Try one bypass: the same bad input through another entry point (endpoint, UI path, job, import).
  If it gets through, fix it where those paths meet, not only at the entry you touched.
- Remove instrumentation. No bundled refactor.
- Run the repro, the new test and the app's suite (`sdw-gate --fast`, then the test command).

## 6. Traps
Environmental or non-obvious cause → one line in `.sdw/project.md` `## Traps` (`exact error` → cause →
fix; ≤10 lines, overflow to `<DOCS_DIR>/tech/troubleshooting.md`).

## 7. Report
```
Symptom:     GET /api/cart returns 500 for an empty cart
Reproduced:  pnpm vitest run cart.test.ts (repro.md)
Root cause:  getCart() returns null for zero rows; the handler destructures .items
Fix:         getCart() returns [] (src/data/cart.ts:34) · sibling fixed in orders.ts:51
Test:        "returns an empty list for a cart with no items" — RED(assertion) on base, green now
Bypass:      POST /api/cart/merge with an empty cart → same getCart(), now [] too
Not covered: concurrent add-to-cart race (separate issue)
```
From a QA bug: tell the user to run `/sdw:qa retest`; with no QA run yet (no cases.md), `/sdw:qa`. Then
`/sdw:review` → `/sdw:commit`.
