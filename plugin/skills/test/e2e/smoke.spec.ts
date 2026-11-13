// The few flows that must never break. Keep this file short; everything else belongs to
// unit and integration tests. fixtures.ts fails any test on page errors, console errors and 5xx.
import { expect, test } from './fixtures'
import { probeName } from './test-data'

test('home loads for a signed-in user', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('main')).toBeVisible()
})

test('create → see it in the list', async ({ page }) => {
  const name = probeName('item')
  await page.goto('/items/new') // your main create flow
  await page.getByLabel(/name/i).fill(name)
  await page.getByRole('button', { name: /save|create/i }).click()
  await expect(page.getByText(name)).toBeVisible()
})

test.describe('when the API fails', () => {
  test.use({ healthAllow: [/\/api\/items/, /500/] })

  test('the list shows an error state, not a blank page', async ({ page }) => {
    await page.route('**/api/items**', (route) => route.fulfill({ status: 500, body: '{}' }))
    await page.goto('/items')
    await expect(page.getByRole('alert').or(page.getByText(/something went wrong|try again/i))).toBeVisible()
  })
})
