#!/usr/bin/env bash
# Release sanity: plugin.json version is semver, any marketplace entry agrees, and a commit tagged
# vX.Y.Z carries version X.Y.Z (bootstrap installs the newest tag).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdw-tests-lint.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CEILING_DIRECTORIES="$tmp"
mkdir -p "$HOME"

check() {
  python3 - "$1" <<'EOF'
import json, os, re, subprocess, sys

d = sys.argv[1]
SEMVER = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?")
rel = "plugin/.claude-plugin/plugin.json"
v = json.load(open(os.path.join(d, rel), encoding="utf-8")).get("version")
bad = []
if not isinstance(v, str) or not SEMVER.fullmatch(v):
    bad.append("%s: version %r is not semver" % (rel, v))
mp = os.path.join(d, ".claude-plugin/marketplace.json")
if os.path.exists(mp):
    for p in json.load(open(mp, encoding="utf-8")).get("plugins", []):
        if p.get("name") == "sdw" and "version" in p and p["version"] != v:
            bad.append("marketplace.json: sdw version %r, plugin.json %r" % (p["version"], v))


def git(*args):
    return subprocess.run(["git", "-C", d] + list(args), capture_output=True, text=True)


if git("rev-parse", "--verify", "-q", "HEAD").returncode == 0:
    tags = [t for t in git("tag", "--points-at", "HEAD").stdout.split() if re.fullmatch(r"v\d+\.\d+\.\d+", t)]
    if tags:
        shown = git("show", "HEAD:" + rel)
        at_head = json.loads(shown.stdout).get("version") if shown.returncode == 0 else None
        for t in tags:
            if at_head != t[1:]:
                bad.append("HEAD is tagged %s but its %s says %r" % (t, rel, at_head))
for b in bad:
    print("FAIL " + b)
sys.exit(1 if bad else 0)
EOF
}

fixture() {
  f="$tmp/$1"
  mkdir -p "$f/plugin/.claude-plugin"
  printf '{"name":"sdw","version":"%s"}\n' "$2" > "$f/plugin/.claude-plugin/plugin.json"
  echo "$f"
}

expect() {
  want=$1 name=$2 dir=$3
  check "$dir" > "$tmp/out" 2>&1
  rc=$?
  [ "$rc" = "$want" ] || { echo "FAIL $name: exit $rc, want $want"; cat "$tmp/out"; exit 1; }
  echo "ok $name"
}

expect 0 "this repo" "$ROOT"

expect 1 "version not semver" "$(fixture badver 2.1)"
expect 0 "no git: tag check skipped" "$(fixture nogit 2.1.0)"

f=$(fixture tagged 2.1.0)
(cd "$f" && git init -q . && git add -A && git commit -qm init && git tag v2.1.0) || exit 1
expect 0 "HEAD at v2.1.0 with 2.1.0" "$f"
(cd "$f" && git tag v2.2.0) || exit 1
expect 1 "HEAD at v2.2.0 with 2.1.0" "$f"
(cd "$f" && git tag -d v2.2.0 >/dev/null && printf '{"name":"sdw","version":"2.2.0"}\n' > plugin/.claude-plugin/plugin.json) || exit 1
expect 0 "uncommitted bump after the tag" "$f"

mkdir -p "$f/.claude-plugin"
printf '{"plugins":[{"name":"sdw","source":"./plugin","version":"2.0.0"}]}\n' > "$f/.claude-plugin/marketplace.json"
expect 1 "marketplace version disagrees" "$f"

echo "PASS test-release"
