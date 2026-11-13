#!/usr/bin/env bash
# sdw-workdir: projdir from repo root, non-git parent, sibling and $TMPDIR worktrees; repos; branch slug; phase.
. "$(dirname "$0")/_lib.sh"

# Layout A: .sdw/ in a single repo, plus a sibling worktree next to it.
A="$tmp/solo repo"
mkrepo "$A"
mkdir -p "$A/.sdw" "$A/src/deep"
(cd "$A" && git worktree add -b feat/x "$tmp/solo repo-x" main >/dev/null 2>&1) || fail setup "sibling worktree"
THROW=$(mktemp -d "${TMPDIR:-/tmp}/sdw-tests-throw.XXXXXX"); rm -rf "$THROW"
(cd "$A" && git worktree add --detach "$THROW" HEAD >/dev/null 2>&1) || fail setup "throwaway worktree"
trap 'rm -rf "$tmp" "$THROW"' EXIT

expect_rc 0 "projdir from repo root" sh -c "cd \"$A\" && sdw-workdir --projdir"
[ "$OUT" = "$A" ] || fail "projdir from repo root" "got $OUT"
expect_rc 0 "projdir from a subdir" sh -c "cd \"$A/src/deep\" && sdw-workdir --projdir"
[ "$OUT" = "$A" ] || fail "projdir from a subdir" "got $OUT"
expect_rc 0 "projdir from sibling worktree" sh -c "cd \"$tmp/solo repo-x\" && sdw-workdir --projdir"
[ "$OUT" = "$A" ] || fail "projdir from sibling worktree" "got $OUT"
expect_rc 0 "projdir from \$TMPDIR throwaway worktree" sh -c "cd \"$THROW\" && sdw-workdir --projdir"
[ "$OUT" = "$A" ] || fail "projdir from throwaway" "got $OUT"
expect_rc 0 "work dir in sibling worktree uses its branch" sh -c "cd \"$tmp/solo repo-x\" && sdw-workdir"
[ "$OUT" = "$A/.sdw/work/feat__x" ] && [ -d "$OUT" ] || fail "work dir slug" "got $OUT"
expect_rc 0 "detached HEAD slug" sh -c "cd \"$THROW\" && sdw-workdir --branch"
case "$OUT" in detached-???????) ok "detached slug $OUT" ;; *) fail "detached slug" "got $OUT" ;; esac
expect_rc 0 "repos of a repo-root projdir" sh -c "cd \"$A\" && sdw-workdir --repos"
[ "$OUT" = "$A" ] || fail "repos of repo-root" "got $OUT"

# Layout B: non-git workspace parent holding two repos, one nested two levels, plus noise.
B="$tmp/work space"
mkdir -p "$B/.sdw" "$B/apps" "$B/node_modules/pkg"
mkrepo "$B/web"
mkrepo "$B/apps/api"
mkrepo "$B/node_modules/pkg"
printf 'gitdir: /nowhere\n' > "$B/apps/.git"
expect_rc 0 "projdir from repo in workspace parent" sh -c "cd \"$B/web/src\" && sdw-workdir --projdir"
[ "$OUT" = "$B" ] || fail "projdir workspace" "got $OUT"
expect_rc 0 "projdir from non-git parent itself" sh -c "cd \"$B\" && sdw-workdir --projdir"
[ "$OUT" = "$B" ] || fail "projdir parent" "got $OUT"
expect_rc 0 "repos in workspace parent" sh -c "cd \"$B\" && sdw-workdir --repos"
[ "$OUT" = "$(printf '%s\n%s' "$B/apps/api" "$B/web")" ] || fail "repos list" "got $OUT"
expect_rc 4 "ambiguous repo from parent with two repos" sh -c "cd \"$B\" && sdw-workdir"
expect_rc 0 "work dir from inside a repo" sh -c "cd \"$B/web\" && sdw-workdir --no-create"
[ "$OUT" = "$B/.sdw/work/main" ] && [ ! -d "$OUT" ] || fail "--no-create" "got $OUT"

# One repo under a parent: the parent resolves the branch.
C="$tmp/one"
mkdir -p "$C/.sdw"
mkrepo "$C/only" dev
expect_rc 0 "single repo under parent resolves branch" sh -c "cd \"$C\" && sdw-workdir --branch"
[ "$OUT" = dev ] || fail "single repo branch" "got $OUT"
# With a linked worktree the parent cannot tell which checkout is meant: no silent main checkout.
(cd "$C/only" && git worktree add -b feat/y "$C/only-y" dev >/dev/null 2>&1) || fail setup "linked worktree under parent"
expect_rc 4 "parent of a repo with a linked worktree is ambiguous" sh -c "cd \"$C\" && sdw-workdir --branch"
case "$OUT" in *"linked worktree"*) ok "ambiguity names the linked worktree" ;; *) fail "ambiguity message" "$OUT" ;; esac
expect_rc 4 "work dir from that parent is ambiguous too" sh -c "cd \"$C\" && sdw-workdir --no-create"
expect_rc 0 "linked worktree resolves its own branch" sh -c "cd \"$C/only-y\" && sdw-workdir --branch"
[ "$OUT" = feat__y ] || fail "linked worktree branch" "got $OUT"
expect_rc 0 "main checkout still resolves its branch" sh -c "cd \"$C/only\" && sdw-workdir --branch"
[ "$OUT" = dev ] || fail "main checkout branch" "got $OUT"
expect_rc 0 "projdir still resolves from the parent" sh -c "cd \"$C\" && sdw-workdir --projdir"

# Not onboarded, and the CLAUDE_PROJECT_DIR fallback.
mkrepo "$tmp/plain"
expect_rc 3 "not onboarded" sh -c "cd \"$tmp/plain\" && sdw-workdir --projdir"
mkdir -p "$tmp/nogit"
expect_rc 0 "CLAUDE_PROJECT_DIR fallback" sh -c "cd \"$tmp/nogit\" && CLAUDE_PROJECT_DIR=\"$B\" sdw-workdir --projdir"
[ "$OUT" = "$B" ] || fail "fallback" "got $OUT"
expect_rc 3 "CLAUDE_PROJECT_DIR without .sdw" sh -c "cd \"$tmp/nogit\" && CLAUDE_PROJECT_DIR=\"$tmp/plain\" sdw-workdir --projdir"

# Walking up stops at $HOME.
mkdir -p "$HOME/.sdw" "$HOME/proj"
mkrepo "$HOME/proj/r"
expect_rc 3 "walk stops before \$HOME" sh -c "cd \"$HOME/proj/r\" && sdw-workdir --projdir"

# QA phase.
expect_rc 0 "phase defaults to none" sh -c "cd \"$A\" && sdw-workdir --phase"
[ "$OUT" = none ] || fail "phase none" "got $OUT"
expect_rc 0 "phase write" sh -c "cd \"$A\" && sdw-workdir --phase design"
expect_rc 0 "phase read" sh -c "cd \"$A\" && sdw-workdir --phase"
[ "$OUT" = design ] || fail "phase read" "got $OUT"
expect_rc 2 "phase bad value" sh -c "cd \"$A\" && sdw-workdir --phase later"
expect_rc 2 "unknown flag" sdw-workdir --nope
expect_rc 0 "help" sdw-workdir -h
