---
name: create-ticket
description: Create a tracker ticket from a template or a QA bug report; show the exact payload, post only on a yes.
argument-hint: "[story|task|bug BUG-nn] <summary>"
disable-model-invocation: true
---

# Create ticket

A ticket is visible to the whole team at once and often cannot be deleted. Run only because
the user typed this command; if you got here on your own, stop and offer the text instead.
References: `${CLAUDE_SKILL_DIR}/../../reference/tracker-jira.md`, `tracker-github.md` beside it.

## 1. Gate and inputs

```bash
sdw-workdir --projdir >/dev/null; echo "projdir=$?"; echo "tracker=$(sdw-cfg TRACKER) team=$(sdw-cfg TEAM_SKILLS)"
WD=$(sdw-workdir) && echo "draft=$WD/ticket-draft.md"
```

projdir=3 → "run /sdw:onboard first", stop. team has `create-ticket`, no `--anyway` → say `this repo
has its own ticket command, use it`, stop. `$ARGUMENTS`: type `story`, `task` (default) or `bug
BUG-nn`; the rest is the summary. Empty → ask. Later blocks start with `WD=$(sdw-workdir) &&`.

## 2. Draft `$WD/ticket-draft.md` (light markdown, English)

- Summary: one imperative line, ≤80 chars, no key prefix.
- Story/Task: `## Context` (what and why, from the user or plan.md), `## Acceptance criteria`
  as `- Given … when … then …`, links. Never invent criteria: leave the section out and say so.
- Bug from `$WD/bugs/BUG-nn.md`: summary from `Title:`; sections Environment, Preconditions,
  Steps (numbered), Expected (with its source), Actual (verbatim, fenced), Evidence, Repro rate,
  Regression vs base. Strip workflow ids (BUG-nn, TC-nn, AC-n, S1–S4, lanes), local paths,
  `.sdw` references, cookies, tokens and test-user secrets. Severity becomes one plain
  sentence of impact. Screenshots are attached by the user afterwards; say which ones.

## 3. Preview the exact payload

- jira: `sdw-jira sprint` (one → use it; none → backlog, say so; several → ask), then
  `WD=$(sdw-workdir) && sdw-jira create --type <Story|Task|Bug> --summary '<summary>' --description-file "$WD/ticket-draft.md" --assignee me [--sprint <id>] --dry-run`
  and show its whole output.
- github: show the title, the file, and the exact command
  `WD=$(sdw-workdir) && gh issue create --title '<summary>' --body-file "$WD/ticket-draft.md" --assignee @me [--label bug]`,
  plus, when `GH_PROJECT` is set, the `gh project item-add` from tracker-github.md.
- none: print the summary and draft for the user to paste; stop.

End the preview with: "Issues may not be deletable; a mistaken one needs an admin. Create it?
(yes / edit / no)". Anything but an explicit yes is a no. Edit → change the draft, preview again.

## 4. Create and report

Run the previewed command (with its `WD=$(sdw-workdir) &&` prefix) without `--dry-run`. Jira exit 1 → show its message, fix the field it
names, preview again; never retry blind. Report the key and `<JIRA_BASE_URL>/browse/<KEY>`, or
the issue URL gh printed. If the user is about to work on it: "type /sdw:plan <KEY>".

One ticket per yes. No transitions, comments or issue links as side effects.
