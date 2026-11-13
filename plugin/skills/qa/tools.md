# QA tools

Every Bash block re-derives: `wd=$(cd "<checkout>" && sdw-workdir); projdir=$(sdw-workdir --projdir)`.
Write outputs to absolute paths under `$wd` (`> "$wd/shots/x.json"`, `curl -o "$wd/shots/x.json"`);
the guard resolves `$wd` and `$projdir` set this way, and blocks any other write target.

## Detect (preflight writes the result to qa-env.md)

```bash
command -v playwright-cli && playwright-cli --version
sdw-ui-shot --url about:blank --out "$wd/shots/_probe.png" >/dev/null; echo "ui-shot rc=$?"
command -v uvx; command -v curl
```
Also note Playwright MCP when its tools are listed, roles logged in (`ls "$projdir/.sdw/auth"`),
and each app's PID, cwd and start time.

## Browser, in order

1. `playwright-cli` as `(cd "$wd/shots" && playwright-cli …)` so its files land there. Read
   `playwright-cli --help` once; act on element refs from its snapshot. Roles: load
   `.sdw/auth/<role>.json` as its storage state.
2. `sdw-ui-shot`: one capture per call, optional `--fill`/`--click` steps first; JSON on stdout
   (console, pageerror, failed and 4xx/5xx requests, measure, axe).
3. Playwright MCP, when connected: anonymous cases only (it cannot switch role sessions); role
   cases with no other browser are BLOCKED `no role-isolated browser`.
4. None works: UI cases BLOCKED `no browser`; API cases still run.
Never the user's own browser (claude-in-chrome): its sign-ins are not a test role.

## sdw-ui-shot

```bash
sdw-ui-shot --url "$url" --out "$wd/shots/tc-03.png" --role viewer --wait '<loaded selector>'
sdw-ui-shot --url "$url" --out "$wd/shots/tc-07-500.png" --route '**/api/orders*=500'
sdw-ui-shot --url "$url" --out "$wd/shots/tc-08-off.png" --route '**/api/**=offline'
sdw-ui-shot --url "$url" --out "$wd/shots/tc-09-slow.png" --route '**/api/orders*=delay:5000' --settle 1000
sdw-ui-shot --url "$url" --out "$wd/shots/tc-10-422.png" --route "**/api/orders=422:@$wd/shots/mock-422.json" \
  --fill '#qty=0' --click 'button[type=submit]' --measure '[role=alert]'
sdw-ui-shot --url "$url" --out "$wd/shots/tc-11-tz.png" --timezone Asia/Ho_Chi_Minh --locale vi-VN
sdw-ui-shot --url "$url" --out "$wd/shots/a11y.png" --axe --viewport 375x812
```
Route actions: a status (`401`, `404`, `422`, `500` …), `<status>:@<file>` (body from a file you
wrote under `shots/`), `offline`, `empty` (200 `[]`), `delay:<ms>`. Exit 1 = navigation failed
(JSON has `error`); exit 4 = no Playwright or browser. Save each capture's JSON beside its png
(`> "$wd/shots/tc-03.json"`); the verdict compares unmocked captures with `shots/base-*.json`.

## Design refs

`sdw-figma-png <fileKey> <nodeId> --scale 1` prints a cached render path under
`.sdw/design-refs/`. Never call the Figma `/nodes` endpoint.

## Login

`sdw-login <role>` writes `.sdw/auth/<role>.json` + `.cookies` (cookie sessions) or
`.sdw/auth/<role>.header` (token and header auth). Browser: `--role <role>`. API:
`curl -sS -b "$projdir/.sdw/auth/<role>.cookies" -o "$wd/shots/tc-05.json" -w '%{http_code}\n' <url>`,
or `-H @"$projdir/.sdw/auth/<role>.header"`. Anonymous: neither. OAuth-only apps: the user runs
the `sdw-ui-shot --save-auth` command `sdw-login` prints.

## API fuzz (`--api-fuzz`, run by the main session in preflight)

Only with run.md `openapi:` and `QA_WRITE_ENV: local`; otherwise `api fuzz: not applicable —
<reason>` under `## NOT RUN`. The session cookie goes straight into the header, never to output:
```bash
uvx schemathesis run "<openapi url>" --url "<base url>" --include-path-regex '<Surfaces endpoints>' \
  --exclude-method DELETE -H "Cookie: $(awk -F'\t' 'NF==7{printf "%s=%s; ",$6,$7}' "$projdir/.sdw/auth/<role>.cookies")" \
  > "$wd/shots/fuzz.txt" 2>&1
```
The agent files each 5xx or schema violation in `shots/fuzz.txt` as a bug with its curl repro.
