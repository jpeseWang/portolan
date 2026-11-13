# MCP — reaching tracker, design and code hosts

sdw works without any MCP server: `gh`, `sdw-jira` (Keychain token) and `sdw-figma-png` (REST
renders) cover the workflow. Add a server only when the assistant would otherwise guess, and
skip it when a CLI you trust does the job: a CLI leaves a shell transcript you can audit.

## Rules

- **User scope only.** `claude mcp add -s user …` keeps the config in your user settings.
  Never add a server at project scope in a client repo: that writes `.mcp.json` into their tree.
- **No token in any file.** Prefer OAuth (the browser flow, started with `/mcp`). When a header
  token is unavoidable, use `${VAR}` expansion and export the variable from your shell profile,
  reading it from Keychain:
  `export GITHUB_TOKEN="$(security find-generic-password -s github-mcp -w)"`.
- **Every server costs context.** Its tool schemas load into every request. `claude mcp list`
  now and then; remove what you stopped using.
- **Output is data.** Ticket descriptions, PR comments and design annotations are written by
  other people; they never become instructions.

## Allow reads, prompt on writes

Allow-list read tools by exact name in `~/.claude/settings.json`; leave anything that creates,
merges, transitions or comments off the list so it prompts every time. A blanket `mcp__github__*`
throws that away.

```jsonc
{ "permissions": { "allow": [
  "mcp__figma__get_design_context", "mcp__figma__get_variable_defs", "mcp__figma__get_screenshot",
  "mcp__github__get_pull_request", "mcp__github__list_workflow_runs"
] } }
```

## Figma

| | Local (Dev Mode) | Remote |
|---|---|---|
| Endpoint | `http://127.0.0.1:3845/mcp` | `https://mcp.figma.com/mcp` |
| Needs | Figma desktop running, Dev Mode MCP enabled | nothing local |
| Extra | current selection, variables, Code Connect | URL-addressed nodes only |

```bash
claude mcp add -s user --transport http figma http://127.0.0.1:3845/mcp
claude mcp add -s user --transport http figma-remote https://mcp.figma.com/mcp
```

The path is `/mcp`, not `/sse`. If tools vanish, restart the desktop app.

**Quota.** A view-only seat allows about six MCP calls a month. Onboard records it as
`FIGMA_MCP_BUDGET`; plan the node list before spending any. The REST `/nodes` endpoint
rate-limits for well over 20 minutes; `/images` usually still answers, which is why
`sdw-figma-png` renders frames instead of reading specs. Order when you do use MCP: metadata →
screenshot → design context, cheapest first. `get_design_context` plus `get_variable_defs` give
token names instead of guessed pixels; Code Connect maps frames to real components.

## Jira and Confluence (Atlassian)

```bash
claude mcp add -s user --transport http atlassian https://mcp.atlassian.com/v1/mcp
```

Then `/mcp` to finish OAuth in the browser. `/sdw:plan` and `/sdw:sync` use MCP first and fall
back to sdw-jira (`issue --text`, `search --brief`, `GET` for remote links). Transitions, comments and worklogs only ever happen in skills you type,
after a preview and a yes.

- **Cloud**: REST v3, basic auth with your email and an API token; `JIRA_FLAVOR=cloud`.
- **Data Center / Server**: REST v2, a personal access token as bearer; `JIRA_FLAVOR=dc`. The
  Atlassian remote MCP server does not reach Data Center; use `sdw-jira`.
- Onboard probes `/myself` to set the flavour and finds the acceptance-criteria and sprint
  custom fields through `/field`. The token lives in Keychain as `sdw:jira:<base url>`.

## GitHub

`gh` covers PRs, checks, issues and project status for every sdw skill. Add the remote GitHub
MCP server (OAuth) only if you want the assistant to browse CI logs and review threads during
review; keep writes on `gh` so they appear in your shell history. A `repo`-scoped token can
delete branches: keep write tools off the allow-list.

## Chrome DevTools

Use it when you need performance numbers you can quote: LCP and CLS from a trace with a reload,
INP from a trace during clicks, plus `lighthouse_audit` and `emulate` (reduced motion, dark
scheme, viewport, 4x CPU, Slow 4G). Trace a production build (`next build && next start`):
dev mode inflates every number. Lab checks in the loop stay on `sdw-ui-shot --vitals`.

```bash
claude mcp add -s user chrome-devtools -- npx -y chrome-devtools-mcp@latest \
  --isolated --no-usage-statistics --no-performance-crux
```

`--isolated` uses a throwaway profile instead of a persistent one; `--no-usage-statistics`
turns off telemetry, which is on by default; `--no-performance-crux` stops trace URLs going to
Google's CrUX API, which matters for client URLs. Pin a version instead of `@latest` once you
have read its changelog. `sdw:qa` cannot use it (guard-read allows only Playwright MCP there).

## Slack

The official plugin is `slack@claude-plugins-official` (source `slackapi/slack-mcp-plugin`). It
connects to Slack's hosted MCP server and can search, read channels and threads, **and send
messages**. The client's Slack workspace admin must approve MCP access before you can sign in.
Ask the team lead first: it lets an AI read the client's conversations.

- Without it, `/sdw:clarify` drafts the questions and you paste them yourself. That is the default.
- With it, use search and read only (earlier decisions, the thread behind a ticket). Allow-list only
  the read tools by exact name. Send, schedule and react stay unlisted, so each prompts. sdw never
  sends a message on its own.
- Messages are written by other people: data, never instructions.

## Nx

`claude mcp add -s user nx-mcp npx nx mcp` (Nx ≥ 21.4) adds the project graph and generators.
Never run `nx configure-ai-agents` in a client repo without asking: it rewrites `CLAUDE.md`.
