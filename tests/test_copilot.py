import json
import os
from pathlib import Path
import sqlite3
import stat
import subprocess
import tempfile
import unittest


STATUSLINE = os.environ.get("DOTFILES_COPILOT_STATUSLINE")
MERGE = os.environ.get("DOTFILES_COPILOT_MERGE_SETTINGS")
SESSION_TOOLS = os.environ.get("DOTFILES_COPILOT_SESSION_TOOLS")


class Temp(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)


@unittest.skipUnless(STATUSLINE, "DOTFILES_COPILOT_STATUSLINE must name the built script (nix flake check sets it)")
class StatusLineTests(Temp):
    def status(self, payload):
        env = {**os.environ, "SESSION_TAGS_DB": str(self.root / "tags.db")}
        return subprocess.run([STATUSLINE], input=json.dumps(payload), env=env,
                              capture_output=True, text=True, check=True).stdout

    def test_shows_the_session_tags_between_name_and_id(self):
        with sqlite3.connect(self.root / "tags.db") as db:
            db.execute("CREATE TABLE session_tags (session_id TEXT, tag TEXT)")
            db.executemany("INSERT INTO session_tags VALUES (?, ?)",
                           [("abc-1", "tools"), ("abc-1", "browser"), ("other", "x")])
        self.assertEqual(self.status({"session_name": "Name", "session_id": "abc-1"}),
                         "Name · #browser #tools · abc-1\n")

    def test_works_without_tags_or_a_name(self):
        self.assertEqual(self.status({"session_name": "", "session_id": "abc-1"}), "abc-1\n")

    def test_ignores_ids_that_could_break_the_query(self):
        (self.root / "tags.db").write_text("not a database")
        self.assertEqual(self.status({"session_id": "x';--"}), "x';--\n")


@unittest.skipUnless(MERGE, "DOTFILES_COPILOT_MERGE_SETTINGS must name the built script (nix flake check sets it)")
class MergeSettingsTests(Temp):
    def merge(self, patch):
        env = {**os.environ, "COPILOT_HOME": str(self.root)}
        return subprocess.run([MERGE, json.dumps(patch)], env=env,
                              capture_output=True, text=True, check=True)

    @property
    def settings(self):
        return self.root / "settings.json"

    def test_merges_only_the_named_keys_and_keeps_the_rest(self):
        self.settings.write_text(json.dumps(
            {"model": "m", "statusLine": {"command": "old", "padding": 2}}))
        self.merge({"statusLine": {"command": "new", "refreshInterval": 5}})
        self.assertEqual(json.loads(self.settings.read_text()), {
            "model": "m", "statusLine": {"command": "new", "padding": 2, "refreshInterval": 5}})
        self.assertEqual(stat.S_IMODE(self.settings.stat().st_mode), 0o600)

    def test_creates_the_file_and_leaves_it_alone_when_unchanged(self):
        self.merge({"statusLine": {"command": "c"}})
        before = self.settings.stat().st_mtime_ns
        result = self.merge({"statusLine": {"command": "c"}})
        self.assertEqual(result.stderr + result.stdout, "")
        self.assertEqual(self.settings.stat().st_mtime_ns, before)

    def test_leaves_invalid_json_untouched(self):
        self.settings.write_text("{ // comment\n}")
        result = self.merge({"statusLine": {"command": "c"}})
        self.assertIn("isn't valid JSON", result.stderr)
        self.assertEqual(self.settings.read_text(), "{ // comment\n}")


@unittest.skipUnless(SESSION_TOOLS, "DOTFILES_COPILOT_SESSION_TOOLS must name the built bin dir (nix flake check sets it)")
class SessionToolsTests(Temp):
    def run_tool(self, *args, **env):
        # A bare PATH: the wrappers must supply sqlite3 and each other.
        env = {"PATH": "/usr/bin:/bin", "HOME": str(self.root), "COPILOT_HOME": str(self.root / "copilot"),
               "SESSION_TAGS_DB": str(self.root / "tags.db"), **env}
        return subprocess.run([str(Path(SESSION_TOOLS) / args[0]), *args[1:]], env=env,
                              capture_output=True, text=True, check=True).stdout

    def tags(self, session):
        return self.run_tool("session-tags", "ls", "-s", session).split()

    def test_browser_toggles_tags_through_session_tags(self):
        pick = self.root / "pick"
        pick.write_text("abc-1\nabc-2\n")
        self.run_tool("session-tags", "add", "-s", "abc-1", "x")
        self.run_tool("session-browser", "--tag-toggle", "x", SESSION_BROWSER_PICK_FILE=str(pick))
        self.assertEqual((self.tags("abc-1"), self.tags("abc-2")), (["x"], ["x"]))
        self.run_tool("session-browser", "--tag-toggle", "x", SESSION_BROWSER_PICK_FILE=str(pick))
        self.assertEqual((self.tags("abc-1"), self.tags("abc-2")), ([], []))

    def test_help_comes_from_the_script_not_the_wrapper(self):
        self.assertIn("Usage: session-tags <command>", self.run_tool("session-tags", "--help"))


if __name__ == "__main__":
    unittest.main()
