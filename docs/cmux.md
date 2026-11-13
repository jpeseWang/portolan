# cmux — parallel agents, one worktree per tab

With several agents running at once the bottleneck stops being how fast an agent codes and
becomes your attention and the isolation between working trees. cmux (a macOS terminal on
libghostty: vertical tabs showing branch, directory, ports and notifications, a CLI and an
in-app browser) makes both visible. Any agent runs in a pane.

## One worktree per tab

Two agents in one working tree corrupt each other's edits. Give each its own worktree:

```bash
sdw-wt add PROJ-123                     # sibling ../<repo>-PROJ-123 on a new branch
sdw-wt add PROJ-123 --branch PROJ-123-csv-export --base origin/main
sdw-wt list
sdw-wt rm PROJ-123                      # refuses a dirty tree without --force
```

`/sdw:plan` offers this when you say the work runs in parallel. `sdw-wt` copies untracked
`.env*` files, installs dependencies offline, and registers the path so `/sdw:wrap` and
`/sdw:offboard` can remove it. Every worktree shares the main checkout's `.sdw/`.

Keep one tab on the main checkout with no agent in it: that is where you review, read
`git log` and think.

## Rules that bite

1. **Non-overlapping scope, decided by you.** Split by file boundary, not by feature. If you
   cannot state the boundary in one sentence, run the tasks in sequence.
2. **Dependencies are per worktree.** Each needs its own `node_modules` (pnpm makes that cheap).
3. **The parallel-agent rules in [core.md](../plugin/rules/core.md) apply**: one stack owner
   (`lsof -nP -iTCP -sTCP:LISTEN` first), no stash, stage by path, re-measure budgets, confirm the
   PR head after a push.
4. **Merge order is yours.** Land one branch, rebase the others, then ship them.
5. **Review does not parallelise.** Two or three concurrent tasks is the realistic ceiling.

## Notifications

An agent waiting unnoticed in a background tab is worse than no parallelism. Add to
`~/.claude/settings.json` (user level, never a client repo):

```jsonc
{ "hooks": {
  "Notification": [{ "hooks": [{ "type": "command",
    "command": "cmux notify --title 'Claude needs input' --body \"$(basename \"$PWD\")\"" }] }],
  "Stop": [{ "hooks": [{ "type": "command",
    "command": "cmux notify --title 'Claude done' --body \"$(git symbolic-ref --short -q HEAD)\"" }] }]
} }
```

## CLI

```bash
cmux list-workspaces
cmux identify --json          # which pane and workspace am I in
cmux notify --title "Build complete" --body "..."
cmux --help                   # splits, send-input, capture, screenshots
```

Configuration lives in two places: `~/.config/ghostty/config` (theme, font, colours: cmux
renders through libghostty) and `~/.config/cmux/cmux.json` (sidebar, tabs, splits). Plain
Ghostty is enough for one agent; cmux pays off once you run two or more.

## When a CLI is missing in cmux

`claude not found` (or any agent CLI) in cmux while Terminal finds it is a PATH problem. Compare
`echo $PATH` in both. For CLIs installed through nvm, make `~/.zshrc` load nvm:

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
```

For a standalone binary, `export PATH="$HOME/.local/bin:$PATH"`. Then `source ~/.zshrc`,
`hash -r`, and quit cmux completely before reopening it.

## Handing a task to another agent

When one agent runs out of budget mid-task, ask it before you leave:

```text
Write a concise handoff to .sdw/work/<branch>/handoff.md for the next coding agent: current
goal, completed work, files changed, important decisions, remaining tasks, known bugs, failing
tests, exact verification commands. Make no code changes after writing it.
```

Then check `git status` and `git diff` yourself, start the next agent in the same worktree, and
tell it to read `.sdw/work/<branch>/` (plan, cases, handoff) and the current diff, verify the
existing changes before touching anything, and not redo completed work.

## Optional tools

Software you run around the plugin, not part of it. All third-party: read one before running it.
Add each only when you feel the specific pain.

- **Voice input** ([OpenSuperWhisper](https://github.com/starmel/OpenSuperWhisper) or any local
  dictation): describing a task out loud is several times faster than typing it. Cheapest win here.
- **[firstmate](https://github.com/kunchenguid/firstmate)**: one liaison agent splits the work,
  hands each piece to a crewmate in its own worktree and escalates only collisions. The running
  version of this page; reach for it when juggling tabs becomes the job.
- **[treehouse](https://github.com/kunchenguid/treehouse)**: a pool of warm worktrees that keeps
  dependencies and build caches, so a new tab does not pay `npm install` again (`sdw-wt` creates
  plain ones).
- **[gnhf](https://github.com/kunchenguid/gnhf)** and
  **[no-mistakes](https://github.com/kunchenguid/no-mistakes)**: an overnight loop and an AI gate at
  `git push`. Both overlap `/sdw:ship` and CI; keep CI as the judge the agent cannot edit.
- **[AXI](https://axi.md)**: design principles for CLIs an agent drives (terse output, structured
  errors). Read before writing the next internal tool.
