# Onboard notes — stack heuristics

## Fast gates
- Next.js: never `next build` as a fast gate; it rewrites `.next/` under a running `next dev`. Use `tsc --noEmit` + `eslint`.
- .NET: never a plain `dotnet build` while `dotnet run`/`watch` holds the outputs. Use `dotnet build <proj>.csproj --no-restore -o "$TMPDIR/sdw-build"` (`-o` on a .sln errors on SDK 8+; pick the project).
- Vite/Vue: `vue-tsc --noEmit` (or `tsc --noEmit`) + `eslint`; `vite build` belongs to the full gate.
- Python: `ruff check` + `mypy`/`pyright` if the repo configures them; pytest is full.
- A fast gate that needs a DB, Docker or network is a full gate.

## Full gates (mirror CI, locally runnable steps only)
- Install steps are not gates (`npm ci`, `pnpm install --frozen-lockfile`, `dotnet restore`): they rewrite dependencies under running servers and need the network. Mirror only the check steps.
- Format check exactly as CI: `prettier --check`, `dotnet format --verify-no-changes`, CSharpier (`dotnet csharpier check .` on 1.x, `dotnet csharpier --check .` before 1.0).
- commitlint when CI runs it: `npx commitlint --from origin/<base> --to HEAD`.
- Codegen drift: `<generate> && git diff --exit-code <generated dir>`.
- EF Core 8+: `dotnet ef migrations has-pending-model-changes` (needs the startup project args the repo uses).
- Prisma: `prisma migrate diff --exit-code` between migrations and schema (needs a shadow DB URL).
- gitleaks only if CI runs it or the user asks: `gitleaks git --staged --redact` (v8.19+), `gitleaks protect --staged --redact` before.

## Red on base
- Narrow first (one project, one lint rule set). Otherwise `sdw-gate --write-baseline <key> [--full]` from a clean base checkout; recognised diagnostics: tsc `error TS…`, MSBuild `error CS…/warning CS…`, eslint `--format unix`.
- eslint lines are recognised only in `--format unix` (built in up to eslint 8; a separate package on 9, so on 9 prefer narrowing).

## Monorepos
- Turbo: `turbo run <tasks> --filter=...[HEAD]` (fast) and `--filter=...[origin/<base>]` (full) in one `.` line.
- Nx: `nx affected -t lint,typecheck --base=HEAD` (fast), `-t lint,test,build --base=origin/<base>` (full). `nx show projects` and `nx graph --focus=<p>` give the blast radius for /sdw:plan.
- `nx configure-ai-agents` writes its own CLAUDE.md and .mcp.json; never run it on a client repo without the team's yes.
- No Turbo/Nx: one line per app plus `deps:` from shared packages to their consumers.

## Toolchain
- The lockfile decides the package manager, not the README. `packageManager` in package.json → corepack shims in `.sdw/state/corepack-bin`.
- `global.json` with `rollForward`: an SDK newer in the same feature band is fine; `sdw-toolchain` reports real mismatches only.
- Keep SDKs out of the user's permanent PATH; `.sdw/env.sh` scopes them to this project.

## Team tooling
- A team `/commit` or `/push` usually encodes scoring, ticket prefixes or PR title checks; prefer it (TEAM_SKILLS) over sdw's.
- Required PR checks: `gh api repos/{owner}/{repo}/branches/<base>/protection` (needs admin) or read the workflow names.
