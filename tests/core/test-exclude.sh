#!/usr/bin/env bash
# sdw-exclude: idempotent block in info/exclude of every repo, worktree-safe, --check, --remove, --legacy.
. "$(dirname "$0")/_lib.sh"

W="$tmp/work space"
mkdir -p "$W/.sdw"
mkrepo "$W/web"
mkrepo "$W/api"
(cd "$W/web" && git worktree add -b feat "$W/web-feat" main >/dev/null 2>&1) || fail setup worktree
printf 'user-pattern\n' > "$W/web/.git/info/exclude"
cd "$W" || exit 1

expect_rc 1 "--check before" sdw-exclude --check
expect_rc 0 "write" sdw-exclude
printf '%s\n' "$OUT" | grep -q "^added $W/web/.git/info/exclude" || fail write "$OUT"
cp "$W/web/.git/info/exclude" "$tmp/first"
expect_rc 0 "second write" sdw-exclude
printf '%s\n' "$OUT" | grep -q '^unchanged' && ! printf '%s\n' "$OUT" | grep -qv '^unchanged' || fail idempotent "$OUT"
cmp -s "$tmp/first" "$W/web/.git/info/exclude" || fail idempotent "file changed"
[ "$(grep -c '^# >>> sdw >>>$' "$W/web/.git/info/exclude")" = 1 ] || fail idempotent "duplicate block"
grep -qx user-pattern "$W/web/.git/info/exclude" || fail "keeps user lines" "lost"
ok "keeps user lines"
expect_rc 0 "--check after" sdw-exclude --check

mkdir -p "$W/web/.sdw/x" "$W/web/e2e/.auth"
touch "$W/web/.sdw/x/f" "$W/web/e2e/.auth/admin.json"
[ -z "$(cd "$W/web" && git status --porcelain)" ] || fail "git status clean" "$(cd "$W/web" && git status --porcelain)"
ok "git status clean with .sdw/ and e2e/.auth/"
expect_rc 0 "from a sibling worktree writes the common dir" sh -c "cd \"$W/web-feat\" && sdw-exclude \"$W/web-feat\""
printf '%s\n' "$OUT" | grep -q "unchanged $W/web/.git/info/exclude" || fail "worktree common dir" "$OUT"

expect_rc 0 "remove" sdw-exclude --remove
grep -q 'sdw' "$W/web/.git/info/exclude" && fail remove "block left"
grep -qx user-pattern "$W/web/.git/info/exclude" || fail remove "user line lost"
ok "remove keeps user lines"
expect_rc 1 "--check after remove" sdw-exclude --check

printf 'mine\n\n# Solo Dev Workflow — never commit these\nconfig.env\n.claude/\nlocal-docs/\nkeep-me\n' > "$W/api/.git/info/exclude"
expect_rc 0 "legacy" sdw-exclude --legacy "$W/api"
want=$(printf 'mine\nkeep-me\n# >>> sdw >>>\n.sdw/\ne2e/.auth/\nplaywright/.auth/\n.claude/settings.local.json\n# <<< sdw <<<')
[ "$(cat "$W/api/.git/info/exclude")" = "$want" ] || fail legacy "got: $(cat "$W/api/.git/info/exclude")"
ok "legacy block removed, foreign line kept"
expect_rc 4 "not a repo" sdw-exclude "$tmp"
mkdir -p "$tmp/nope"
expect_rc 3 "not onboarded" sh -c "cd \"$tmp/nope\" && sdw-exclude"
