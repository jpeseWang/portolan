"""Run: python3 -I -B tests/route/test_portable.py
Checks that the repo carries nothing from one machine, that a copy of it works from another path,
that setup.sh is safe to re-run, and that the README setup prompt stays in step with the repo."""
import hashlib
import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROUTE = os.path.join(ROOT, "route")
HAVE_ZSH = shutil.which("zsh") is not None
HAVE_GIT = shutil.which("git") is not None

# Patterns that identify a machine, an account or a client. None may appear in a committed file.
# Specific names are stored as SHA-256 hashes of the lowercase word so that this file does not publish them.
# To guard another name, add its hash here, or list words (one per line) in route/projects/local/forbidden.txt (not committed).
FORBIDDEN_PATTERNS = [r"/Users/(?!someone/)", r"/home/(?!someone/|runner/)[a-z][\w.-]*/", r"PIN-\d+",
                      r"[\w.+-]+@(?:gmail|outlook|hotmail|yahoo)\.com"]
FORBIDDEN_WORD_HASHES = {
    "0cfcdc2f0991b0be44828249e5a914c80d7d1975d1238729f8b360839090953c",
    "324835f3a05888ab88c54e74c45acecf91008c7b589e4bac4eba12a740618518",
    "49400da1e2c892bdcb2cf806ffe2ef2ec944a3d5b07ef898e653e1befa136742",
    "61fa6bdf54ca8ee3c1f31d853649ca22fef9f9f929ff72595dacc176389ad28f",
    "64e016e1ae0bbb98cb25ced3e05843c303df49b3a27e77337e351aba65b08c09",
    "6e42ca3cdc3e2912499f65b494fb4ac84b968cd334fed6f9d2125db163ef8f87",
    "c23e2498e94b9e4347373ad29720902f1c05e9045a68f22dbec0e07757c31d6a",
    "f3775413fd3b8d53b6c5ba7b0e79bcaf19eb838a7317451d16abab2af53b9964",
}
WORD = re.compile(r"[A-Za-z0-9_]+")


def local_forbidden_words():
    path = os.path.join(ROUTE, "projects", "local", "forbidden.txt")
    try:
        with open(path, encoding="utf-8") as f:
            return {w.strip().lower() for w in f if w.strip() and not w.startswith("#")}
    except OSError:
        return set()


SELF = os.path.join("tests", "route", "test_portable.py")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def shipped_files():
    """Files that would be committed: tracked plus untracked and not ignored."""
    if HAVE_GIT and os.path.isdir(os.path.join(ROOT, ".git")):
        out = subprocess.run(["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=ROOT,
                             capture_output=True, check=True).stdout.decode()
        return [f for f in out.split("\0") if f and os.path.isfile(os.path.join(ROOT, f))]
    return [f for f in (os.path.relpath(os.path.join(d, n), ROOT) for d, _, ns in os.walk(ROOT) for n in ns)
            if not f.startswith((".git", "route/state", "route/projects/local", "route/local.zsh", "__pycache__"))
            and "__pycache__" not in f]


def copy_route(dest):
    """Copy the shipped files of route/ to dest/route and return that path."""
    for f in shipped_files():
        if not f.startswith("route/"):
            continue
        target = os.path.join(dest, f)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(os.path.join(ROOT, f), target)
    return os.path.join(dest, "route")


def run(cmd, **kw):
    kw.setdefault("capture_output", True)
    kw.setdefault("text", True)
    return subprocess.run(cmd, **kw)


class NoMachineSpecifics(unittest.TestCase):
    def test_no_author_or_client_details_in_shipped_files(self):
        pattern = re.compile("|".join(FORBIDDEN_PATTERNS))
        local_words = local_forbidden_words()
        hits = []
        for f in shipped_files():
            if f == SELF or f == "LICENSE":
                continue
            try:
                text = read(os.path.join(ROOT, f))
            except (UnicodeDecodeError, OSError):
                continue
            for n, line in enumerate(text.splitlines(), 1):
                words = {w.lower() for w in WORD.findall(line)}
                bad_word = any(hashlib.sha256(w.encode()).hexdigest() in FORBIDDEN_WORD_HASHES for w in words) \
                    or bool(words & local_words)
                if pattern.search(line) or bad_word:
                    hits.append(f"{f}:{n}")  # no line text: a hit must not echo the word it found
        self.assertEqual(hits, [], "forbidden text at:\n" + "\n".join(hits))

    def test_machine_files_are_ignored_by_git(self):
        ignore = read(os.path.join(ROOT, ".gitignore")).split()
        for name in ("route/local.zsh", "route/projects/local/", "route/.master", "route/.dbpass", "route/state/",
                     "route/proxy.log"):
            self.assertIn(name, ignore)


@unittest.skipUnless(HAVE_ZSH, "zsh not installed")
class EnvZsh(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.clone = copy_route(os.path.join(self.tmp, "somewhere else", "portolan copy"))
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)

    def zsh(self, script, extra_env=None):
        env = {"HOME": self.home, "PATH": "/usr/bin:/bin", **(extra_env or {})}
        return run(["zsh", "-f", "-c", f'source "{self.clone}/env.zsh"; {script}'], env=env)

    def test_aim_home_is_the_folder_env_zsh_lives_in(self):
        r = self.zsh('print -r -- "$AIM_HOME"')
        self.assertEqual(r.stdout.strip(), self.clone, r.stderr)

    def test_a_clone_with_no_local_zsh_still_loads(self):
        r = self.zsh('print -r -- "ok:${#AIM_PROJECTS}:${AIM_NO_DS_PATHS_STR}:$AIM_AGY_AUTOAPPROVE"')
        self.assertEqual(r.stdout.strip(), "ok:0::0", r.stderr)

    def test_local_zsh_supplies_projects_and_deny_list(self):
        write(os.path.join(self.clone, "local.zsh"), 
            f'AIM_NO_DS_PATHS=("{self.tmp}/a" "{self.tmp}/b")\nAIM_PROJECTS=(web "{self.tmp}/web")\n')
        r = self.zsh('print -r -- "$AIM_NO_DS_PATHS_STR|${AIM_PROJECTS[web]}"')
        self.assertEqual(r.stdout.strip(), f"{self.tmp}/a:{self.tmp}/b|{self.tmp}/web", r.stderr)

    def test_deepseek_is_refused_under_a_denied_path_even_through_a_symlink(self):
        real = os.path.join(self.tmp, "client")
        os.makedirs(os.path.join(real, "sub"))
        link = os.path.join(self.tmp, "client-link")
        os.symlink(real, link)
        write(os.path.join(self.clone, "local.zsh"), f'AIM_NO_DS_PATHS=("{link}")\n')
        for d in (real, os.path.join(real, "sub"), os.path.join(link, "sub")):
            r = self.zsh(f'_aim_ds_ok "{d}"; print -r -- "rc=$?"')
            self.assertIn("rc=1", r.stdout, d)
        r = self.zsh(f'_aim_ds_ok "{self.tmp}"; print -r -- "rc=$?"')
        self.assertIn("rc=0", r.stdout)

    def test_agy_is_not_auto_approved_unless_local_zsh_asks_for_it(self):
        stub = os.path.join(self.tmp, "bin")
        os.makedirs(stub)
        write(os.path.join(stub, "agy"), '#!/bin/sh\necho "args: $*"\n')
        os.chmod(os.path.join(stub, "agy"), 0o755)
        env = {"PATH": f"{stub}:/usr/bin:/bin"}
        self.assertEqual(self.zsh("agy -p hello", env).stdout.strip(), "args: -p hello")
        write(os.path.join(self.clone, "local.zsh"), "AIM_AGY_AUTOAPPROVE=1\n")
        self.assertEqual(self.zsh("agy -p hello", env).stdout.strip(),
                         "args: --dangerously-skip-permissions -p hello")
        self.assertEqual(self.zsh("agy --dangerously-skip-permissions -p hi", env).stdout.strip(),
                         "args: --dangerously-skip-permissions -p hi")


class Bin(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.clone = copy_route(os.path.join(self.tmp, "clone"))

    def test_roles_listed_offline_and_include_qa(self):
        r = run([os.path.join(self.clone, "bin", "ai-quota"), "--roles"])
        self.assertEqual(r.returncode, 0, r.stderr)
        for role in ("lead", "worker", "reviewer", "qa-design", "qa-run", "qa-report", "qa-escalate"):
            self.assertIn(role, r.stdout.split())

    def test_symlinked_command_finds_the_clone(self):
        os.makedirs(os.path.join(self.tmp, "bin"))
        link = os.path.join(self.tmp, "bin", "ai-quota")
        os.symlink(os.path.join(self.clone, "bin", "ai-quota"), link)
        r = run([link, "--roles"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("qa-run", r.stdout)

    def test_the_scripts_are_executable(self):
        for name in ("route/setup.sh", "route/bin/ai-quota", "route/bin/aim-pick", "bootstrap.sh",
                     "tests/route/test-routing.sh", "tests/route/test-portable.sh"):
            self.assertTrue(os.stat(os.path.join(ROOT, name)).st_mode & stat.S_IXUSR, name)


class Setup(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.clone = copy_route(os.path.join(self.tmp, "clone"))
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        for f in ("local.zsh",):
            p = os.path.join(self.clone, f)
            if os.path.exists(p):
                os.remove(p)

    def setup(self, *args):
        env = {"HOME": self.home, "PATH": os.environ.get("PATH", ""), "SHELL": "/bin/zsh"}
        return run(["bash", os.path.join(self.clone, "setup.sh"), "--no-test", *args], env=env)

    def tree(self):
        out = []
        for base in (self.home, self.clone):
            for d, _, ns in os.walk(base):
                out += [os.path.join(d, n) for n in ns] + [d]
        return sorted(out)

    def test_dry_run_changes_nothing_even_with_every_option(self):
        before = self.tree()
        r = self.setup("--dry-run", "--write-rc", "--link", "--with-proxy")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.tree(), before)
        self.assertIn("would:", r.stdout)

    def test_default_run_creates_only_local_zsh_and_state(self):
        before = set(self.tree())
        r = self.setup()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        added = {os.path.relpath(p, self.tmp) for p in set(self.tree()) - before}
        self.assertEqual(added, {os.path.join("clone", "route", "local.zsh"), os.path.join("clone", "route", "state")})
        self.assertFalse(os.path.exists(os.path.join(self.home, ".zshrc")))

    def test_second_run_changes_nothing_and_keeps_an_edited_local_zsh(self):
        self.assertEqual(self.setup().returncode, 0)
        mine = os.path.join(self.clone, "local.zsh")
        write(mine, "AIM_PROJECTS=(mine /somewhere)\n")
        before = self.tree()
        self.assertEqual(self.setup().returncode, 0)
        self.assertEqual(self.tree(), before)
        self.assertEqual(read(mine), "AIM_PROJECTS=(mine /somewhere)\n")

    def test_write_rc_backs_up_and_appends_once(self):
        rc = os.path.join(self.home, ".zshrc")
        write(rc, "export KEEP=1\n")
        self.assertEqual(self.setup("--write-rc").returncode, 0)
        self.assertEqual(self.setup("--write-rc").returncode, 0)
        text = read(rc)
        self.assertTrue(text.startswith("export KEEP=1\n"))
        self.assertEqual(text.count(f'{self.clone}/env.zsh'), 1)
        backups = [n for n in os.listdir(self.home) if n.startswith(".zshrc.portolan-backup-")]
        self.assertEqual(len(backups), 1)
        self.assertEqual(read(os.path.join(self.home, backups[0])), "export KEEP=1\n")

    def test_link_makes_working_commands_and_leaves_foreign_files(self):
        bindir = os.path.join(self.home, ".local", "bin")
        os.makedirs(bindir)
        write(os.path.join(bindir, "aim-pick"), "not ours\n")
        r = self.setup("--link")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(run([os.path.join(bindir, "ai-quota"), "--roles"]).returncode, 0)
        self.assertEqual(read(os.path.join(bindir, "aim-pick")), "not ours\n")
        self.assertIn("left alone", r.stdout)

    def test_a_non_zsh_login_shell_is_told_to_use_link(self):
        env = {"HOME": self.home, "PATH": os.environ.get("PATH", ""), "SHELL": "/bin/bash"}
        r = run(["bash", os.path.join(self.clone, "setup.sh"), "--no-test", "--write-rc"], env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("--link", r.stdout)
        self.assertFalse(os.path.exists(os.path.join(self.home, ".zshrc")))

    def test_unknown_option_is_a_usage_error(self):
        self.assertEqual(self.setup("--nope").returncode, 2)


class ReadmePrompt(unittest.TestCase):
    START, END = "<!-- ai-setup-prompt:start -->", "<!-- ai-setup-prompt:end -->"

    def prompt(self):
        text = read(os.path.join(ROOT, "README.md"))
        self.assertIn(self.START, text)
        self.assertIn(self.END, text)
        return re.sub(r"[ \t]*\n[ \t]*", " ", text.split(self.START, 1)[1].split(self.END, 1)[0])  # one line: wrapping may change

    def test_every_file_the_prompt_names_exists(self):
        names = {n[2:] if n.startswith("./") else n
                 for n in re.findall(r"[\w./-]+\.(?:sh|zsh|py|json|md|yaml)\b", self.prompt())}
        self.assertTrue(names)
        elsewhere = {"local.zsh", "bootstrap.sh"}  # created by setup.sh / lives in the sdw repo named in Part B
        missing = [n for n in sorted(names) if not os.path.exists(os.path.join(ROOT, n)) and n not in elsewhere]
        self.assertEqual(missing, [])

    def test_the_prompt_keeps_its_safety_rules(self):
        p = self.prompt().lower()
        for phrase in ("--dry-run", "never read, print or ask me for", "api key", "without sudo",
                       "do not commit or push", "ask me before", "stop and show me the error"):
            self.assertIn(phrase, p, phrase)
        self.assertIn("do not run ./route/setup.sh --with-proxy unless i ask", p)

    def test_part_b_is_optional_and_does_not_let_the_agent_touch_claude_settings_unasked(self):
        p = self.prompt().lower()
        for phrase in ("only if i use claude code and say yes", "./bootstrap.sh --dry-run", "settings diff", "claude_config_dir",
                       "only after i say yes, run ./bootstrap.sh with no other option",
                       "never run --uninstall, --update or --migrate", "do not onboard a project for me"):
            self.assertIn(phrase, p, phrase)

    def test_the_prompt_points_at_the_repo_and_the_tests(self):
        p = self.prompt()
        self.assertIn("github.com/jpeseWang/portolan", p)
        self.assertIn("tests/route/test_routing.py", p)
        self.assertIn("tests/route/test_portable.py", p)


class AgentFiles(unittest.TestCase):
    def test_agents_md_exists_and_claude_md_imports_it(self):
        self.assertTrue(os.path.exists(os.path.join(ROOT, "AGENTS.md")))
        self.assertIn("@AGENTS.md", read(os.path.join(ROOT, "CLAUDE.md")))


if __name__ == "__main__":
    unittest.main(verbosity=1)
