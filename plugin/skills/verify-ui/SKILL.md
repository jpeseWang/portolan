---
name: verify-ui
description: "sdw project: prove a screen matches its design: artboard-size capture, image diff against the reference, measured deltas."
argument-hint: "<route> <figma-url | node-id | png>"
---

# Verify UI

Arguments: `$ARGUMENTS`: the route, then the reference. This is design fidelity only; states
(loading, empty, error, roles) belong to `/sdw:qa`.

```bash
sdw-workdir --projdir >/dev/null; echo "projdir rc=$?"; wd=$(sdw-workdir) && echo "wd=$wd"
```
rc 3 → say `run /sdw:onboard first` and stop. No reference given → say `nothing to match,
run /sdw:qa for states` and stop.

## 1. Pin the reference

- PNG path: use it; its size is the artboard size (halve it for a 2x export).
- Figma URL `…/design/<fileKey>/…?node-id=12-345` (or `/file/`): take fileKey and node id.
  Node id alone: fileKey from `sdw-cfg FIGMA_FILE_KEY`.
- Render at scale 1, so its pixel size is the artboard size:
  ```bash
  ref=$(sdw-figma-png <fileKey> <nodeId> --scale 1) && echo "$ref"
  python3 -c 'import sys; from PIL import Image; print("%dx%d" % Image.open(sys.argv[1]).size)' "$ref"
  ```
  Exit 4 → print the Keychain one-liner it gave and stop. `cache (unverified)` on stderr →
  say so in the report. Never call the Figma `/nodes` endpoint.
- Design numbers for the 3–8 elements that carry the layout (title, primary button, card,
  row, sidebar): Figma MCP only while this month's calls stay within `sdw-cfg
  FIGMA_MCP_BUDGET`; otherwise read them off the scale-1 render and say so.
- A state the design does not draw is a design question, not a licence to invent.

## 2. Capture at the artboard size

Seed data that matches the frame (row count, text lengths), or every row is a false diff.
```bash
wd=$(sdw-workdir)
sdw-ui-shot --url "<url>" --viewport <W>x<H> --dpr 1 --out "$wd/shots/<slug>.png" \
  --wait '<selector that means loaded>' [--role <role>] --measure '<sel>' --measure '<sel>'
```
Viewport = the render's size; a frame taller than the screen uses the run.md `artboards`
height plus `--full-page`. Console errors, pageerror and 4xx/5xx are findings regardless.

## 3. Diff, then look

```bash
wd=$(sdw-workdir)
sdw-ui-diff "<ref.png>" "$wd/shots/<slug>.png" --out "$wd/shots/diff/<slug>" --key "<route>" --path "<app prefix>"
```
It records the evidence entry. Read `<slug>.side-by-side.png` and `<slug>.heatmap.png`. The
region list says where to look, not what is wrong. Scattered red is anti-aliasing; a solid
block is a finding.

## 4. Measure, fix, re-capture

| Element | Property | Design | Build | Δ |
|---|---|---|---|---|

Build values come from `measure` in the sdw-ui-shot JSON. Fix the largest real deltas
first: layout and spacing, then type, then colour. Use the project's tokens and shared
components; a value the token set lacks is reported, not hardcoded, and a shared component
is not changed to fit one screen. Repeat steps 2–3; stop after three rounds and report what
is left.

## 5. Report

```
Screen:      <route> vs <ref> @ <W>x<H>, DPR 1 (reference: fresh | cache unverified)
Rounds:      <n>   Mismatch: <first>% → <last>%
Remaining Δ: <element property design vs build — why accepted>
Console:     <clean | lines>   Requests: <failed/4xx/5xx>
Evidence:    shots/<slug>.png, shots/diff/<slug>.side-by-side.png
Design questions: <states or values the design does not define>
NOT verified: <dark mode, other widths, …>
```
Every ✓ carries a screenshot path or a number. Never call it pixel-perfect. A design that
contradicts the API contract or an accessibility rule is a question for its owner. Never
update a visual baseline to make a test pass.
