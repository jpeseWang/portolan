"""Run: python3 -I -B tests/route/test_routing.py   (stdlib only, no network, no Keychain)"""
import hashlib
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import unittest

ROUTE = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "route")
sys.path.insert(0, ROUTE)


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROUTE, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


q = load("ai_quota", "ai-quota.py")
providers = load("providers", "providers.py")
CHAINS = json.load(open(os.path.join(ROUTE, "routing.json")))["chains"]
FULL = {"claude": {"5h": 80, "7d": 80}, "codex": {"*": 60}, "antigravity:Gemini": {"*": 90},
        "antigravity:Claude and GPT": {"*": 90}, "deepseek": {"*": 5}}
QA_ROLES = ("qa-design", "qa-run", "qa-report", "qa-escalate")


def win(label, left):
    return {"label": label, "remainingPercent": left, "resetsAt": None, "models": []}


def pick(role, pools, directory="/tmp", exclude=None):
    rows, chosen, unknown = q.choose(CHAINS[role], pools, directory, exclude)
    return (chosen or unknown or {}).get("name"), chosen is not None


class Pools(unittest.TestCase):
    def setUp(self):
        q.STATE = os.path.join(ROUTE, "_no_state")  # no statusline or balance cache

    def test_claude_model_windows_do_not_replace_the_weekly_window(self):
        p = [{"id": "claude", "state": "ok", "windows": [
            win("5 giờ", 70), win("Hàng tuần", 40), win("Sonnet · hàng tuần", 95),
            win("Opus · hàng tuần", 3), win("OAuth apps · hàng tuần", 100)]}]
        self.assertEqual(q.quota_pools(p)["claude"], {"5h": 70, "7d": 40})

    def test_codex_uses_the_tightest_main_window_and_ignores_model_extras(self):
        p = [{"id": "codex", "state": "ok", "windows": [
            win("5 giờ", 20), win("Hàng tuần", 60), win("Model · Hàng tuần", 99)]}]
        self.assertEqual(q.quota_pools(p)["codex"], {"*": 20})

    def test_antigravity_groups_are_separate_pools(self):
        p = [{"id": "antigravity", "state": "ok", "windows": [
            win("Gemini Models · hàng tuần", 57), win("Claude and GPT models · hàng tuần", 0)]}]
        pools = q.quota_pools(p)
        self.assertEqual(pools["antigravity:Gemini"], {"*": 57})
        self.assertEqual(pools["antigravity:Claude and GPT"], {"*": 0})

    def test_claude_without_an_open_5h_window_counts_as_unused(self):
        p = [{"id": "claude", "state": "ok", "windows": [win("Hàng tuần", 54)]}]
        self.assertEqual(q.quota_pools(p)["claude"], {"5h": 100, "7d": 54})

    def test_cached_claude_result_of_another_account_is_stale(self):
        self.assertTrue(q.other_account({"account": "Claude Code (default config)"}, "Claude Code (.claude-work)"))
        self.assertFalse(q.other_account({"account": "Claude Code (.claude-work)"}, "Claude Code (.claude-work)"))
        self.assertTrue(q.other_account({"state": "login_required"}, "Claude Code (.claude-work)"))

    def test_unreadable_provider_has_no_pool(self):
        p = [{"id": "claude", "state": "auth_expired", "windows": [win("5 giờ", 70)]}]
        self.assertNotIn("claude", q.quota_pools(p))


class Chains(unittest.TestCase):
    def test_lead_falls_through_the_chain(self):
        self.assertEqual(pick("lead", FULL), ("claude-opus", True))
        self.assertEqual(pick("lead", {**FULL, "claude": {"5h": 20, "7d": 80}}), ("claude-sonnet", True))
        self.assertEqual(pick("lead", {**FULL, "claude": {"5h": 80, "7d": 3}}), ("agy-sonnet", True))
        out = {**FULL, "claude": {"5h": 0, "7d": 0}, "antigravity:Claude and GPT": {"*": 0}}
        self.assertEqual(pick("lead", out), ("codex", True))
        self.assertEqual(pick("lead", {"antigravity:Gemini": {"*": 90}}), ("agy-gemini", True))

    def test_unknown_quota_is_skipped_for_a_verified_entry(self):
        pools = {k: v for k, v in FULL.items() if k != "claude"}
        self.assertEqual(pick("lead", pools), ("agy-sonnet", True))

    def test_nothing_readable_offers_the_first_entry_as_unverified(self):
        self.assertEqual(pick("lead", {}), ("claude-opus", False))

    def test_reviewer_excludes_the_implementer_vendor(self):
        self.assertEqual(pick("reviewer", FULL, exclude="openai")[0], "agy-gemini")
        self.assertEqual(pick("reviewer", {**FULL, "antigravity:Gemini": {"*": 0}}, exclude="anthropic")[0], "codex")

    def test_deepseek_is_never_offered_under_a_denied_path(self):
        denied = tempfile.mkdtemp()
        old = os.environ.get("AIM_NO_DS_PATHS_STR")
        os.environ["AIM_NO_DS_PATHS_STR"] = denied + os.pathsep + "/nonexistent-other"
        try:
            dry = {**FULL, "claude": {"5h": 0, "7d": 0}, "antigravity:Gemini": {"*": 0}, "codex": {"*": 0}}
            self.assertEqual(pick("worker", dry, os.path.join(denied, "proj"))[0], None)
            self.assertEqual(pick("worker", dry, denied)[0], None)
            self.assertEqual(pick("worker", dry, "/tmp")[0], "claude-ds")
        finally:
            os.rmdir(denied)
            if old is None:
                os.environ.pop("AIM_NO_DS_PATHS_STR", None)
            else:
                os.environ["AIM_NO_DS_PATHS_STR"] = old

    def test_no_deny_list_means_deepseek_is_allowed(self):
        os.environ.pop("AIM_NO_DS_PATHS_STR", None)
        dry = {**FULL, "claude": {"5h": 0, "7d": 0}, "antigravity:Gemini": {"*": 0}, "codex": {"*": 0}}
        self.assertEqual(pick("worker", dry, "/tmp")[0], "claude-ds")


@unittest.skipUnless(shutil.which("zsh"), "zsh not installed")
class DenyListWithoutTheShellFunctions(unittest.TestCase):
    """aim-pick may run from bash or an agent's shell that never loaded env.zsh."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.local = os.path.join(self.tmp, "local.zsh")
        with open(self.local, "w") as f:
            f.write('AIM_NO_DS_PATHS=("$HOME/clients/a" "/srv/b")\n')
        self.entry = {"deny_env": "AIM_NO_DS_PATHS_STR"}
        self.env = {"HOME": "/home/someone", "PATH": os.environ.get("PATH", "")}

    def test_deny_list_is_read_from_local_zsh_when_the_variable_is_missing(self):
        got = q.denied_paths(self.entry, environ=self.env, local_zsh=self.local)
        self.assertEqual(got, ["/home/someone/clients/a", "/srv/b"])

    def test_the_variable_wins_over_local_zsh_and_empty_means_none(self):
        self.assertEqual(q.denied_paths(self.entry, {**self.env, "AIM_NO_DS_PATHS_STR": "/x"}, self.local), ["/x"])
        self.assertEqual(q.denied_paths(self.entry, {**self.env, "AIM_NO_DS_PATHS_STR": ""}, self.local), [])

    def test_no_local_zsh_means_nothing_is_denied(self):
        self.assertEqual(q.denied_paths(self.entry, self.env, os.path.join(self.tmp, "absent.zsh")), [])

    def test_an_unreadable_local_zsh_makes_the_entry_unverified_not_allowed(self):
        with open(self.local, "w") as f:
            f.write("this is ( not valid\n")
        with self.assertRaises(q.DenyListUnreadable):
            q.denied_paths(self.entry, self.env, self.local)
        rows, chosen, unknown = q.choose([{"name": "claude-ds", "vendor": "deepseek", "cmd": "x", "pool": "deepseek",
                                           "min": {"*": 0.2}, "deny_env": "AIM_NO_DS_PATHS_STR"}],
                                         FULL, "/anywhere", environ=self.env, local_zsh=self.local)
        self.assertIsNone(chosen)
        self.assertEqual(unknown["name"], "claude-ds")
        self.assertIn("deny list unreadable", rows[0][2])

    def test_choose_uses_it(self):
        rows, chosen, _ = q.choose([{"name": "claude-ds", "vendor": "deepseek", "cmd": "x", "pool": "deepseek",
                                     "min": {"*": 0.2}, "deny_env": "AIM_NO_DS_PATHS_STR"}],
                                   FULL, "/srv/b/app", environ=self.env, local_zsh=self.local)
        self.assertIsNone(chosen)
        self.assertIn("not allowed", rows[0][2])


class QaChains(unittest.TestCase):
    def test_roles_exist_and_none_starts_with_opus(self):
        for r in QA_ROLES:
            self.assertIn(r, CHAINS)
        for r in ("qa-design", "qa-run", "qa-report"):
            self.assertNotIn("claude-opus", [c["name"] for c in CHAINS[r]], r)

    def test_running_and_reporting_start_outside_the_claude_pool(self):
        self.assertEqual(pick("qa-run", FULL), ("agy-flash", True))
        self.assertEqual(pick("qa-report", FULL), ("agy-flash-low", True))

    def test_design_uses_sonnet_first(self):
        self.assertEqual(pick("qa-design", FULL), ("claude-sonnet", True))

    def test_run_falls_back_gemini_then_codex_then_haiku(self):
        self.assertEqual(pick("qa-run", {**FULL, "antigravity:Gemini": {"*": 0}}), ("codex", True))
        both = {**FULL, "antigravity:Gemini": {"*": 0}, "codex": {"*": 0}}
        self.assertEqual(pick("qa-run", both), ("claude-haiku", True))

    def test_escalation_tries_the_google_plan_opus_before_the_claude_pool(self):
        self.assertEqual(pick("qa-escalate", FULL), ("agy-opus", True))
        out = {**FULL, "antigravity:Claude and GPT": {"*": 0}}
        self.assertEqual(pick("qa-escalate", out), ("claude-opus", True))

    def test_escalation_skips_opus_when_the_claude_pool_is_low(self):
        pools = {**FULL, "antigravity:Claude and GPT": {"*": 0}, "claude": {"5h": 20, "7d": 80}}
        self.assertEqual(pick("qa-escalate", pools), ("codex", True))


class PlansWithFewerWindows(unittest.TestCase):
    def test_a_plan_with_only_a_5h_window_is_judged_on_that_window(self):
        self.assertEqual(pick("qa-design", {"claude": {"5h": 60}}), ("claude-sonnet", True))

    def test_a_low_5h_window_skips_claude_even_without_a_weekly_one(self):
        self.assertEqual(pick("qa-design", {"claude": {"5h": 5}, "antigravity:Gemini": {"*": 90}})[0], "agy-gemini")

    def test_a_claude_pool_with_no_windows_is_unknown_not_usable(self):
        rows, chosen, unknown = q.choose(CHAINS["qa-design"], {"claude": {}}, "/tmp")
        self.assertIsNone(chosen)
        self.assertEqual(unknown["name"], "claude-sonnet")


class Secrets(unittest.TestCase):
    def test_deepseek_key_falls_back_to_the_environment_without_a_keychain(self):
        def no_security(*a, **k):
            raise FileNotFoundError("security")
        orig, old = q.subprocess.run, os.environ.get("DEEPSEEK_API_KEY")
        q.subprocess.run, os.environ["DEEPSEEK_API_KEY"] = no_security, "from-env"
        try:
            self.assertEqual(q.keychain("deepseek-api", "DEEPSEEK_API_KEY"), "from-env")
        finally:
            q.subprocess.run = orig
            if old is None:
                os.environ.pop("DEEPSEEK_API_KEY", None)
            else:
                os.environ["DEEPSEEK_API_KEY"] = old


class ClaudeKeychain(unittest.TestCase):
    def test_service_name_follows_claude_config_dir(self):
        cfg = "/home/someone/.claude-work"
        want = "Claude Code-credentials-" + hashlib.sha256(cfg.encode()).hexdigest()[:8]
        self.assertEqual(providers.claude_keychain_services({"CLAUDE_CONFIG_DIR": cfg})[0], want)

    def test_default_config_uses_the_plain_service_name(self):
        self.assertEqual(providers.claude_keychain_services({}), ["Claude Code-credentials"])


if __name__ == "__main__":
    unittest.main(verbosity=1)
