#!/usr/bin/env bash
# plugin/hooks/hooks.json mounts exactly the internals §4.1 rows (event, matcher, script, timeout),
# and every command is an executable file. Mutated copies prove a dropped matcher fails.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdw-tests-lint.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
cd "$ROOT" || exit 1

python3 - "$tmp" <<'EOF' || exit 1
import copy, json, os, re, shutil, stat, sys
from collections import Counter

tmp = sys.argv[1]
fails = []


def spec_rows():
    text = open("docs/internals.md", encoding="utf-8").read()
    m = re.search(r"^### 4\.1 hooks\.json\n(.*?)(?=^#)", text, re.S | re.M)
    rows = []
    for line in (m.group(1) if m else "").splitlines():
        cells = [c.strip() for c in re.split(r"(?<!\\)\|", line.strip())[1:-1]]
        if len(cells) != 4 or cells[0] in ("Event", "") or set(cells[0]) <= set("-"):
            continue
        event, matcher, command, timeout = cells
        matcher = None if matcher == "(omitted)" else matcher.strip("`").replace("\\|", "|")
        script = re.match(r'(?:"\$\{CLAUDE_PLUGIN_ROOT\}/hooks|…)/([A-Za-z0-9._-]+)"?$', command.strip("`"))
        rows.append((event, matcher, script.group(1) if script else command, int(timeout)))
    return rows


def mounted(hooks):
    out = []
    if not {"hooks"} <= set(hooks) <= {"hooks", "description"} or not isinstance(hooks["hooks"], dict):
        return None
    for event, groups in hooks["hooks"].items():
        for g in groups:
            for h in g.get("hooks", []):
                out.append((event, g.get("matcher"), h.get("type"), h.get("command"), h.get("timeout")))
    return out


def problems(hooks, plugin_root, rows):
    got = mounted(hooks)
    if got is None:
        return ["top level must be {\"hooks\": {...}} and at most a \"description\""]
    bad = []
    want = [(e, m, "command", '"${CLAUDE_PLUGIN_ROOT}/hooks/%s"' % s, t) for e, m, s, t in rows]
    for w in (Counter(want) - Counter(got)):
        bad.append("missing %s matcher=%r command=%s timeout=%s" % (w[0], w[1], w[3], w[4]))
    for g in (Counter(got) - Counter(want)):
        bad.append("not in §4.1 (or mounted twice): %s matcher=%r type=%s command=%s timeout=%s" % g)
    for g in got:
        cmd = g[3] if isinstance(g[3], str) else ""
        path = cmd.strip('"').replace("${CLAUDE_PLUGIN_ROOT}", plugin_root)
        if not (os.path.isfile(path) and os.access(path, os.X_OK)):
            bad.append("command not an executable file: %s" % cmd)
    return bad


rows = spec_rows()
if len(rows) < 6:
    print("FAIL internals §4.1: parsed %d rows, expected the full table" % len(rows))
    sys.exit(1)
real = json.load(open("plugin/hooks/hooks.json", encoding="utf-8"))
for p in problems(real, os.path.abspath("plugin"), rows):
    fails.append("hooks.json: " + p)
if fails:
    print("\n".join("FAIL " + f for f in fails))
    sys.exit(1)
print("ok hooks.json matches the %d rows of internals §4.1" % len(rows))

fake = os.path.join(tmp, "plugin")
shutil.copytree("plugin/hooks", os.path.join(fake, "hooks"))


def mutant(name, edit, root=fake):
    h = copy.deepcopy(real)
    edit(h["hooks"])
    if not problems(h, root, rows):
        fails.append("mutant not caught: " + name)


def group(hooks, event, script):
    return next(g for g in hooks[event] if g["hooks"][0]["command"].endswith("/" + script + '"'))


def narrow(hooks):
    g = group(hooks, "PreToolUse", "guard-read.sh")
    g["matcher"] = g["matcher"].replace("|mcp__.*", "")


mutant("guard-read without mcp__.*", narrow)
mutant("guard-write without NotebookEdit",
       lambda h: group(h, "PreToolUse", "guard-write.sh").update(matcher="Edit|Write"))
mutant("SessionStart given a matcher", lambda h: h["SessionStart"][0].update(matcher="startup"))
mutant("Stop timeout changed", lambda h: h["Stop"][0]["hooks"][0].update(timeout=60))
mutant("PostToolUse removed", lambda h: h.pop("PostToolUse"))
mutant("extra hook", lambda h: h["PreToolUse"].append(copy.deepcopy(h["PreToolUse"][0])))
os.chmod(os.path.join(fake, "hooks", "guard-bash.sh"), stat.S_IRUSR | stat.S_IWUSR)
mutant("guard-bash.sh not executable", lambda h: None)
print("ok 7 mutated copies fail")
if problems(dict(real, description="x"), os.path.abspath("plugin"), rows):
    fails.append("a top-level description is allowed")
if not problems(dict(real, extra=1), os.path.abspath("plugin"), rows):
    fails.append("mutant not caught: extra top-level key")

for f in fails:
    print("FAIL " + f)
sys.exit(1 if fails else 0)
EOF
echo "PASS test-hooks-json"
