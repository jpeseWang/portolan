# e2e templates

Copy into the web app only when it has no end-to-end setup, and only after a yes (it adds a dependency).

| File | Goes to | Purpose |
|---|---|---|
| `playwright.config.ts` | `<app>/playwright.config.ts` | Runs against `BASE_URL` or starts the app; one sign-in per role |
| `auth.setup.ts` | `<app>/e2e/auth.setup.ts` | Saves sessions to `e2e/.auth/` (ignored by the sdw exclude block; add it to the app's .gitignore too) |
| `fixtures.ts` | `<app>/e2e/fixtures.ts` | Auto fixture: fails on pageerror, unexpected console.error, unexpected 5xx |
| `a11y.ts` | `<app>/e2e/a11y.ts` | axe WCAG 2.x A/AA check, new violations only; needs `@axe-core/playwright` |
| `test-data.ts` | `<app>/e2e/test-data.ts` | `probeName()`: findable names for anything a test creates |
| `smoke.spec.ts` | `<app>/e2e/smoke.spec.ts` | Flows that must never break: loads clean, create → list, error state |
| `visual.spec.ts` | `<app>/e2e/visual.spec.ts` | Screenshot baselines, made in the CI container, approved by a human |

Then `npm i -D @playwright/test && npx playwright install chromium`.

Rules for every spec:
- Locators by role, label or test id; never CSS chains or text that changes with copy.
- Web-first assertions (`await expect(locator).toBeVisible()`); no `waitForTimeout`.
- Every promise awaited (enable `@typescript-eslint/no-floating-promises` for `e2e/`).
- Test names describe behaviour, never internal case or bug ids.
- New specs pass `--repeat-each=3` before they count; a flake is fixed, not retried away.
- Baseline screenshots are updated only in CI's container and approved in the PR.
