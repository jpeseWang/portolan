# Design fidelity — proving a screen matches its design

An agent reads a design, writes code that compiles, and reports the screen done; the reviewer
opens it and the title is 4 px too small and the error state is a blank panel. Reading a design
is not checking against it. Only the rendered page can be checked, against a reference at the
same size.

## Two questions, two tools

| Question | When | Tool | Reference |
|---|---|---|---|
| Did I build what was designed? | while implementing a ticket | `/sdw:verify-ui <route> <frame>` | the design frame |
| Did this screen change by accident? | every PR, in CI | Playwright `toHaveScreenshot` (`plugin/skills/test/e2e/visual.spec.ts`) | a human-approved baseline |

A design comparison is noisy (real data, font hinting, undrawn states), so it needs judgement
and runs once per ticket. A regression baseline compares the build with itself, so it can be
strict. Using the design PNG as the CI baseline gives a test that is always red.

## What a real project taught

- **Capture at the artboard size, at DPR 1.** When the root font size follows the viewport, a
  laptop-width capture against a wide artboard differs everywhere by scale alone.
- **Measure, don't eyeball.** A model comparing screenshots spots a missing element and misses
  4 px of padding. Design geometry against `getBoundingClientRect` and computed style
  (`sdw-ui-shot --measure`) gives numbers a fix can aim at.
- **Design APIs are scarce.** A view-only Figma seat allows a handful of MCP calls a month, and
  the REST `/nodes` endpoint stays rate-limited for well over 20 minutes. `/images` usually
  still answers. Fetch each frame once and reuse it.
- **The design is one state.** Shipped bugs live in states no frame drew: error, empty, a role
  that sees less, a long name. That sweep belongs to `/sdw:qa`, not verify-ui.
- **Side-by-side pairs are good review evidence**: "design | build" turns "it doesn't look
  right" into specific comments.

## The pieces

| Piece | Does |
|---|---|
| `/sdw:verify-ui` | pin the reference → capture → diff → measured deltas; every ✓ needs a path or a number |
| `sdw-figma-png <fileKey> <nodeId>` | REST `/images` render only, never `/nodes`; token from Keychain `sdw:figma`; cached in `.sdw/design-refs/` by node id and the file's last-modified time, so an unchanged file is never re-fetched |
| `sdw-ui-shot` | Playwright capture at a fixed viewport and DPR after `load` plus `--wait`; reports console errors, page errors, failed and 4xx/5xx requests, and boxes and styles for `--measure` selectors |
| `sdw-ui-diff` | scales the design to the app width, writes side-by-side, overlay and heatmap images, lists the regions that differ most, and records a `ui-diff` evidence entry |
| `.sdw/gates` | the fast gate the Stop hook runs, so a styling change cannot end a turn on a type or lint error |

`FIGMA_MCP_BUDGET` in `.sdw/config.env` caps MCP calls per month (0 = REST only).

## What none of this proves

- That the design itself is right, or consistent with the API contract.
- Animation, hover and transition timing; captures use reduced motion. `/sdw:ui-polish` checks
  the declared properties, durations and easing, reduced-motion handling, layout shift and input
  delay. Whether it feels right is still a human call.
- Real-device rendering: headless Chromium on macOS is not Safari on a phone.
- That a 1 % difference is harmless. Mask dynamic regions instead of raising the threshold for
  the whole page.

The verify-ui report's `NOT verified:` line is where these go when they matter for the change.
