#!/usr/bin/env bash
# sdw-redcheck: real python unittest project plus stub commands for each result class.
. "$(dirname "$0")/_lib.sh"

proj="$tmp/my proj"
r="$proj/calc repo"
new_repo "$r"
mkdir -p "$r/tests" "$proj/.sdw"
echo ".sdw/" >>"$r/.git/info/exclude"
cat >"$r/calc.py" <<'EOF'
def clamp(x, lo, hi):
    return max(lo, x)
EOF
touch "$r/tests/__init__.py"
cat >"$r/tests/test_old.py" <<'EOF'
import unittest
from calc import clamp


class Old(unittest.TestCase):
    def test_low(self):
        self.assertEqual(clamp(-1, 0, 3), 0)
EOF
commit_all "$r" base
(cd "$r" && git checkout -q -b fix/clamp)
cat >"$r/calc.py" <<'EOF'
def clamp(x, lo, hi):
    return min(hi, max(lo, x))


def double(x):
    return 2 * x
EOF
cat >"$r/tests/test_clamp.py" <<'EOF'
import unittest
from calc import clamp


class Clamp(unittest.TestCase):
    def test_high(self):
        self.assertEqual(clamp(5, 0, 3), 3)
EOF
cat >"$r/tests/test_double.py" <<'EOF'
import unittest
from calc import double


class Double(unittest.TestCase):
    def test_double(self):
        self.assertEqual(double(2), 4)
EOF
cat >"$r/tests/test_still_green.py" <<'EOF'
import unittest
from calc import clamp


class Green(unittest.TestCase):
    def test_mid(self):
        self.assertEqual(clamp(1, 0, 3), 1)
EOF
UT="python3 -m unittest"
rc_in() { local d=$1; shift; (cd "$d" && "$@"); }
no_leftovers() {
  local n; n=$(cd "$r" && git worktree list --porcelain | grep -c '^worktree ')
  [ "$n" = 1 ] || fail "$1" "worktree left behind: $(cd "$r" && git worktree list)"
  [ -z "$(ls -A "${TMPDIR%/}/sdw" 2>/dev/null)" ] || fail "$1" "files left in ${TMPDIR%/}/sdw"
}

expect_rc branch-green 0 rc_in "$r" $UT tests.test_clamp; ok branch-green

expect_rc assertion 0 rc_in "$r" sdw-redcheck main --test tests/test_clamp.py -- $UT tests.test_clamp
[ "$(printf '%s\n' "$out" | tail -n 1)" = "RESULT: RED(assertion)" ] || fail assertion "$out"
no_leftovers assertion
ev=$(cat "$proj"/.sdw/work/*/evidence.jsonl 2>/dev/null)
printf '%s\n' "$ev" | grep -q '"kind": *"redcheck"' || fail assertion-evidence "no redcheck entry: $ev"
printf '%s\n' "$ev" | grep -q 'RED(assertion)' || fail assertion-evidence "$ev"
printf '%s\n' "$ev" | grep -q 'tests/test_clamp.py' || fail assertion-evidence "$ev"
ok assertion

expect_rc import-error 1 rc_in "$r" sdw-redcheck main --test tests/test_double.py -- $UT tests.test_double
[ "$(printf '%s\n' "$out" | tail -n 1)" = "RESULT: RED(build/import)" ] || fail import-error "$out"
ok import-error

expect_rc green-on-base 1 rc_in "$r" sdw-redcheck main --test tests/test_still_green.py -- $UT tests.test_still_green
[ "$(printf '%s\n' "$out" | tail -n 1)" = "RESULT: GREEN" ] || fail green-on-base "$out"
ok green-on-base

expect_rc from-subdir 0 rc_in "$r/tests" sdw-redcheck main --test test_clamp.py --app . -- $UT tests.test_clamp
ok from-subdir

expect_rc base-code 0 rc_in "$r" sdw-redcheck main --test tests/test_clamp.py -- \
  sh -c '[ "$SDW_REDCHECK" = 1 ] || exit 0; grep -q "min(hi" calc.py && exit 0; echo AssertionError; exit 1'
ok runs-base-code-with-env-flag

stub_class() {
  local name=$1 want=$2 rc=$3 text=$4
  expect_rc "$name" "$rc" rc_in "$r" sdw-redcheck main --test tests/test_clamp.py -- sh -c "echo '$text'; exit 3"
  [ "$(printf '%s\n' "$out" | tail -n 1)" = "RESULT: $want" ] || fail "$name" "$out"
  ok "$name"
}
stub_class ts-module "RED(build/import)" 1 "src/a.test.ts(1,20): error TS2307: Cannot find module './b'"
stub_class cs-type "RED(build/import)" 1 "Foo.cs(3,5): error CS0246: The type or namespace name 'Bar' could not be found"
stub_class conn-refused "RED(setup)" 1 "Error: connect ECONNREFUSED 127.0.0.1:5432"
stub_class route-missing "RED(setup)" 1 "Cannot POST /api/orders"
stub_class jest-expect "RED(assertion)" 0 "expect(received).toBe(expected)"
stub_class unknown "RED(unknown)" 1 "Segmentation fault"
no_leftovers stubs

mut() {
  printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -%s @@\n%s\n' "$1" "$1" "$1" "$1" "$2" "$3" >"$tmp/$4.patch"
}
mut calc.py '5,2 +5,2' ' def double(x):
-    return 2 * x
+    return 3 * x' double
expect_rc mutation 0 rc_in "$r" sdw-redcheck --mutate "$tmp/double.patch" --test tests/test_double.py -- $UT tests.test_double
[ "$(printf '%s\n' "$out" | tail -n 1)" = "RESULT: RED(mutation)" ] || fail mutation "$out"
grep -q 'return 2 \* x' "$r/calc.py" || fail mutation "patch reached the real working tree"
ev=$(grep 'RED(mutation)' "$proj"/.sdw/work/*/evidence.jsonl 2>/dev/null)
printf '%s\n' "$ev" | grep -q '"detail": *"mutation [0-9a-f]* exit 1: calc.py: -    return 2 \* x +    return 3 \* x"' || fail mutation-evidence "$ev"
printf '%s\n' "$ev" | grep -q '"paths": *\["tests/test_double.py"\]' || fail mutation-evidence "$ev"
no_leftovers mutation
ok mutation

mut calc.py '1,3 +1,3' ' def clamp(x, lo, hi):
-    return min(hi, max(lo, x))
+    return max(lo, x)
 ' clamp
expect_rc mutation-survives 1 rc_in "$r" sdw-redcheck --mutate "$tmp/clamp.patch" --test tests/test_double.py -- $UT tests.test_double
[ "$(printf '%s\n' "$out" | tail -n 1)" = "RESULT: GREEN" ] || fail mutation-survives "$out"
ok mutation-survives

mut calc.py '5,2 +5,2' ' def double(x):
-    return 2 * x
+    return 2 *' broken
expect_rc mutation-breaks-build 1 rc_in "$r" sdw-redcheck --mutate "$tmp/broken.patch" --test tests/test_double.py -- $UT tests.test_double
[ "$(printf '%s\n' "$out" | tail -n 1)" = "RESULT: RED(build/import)" ] || fail mutation-breaks-build "$out"
ok mutation-breaks-build

mut tests/test_double.py '7,1 +7,1' '-        self.assertEqual(double(2), 4)
+        self.assertEqual(double(2), 5)' test-edit
expect_rc mutation-touches-test 5 rc_in "$r" sdw-redcheck --mutate "$tmp/test-edit.patch" --test tests/test_double.py -- $UT tests.test_double
grep -q 'test paths' "$tmp/err" || fail mutation-touches-test "$(cat "$tmp/err")"
ok mutation-touches-test
mut 'tests/tést_x.py' '1,1 +1,1' '-a = 1
+a = 2' non-ascii
expect_rc mutation-non-ascii-test-path 5 rc_in "$r" sdw-redcheck --mutate "$tmp/non-ascii.patch" --test tests/test_double.py -- $UT tests.test_double
grep -q 'test paths' "$tmp/err" || fail mutation-non-ascii-test-path "$(cat "$tmp/err")"
ok mutation-non-ascii-test-path
printf 'diff --git a/tests/test_double.py b/calc2.py\nsimilarity index 90%%\nrename from tests/test_double.py\nrename to calc2.py\n--- a/tests/test_double.py\n+++ b/calc2.py\n@@ -1 +1 @@\n-import unittest\n+import os\n' >"$tmp/rename.patch"
expect_rc mutation-rename 5 rc_in "$r" sdw-redcheck --mutate "$tmp/rename.patch" --test tests/test_double.py -- $UT tests.test_double
grep -q 'renames or copies' "$tmp/err" || fail mutation-rename "$(cat "$tmp/err")"
ok mutation-rename
mut calc.py '5,2 +5,2' ' def triple(x):
-    return 3 * x
+    return 4 * x' stale
expect_rc mutation-does-not-apply 4 rc_in "$r" sdw-redcheck --mutate "$tmp/stale.patch" --test tests/test_double.py -- $UT tests.test_double
ok mutation-does-not-apply
printf 'not a patch\n' >"$tmp/junk.patch"
expect_rc mutation-junk 4 rc_in "$r" sdw-redcheck --mutate "$tmp/junk.patch" --test tests/test_double.py -- $UT tests.test_double
ok mutation-junk
expect_rc mutation-missing 4 rc_in "$r" sdw-redcheck --mutate "$tmp/nope.patch" --test tests/test_double.py -- true
ok mutation-missing
expect_rc mutation-and-base 2 rc_in "$r" sdw-redcheck main --mutate "$tmp/double.patch" --test tests/test_double.py -- true
ok mutation-and-base
no_leftovers mutation-end

cat >"$r/tests/test_db.py" <<'EOF'
import os
import unittest

DATABASE_URL = os.environ.get("DATABASE_URL")


class Db(unittest.TestCase):
    def test_noop(self):
        self.assertIsNone(None)
EOF
expect_rc db-refused 5 rc_in "$r" sdw-redcheck main --test tests/test_db.py -- $UT tests.test_db
grep -q "test-db" "$tmp/err" || fail db-refused "$(cat "$tmp/err")"
ok db-refused
printf '## app: api\n- path: other:.\n- test-db: sqlite\n## app: calc\n- path: calc repo:.\n- test-db: none\n' >"$proj/.sdw/run.md"
expect_rc db-refused-by-app-section 5 rc_in "$r" sdw-redcheck main --test tests/test_db.py -- $UT tests.test_db
ok db-refused-by-app-section
printf '## app: calc\n- path: calc repo:.\n- test-db: sqlite\n' >"$proj/.sdw/run.md"
expect_rc db-allowed 1 rc_in "$r" sdw-redcheck main --test tests/test_db.py -- $UT tests.test_db
[ "$(printf '%s\n' "$out" | tail -n 1)" = "RESULT: GREEN" ] || fail db-allowed "$out"
ok db-allowed

expect_rc usage-none 2 sdw-redcheck; ok usage-none
expect_rc usage-no-cmd 2 rc_in "$r" sdw-redcheck main --test tests/test_clamp.py; ok usage-no-cmd
expect_rc usage-no-test 2 rc_in "$r" sdw-redcheck main -- true; ok usage-no-test
expect_rc help 0 sdw-redcheck -h; ok help
expect_rc unknown-base 4 rc_in "$r" sdw-redcheck nope --test tests/test_clamp.py -- true; ok unknown-base
expect_rc missing-test 4 rc_in "$r" sdw-redcheck main --test tests/nope.py -- true; ok missing-test
no_leftovers end
echo "PASS test-redcheck"
