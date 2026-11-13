# Motion and interaction defaults

Use these when the project has no tokens of its own. Each row names its source, so a reviewer
can check it.

## Durations

| What | Duration | Source |
|---|---|---|
| Small feedback: toggle, checkbox, press | ~100 ms (press 100–160) | NN/g "Executing UX Animations: Duration"; Emil Kowalski |
| Hover, small state change | 120–180 ms | userinterface-wiki |
| Tooltip, small popover | 125–200 ms | Emil Kowalski |
| Dropdown, menu | 150–250 ms | Emil Kowalski |
| Modal, drawer | 200–300 ms; up to 500 for a large move | NN/g; Emil Kowalski |
| Anything over 400 ms | "very slow": only for large moves across big screens | NN/g |

Enter runs slightly longer than exit. Page and route transitions have no authoritative number,
so use the project's own value or the modal range.

## Easing

- Enter: ease-out. A strong default is `cubic-bezier(0.23, 1, 0.32, 1)`.
- Never ease-in on UI that appears: it starts slowly and feels laggy. For exits, sources disagree:
  NN/g allows ease-in, Emil uses ease-out. Follow the project.
- Gestures, drags and anything interrupted mid-way use springs, which keep their velocity.

## What to animate

- `transform` and `opacity` run on the compositor; width, height, top, left and margin trigger
  layout on every frame (web.dev "Stick to compositor-only properties").
- `will-change` only on an element about to animate, and removed afterwards.
- Name the properties; `transition: all` animates whatever changes next, layout included.

## Behaviour

- Interruptible: user input cancels or retargets an animation. CSS transitions retarget;
  keyframes restart from zero (Vercel Web Interface Guidelines; Emil).
- Origin-aware: popovers scale from their trigger; modals stay centred (Emil; Radix
  `--radix-popover-content-transform-origin`).
- No animation on keyboard-initiated or high-frequency actions, which may repeat hundreds of
  times a day (Emil, "You don't need animations").
- Reduced motion: honour `prefers-reduced-motion`; remove movement, keep opacity and colour
  (Vercel guidelines; motion.dev "React accessibility"; WCAG 2.3.3, AAA).

## Loading and feedback

- Under 1 s: no indicator. A full-page load under 10 s: a skeleton. A single module: a spinner.
  Over 10 s: a progress bar (NN/g "Skeleton screens").
- Delay a spinner by 150–300 ms and keep it at least 300–500 ms so it never flashes; a skeleton
  matches the final layout exactly (Vercel guidelines).
- Optimistic UI: update at once when success is likely, then reconcile; React `useOptimistic`
  reverts on failure, and the error is still yours to show (react.dev).
- `:hover`, `:active` and `:focus-visible` contrast more with each other than with the rest
  state; dark themes set `color-scheme: dark` on `<html>` (Vercel guidelines).

## Live data (streams, polling, push)

- No motion per update. A value that changes every second is a high-frequency event: swap the
  text. At most, give a short colour highlight (opacity or background, never movement), and only
  when the change matters to the user (Emil, "You don't need animations").
- Render at the screen's pace, not the socket's. Batch incoming messages and apply them at most
  once per animation frame (`requestAnimationFrame`), or at the rate a person can read: a
  dashboard tile rarely needs more than one update per second. Batching also keeps INP low while
  the stream is busy (web.dev "Optimize INP").
- Numbers that change keep their width: `font-variant-numeric: tabular-nums` and a fixed or
  min-width cell, so neighbours never move (MDN `font-variant-numeric`; CLS).
- Charts animate the first draw at most. Appending a point redraws without a transition: for example
  Recharts `isAnimationActive={false}`, Chart.js `animation: false`, or `update('none')`.
- Status changes (online/offline, an alarm) are worth showing with colour, icon and text, never
  colour alone (WCAG 1.4.1).
- Screen readers:
  - an alert or status change can go in `role="status"` (or `aria-live="polite"`);
  - a value that ticks never goes in a live region, or the reader talks non-stop (MDN "ARIA live regions").
- Auto-updating content shown next to other content needs a way to pause, stop or hide it
  (WCAG 2.2.2, level A), unless the updates are essential.
- Connection states belong in the state table:
  - **live**;
  - **reconnecting**: keep the last data, dim it slightly, and show a quiet banner that overlays;
  - **stale**: show "updated <time> ago";
  - **offline**: the data is kept and labelled, never blanked.

  The client's events drive them (SignalR JS `onreconnecting`, `onreconnected`, `onclose`).
  After a reconnect, fetch the missed range before resuming live updates.

## Web Vitals (field thresholds, "good")

LCP ≤ 2.5 s, INP ≤ 200 ms, CLS ≤ 0.1 (web.dev). `sdw-ui-shot --vitals` gives lab numbers from a
single headless run, which is enough to catch a shift or a slow handler but is not a field
measurement.

## Sources

- https://www.nngroup.com/articles/animation-duration/
- https://www.nngroup.com/articles/skeleton-screens/
- https://emilkowal.ski/ui/great-animations · https://emilkowal.ski/ui/you-dont-need-animations
- https://github.com/emilkowalski/skills (MIT)
- https://github.com/vercel-labs/web-interface-guidelines
- https://web.dev/articles/stick-to-compositor-only-properties-and-manage-layer-count
- https://web.dev/articles/vitals · https://web.dev/articles/inp · https://web.dev/articles/optimize-inp
- https://developer.mozilla.org/en-US/docs/Web/CSS/font-variant-numeric
- https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Guides/Live_regions
- https://www.w3.org/WAI/WCAG22/Understanding/pause-stop-hide.html · https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html
- https://learn.microsoft.com/en-us/aspnet/core/signalr/javascript-client
- https://motion.dev/docs/react-accessibility
- https://react.dev/reference/react/useOptimistic
- https://www.radix-ui.com/primitives/docs/components/popover
- https://github.com/raphaelsalaja/userinterface-wiki
