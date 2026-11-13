<!-- reviewed: YYYY-MM-DD | against: <sha> | status: current -->
# Local docs — map

What a person or an agent needs to work here that no live system already holds.
State lives in its source system; this folder holds **pointers, decisions, traps and
synthesis**, each stamped so its age is visible.

## Read order (agent)

1. `STATUS.md` — only if the session hook says it is current; otherwise run `/sdw:sync` first.
2. The latest note in `daily/` — yesterday's "next" is today's start.
3. For a ticket: the live ticket, then `sprints/<current>/`, then the `tech/` doc it touches.

Do not read this whole tree at the start of a session. Open what the task needs.

## What goes where

| Folder | Holds | Stamp | Goes stale? |
|---|---|---|---|
| `overview.md` | business, users, scope, glossary, who decides what | `reviewed` | slowly — review monthly |
| `STATUS.md` | now: sprint, in progress, blockers, next deadline | `reviewed` + `sprint-ends` | daily |
| `tech/` | architecture, how to run, traps with exact error text | `reviewed` + `against` | when the code moves |
| `sprints/<n>/` | sprint goal, ticket notes, demos, test plans | `status: closed` when the sprint ends | no, once closed |
| `decisions/` | one file per decision: what, why, who, source link | none — history | never |
| `daily/YYYY-MM/` | journal: done, decided, learned, blocked, next | none — history | never |
| `refs/` | snapshots of Jira / Figma / Drive with `fetched` + `ttl` | `fetched` | by ttl |

## Rules

- **Link, don't copy.** API spec, code, tickets and designs have a home. Copy only what you
  must have offline, into `refs/`, stamped.
- **Promote out of daily.** A trap goes to `tech/troubleshooting.md`, a decision to
  `decisions/`, a state change to `STATUS.md`. A daily note is an inbox, not memory.
- **Re-verify before telling someone.** A cached fact is fine for orientation; a report,
  PR, comment or standup quotes the live source.
- **Close, don't delete.** An ended sprint folder gets `status: closed`; nobody edits it again.
