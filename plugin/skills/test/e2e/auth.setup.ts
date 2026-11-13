// Signs in once per role and saves the session for every other test. Credentials come from
// the environment — never commit them. e2e/.auth/ must be gitignored.
import { expect, test as setup } from '@playwright/test'

const ROLES = [
  { file: 'e2e/.auth/user.json', email: process.env.E2E_USER_EMAIL, password: process.env.E2E_USER_PASSWORD },
]

for (const role of ROLES) {
  setup(`sign in → ${role.file}`, async ({ page }) => {
    if (!role.email || !role.password) throw new Error(`set credentials for ${role.file}`)
    await page.goto('/login')
    await page.getByLabel(/email/i).fill(role.email)
    await page.getByLabel(/password/i).fill(role.password)
    await page.getByRole('button', { name: /sign in|log in/i }).click()
    await expect(page).not.toHaveURL(/login/)
    await page.context().storageState({ path: role.file })
  })
}
