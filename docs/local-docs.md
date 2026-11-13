# Local docs — project notes that admit their age

How to keep sprint notes, daily notes and project docs so an agent gets the overview fast, and
how to stop them from quietly going out of date.

## The failure this prevents

On a real project the instructions said "read STATUS.md first". Seven weeks later STATUS.md was
260 commits behind, still named a sprint that had ended a month earlier, and two instruction
files disagreed on whether the API spec or the code won. Every session started by loading
confident, wrong context. Making age visible fixed it; more tooling would not have.

## Two kinds of knowledge

| Kind | Examples | Lives in | Local docs hold |
|---|---|---|---|
| **State**: changes daily, has an owner system | branch, PRs, ticket status, sprint, API shape, design frames | git, tracker, spec file, design tool | a pointer, or a stamped snapshot |
| **Understanding**: nobody else stores it | why a decision was made, a trap and its exact error, who decides what | nowhere, unless you write it | the thing itself |

Most stale-doc pain comes from writing state into documents as if it were understanding.

## Layout and freshness

`/sdw:onboard` offers the scaffold (default yes for a non-git workspace parent) and copies it to
`DOCS_DIR`; its map, read order and promotion rules are in
[the scaffold README](../plugin/skills/onboard/local-docs/README.md). Keep it outside the client's
git. Each doc carries one `<!-- reviewed: … -->` or `<!-- fetched: … -->` marker near the top;
`sdw-docs-freshness -h` lists the fields and verdicts. When `DOCS_DIR` exists and something is off,
session-start adds at most two `--brief` lines.

## Should the agent fetch tracker, design and specs automatically?

**Fetch on use, check age on start, never poll everything every session.**

| Source | Cost | Policy | Snapshot TTL |
|---|---|---|---|
| git, PRs, CI | free | always live; never cached in docs | — |
| API spec in the repo | free | read live; `/sdw:sync` lists what changed | — |
| Tracker | cheap, rate-limited | live when starting a ticket and before telling people anything; `/sdw:sync` writes a snapshot | 1 working day |
| Design | scarce: seat quotas, hard rate limits | only frames for active tickets, through `sdw-figma-png` (re-fetched only when the file changed) | until the file changes |
| Drive, meeting notes | manual | export once into `decisions/` or `refs/` with a stamp | review monthly |

Why not fetch everything at session start: quota (one eager hook can spend a month of design
calls in a morning), context (thirty tickets crowd out the code), injection surface (ticket and
comment text is written by other people and stays data), and false confidence (an auto-refreshed
doc looks current while its hand-written parts are old).

A morning `/sdw:sync` on a schedule is fine for the cheap sources. Design never runs on one.
