// Import { test, expect } from here instead of @playwright/test: every test then fails on an
// uncaught page error, an unexpected console.error or an unexpected 5xx response.
import { test as base, expect } from '@playwright/test'

// Known noise for every test, matched against the message or URL. Each entry needs a reason.
const ALLOWED: RegExp[] = []

type Health = { healthAllow: RegExp[]; pageHealth: void }

export const test = base.extend<Health>({
  // A test that provokes errors on purpose: test.use({ healthAllow: [/\/api\/items/] })
  healthAllow: [[], { option: true }],
  pageHealth: [
    async ({ page, healthAllow }, use) => {
      const allowed = (text: string) => [...ALLOWED, ...healthAllow].some((re) => re.test(text))
      const problems: string[] = []
      page.on('pageerror', (err) => {
        if (!allowed(err.message)) problems.push(`pageerror: ${err.message}`)
      })
      page.on('console', (msg) => {
        if (msg.type() === 'error' && !allowed(msg.text())) problems.push(`console.error: ${msg.text()}`)
      })
      page.on('response', (res) => {
        if (res.status() >= 500 && !allowed(res.url())) problems.push(`${res.status()} ${res.request().method()} ${res.url()}`)
      })
      await use()
      expect(problems, 'page health').toEqual([])
    },
    { auto: true },
  ],
})

export { expect }
