# QA with Portolan route

For testers who have a small plan (for example Claude Pro) and want it to last. QA spends tokens on running and
reading, not on thinking, so the expensive model is rarely the right one.

## The four steps and their roles

| Step | Role | Default tool | Why |
|---|---|---|---|
| 1. Turn the ticket and acceptance criteria into test cases, find risks | `qa-design` | Claude Sonnet | short, needs reasoning; Opus is not needed |
| 2. Run the cases, explore the UI, read logs and responses | `qa-run` | Gemini Flash, then Codex, then Haiku | most of the tokens go here; use a pool other than Claude's |
| 3. Write bug reports and the summary | `qa-report` | Gemini Flash low, then Haiku | formatting, a cheap model is enough |
| 4. A failure nobody could reproduce, or a severe bug you want double-checked | `qa-escalate` | Opus on the Google plan, then Claude Opus | the only step where Opus is worth it |

`aim-pick qa-run` shows which one to open right now, given the quota you have left. If a tool you do not own is first
in a chain, remove it from `routing.json` (the README prompt does this with you).

## Running a session

```
aim-pick qa-design            # then open what it names, for example:  claude --model sonnet
aim-pick qa-run --dir ~/work/app
```

Keep one step per session and write the result to a file before you switch tools. The next tool reads the file; it
does not see the previous conversation.

| File | Written by | Read by |
|---|---|---|
| `cases.md` | step 1 | step 2 |
| `run-notes.md` (what you did, what you saw, evidence paths) | step 2 | step 3, step 4 |
| `bugs.md` | step 3 | you, then the tracker |

Starter prompts:

- Step 1: "Read ticket.md. List the acceptance criteria, then write test cases in cases.md: id, steps, expected result,
  and which criterion it covers. Add the 5 riskiest cases at the top. Do not run anything."
- Step 2: "Run the cases in cases.md against <url>. After each case, append to run-notes.md: pass or fail, what you saw,
  and the exact request or screen. Stop at the first blocker and say what you need."
- Step 3: "From run-notes.md write one bug per failed case in bugs.md: title, steps, expected, actual, severity, evidence.
  Merge duplicates. Do not invent steps that are not in the notes."
- Step 4: "Case <id> failed once and could not be reproduced. Read run-notes.md. List three hypotheses ranked by
  likelihood and the cheapest check for each. Do not change any file."

## Spending less, any tool

- Default to Sonnet (`/model`) and let sub-agents use Haiku. Use Opus only in step 4.
- One task per session; `/clear` when you switch. A fresh prompt already costs thousands of tokens of setup.
- Prefer page text or the accessibility tree to screenshots when you do not need to look at the layout.
- Give the tool the failing log lines, not the whole log. Ask for a summary file instead of a long answer in chat.
- Keep `CLAUDE.md` short and disable plugins and MCP servers you are not using.
- Check `ai-quota --subs` before a long run, not after.

## With sdw

If you installed sdw (Part B of the root README), `/sdw:qa` derives the cases from the ticket and acceptance
criteria, runs them in a browser or against the API, and files bug reports to disk with a verdict. Use it for steps 1
and 2 while Claude has quota. When it does not, use the chains above: sdw's skills and hooks run only inside Claude
Code, so a Codex or Antigravity session follows the same files by hand and the project's own rules still apply.

## Limits

- Antigravity and Codex run without any hooks or gates your Claude Code setup enforces. Review what they report.
- Quota windows differ by plan, and behaviour on Claude Pro is untested; run `ai-quota --subs` once and look at what
  your plan actually returns before you trust a pick.
- Which test data you may create, and on which environment, is set by your project, not by this tool.
