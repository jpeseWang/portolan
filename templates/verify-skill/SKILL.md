---
name: verify
description: Check the change before any git commit, including one made through a repo's own commit command. Runs gates and the weakened-test scan; never commits.
---
<!-- sdw-verify-skill -->
Run from the repo or worktree you are about to commit in. Report results; do not commit, stage or fix anything here.

1. Project check:
   ```bash
   sdw-workdir --projdir
   ```
   Exit 3: say "no sdw project, nothing to verify" and stop. Command not found: say "sdw plugin not installed, nothing verified" and stop.

2. Gate (fresh stamp, else the fast gate):
   ```bash
   sdw-gate --check || sdw-gate --fast
   ```

3. Weakened tests in what is staged:
   ```bash
   sdw-tamper --staged
   ```

4. Report, one line each: `gate: green|red <keys>`, `tamper: none|<n> hits`.
   - Red gate: show the failing output; the commit should wait. Fix the cause, never the test, lint rule or type.
   - Tamper hits: each needs `TEST WEAKENED: <file> — <why>` from the author, or a revert.
