#!/usr/bin/env python3
"""usage: payload.py --check DRAFTS DIFF
       payload.py DRAFTS DIFF --sha SHA --select 1,3|all [--summary-file F] [--all-body]

DRAFTS is a JSON list of {"n", "path", "line"?, "severity", "body"}; DIFF is
`git diff <merge-base> <head>` with default context. A draft is inline only when its line is
inside a new-side hunk of its file; the rest go into the review body. Prints the GitHub
review payload (event COMMENT). Exit 0 ok, 2 usage or bad input."""
import json
import re
import sys

LABEL = {"S1": "Must fix", "S2": "Must fix", "S3": "Suggestion", "S4": "Nit"}


def visible_lines(diff_path):
    ranges, path = {}, None
    for line in open(diff_path, encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if line.startswith("+++ "):
            p = line[4:].rstrip("\t")
            if p.startswith('"'):
                p = p[1:-1].encode("latin-1", "backslashreplace").decode("unicode_escape")
                p = p.encode("latin-1").decode("utf-8", "replace")
            path = None if p == "/dev/null" else p[2:]
        elif line.startswith("@@") and path:
            m = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))?", line)
            if m:
                start, count = int(m.group(1)), int(m.group(2) or 1)
                if count:
                    ranges.setdefault(path, []).append((start, start + count - 1))
    return ranges


def inline(draft, ranges):
    line = draft.get("line")
    if not isinstance(line, int) or line < 1:
        return False
    return any(a <= line <= b for a, b in ranges.get(draft.get("path"), []))


def text(d):
    return "**%s:** %s" % (LABEL.get(d.get("severity"), "Note"), d["body"].strip())


def fail(msg):
    sys.stderr.write("payload.py: %s\n" % msg)
    sys.exit(2)


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv else 2
    check = argv[0] == "--check"
    args = argv[1:] if check else argv
    if len(args) < 2:
        fail("need DRAFTS and DIFF")
    try:
        drafts = json.load(open(args[0], encoding="utf-8"))
        ranges = visible_lines(args[1])
    except (OSError, ValueError) as e:
        fail(str(e))
    if not isinstance(drafts, list) or not all(isinstance(d, dict) and "n" in d and "path" in d and "body" in d for d in drafts):
        fail("drafts must be a list of objects with n, path, body")
    if check:
        for d in drafts:
            where = "%s:%s" % (d["path"], d.get("line", "-"))
            print("%s %s %s" % (d["n"], "inline" if inline(d, ranges) else "body", where))
        return 0
    opts = {"--sha": None, "--select": None, "--summary-file": None}
    all_body, rest = False, args[2:]
    while rest:
        k = rest.pop(0)
        if k == "--all-body":
            all_body = True
        elif k in opts and rest:
            opts[k] = rest.pop(0)
        else:
            fail("unknown argument: %s" % k)
    if not opts["--sha"] or not re.fullmatch(r"[0-9a-f]{40}", opts["--sha"]) or not opts["--select"]:
        fail("--sha <40-hex> and --select are required")
    sel = opts["--select"]
    if sel == "all":
        chosen = drafts
    else:
        try:
            want = {int(x) for x in sel.split(",") if x.strip()}
        except ValueError:
            fail("bad --select: %s" % sel)
        chosen = [d for d in drafts if d["n"] in want]
        missing = want - {d["n"] for d in chosen}
        if missing:
            fail("no draft numbered %s" % ",".join(map(str, sorted(missing))))
    summary = open(opts["--summary-file"], encoding="utf-8").read().strip() if opts["--summary-file"] else ""
    comments, loose = [], []
    for d in chosen:
        if not all_body and inline(d, ranges):
            comments.append({"path": d["path"], "line": d["line"], "side": "RIGHT", "body": text(d)})
        else:
            where = d["path"] + (":%d" % d["line"] if isinstance(d.get("line"), int) else "")
            loose.append("**%s** — %s" % (where, text(d)))
    body = "\n\n".join([summary] + loose if summary else loose)
    print(json.dumps({"commit_id": opts["--sha"], "event": "COMMENT", "body": body, "comments": comments},
                     ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
