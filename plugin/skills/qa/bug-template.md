Title: <≤60 chars, symptom first>
Severity: <S1|S2|S3|S4>
Status: <open | pre-existing>
Source: <AC-n | ticket | spec §x | design <node> | WCAG x.y.z | consistent with <sibling> | base behaviour>

## Environment
sha <HEAD sha7> · tree <from stamp> · <url> · <browser/channel> · <viewport> · role <role> · data <Probe …>
at <ISO timestamp> · TZ <browser>/<server> · locale <locale>

## Preconditions
## Steps
1.
## Request (api layer)
curl -sS -b "$projdir/.sdw/auth/<role>.cookies" -X <METHOD> -H 'Content-Type: application/json' -d '<body>' '<url>'
(the jar path only, never its contents)
## Expected (with source)
## Actual (verbatim)
<status line, error text, console line: copied, not paraphrased>
## Evidence
shots/<file>.png · shots/<file>.json
## Repro rate
<n>/<m>
## Regression vs base
<yes|no|unknown> — <how checked>
## Server log (optional)
<matching log lines with timestamps>
## Suspected area (guess)
<area> — evidence: <log line, stack frame or response field that points there>

<!-- Severity: S1 blocker, data loss, security, main-flow crash · S2 AC not met, no workaround ·
S3 workaround exists · S4 cosmetic. One defect per file. Never filed to a tracker by QA.
Status: open → fixed (the author) → verified (a retest only). wontfix needs a `Decided-by: <who,
where>` line. pre-existing: no AC in Source, Regression vs base `no — shots/base-<file>` (exists);
else it counts as open. -->
