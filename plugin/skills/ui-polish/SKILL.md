---
name: ui-polish
description: "Interaction polish on a UI change: each control's states, motion timing, reduced motion, layout shift, input delay, widths, dark mode. Rules, then measured."
argument-hint: "<route> [control selectors]"
---

# UI polish

Arguments: `$ARGUMENTS`: the route, then selectors for the controls the change adds or touches.
This is how the screen behaves between states. Match to a design is `/sdw:verify-ui`; loading,
empty, error and roles are `/sdw:qa`.

```bash
wd=$(sdw-workdir 2>/dev/null) && echo "wd=$wd" || { wd="${TMPDIR:-/tmp}/sdw-polish"; mkdir -p "$wd/shots"; echo "not onboarded: shots in $wd, no work-dir files"; }
```

## 1. Inventory, before code

One row per control the slice adds or changes:

| Control | rest | hover | focus-visible | pressed | disabled | pending | success / error |
|---|---|---|---|---|---|---|---|

A view fed by live data (socket, SSE, polling) adds a row with these columns: live, reconnecting, stale (with
"updated … ago"), offline, and no data yet.

Fill it from the design, then from the project's nearest existing control of the same kind, and
reuse that component. A state neither defines is a design question, not something to invent.
Find the motion tokens first: `git grep -nE "duration|easing|--ease|transitionTimingFunction|motion" -- '*.css' '*.scss' '*tailwind.config*' '*theme*' | head -20`.
Project tokens win over the defaults in `${CLAUDE_SKILL_DIR}/motion.md`.

## 2. Build rules

Sources and the numbers behind them: `${CLAUDE_SKILL_DIR}/motion.md`.
- Input gets visible feedback within 100 ms. A submit disables itself while pending. A spinner
  appears only after 150–300 ms and then stays at least 300 ms. A skeleton has the final layout.
- Animate `transform` and `opacity` (colour for hover). Name the properties: never
  `transition: all` or Tailwind `transition-all` on a component.
- Durations: press and hover 100–160 ms, tooltip and popover 125–200, dropdown 150–250, modal and
  drawer 200–300 (up to 500 for a large move). Exit is faster than enter. Enter eases out;
  never `ease-in` on enter.
- Anything toggled repeatedly uses a CSS transition (it retargets mid-way), not keyframes.
- Popovers and menus scale from their trigger (`transform-origin`; Radix exposes
  `--radix-<part>-transform-origin`); modals stay centred.
- No animation on keyboard-driven or high-frequency actions: shortcuts, list navigation, typing.
- `prefers-reduced-motion: reduce` removes movement (transform, layout) and keeps opacity and
  colour. Motion for React: `<MotionConfig reducedMotion="user">`.
- No layout shift: media carries width and height or `aspect-ratio`; late content gets reserved
  space; a banner or toast overlays, it does not push the page down.
- Hover-only styling sits under `@media (hover: hover)`; anything revealed on hover is also
  revealed on `:focus-within` and reachable by touch.
- Optimistic update only when success is likely and the action can be undone; on failure,
  roll back and say what failed.
- Dark theme, when the app ships one: colours from tokens, `color-scheme` set on the root.
- Live data (`motion.md` "Live data"):
  - no movement per update, and updates batched to one per frame or slower;
  - `tabular-nums` on changing numbers;
  - no transition when a chart appends;
  - ticking values never go in an `aria-live` region;
  - a pause control for auto-updating content.

## 3. Measure

```bash
wd=$(sdw-workdir 2>/dev/null || echo "${TMPDIR:-/tmp}/sdw-polish"); u="<url>"; s="<slug>"
sdw-ui-shot --url "$u" --out "$wd/shots/polish-$s.png" --reduced-motion no-preference --motion '<sel>' > "$wd/shots/polish-$s.json"
sdw-ui-shot --url "$u" --out "$wd/shots/polish-$s-reduce.png" --motion '<sel>' > "$wd/shots/polish-$s-reduce.json"
sdw-ui-shot --url "$u" --out "$wd/shots/polish-$s-load.png" --vitals --settle 1500 > "$wd/shots/polish-$s-load.json"
sdw-ui-shot --url "$u" --out "$wd/shots/polish-$s-act.png" --vitals --click '<primary action>' > "$wd/shots/polish-$s-act.json"
```
Add `--role <r>` and `--wait '<loaded selector>'` as the route needs.

- `motion`: no `all` and no width, height, top, left or margin in `transitionProperty`;
  durations inside the table or the project's tokens; no `ease-in` on an entering element. The
  `-reduce` capture shows movement gone (`0s` or no transform property).
- `vitals`: `cls` ≤ 0.1 on load; `shifts[].sources` names what moved, and any shift is worth a
  look. `inpMs` ≤ 200 for the action. Lab numbers from an unthrottled headless dev build: a pass
  is weak and a fail is real. For numbers to quote, use a production build and a Chrome DevTools
  MCP trace (`performance_start_trace`) at 4x CPU throttling.
- Widths: capture 375, 768 and 1280 (plus the artboard) and read each one. Look for overflow,
  clipped labels, and targets under 24×24 px (`--measure` on the controls; WCAG 2.5.8).
- Dark: `--color-scheme dark` when the app has a dark theme.
- Hover and focus: `sdw-ui-shot` does not hover. Use `playwright-cli` `hover <ref>` / `press Tab`,
  then `screenshot`, and check that hover differs from rest and the focus ring is visible.
- Live view: keep it open with the stream running (or a mock emitting at the real rate) and run
  `--vitals --settle 10000`. Any `shifts[]` while the data ticks is a finding. For the
  never-connected state, use `--route '**/<hub>/negotiate*=offline'`. For reconnecting and offline, stop
  the API you started while a `playwright-cli` session keeps the page open, then screenshot.
  `--route` does not intercept an open WebSocket.
- JS-driven animation (Motion, GSAP, react-spring) has no computed transition. Read its config in
  the code (duration, easing, reduced-motion handling) and say that is where it came from.

Fix findings in the changed code and capture again. A shared component that is wrong for every
screen is reported, not changed to fit this one.

## 4. Report

```
Polish:     <route> — <n> controls
States:     <control: missing states> | all defined
Motion:     <sel: property duration easing — ok | finding>   Reduced: removed | still moves: <sel>
Vitals:     CLS <n> load · INP <n> ms <action> · long tasks <n>/<ms> — lab, dev build
Widths:     375 ✓ 768 ✓ 1280 ✓ (shots/polish-…)   Dark: ✓ | n/a | NOT VERIFIED
NOT verified: timing and feel by eye, real devices and Safari, JS animation at runtime
```
Every ✓ carries a shot path or a number. Never call motion "smooth" without a number.
