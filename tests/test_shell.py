import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
COMMON = os.environ.get("DOTFILES_COMMON", str(ROOT / "shell/common.sh"))
BASH = shutil.which("bash")
ZSH = shutil.which("zsh")

if os.environ.get("REQUIRE_ZSH") == "1" and not ZSH:
    raise RuntimeError("Zsh is required for the flake's shell checks")


class UpdaterTests:
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls"
        self.git_bin = shutil.which("git")
        for name in ("python3", "git", "dirname", "readlink", "env"):
            (self.bin / name).symlink_to(shutil.which(name))
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("GIT_")
        }
        self.env.update(
            HOME=str(self.home),
            PATH=str(self.bin),
            XDG_CONFIG_HOME=str(self.home / ".config"),
            COPILOT_CONFIG_DIR=str(self.home / ".copilot"),
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_TERMINAL_PROMPT="0",
            TEST_LOG=str(self.log),
            COMMON=COMMON,
            FAIL_CATALOG="0",
            FAIL_PLUGINS="0",
        )
        self.write_executable(
            self.bin / "copilot",
            """
printf '%s\\n' "$*" >> "$TEST_LOG"
if [ "$*" = "plugin marketplace update" ]; then
    exit "$FAIL_CATALOG"
fi
if [ "$FAIL_PLUGINS" -ne 0 ]; then
    echo "plugin failure" >&2
    exit "$FAIL_PLUGINS"
fi
echo "No plugins installed."
""",
        )

    def write_executable(self, path, body):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"#!{BASH}\n{body}", encoding="utf-8")
        path.chmod(0o755)

    def run_shell(self, command='source "$COMMON"; cup'):
        flags = ["--noprofile", "--norc"] if self.shell == BASH else ["-f"]
        return subprocess.run(
            [self.shell, *flags, "-c", command],
            cwd=self.root, env=self.env, text=True, capture_output=True,
        )

    def settings(self, data):
        path = self.home / ".copilot/settings.json"
        path.parent.mkdir(exist_ok=True)
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def marketplace(self, path):
        self.settings({
            "extraKnownMarketplaces": {
                "local": {"source": {"source": "directory", "path": str(path)}}
            }
        })

    def git(self, *args):
        return subprocess.run(
            [self.git_bin, *args], cwd=self.root, env=self.env,
            text=True, capture_output=True, check=True,
        )

    def repository(self):
        remote = self.root / "remote.git"
        repo = self.root / "repo with spaces"
        self.git("init", "--bare", "--initial-branch=main", str(remote))
        self.git("clone", str(remote), str(repo))
        self.git("-C", str(repo), "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "Initial")
        self.git("-C", str(repo), "push", "-u", "origin", "main")
        return repo

    def assert_cli_updates(self):
        self.assertEqual(
            self.log.read_text().splitlines(),
            ["plugin marketplace update", "plugin update --all"],
        )

    def test_missing_settings_still_updates_plugins(self):
        result = self.run_shell()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("No plugins installed.", result.stdout)
        self.assert_cli_updates()

    def test_clean_repository_preserves_path(self):
        self.marketplace(self.repository())
        result = self.run_shell(
            'source "$COMMON"; before=$PATH; cup; code=$?; '
            '[[ $PATH == "$before" ]] || exit 99; exit "$code"'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_cli_updates()

    def test_worktree_subdirectory_is_supported(self):
        repo = self.repository()
        linked = self.root / "linked worktree"
        self.git("-C", str(repo), "worktree", "add", "-b", "linked", str(linked))
        self.git("-C", str(linked), "branch", "--set-upstream-to=origin/main")
        nested = linked / "marketplace"
        nested.mkdir()
        self.marketplace(nested)
        result = self.run_shell()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("pulling local", result.stdout)
        self.assert_cli_updates()

    def test_tilde_path_is_expanded(self):
        self.repository()
        self.marketplace("~/../repo with spaces")
        result = self.run_shell()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_cli_updates()

    def test_independent_marketplaces_continue_after_failure(self):
        repo = self.repository()
        self.settings({"extraKnownMarketplaces": {
            "missing": {"source": {"source": "directory", "path": str(self.root / "absent")}},
            "working": {"source": {"source": "directory", "path": str(repo)}},
        }})
        result = self.run_shell()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pulling working", result.stdout)
        self.assert_cli_updates()

    def test_dirty_repository_is_not_pulled(self):
        repo = self.repository()
        (repo / "uncommitted.txt").write_text("Keep me")
        self.marketplace(repo)
        result = self.run_shell()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("uncommitted changes", result.stderr)
        self.assertEqual((repo / "uncommitted.txt").read_text(), "Keep me")
        self.assert_cli_updates()

    def test_pull_failure_is_reported(self):
        repo = self.repository()
        self.git("-C", str(repo), "remote", "remove", "origin")
        self.marketplace(repo)
        result = self.run_shell()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pull failed", result.stderr)
        self.assert_cli_updates()

    def test_missing_directory_is_reported(self):
        self.marketplace(self.root / "absent")
        result = self.run_shell()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not exist", result.stderr)
        self.assert_cli_updates()

    def test_non_git_directory_is_reported(self):
        self.marketplace(self.home)
        result = self.run_shell()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a usable Git worktree", result.stderr)
        self.assert_cli_updates()

    def test_status_failure_is_not_treated_as_clean(self):
        self.marketplace(self.home)
        (self.bin / "git").unlink()
        self.write_executable(self.bin / "git", """
if [ "$3" = "rev-parse" ]; then
    echo true
elif [ "$3" = "status" ]; then
    echo "simulated status error" >&2
    exit 42
else
    echo "unexpected Git command" >&2
    exit 99
fi
""")
        result = self.run_shell()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot inspect", result.stderr)
        self.assertNotIn("unexpected Git command", result.stderr)
        self.assert_cli_updates()

    def test_invalid_settings_abort_before_updates(self):
        for invalid in ([], {"extraKnownMarketplaces": []},
                        {"extraKnownMarketplaces": {"broken": None}},
                        {"extraKnownMarketplaces": {"broken": {
                            "source": {"source": "directory", "path": "bad\npath"}
                        }}},
                        {"extraKnownMarketplaces": {"broken": {
                            "source": {"source": "directory", "path": "bad\0path"}
                        }}},
                        {"extraKnownMarketplaces": {"bad\0name": {
                            "source": {"source": "directory", "path": "/some/path"}
                        }}}):
            with self.subTest(data=invalid):
                self.settings(invalid)
                result = self.run_shell()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cannot parse", result.stderr)
                self.assertFalse(self.log.exists())

    def test_malformed_json_aborts_before_updates(self):
        self.settings({}).write_text("{broken")
        result = self.run_shell()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())

    def test_unreadable_settings_aborts_before_updates(self):
        path = self.home / ".copilot/settings.json"
        path.mkdir(parents=True)
        result = self.run_shell()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot read", result.stderr)
        self.assertFalse(self.log.exists())

    def test_whole_line_comments_are_accepted(self):
        self.settings({}).write_text('// comment\n{"extraKnownMarketplaces": {}}')
        result = self.run_shell()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_cli_updates()

    def test_catalog_failure_is_not_masked(self):
        self.env["FAIL_CATALOG"] = "23"
        result = self.run_shell()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("catalog update failed", result.stderr)
        self.assert_cli_updates()

    def test_plugin_failure_is_not_masked(self):
        self.env["FAIL_PLUGINS"] = "24"
        result = self.run_shell()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("plugin failure", result.stderr)
        self.assert_cli_updates()

    def test_fallback_uses_highest_executable_version_without_gnu_sort(self):
        (self.bin / "copilot").unlink()
        for version in ("0.9.0", "0.10.0", "0.11.0"):
            self.write_executable(self.home / ".copilot-cli" / version / "copilot", "exit 0")
        (self.home / ".copilot-cli/0.11.0/copilot").chmod(0o644)
        result = self.run_shell('source "$COMMON"; _copilot_bin')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.home / ".copilot-cli/0.10.0/copilot"))

    def test_missing_copilot_is_reported(self):
        (self.bin / "copilot").unlink()
        result = self.run_shell()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("copilot CLI not found", result.stderr)
        self.assertFalse(self.log.exists())

    def test_copilot_launcher_preserves_arguments_and_parent_environment(self):
        self.env["TMUX"] = "parent"
        self.write_executable(self.bin / "copilot", """
printf '%s\\n' "${TMUX-unset}" "$#" "$1" "$2"
""")
        result = self.run_shell(
            'source "$COMMON"; _dotfiles_copilot --yolo "path with spaces"; printf "%s\\n" "$TMUX"'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["unset", "2", "--yolo", "path with spaces", "parent"])

    def test_manual_rc_follows_relative_symlinks_to_shared_helpers(self):
        if self.shell == BASH:
            content = Path(os.environ.get("DOTFILES_BASHRC", ROOT / "bash/bashrc")).read_text()
            start = content.index("_dotfiles_bashrc=${BASH_SOURCE[0]}")
            end = content.index("unset _dotfiles_bashrc _dotfiles_dir", start)
            loader = content[start:end] + "unset _dotfiles_bashrc _dotfiles_dir\n"
            shell_dir = "bash"
        else:
            content = Path(os.environ.get("DOTFILES_ZSHRC", ROOT / "zsh/zshrc")).read_text()
            loader = next(line for line in content.splitlines()
                          if line.startswith("source ") and "/shell/common.sh" in line)
            shell_dir = "zsh"
        checkout = self.root / "checkout with spaces"
        (checkout / shell_dir).mkdir(parents=True)
        (checkout / "shell").mkdir()
        (checkout / "shell/common.sh").symlink_to(COMMON)
        rc = checkout / shell_dir / "rc"
        rc.write_text(loader)
        (checkout / shell_dir / "link").symlink_to("rc")
        entry = self.home / "rc"
        entry.symlink_to(f"../checkout with spaces/{shell_dir}/link")
        self.env["RC"] = str(entry)
        result = self.run_shell('source "$RC"; typeset -f cup')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("plugin marketplace update", result.stdout)


class BashTests(UpdaterTests, unittest.TestCase):
    shell = BASH


@unittest.skipUnless(ZSH, "Zsh is not installed")
class ZshTests(UpdaterTests, unittest.TestCase):
    shell = ZSH
