#!/usr/bin/env bash
# sdw-tamper: test-path classifier, every hit kind, false positives, modes and exit codes.
. "$(dirname "$0")/_lib.sh"

# --- classifier
want="src/a.test.ts
src/a.spec.tsx
pkg/calc_test.go
tests/helpers.py
test_calc.py
Api/CalcTest.cs
Api/CalcTests.cs
src/__snapshots__/a.test.ts.snap
src/__tests__/a.ts
e2e/login.ts
Api.Tests/Fixture.cs
spec/models/user_rb.rb
web/home.spec.ts-snapshots/home.png"
got=$(printf '%s\n' "$want" src/a.ts src/testing.ts README.md Api/Calc.cs src/latest/x.ts \
  .sdw/work/b/a.test.ts "my app/x.ts" | sdw-tamper --test-paths)
[ "$got" = "$want" ] || fail classifier "got: $got"
ok classifier

# --- base fixture
base="$tmp/base"
new_repo "$base"
mkdir -p "$base/src/__snapshots__" "$base/e2e/home.spec.ts-snapshots" "$base/tests" "$base/Api.Tests" "$base/my tests"
cat >"$base/src/math.ts" <<'EOF'
export const add = (a: number, b: number) => a + b;
EOF
cat >"$base/src/util.ts" <<'EOF'
export function check(x: number) {
  assert(x > 0);
}
EOF
cat >"$base/src/math.test.ts" <<'EOF'
import { add } from './math';
describe('add', () => {
  it('adds', () => {
    expect(add(1, 1)).toBe(2);
    expect(add(2, 2)).toBe(4);
  });
  it('handles zero', () => {
    expect(add(0, 0)).toBe(0);
  });
});
EOF
echo 'exports[`add 1`] = `2`;' >"$base/src/__snapshots__/math.test.ts.snap"
printf '\211PNG\000\001\002' >"$base/e2e/home.spec.ts-snapshots/home.png"
cat >"$base/playwright.config.ts" <<'EOF'
export default {
  timeout: 5000,
  expect: { toHaveScreenshot: { maxDiffPixels: 10 } },
};
EOF
cat >"$base/jest.config.js" <<'EOF'
module.exports = {
  coverageThreshold: {
    global: {
      branches: 80,
    },
  },
};
EOF
cat >"$base/tests/test_calc.py" <<'EOF'
import unittest


class T(unittest.TestCase):
    def test_a(self):
        self.assertEqual(1, 1)

    def test_b(self):
        self.assertEqual(2, 2)
EOF
touch "$base/tests/__init__.py"
cat >"$base/Api.Tests/CalcTests.cs" <<'EOF'
public class CalcTests
{
    [Fact]
    public void Adds() { Assert.Equal(2, 1 + 1); }
}
EOF
echo "test('x', () => { expect(1).toBe(1); });" >"$base/my tests/a b.test.js"
echo '# demo' >"$base/README.md"
echo '{"name":"x","version":"1.0.0"}' >"$base/package.json"
commit_all "$base" base

n=0
fresh() { n=$((n + 1)); r="$tmp/r$n"; cp -R "$base" "$r"; }
sub() { python3 - "$r/$1" "$2" "$3" <<'EOF'
import sys
p, a, b = sys.argv[1:]
s = open(p).read()
assert a in s, (p, a)
open(p, "w").write(s.replace(a, b, 1))
EOF
}
# hit <case> <expected line> [mode args]: exit 1 and the exact line among the hits.
hit() {
  local name=$1 line=$2; shift 2
  expect_rc "$name" 1 sh -c 'cd "$1" && shift && sdw-tamper "$@"' _ "$r" "$@"
  printf '%s\n' "$out" | grep -qxF -- "$line" || fail "$name" "missing '$line' in: $out"
  ok "$name"
}
clean() {
  local name=$1; shift
  expect_rc "$name" 0 sh -c 'cd "$1" && shift && sdw-tamper "$@"' _ "$r" "$@"
  [ -z "$out" ] || fail "$name" "unexpected output: $out"
  ok "$name"
}

fresh; clean no-change
fresh; sub src/math.test.ts "it('adds'" "it.only('adds'"
hit only "skip-added src/math.test.ts:3 it.only('adds', () => {"
fresh; sub src/math.test.ts "it('handles zero'" "xit('handles zero'"
hit xit "skip-added src/math.test.ts:7 xit('handles zero', () => {"
fresh; sub tests/test_calc.py "    def test_b" "    @unittest.skip(\"flaky\")
    def test_b"
hit pytest-skip 'skip-added tests/test_calc.py:8 @unittest.skip("flaky")'
fresh; sub Api.Tests/CalcTests.cs "[Fact]" '[Fact(Skip = "later")]'
hit xunit-skip 'skip-added Api.Tests/CalcTests.cs:3 [Fact(Skip = "later")]'
fresh; sub src/math.test.ts "    expect(add(2, 2)).toBe(4);
" ""
hit assert-deleted "assert-removed src/math.test.ts:5 expect(add(2, 2)).toBe(4);"
fresh; sub src/math.test.ts "expect(add(1, 1)).toBe(2)" "expect(add(1, 1)).toBeDefined()"
hit assert-loosened "assert-removed src/math.test.ts:4 expect(add(1, 1)).toBe(2);"
fresh; sub tests/test_calc.py "self.assertEqual(1, 1)" "self.assertTrue(1)"
hit assert-loosened-py "assert-removed tests/test_calc.py:6 self.assertEqual(1, 1)"
fresh; rm "$r/tests/test_calc.py"
hit test-file-deleted "test-deleted tests/test_calc.py:0 (file deleted)"
fresh; sub src/math.test.ts "  it('handles zero', () => {
    expect(add(0, 0)).toBe(0);
  });
" ""
hit test-case-deleted "test-deleted src/math.test.ts:7 it('handles zero', () => {"
fresh; echo 'exports[`add 1`] = `3`;' >"$r/src/__snapshots__/math.test.ts.snap"
hit snapshot-text 'snapshot-changed src/__snapshots__/math.test.ts.snap:1 exports[`add 1`] = `3`;'
fresh; printf '\211PNG\000\001\003' >"$r/e2e/home.spec.ts-snapshots/home.png"
hit snapshot-png "snapshot-changed e2e/home.spec.ts-snapshots/home.png:0 (binary changed)"
fresh; sub playwright.config.ts "timeout: 5000" "timeout: 30_000"
hit timeout-raised "threshold-loosened playwright.config.ts:2 timeout: 5000 -> timeout: 30_000"
fresh; sub playwright.config.ts "maxDiffPixels: 10" "maxDiffPixels: 400"
hit diff-pixels-raised "threshold-loosened playwright.config.ts:3 expect: { toHaveScreenshot: { maxDiffPixels: 10 } } -> expect: { toHaveScreenshot: { maxDiffPixels: 400 } }"
fresh; sub jest.config.js "branches: 80" "branches: 60"
hit coverage-lowered "threshold-loosened jest.config.js:4 branches: 80 -> branches: 60"
fresh; sub src/math.ts "export const add" "// eslint-disable-next-line
export const add"
hit eslint-disable "suppression-added src/math.ts:1 // eslint-disable-next-line"
fresh; sub src/util.ts "  assert(x > 0);" "  // @ts-ignore
  assert(x > 0);"
hit ts-ignore "suppression-added src/util.ts:2 // @ts-ignore"
fresh; printf "it.only('new', () => { expect(1).toBe(1); });\n" >"$r/src/new.test.ts"
hit untracked-only "skip-added src/new.test.ts:1 it.only('new', () => { expect(1).toBe(1); });"
fresh; sub "my tests/a b.test.js" "test('x'" "test.only('x'"
hit path-with-spaces "skip-added my tests/a b.test.js:1 test.only('x', () => { expect(1).toBe(1); });"
fresh; sub src/math.test.ts "it('adds'" "it.only('adds'"; commit_all "$r" weaken
hit range "skip-added src/math.test.ts:3 it.only('adds', () => {" --range HEAD~1..HEAD
clean range-before-weakening --range HEAD~1..HEAD~1
fresh; sub src/math.test.ts "it('adds'" "it.only('adds'"; (cd "$r" && git add src/math.test.ts)
sub src/math.test.ts "it('handles zero'" "it.skip('handles zero'"
hit staged "skip-added src/math.test.ts:3 it.only('adds', () => {" --staged
printf '%s\n' "$out" | grep -q "it.skip" && fail staged-ignores-unstaged "$out"
ok staged-ignores-unstaged

# --- false positives
fresh; printf "it('sub', () => { expect(1).toBe(1); });\n" >"$r/src/sub.test.ts"
echo 'exports[`sub 1`] = `1`;' >"$r/src/__snapshots__/sub.test.ts.snap"
(cd "$r" && git add -A); clean new-test-and-snapshot
fresh; (cd "$r" && git mv src/math.test.ts src/arith.test.ts); clean renamed-test
fresh; sub src/math.test.ts "    expect(add(2, 2)).toBe(4);" "      expect(add(2, 2)).toBe(4) ;"; clean reindented-assert
fresh; sub src/math.test.ts "toBe(4)" "toStrictEqual(4)"; clean assert-swapped-same-strength
fresh; sub src/math.test.ts "  it('adds'" "  it('adds two numbers'"; clean test-renamed
fresh; sub playwright.config.ts "timeout: 5000" "timeout: 1000"; clean timeout-lowered
fresh; sub jest.config.js "branches: 80" "branches: 95"; clean coverage-raised
fresh; printf 'Never use it.only or eslint-disable.\n' >>"$r/README.md"; clean docs-mention
fresh; mkdir -p "$r/.sdw/work/b"; printf "it.only('x', () => {});\n" >"$r/.sdw/work/b/x.test.ts"; clean sdw-dir-skipped
fresh; sub src/util.ts "  assert(x > 0);
" ""; clean assert-removed-from-source
fresh; sub package.json '"1.0.0"' '"1.3.0"'; clean version-bump
fresh; sub src/math.test.ts "    expect(add(2, 2)).toBe(4);
" ""
printf "it('moved', () => {\n    expect(add(2, 2)).toBe(4);\n});\n" >"$r/src/more.test.ts"
(cd "$r" && git add -A); clean assert-moved-to-new-file

r="$tmp/unborn"; new_repo "$r"; printf "it.only('a', () => {});\n" >"$r/a.test.js"; (cd "$r" && git add a.test.js)
hit unborn-staged "skip-added a.test.js:1 it.only('a', () => {});" --staged
hit unborn-default "skip-added a.test.js:1 it.only('a', () => {});"

# --- usage and errors
expect_rc help 0 sdw-tamper -h; ok help
mkdir -p "$tmp/nogit"; expect_rc bad-arg 2 sh -c 'cd "$1" && sdw-tamper --bogus' _ "$tmp/nogit"; ok bad-arg
fresh; expect_rc bad-range 2 sh -c 'cd "$1" && sdw-tamper --range nope..HEAD' _ "$r"; ok bad-range
expect_rc not-a-repo 4 sh -c 'cd "$1" && sdw-tamper' _ "$tmp/nogit"; ok not-a-repo
fresh; mkdir -p "$r/src/deep"; expect_rc from-subdir 1 sh -c 'cd "$1/src/deep" && printf "it.only(1)\n" > x.test.ts && sdw-tamper' _ "$r"
printf '%s\n' "$out" | grep -qxF "skip-added src/deep/x.test.ts:1 it.only(1)" || fail from-subdir "$out"
ok from-subdir
echo "PASS test-tamper"
