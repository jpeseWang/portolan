// Needs @axe-core/playwright in the app's devDependencies; add it only with the team's yes.
import AxeBuilder from '@axe-core/playwright'
import type { Page } from '@playwright/test'
import { expect } from './fixtures'

export const WCAG_TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa']

// Pre-existing violations go in `known` (rule ids) so only new ones fail.
export async function expectNoNewA11yViolations(page: Page, known: string[] = []) {
  const { violations } = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze()
  const fresh = violations.filter((v) => !known.includes(v.id))
  expect(fresh.map((v) => `${v.id} (${v.impact}): ${v.nodes.length} nodes`)).toEqual([])
}
