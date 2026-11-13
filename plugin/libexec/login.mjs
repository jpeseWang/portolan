// Called only by bin/sdw-login; the password arrives on stdin, never on argv.
// Exit: 0 logged in, 1 success marker not seen, 2 usage, 4 no Playwright/browser.

import { chmodSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'
import { ExitError, launchBrowser, loadPlaywright } from './ui-shot.mjs'

function parseArgs(argv) {
  const o = {}
  const keys = { '--url': 'url', '--user-field': 'userField', '--pass-field': 'passField', '--submit': 'submit',
    '--success': 'success', '--user': 'user', '--out': 'out' }
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--headed') { o.headed = true; continue }
    const k = keys[argv[i]]
    if (!k || i + 1 >= argv.length) throw new ExitError(2, `bad argument ${argv[i]}`)
    o[k] = argv[++i]
  }
  for (const k of ['url', 'userField', 'passField', 'submit', 'success', 'user', 'out']) {
    if (!o[k]) throw new ExitError(2, `missing ${k}`)
  }
  return o
}

async function main() {
  const o = parseArgs(process.argv.slice(2))
  const secret = readFileSync(0, 'utf8').replace(/\r?\n$/, '')
  if (!secret) throw new ExitError(4, 'empty credential on stdin')
  const { mod } = loadPlaywright()
  const browser = await launchBrowser(mod.chromium, { headed: o.headed })
  try {
    const context = await browser.newContext()
    const page = await context.newPage()
    await page.goto(o.url, { waitUntil: 'load', timeout: 30000 })
    await page.fill(o.userField, o.user, { timeout: 15000 })
    await page.fill(o.passField, secret, { timeout: 15000 })
    await page.click(o.submit, { timeout: 15000 })
    try {
      if (o.success.startsWith('url:')) await page.waitForURL(o.success.slice(4), { timeout: 20000 })
      else await page.waitForSelector(o.success, { state: 'visible', timeout: 20000 })
    } catch {
      throw new ExitError(1, `success marker not seen: ${o.success}`)
    }
    const state = await context.storageState()
    mkdirSync(dirname(o.out), { recursive: true, mode: 0o700 })
    writeFileSync(o.out, JSON.stringify(state, null, 2), { mode: 0o600 })
    chmodSync(o.out, 0o600)
  } finally {
    await browser.close().catch(() => {})
  }
}

main().catch((err) => {
  console.error(`sdw-login: ${String(err.message).split('\n')[0]}`)
  process.exit(err instanceof ExitError ? err.code : 1)
})
