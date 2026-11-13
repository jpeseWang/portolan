#!/usr/bin/env bash
# Static checks: always-loaded caps, skill and agent frontmatter, git 2.15 and removed v1 paths,
# fetches guarded for VCS_HOST=none, and every bash block in skills, agents and references parses.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdw-tests-lint.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
cd "$ROOT" || exit 1

python3 - "$tmp" <<'EOF' || exit 1
import glob, os, re, subprocess, sys

tmp = sys.argv[1]
bad = []

caps = {"plugin/rules/core.md": (4500, 60), "plugin/skills/onboard/project.md": (2500, 40)}
for path, (chars, lines) in caps.items():
    text = open(path, encoding="utf-8").read()
    if len(text) > chars or text.count("\n") > lines:
        bad.append(f"{path}: {len(text)}/{chars} chars, {text.count(chr(10))}/{lines} lines")
print("ok always-loaded caps")

dmi = {"onboard", "plan", "review-pr", "commit", "ship", "wrap", "offboard", "logwork", "create-ticket"}
model = {"sync", "debug", "test", "qa", "verify-ui", "ui-polish", "review", "daily-report", "clarify"}


def check(path, name, want_dmi):
    m = re.match(r"---\n(.*?)\n---\n", open(path, encoding="utf-8").read(), re.S)
    if not m:
        bad.append(f"{path}: no frontmatter")
        return
    fm = dict(re.findall(r"^([A-Za-z-]+):[ \t]*(.*)$", m.group(1), re.M))
    if fm.get("name") != name:
        bad.append(f"{path}: name is {fm.get('name')!r}, expected {name!r}")
    desc = fm.get("description", "").strip().strip("'\"")
    if not desc or len(desc) > 200:
        bad.append(f"{path}: description missing or over 200 chars ({len(desc)})")
    if want_dmi is not None and (fm.get("disable-model-invocation", "").strip() == "true") != want_dmi:
        bad.append(f"{path}: disable-model-invocation should be {want_dmi}")


for name in sorted(dmi | model):
    p = f"plugin/skills/{name}/SKILL.md"
    if os.path.exists(p):
        check(p, name, name in dmi)
    else:
        bad.append(f"{p}: missing")
for d in sorted(os.listdir("plugin/skills")):
    if d not in dmi | model:
        bad.append(f"plugin/skills/{d}: not in the contract's skill list")
for name in ("qa", "reviewer"):
    check(f"plugin/agents/{name}.md", name, None)
check("templates/verify-skill/SKILL.md", "verify", False)
print("ok frontmatter")

NEW_GIT = re.compile(r"git (switch|restore)|branch --show-current|diff --merge-base|worktree remove|--path-format|git stash(?! (list|show))")
for f in ["bootstrap.sh"] + sorted(glob.glob("plugin/bin/*") + glob.glob("plugin/hooks/*.sh")):
    if f.endswith("guard-bash.sh"):
        continue
    for n, line in enumerate(open(f, encoding="utf-8", errors="replace"), 1):
        if NEW_GIT.search(line) and not line.lstrip().startswith("#"):
            bad.append(f"{f}:{n}: git newer than 2.15 (or stash) in code")
docs = sorted(glob.glob("plugin/skills/*/*.md") + glob.glob("plugin/agents/*.md") + glob.glob("plugin/reference/*.md"))
blocks = []
for f in docs:
    text = open(f, encoding="utf-8").read()
    if f.startswith(("plugin/skills/", "plugin/agents/")) and re.search(r"variants/|\.claude/tools/|PLAN_ARTIFACT|cfg\.sh|CLAUDE_PLUGIN_ROOT", text):
        bad.append(f"{f}: names a removed v1 path or CLAUDE_PLUGIN_ROOT (unset in the Bash tool)")
    for i, b in enumerate(re.findall(r"```bash\n(.*?)```", text, re.S)):
        blocks.append((f, i, b))
        for line in b.splitlines():
            if NEW_GIT.search(line):
                bad.append(f"{f}: git newer than 2.15 (or stash) in a bash block: {line.strip()[:80]}")
            if re.search(r"git fetch( -q| --quiet)* origin( --quiet)?\s*($|[;&|])", line) and "none" not in line:
                bad.append(f"{f}: git fetch origin without a VCS_HOST=none guard: {line.strip()[:80]}")
print("ok git 2.15, v1 paths, fetch guards")

shells = ["bash"] + (["zsh"] if subprocess.run(["sh", "-c", "command -v zsh"], capture_output=True).returncode == 0 else [])
for f, i, b in blocks:
    path = os.path.join(tmp, "%s.%d.sh" % (f.replace("/", "_"), i))
    open(path, "w").write(re.sub(r"<[^<>\n]*>", "x", b))
    for sh in shells:
        r = subprocess.run([sh, "-n", path], capture_output=True, text=True)
        if r.returncode:
            bad.append(f"{f} block {i}: {sh}: {r.stderr.strip()[:160]}")
print(f"ok {len(blocks)} bash blocks parse ({', '.join(shells)}; <placeholders> as x)")

for b in bad:
    print(f"FAIL {b}")
sys.exit(1 if bad else 0)
EOF
echo "PASS test-static"
