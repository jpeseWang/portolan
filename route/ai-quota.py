#!/usr/bin/env python3
"""One-shot quota view and tool picker.
  ai-quota [--subs] [--force]     Claude, Codex and Antigravity quota, DeepSeek balance, proxy spend
  ai-quota --roles                list the roles in routing.json (offline)
  ai-quota --pick [role] [--exclude VENDOR] [--dir PATH] [--cmd]   choose a tool by remaining quota
  ai-quota --refresh-ds           refresh the DeepSeek balance cache (used by the statusline)
Run with `python3 -I -B`."""
import json, os, shutil, subprocess, sys, time, urllib.request
from datetime import datetime

HOME = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(HOME, "state")
PORT = os.environ.get("AIM_PORT", "4000")
os.makedirs(STATE, exist_ok=True)


def http_json(url, headers, timeout=15):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def keychain(service, env_name=None):
    """macOS Keychain first; without it (or without the item) the environment variable, if given."""
    try:
        p = subprocess.run(["security", "find-generic-password", "-s", service, "-w"],
                           capture_output=True, text=True)
        if p.returncode == 0 and p.stdout.strip():
            return p.stdout.strip()
    except OSError:
        pass
    return os.environ.get(env_name, "").strip() if env_name else ""


def refresh_deepseek():
    key = keychain("deepseek-api", "DEEPSEEK_API_KEY")
    if not key:
        return None
    # curl uses system CAs (python.org builds lack them); header goes via stdin so the key is not in argv
    p = subprocess.run(["/usr/bin/curl", "-sS", "-m", "15", "-K", "-", "https://api.deepseek.com/user/balance"],
                       input=f'header = "Authorization: Bearer {key}"\nheader = "Accept: application/json"\n',
                       capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError("curl failed")
    d = json.loads(p.stdout)
    infos = d.get("balance_infos") or []
    info = next((i for i in infos if i.get("currency") == "USD"), infos[0] if infos else {})
    out = {"balance": float(info.get("total_balance", "nan")), "currency": info.get("currency", "?"),
           "available": d.get("is_available"), "ts": int(time.time())}
    tmp = os.path.join(STATE, "ds-balance.json.tmp")
    with open(tmp, "w") as f:
        json.dump(out, f)
    os.replace(tmp, os.path.join(STATE, "ds-balance.json"))
    return out


def age(ts):
    s = int(time.time()) - int(ts)
    return f"{s}s ago" if s < 120 else f"{s // 60}m ago" if s < 7200 else f"{s // 3600}h ago"


INTERVAL = 300      # min seconds between provider reads
BACKOFF = 900       # after a rate_limited answer
CACHE = os.path.join(STATE, "subs-cache.json")


def other_account(cached, label):
    """A cached Claude result belongs to another login when CLAUDE_CONFIG_DIR differs from the one that wrote it."""
    return cached.get("account") != label


def read_subs(force=False):
    """Claude, Codex, Antigravity via providers.py (vendored from the former ALS Quota monitor). Cached."""
    sys.path.insert(0, HOME)
    from concurrent.futures import ThreadPoolExecutor
    from providers import FETCHERS, fetch_provider, claude_account_label
    label = claude_account_label()
    now = time.time()
    try:
        cached = json.load(open(CACHE))
    except Exception:
        cached = {}
    data, nxt = cached.get("data", {}), cached.get("next", {})
    due = [k for k in FETCHERS if force or now >= nxt.get(k, 0)
           or (k == "claude" and other_account(data.get(k, {}), label))]
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = dict(zip(due, pool.map(fetch_provider, due)))
    for key, res in results.items():
        old = data.get(key, {})
        if key == "claude":
            if other_account(old, label):
                old = {}
            res["account"] = label
        if res["state"] != "ok" and old.get("windows"):
            res["windows"] = old["windows"]
            res["lastSuccessAt"] = old.get("lastSuccessAt")
            res["stale"] = True
        elif res["state"] == "ok":
            res["lastSuccessAt"] = res.get("checkedAt")
        data[key] = res
        nxt[key] = now + (BACKOFF if res["state"] == "rate_limited" else INTERVAL)
    if results:
        try:
            tmp = CACHE + ".tmp"
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as f:
                json.dump({"data": data, "next": nxt}, f, ensure_ascii=False)
            os.replace(tmp, CACHE)
        except OSError:
            pass
    return [data[k] for k in FETCHERS if k in data]


def als_lines(force=False):
    try:
        providers = read_subs(force)
    except Exception as e:
        return None
    out = []
    for p in providers:
        ws = p.get("windows") or []
        if p.get("state") != "ok" or not ws:
            msg = p.get("message") or p.get("state") or "no data"
            if p.get("id") == "claude" and claude_fallback():
                msg = f"{msg} | {claude_fallback()}"
            out.append((p.get("id", "?"), msg))
            continue
        parts = []
        for w in ws:
            try:
                reset = datetime.fromisoformat(w["resetsAt"]).astimezone().strftime("%d/%m %H:%M")
            except Exception:
                reset = "?"
            parts.append(f"{w.get('label', '?')} {w.get('remainingPercent', '?'):g}% left (resets {reset})")
        stale = "  [stale]" if p.get("stale") else ""
        who = f"  [{p['account']}]" if p.get("id") == "claude" and p.get("account") else ""
        out.append((p.get("id", "?"), " | ".join(parts) + stale + who))
    return out


def claude_line():
    try:
        d = json.load(open(os.path.join(STATE, "claude-rate.json")))
    except Exception:
        return "no cache yet (appears after a normal `claude` session refreshes the statusline)"
    return f"5h {d['h5']}% used  7d {d['d7']}% used  [statusline {d.get('acct', '?')}, {age(d['ts'])}]"


def claude_fallback():
    """Fresh (under 1h) numbers written by a real Claude session's statusline, or empty."""
    try:
        d = json.load(open(os.path.join(STATE, "claude-rate.json")))
    except Exception:
        return ""
    if int(time.time()) - int(d["ts"]) > 3600:
        return ""
    return claude_line()


def deepseek_line():
    try:
        d = refresh_deepseek()
    except Exception as e:
        return f"error: {type(e).__name__}"
    if d is None:
        return "not configured (Keychain item deepseek-api or DEEPSEEK_API_KEY); optional"
    return f"balance {d['balance']:.2f} {d['currency']}" + ("" if d["available"] else "  (NOT available)")


def proxy_line():
    try:
        key = open(os.path.join(HOME, ".master")).read().strip()
        rows = http_json(f"http://127.0.0.1:{PORT}/spend/logs?summarize=true",
                         {"Authorization": f"Bearer {key}"})
    except Exception as e:
        return [f"proxy down or unreachable ({type(e).__name__}); start it with ai-proxy-up"]
    today = datetime.now().date()
    per, total = {}, 0.0
    for r in rows if isinstance(rows, list) else []:
        try:
            t = datetime.fromisoformat(r["startTime"].replace("Z", "+00:00")).astimezone()
        except Exception:
            continue
        if t.date() != today:
            continue
        g = r.get("model_group") or r.get("model") or "?"
        per[g] = per.get(g, 0.0) + float(r.get("spend") or 0)
        total += float(r.get("spend") or 0)
    if not per:
        return ["no requests today"]
    return [f"{g:<10} ${v:.5f}" for g, v in sorted(per.items())] + [f"{'total':<10} ${total:.5f}  (cap $5/day is configured in litellm.yaml, enforcement not verified)"]


def quota_pools(providers):
    """{pool: {window: percent left}} from provider results; a pool that cannot be read is absent."""
    pools = {}
    for p in providers:
        pid = p.get("id")
        if p.get("state") != "ok" or not p.get("windows"):
            continue
        for w in p["windows"]:
            lab, left = w.get("label", ""), w.get("remainingPercent")
            if left is None:
                continue
            if pid == "claude":
                key = {"5 giờ": "5h", "Hàng tuần": "7d"}.get(lab)  # per-model windows are not the account limit
                if key:
                    pools.setdefault("claude", {})[key] = left
            elif pid == "codex":
                if " · " in lab:  # per-model extras
                    continue
                cur = pools.setdefault("codex", {}).get("*")
                pools["codex"]["*"] = left if cur is None else min(cur, left)
            elif pid == "antigravity":
                key = ("antigravity:Gemini" if lab.startswith("Gemini")
                       else "antigravity:Claude and GPT" if lab.startswith("Claude and GPT") else None)
                if key:
                    pools.setdefault(key, {})["*"] = left
    if "7d" in pools.get("claude", {}):
        pools["claude"].setdefault("5h", 100)  # no open 5-hour window means nothing used in it
    if "claude" not in pools:  # fresh statusline numbers are "used", convert to "left"
        try:
            d = json.load(open(os.path.join(STATE, "claude-rate.json")))
            if int(time.time()) - int(d["ts"]) <= 3600:
                pools["claude"] = {"5h": 100 - d["h5"], "7d": 100 - d["d7"]}
        except Exception:
            pass
    try:
        pools["deepseek"] = {"*": float(json.load(open(os.path.join(STATE, "ds-balance.json")))["balance"])}
    except Exception:
        pass
    return pools


class DenyListUnreadable(Exception):
    pass


def _deny_list_from_local_zsh(path, environ):
    """AIM_NO_DS_PATHS as env.zsh would build it, for callers that never loaded env.zsh (bash, an agent's shell)."""
    if not os.path.isfile(path):
        return None  # no local.zsh: nothing was configured
    if not shutil.which("zsh"):
        raise DenyListUnreadable("zsh is needed to read local.zsh; or export AIM_NO_DS_PATHS_STR")
    script = 'AIM_NO_DS_PATHS=(); source "$1" >/dev/null 2>&1 || exit 3; print -r -- "${(j.:.)AIM_NO_DS_PATHS}"'
    try:
        r = subprocess.run(["zsh", "-f", "-c", script, "zsh", path], capture_output=True, text=True, timeout=5,
                           env={"HOME": environ.get("HOME", ""), "PATH": environ.get("PATH", "")})
    except (OSError, subprocess.TimeoutExpired):
        raise DenyListUnreadable("could not run zsh") from None
    if r.returncode != 0:
        raise DenyListUnreadable("local.zsh does not load")
    return r.stdout.strip()


def denied_paths(c, environ=None, local_zsh=None):
    """Directories where this chain entry must not be used. The variable named by deny_env wins (empty = none);
    for AIM_NO_DS_PATHS_STR it falls back to reading local.zsh. Raises DenyListUnreadable when it cannot tell."""
    environ = os.environ if environ is None else environ
    out = list(c.get("deny_paths", []))
    name = c.get("deny_env")
    if name:
        val = environ.get(name)
        if val is None and name == "AIM_NO_DS_PATHS_STR":
            val = _deny_list_from_local_zsh(local_zsh or os.path.join(HOME, "local.zsh"), environ)
        out += [p for p in (val or "").split(os.pathsep) if p]
    return out


def _expand_home(path, home):
    if home and (path == "~" or path.startswith("~/")):
        return home + path[1:]
    return os.path.expanduser(path)


def entry_status(c, pools, directory, environ=None, local_zsh=None):
    """True = usable, False = skipped, None = unknown (quota or deny list unreadable)."""
    real = os.path.realpath(directory)
    try:
        denied = denied_paths(c, environ, local_zsh)
    except DenyListUnreadable as e:
        return None, f"deny list unreadable: {e}"
    home = (environ or os.environ).get("HOME")
    for dp in denied:
        dp = os.path.realpath(_expand_home(dp, home))
        if real == dp or real.startswith(dp + os.sep):
            return False, f"not allowed under {dp}"
    pool = pools.get(c["pool"])
    if pool is None:
        return None, "quota unknown"
    checked = False
    for key, need in c["min"].items():
        left = pool.get(key, pool.get("*"))
        if left is None:  # the plan has no such window (for example no weekly limit): nothing to check
            continue
        checked = True
        if left < need:
            return False, f"{key} {left:g} left, needs {need:g}"
    if not checked:
        return None, "no usable window"
    return True, " ".join(f"{k}:{v:g}" for k, v in pool.items())


def choose(chain, pools, directory, exclude=None, environ=None, local_zsh=None):
    rows, pick, unknown = [], None, None
    for c in chain:
        if exclude and c["vendor"] == exclude:
            rows.append((c, False, f"same vendor as implementer ({exclude})"))
            continue
        ok, why = entry_status(c, pools, directory, environ, local_zsh)
        rows.append((c, ok, why))
        if ok is True and pick is None:
            pick = c
        if ok is None and unknown is None:
            unknown = c
    return rows, pick, unknown


def pick_main(argv):
    def opt(name, default=None):
        return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else default
    chains = json.load(open(os.path.join(HOME, "routing.json")))["chains"]
    role = next((a for a in argv if a in chains), None)
    directory, exclude = opt("--dir", os.getcwd()), opt("--exclude")
    pools = quota_pools(read_subs())
    only_cmd = "--cmd" in argv
    for r in ([role] if role else list(chains)):
        rows, pick, unknown = choose(chains[r], pools, directory, exclude)
        if only_cmd:
            chosen = pick or unknown
            if chosen is None:
                print(f"no usable tool for {r}", file=sys.stderr)
                sys.exit(1)
            if pick is None:
                print(f"warning: quota unknown for {chosen['name']}, nothing verified", file=sys.stderr)
            print(chosen["cmd"])
            return
        print(r)
        for i, (c, ok, why) in enumerate(rows, 1):
            mark = {True: "ok  ", False: "skip", None: "?   "}[ok]
            print(f"  {i}. {mark} {c['name']:<14} {why}")
        chosen = pick or unknown
        tail = "" if pick else "  (quota unknown, unverified)" if unknown else ""
        print(f"  -> {chosen['name'] + '  ' + chosen['cmd'] + tail if chosen else 'nothing usable'}")


def main():
    if "--roles" in sys.argv:
        for r in json.load(open(os.path.join(HOME, "routing.json")))["chains"]:
            print(r)
        return
    if "--pick" in sys.argv:
        return pick_main(sys.argv)
    if "--refresh-ds" in sys.argv:
        try:
            refresh_deepseek()
        except Exception:
            pass
        return
    als = als_lines(force="--force" in sys.argv)
    if als is None:
        print(f"{'Claude (sub)':<18}{claude_line()}")
        print(f"{'Codex, Antigravity':<18}could not read subscription quota (providers.py failed)")
    else:
        for pid, text in als:
            print(f"{pid:<18}{text}")
    if "--subs" in sys.argv:
        return
    print(f"{'DeepSeek (api)':<18}{deepseek_line()}")
    lines = proxy_line()
    print(f"{'Proxy spend today':<18}{lines[0]}")
    for l in lines[1:]:
        print(f"{'':<18}{l}")


if __name__ == "__main__":
    main()
