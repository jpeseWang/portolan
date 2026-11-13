#!/usr/bin/env bash
# sdw-wt: sibling and throwaway worktrees, .env copy, registry, guarded removal.
. "$(dirname "$0")/_lib.sh"

W="$tmp/work space"
mkdir -p "$W/.sdw"
mkrepo "$W/web"
printf 'SECRET_NAME=x\n' > "$W/web/.env.local"
mkdir -p "$W/web/apps/site" && printf 'A=1\n' > "$W/web/apps/site/.env"
export TMPDIR="$tmp/t"; mkdir -p "$TMPDIR"
cd "$W/web" || exit 1

expect_rc 0 "add sibling" sdw-wt add KEY-1 --no-deps
SIB=$(printf '%s\n' "$OUT" | tail -n 1)
[ "$SIB" = "$W/web-KEY-1" ] && [ -d "$SIB" ] || fail "sibling path" "$OUT"
[ "$(cd "$SIB" && git symbolic-ref --short HEAD)" = KEY-1 ] || fail "sibling branch" "wrong"
[ -f "$SIB/.env.local" ] && [ -f "$SIB/apps/site/.env" ] || fail ".env copy" "missing"
ok "untracked .env files copied"
grep -q "^KEY-1	web	$SIB	KEY-1	" "$W/.sdw/state/worktrees" || fail registry "$(cat "$W/.sdw/state/worktrees")"
ok "registered"
expect_rc 5 "add over an existing path" sdw-wt add KEY-1 --no-deps

expect_rc 0 "add throwaway" sdw-wt add red-1 --detach HEAD --no-deps
THR=$(printf '%s\n' "$OUT" | tail -n 1)
[ "$THR" = "$(cd "$TMPDIR" && pwd -P)/sdw/web-red-1" ] || fail "throwaway path" "$THR"
expect_rc 0 "re-add throwaway replaces it" sdw-wt add red-1 --detach HEAD --no-deps
[ "$(grep -c 'red-1' "$W/.sdw/state/worktrees")" = 1 ] || fail "registry dedupe" "$(cat "$W/.sdw/state/worktrees")"
expect_rc 0 "list" sdw-wt list
[ "$(printf '%s\n' "$OUT" | grep -c .)" = 2 ] || fail list "$OUT"

echo dirty >> "$SIB/README.md"
expect_rc 5 "dirty sibling needs --force" sdw-wt rm KEY-1
[ -d "$SIB" ] || fail "dirty sibling" "removed anyway"
expect_rc 0 "rm --force" sdw-wt rm KEY-1 --force
[ ! -d "$SIB" ] || fail "rm" "still there"
(git worktree list --porcelain | grep -q "web-KEY-1") && fail "prune" "still registered in git"
grep -q KEY-1 "$W/.sdw/state/worktrees" && fail "registry drop" "row left"
ok "removed, pruned, dropped from registry"
expect_rc 0 "rm throwaway (dirty allowed)" sh -c "echo x >> \"$THR/README.md\" && sdw-wt rm red-1"
expect_rc 5 "rm unregistered slug" sdw-wt rm nope
printf 'main\tweb\t%s\tmain\tx\n' "$W/web" >> "$W/.sdw/state/worktrees"
expect_rc 5 "rm refuses the main checkout" sdw-wt rm main
expect_rc 2 "bad slug" sdw-wt add ../x
expect_rc 2 "usage" sdw-wt
expect_rc 4 "not in a repo" sh -c "cd \"$tmp\" && sdw-wt add x"

# A dirty sibling stays protected when the throwaway root ($TMPDIR/sdw) does not exist.
export TMPDIR="$tmp/t2"; mkdir -p "$TMPDIR"
cd "$W/web" || exit 1
expect_rc 0 "add sibling without a throwaway root" sdw-wt add KEY-2 --no-deps
SIB2=$(printf '%s\n' "$OUT" | tail -n 1)
[ ! -e "$TMPDIR/sdw" ] || fail "setup" "throwaway root exists"
echo dirty >> "$SIB2/README.md"
expect_rc 5 "dirty sibling needs --force without a throwaway root" sdw-wt rm KEY-2
[ -d "$SIB2" ] || fail "dirty sibling without a throwaway root" "removed anyway"
expect_rc 0 "rm --force without a throwaway root" sdw-wt rm KEY-2 --force
