# Memory and context — what loads every turn

Everything below is read before the agent looks at the task. Past a point more context makes
it worse, not better, and a stale rule misleads silently in every repo. Treat this list as a
hot path: every line has to earn its place.

## What loads, and who owns it

| Source | Owner | Size control |
|---|---|---|
| `~/.claude/CLAUDE.md`, `~/.claude/rules/*.md` | you | one screen; from `templates/global-memory.md` |
| the client's `CLAUDE.md` / `AGENTS.md` / `.claude/rules` | the team | not yours to edit; they win |
| sdw SessionStart text: `plugin/rules/core.md` + `.sdw/project.md` + ≤8 state lines | sdw | ≤4,500 + ≤2,500 chars, ≤9,000 total (the hook cap is 10,000); CI checks it |
| auto-memory index (`~/.claude/projects/<slug>/memory/MEMORY.md`) | Claude | prune what is no longer true |
| descriptions of model-invocable skills | each skill | sdw exposes 7 (sync, debug, test, qa, verify-ui, review, daily-report), plus `verify` if installed |
| MCP tool schemas | each server | remove idle servers; see [mcp.md](mcp.md) |

`claude plugin details` does not count the SessionStart text (capped at 9,000 chars; `sdw-doctor`
prints its size). The sdw text is re-injected after `/clear` and compaction, so plans, ACs and verdicts survive in
`.sdw/work/<branch>/` instead of in chat. plan.md `## Progress` (done, now, next, decisions with
their reasons) is updated by `/sdw:commit` and `/sdw:ship` and read first when work resumes.

## Global memory: who you are, not what a repo is

- **Cross-project only.** Test: would it still be right in a brand-new empty repo? A build
  command or base branch belongs in `.sdw/project.md`, never here.
- **Add on the second occurrence.** The trigger is giving the same correction in a second
  project; one-offs stay in the session.
- **Let tools enforce what tools can.** Formatting, secret blocking and destructive-command
  guards are hooks and settings, not prose the model may skip.
- **No secrets, no client names.** A memory file gets pasted into bug reports.

## AGENTS.md and CLAUDE.md

By default Claude Code loads a project's `AGENTS.md` only when there is no `CLAUDE.md` for it.
In a workspace-parent layout, your parent `CLAUDE.md` can therefore hide a team's `AGENTS.md`
deeper down, and team rules are supposed to win. `sdw-doctor` warns when that happens.
`./bootstrap.sh --agents-md` prints the user-level opt-in (`instructionFiles` =
`claude-md-and-agents-md` on the built-in `cc-plugin-agents-md` plugin) that loads both. It is
printed, not applied, until it has been verified on the installed version.

## Auto-memory on client work

Auto-memory stays on by default. For a client under NDA, onboard asks once and, on a yes, sets
`"autoMemoryEnabled": false` in that repo's `.claude/settings.local.json` (a protected path:
one prompt). Either way `/sdw:offboard` deletes in-project data and Keychain items, and prints the
commands that remove `~/.claude/projects/<slug>`, file-history and history.jsonl lines for you to
run after the session ends. Lessons worth keeping are rewritten without client detail
before they go into global memory.

## Skills: typed versus self-activating

A skill the model may invoke keeps its description in context on every turn and fires on the
model's judgement. That is a win only when the trigger is narrow and a wrong-time run is cheap.

- Anything with side effects (commit, push, merge, tickets, worklogs, deleting data) sets
  `disable-model-invocation: true`, so it runs only when typed. All nine such sdw skills do.
- Keep descriptions short and specific; two skills that claim the same trigger both lose.
- Read a third-party skill before installing it: it is instructions that load themselves into
  your agent, the highest-leverage place for a prompt injection to live.
- Audit now and then: did it fire this month, and was it right when it did? If not, remove it.
- The playwright-cli global skill is deliberately not installed; the QA agent carries its own
  notes, loaded only when QA runs.
