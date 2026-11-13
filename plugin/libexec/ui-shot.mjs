// Called only through bin/sdw-ui-shot and libexec/login.mjs. Exit codes: 0 captured,
// 1 navigation failed (JSON still printed), 2 usage, 3 not onboarded, 4 no Playwright/browser.

import { createRequire } from 'node:module'
import { execFileSync } from 'node:child_process'
import { chmodSync, existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { delimiter, dirname, join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

export const PW_PIN = '1.55.0'
const AXE_PIN = '4.10.3'
const AXE_TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa']
const STYLE_KEYS = [
  'fontFamily', 'fontSize', 'fontWeight', 'lineHeight', 'letterSpacing', 'color',
  'backgroundColor', 'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
  'gap', 'borderRadius', 'borderTopWidth', 'borderTopColor',
]
const MOTION_KEYS = [
  'transitionProperty', 'transitionDuration', 'transitionTimingFunction', 'transitionDelay',
  'animationName', 'animationDuration', 'animationTimingFunction', 'willChange',
]

export class ExitError extends Error {
  constructor(code, message) { super(message); this.code = code }
}

const cacheDir = (name) => join(process.env.SDW_CACHE_DIR || join(homedir(), '.cache', 'sdw'), name)

function tryRequire(base, names) {
  const req = createRequire(base)
  for (const name of names) {
    try { return { mod: req(name), req, name } } catch { /* next */ }
  }
  return null
}

function onPath(cmd) {
  for (const dir of (process.env.PATH || '').split(delimiter)) {
    const p = join(dir, cmd)
    if (dir && existsSync(p)) return realpathSync(p)
  }
  return null
}

// Order is the contract: the app's own Playwright, then playwright-cli's, then a pinned cache.
export function loadPlaywright() {
  const names = ['@playwright/test', 'playwright', 'playwright-core']
  const local = tryRequire(join(process.cwd(), 'noop.js'), names)
  if (local) return local
  const cli = onPath('playwright-cli')
  if (cli) {
    const viaCli = tryRequire(cli, ['playwright-core', 'playwright'])
    if (viaCli) return viaCli
  }
  const dir = cacheDir('pw')
  const cached = () => tryRequire(join(dir, 'noop.js'), ['playwright-core'])
  if (cached()) return cached()
  if (process.env.SDW_OFFLINE === '1') {
    throw new ExitError(4, 'Playwright not found from ' + process.cwd() + ' (SDW_OFFLINE=1, no cache)')
  }
  console.error(`sdw-ui-shot: installing playwright-core@${PW_PIN} into ${dir}`)
  try {
    mkdirSync(dir, { recursive: true })
    execFileSync('npm', ['install', '--prefix', dir, '--no-audit', '--no-fund', `playwright-core@${PW_PIN}`],
      { stdio: ['ignore', 2, 2] })
  } catch (err) {
    throw new ExitError(4, `Playwright not found and the pinned install failed: ${err.message}`)
  }
  const got = cached()
  if (!got) throw new ExitError(4, 'Playwright not found after install')
  return got
}

// A laptop whose e2e only runs in CI rarely has Playwright's own browsers; system Chrome works.
export async function launchBrowser(chromium, { channel, headed }) {
  const base = { headless: !headed }
  if (channel) {
    try { return await chromium.launch({ ...base, channel }) } catch (err) {
      throw new ExitError(4, `cannot launch channel ${channel}: ${firstLine(err)}`)
    }
  }
  try { return await chromium.launch(base) } catch (err) {
    console.error(`sdw-ui-shot: bundled browser unavailable (${firstLine(err)}), trying system Chrome`)
    try { return await chromium.launch({ ...base, channel: 'chrome' }) } catch (err2) {
      throw new ExitError(4, `no browser: ${firstLine(err2)}`)
    }
  }
}

const firstLine = (err) => String(err && err.message || err).split('\n')[0]

function parseArgs(argv) {
  const o = {
    viewport: '1440x900', dpr: 1, settle: 300, measure: [], motion: [], route: [], steps: [], fullPage: false,
    reducedMotion: 'reduce', vitals: false,
  }
  for (let i = 0; i < argv.length; i++) {
    const key = argv[i]
    const next = () => {
      if (i + 1 >= argv.length) throw new ExitError(2, `${key} needs a value`)
      return argv[++i]
    }
    switch (key) {
      case '--url': o.url = next(); break
      case '--out': o.out = next(); break
      case '--viewport': o.viewport = next(); break
      case '--dpr': o.dpr = Number(next()); break
      case '--wait': o.wait = next(); break
      case '--settle': o.settle = Number(next()); break
      case '--storage': o.storage = next(); break
      case '--role': o.role = next(); break
      case '--measure': o.measure.push(next()); break
      case '--motion': o.motion.push(next()); break
      case '--reduced-motion': o.reducedMotion = next(); break
      case '--vitals': o.vitals = true; break
      case '--color-scheme': o.colorScheme = next(); break
      case '--channel': o.channel = next(); break
      case '--route': o.route.push(parseRoute(next())); break
      case '--timezone': o.timezone = next(); break
      case '--locale': o.locale = next(); break
      case '--click': o.steps.push({ click: next() }); break
      case '--fill': {
        const v = next(); const eq = v.indexOf('=')
        if (eq <= 0) throw new ExitError(2, `--fill needs SEL=VALUE, got ${v}`)
        o.steps.push({ fill: v.slice(0, eq), value: v.slice(eq + 1) }); break
      }
      case '--save-auth': o.saveAuth = next(); break
      case '--full-page': o.fullPage = true; break
      case '--networkidle': o.networkidle = true; break
      case '--axe': o.axe = true; break
      case '--headed': o.headed = true; break
      default: throw new ExitError(2, `unknown argument ${key}`)
    }
  }
  if (!o.url) throw new ExitError(2, '--url is required')
  if (!o.saveAuth && !o.out) throw new ExitError(2, '--out is required')
  const m = /^(\d+)x(\d+)$/.exec(o.viewport)
  if (!m) throw new ExitError(2, `--viewport must look like 1440x900, got ${o.viewport}`)
  if (o.colorScheme && !['light', 'dark'].includes(o.colorScheme)) throw new ExitError(2, '--color-scheme light|dark')
  if (!['reduce', 'no-preference'].includes(o.reducedMotion)) throw new ExitError(2, '--reduced-motion reduce|no-preference')
  if (o.storage && o.role) throw new ExitError(2, 'use --storage or --role, not both')
  if (!(o.dpr > 0) || !(o.settle >= 0)) throw new ExitError(2, '--dpr and --settle must be numbers')
  o.width = Number(m[1]); o.height = Number(m[2])
  return o
}

function parseRoute(spec) {
  const at = spec.lastIndexOf('=')
  const glob = spec.slice(0, at)
  const action = spec.slice(at + 1)
  if (at <= 0) throw new ExitError(2, `--route needs GLOB=ACTION, got ${spec}`)
  if (/^[1-5]\d\d$/.test(action)) return { glob, status: Number(action) }
  const f = /^([1-5]\d\d):@(.+)$/.exec(action)
  if (f) {
    let body
    try { body = readFileSync(f[2], 'utf8') } catch { throw new ExitError(2, `--route body file not readable: ${f[2]}`) }
    return { glob, status: Number(f[1]), body }
  }
  if (action === 'offline') return { glob, offline: true }
  if (action === 'empty') return { glob, status: 200, body: '[]' }
  const d = /^delay:(\d+)$/.exec(action)
  if (d) return { glob, delay: Number(d[1]) }
  throw new ExitError(2, `--route action must be <status>|<status>:@file|offline|empty|delay:<ms>, got ${action}`)
}

function authFile(role, ext = 'json') {
  if (!/^[a-z0-9-]+$/.test(role)) throw new ExitError(2, `bad role ${role}`)
  if (!process.env.SDW_PROJDIR) throw new ExitError(3, 'not onboarded (run /sdw:onboard)')
  return join(process.env.SDW_PROJDIR, '.sdw', 'auth', `${role}.${ext}`)
}

// "Name: value" lines written by sdw-login for token and header auth.
function readHeaders(file) {
  const out = {}
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    const i = line.indexOf(':')
    if (i > 0) out[line.slice(0, i).trim()] = line.slice(i + 1).trim()
  }
  return out
}

async function installRoutes(page, routes) {
  for (const r of routes) {
    await page.route(r.glob, async (route) => {
      if (r.offline) return route.abort('internetdisconnected')
      if (r.delay !== undefined) {
        await new Promise((res) => setTimeout(res, r.delay))
        return route.continue()
      }
      return route.fulfill({
        status: r.status,
        contentType: 'application/json',
        body: r.body ?? JSON.stringify({ error: `sdw mock ${r.status}` }),
      })
    })
  }
}

function axeSource(req) {
  const tries = []
  if (req) tries.push(() => req.resolve('axe-core/axe.min.js'))
  tries.push(() => createRequire(join(process.cwd(), 'noop.js')).resolve('axe-core/axe.min.js'))
  tries.push(() => createRequire(join(cacheDir('axe'), 'noop.js')).resolve('axe-core/axe.min.js'))
  for (const t of tries) {
    try { return readFileSync(t(), 'utf8') } catch { /* next */ }
  }
  return null
}

async function runAxe(page, pwReq) {
  let raw
  const builder = tryRequire(join(process.cwd(), 'noop.js'), ['@axe-core/playwright'])
  if (builder) {
    const AxeBuilder = builder.mod.default || builder.mod.AxeBuilder
    raw = await new AxeBuilder({ page }).withTags(AXE_TAGS).analyze()
  } else {
    const src = axeSource(pwReq)
    if (!src) {
      return { violations: [], notRun: `axe-core not found; npm install --prefix ~/.cache/sdw/axe axe-core@${AXE_PIN}` }
    }
    await page.addScriptTag({ content: src })
    raw = await page.evaluate((tags) => window.axe.run(document, { runOnly: { type: 'tag', values: tags } }), AXE_TAGS)
  }
  return {
    violations: raw.violations.map((v) => ({
      id: v.id, impact: v.impact, nodes: v.nodes.length,
      targets: v.nodes.slice(0, 3).map((n) => n.target.join(' ')),
    })),
  }
}

async function measure(page, selector, keys = STYLE_KEYS) {
  return page.evaluate(({ selector, keys }) => {
    return [...document.querySelectorAll(selector)].slice(0, 5).map((el) => {
      const r = el.getBoundingClientRect()
      const cs = getComputedStyle(el)
      return {
        box: { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) },
        style: Object.fromEntries(keys.map((k) => [k, cs[k]])),
        text: (el.textContent || '').trim().slice(0, 60),
      }
    })
  }, { selector, keys })
}

// Lab numbers from one headless load: CLS is the sum of shifts without recent input during the
// capture, inpMs the slowest interaction from --click/--fill (Event Timing reports only >= 16 ms).
function vitalsInit() {
  const v = { cls: 0, shifts: [], lcp: null, longTasks: { count: 0, totalMs: 0 }, events: [] }
  window.__sdwVitals = v
  const name = (n) => {
    if (!n || n.nodeType !== 1) return null
    if (n.id) return `${n.tagName.toLowerCase()}#${n.id}`
    return [n.tagName.toLowerCase(), ...[...n.classList].slice(0, 2)].join('.')
  }
  const watch = (type, fn, extra) => {
    try { new PerformanceObserver((l) => l.getEntries().forEach(fn)).observe({ type, buffered: true, ...extra }) } catch { /* unsupported */ }
  }
  watch('layout-shift', (e) => {
    if (e.hadRecentInput) return
    v.cls += e.value
    if (v.shifts.length < 50) v.shifts.push({ value: e.value, at: Math.round(e.startTime), sources: (e.sources || []).map((s) => name(s.node)).filter(Boolean).slice(0, 3) })
  })
  watch('largest-contentful-paint', (e) => { v.lcp = { ms: Math.round(e.startTime), element: name(e.element) } })
  watch('longtask', (e) => { v.longTasks.count++; v.longTasks.totalMs += Math.round(e.duration) })
  watch('event', (e) => { if (e.interactionId) v.events.push({ type: e.name, ms: Math.round(e.duration), target: name(e.target) }) }, { durationThreshold: 16 })
}

async function readVitals(page) {
  const v = await page.evaluate(() => window.__sdwVitals || null)
  if (!v) return { notRun: 'no vitals observer on this document' }
  const top = (xs, key) => [...xs].sort((a, b) => b[key] - a[key]).slice(0, 3)
  return {
    cls: Number(v.cls.toFixed(4)),
    shifts: top(v.shifts, 'value').map((s) => ({ ...s, value: Number(s.value.toFixed(4)) })),
    lcpMs: v.lcp ? v.lcp.ms : null, lcpElement: v.lcp ? v.lcp.element : null,
    longTasks: v.longTasks,
    inpMs: v.events.length ? Math.max(...v.events.map((e) => e.ms)) : null,
    interactions: top(v.events, 'ms'),
  }
}

async function saveAuth(chromium, o) {
  const file = authFile(o.saveAuth)
  const browser = await launchBrowser(chromium, { channel: o.channel, headed: true })
  const context = await browser.newContext({ viewport: { width: o.width, height: o.height } })
  const page = await context.newPage()
  await page.goto(o.url).catch(() => {})
  console.error('sdw-ui-shot: log in, then close the browser window')
  let state = null
  const deadline = Date.now() + 10 * 60 * 1000
  while (!page.isClosed() && browser.isConnected() && Date.now() < deadline) {
    try { state = await context.storageState() } catch { break }
    await new Promise((res) => setTimeout(res, 1000))
  }
  try { state = await context.storageState() } catch { /* window gone, keep last snapshot */ }
  await browser.close().catch(() => {})
  if (!state || !state.cookies.length) throw new ExitError(1, 'no session captured')
  mkdirSync(dirname(file), { recursive: true, mode: 0o700 })
  writeFileSync(file, JSON.stringify(state, null, 2), { mode: 0o600 })
  chmodSync(file, 0o600)
  console.log(JSON.stringify({ saved: file, cookies: state.cookies.length }))
}

async function capture(chromium, pwReq, o) {
  let storage = o.storage
  let headers
  if (o.role) {
    const json = authFile(o.role)
    const hdr = authFile(o.role, 'header')
    if (existsSync(hdr)) headers = readHeaders(hdr)
    if (existsSync(json)) storage = json
    else if (!headers) throw new ExitError(4, `no session for role ${o.role}: run sdw-login ${o.role}`)
  }
  if (storage && !existsSync(storage)) throw new ExitError(4, `storage state missing: ${storage}`)
  const browser = await launchBrowser(chromium, { channel: o.channel, headed: o.headed })
  const report = {
    url: o.url, out: resolve(o.out), viewport: `${o.width}x${o.height}@${o.dpr}x`, status: null,
    timezone: o.timezone ?? null, locale: o.locale ?? null, steps: o.steps.length, mocked: o.route.length,
    reducedMotion: o.reducedMotion,
    console: [], pageerror: [], requests: [], measure: {}, motion: {}, vitals: null, axe: null, error: null,
  }
  let code = 0
  try {
    const context = await browser.newContext({
      viewport: { width: o.width, height: o.height }, deviceScaleFactor: o.dpr,
      storageState: storage, colorScheme: o.colorScheme, reducedMotion: o.reducedMotion, bypassCSP: !!o.axe,
      extraHTTPHeaders: headers, timezoneId: o.timezone, locale: o.locale,
    })
    if (o.vitals) await context.addInitScript(vitalsInit)
    const page = await context.newPage()
    page.on('console', (m) => {
      if (m.type() === 'error' || m.type() === 'warning') report.console.push({ type: m.type(), text: m.text() })
    })
    page.on('pageerror', (e) => report.pageerror.push(e.message))
    page.on('requestfailed', (r) => report.requests.push({ method: r.method(), url: r.url(), failure: r.failure()?.errorText ?? 'failed' }))
    page.on('response', (r) => {
      if (r.status() >= 400) report.requests.push({ method: r.request().method(), url: r.url(), status: r.status() })
    })
    await installRoutes(page, o.route)
    try {
      const res = await page.goto(o.url, { waitUntil: o.networkidle ? 'networkidle' : 'load', timeout: 30000 })
      report.status = res ? res.status() : null
      if (o.wait) await page.waitForSelector(o.wait, { state: 'visible', timeout: 15000 })
      for (const st of o.steps) {
        if (st.click) await page.click(st.click, { timeout: 15000 })
        else await page.fill(st.fill, st.value, { timeout: 15000 })
      }
      if (o.steps.length) await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {})
      await page.evaluate(() => document.fonts.ready)
      await page.waitForTimeout(o.settle)
    } catch (err) {
      report.error = firstLine(err)
      code = 1
    }
    if (code === 0) report.url = page.url()
    mkdirSync(dirname(report.out), { recursive: true })
    await page.screenshot({ path: report.out, fullPage: o.fullPage, animations: 'disabled' }).catch((err) => {
      report.error = report.error || `screenshot: ${firstLine(err)}`
      code = 1
    })
    if (code === 0) {
      for (const sel of o.measure) report.measure[sel] = await measure(page, sel)
      for (const sel of o.motion) report.motion[sel] = await measure(page, sel, MOTION_KEYS)
      if (o.vitals) report.vitals = await readVitals(page)
      if (o.axe) report.axe = await runAxe(page, pwReq)
    }
  } finally {
    await browser.close().catch(() => {})
  }
  console.log(JSON.stringify(report, null, 2))
  return code
}

async function main() {
  const o = parseArgs(process.argv.slice(2))
  const pw = loadPlaywright()
  const chromium = pw.mod.chromium
  if (o.saveAuth) { await saveAuth(chromium, o); return 0 }
  return capture(chromium, pw.req, o)
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  main().then((code) => process.exit(code)).catch((err) => {
    console.error(`sdw-ui-shot: ${err.message}`)
    process.exit(err instanceof ExitError ? err.code : 1)
  })
}
