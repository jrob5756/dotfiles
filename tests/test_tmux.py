import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("tmux"), "tmux is required")
class TmuxTests(unittest.TestCase):
    def test_managed_and_compatibility_configs(self):
        configs = [Path(os.environ.get("DOTFILES_LEGACY_TMUX_CONFIG", ROOT / "tmux/tmux.conf"))]
        if os.environ.get("DOTFILES_TMUX_CONFIG"):
            configs.append(Path(os.environ["DOTFILES_TMUX_CONFIG"]))
        for source in configs:
            with self.subTest(source=source), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                socket = root / "socket"
                config = root / "tmux.conf"
                # Plugin launchers are excluded so tests cannot restore real sessions.
                config.write_text(re.sub(r"(?m)^\s*run(?:-shell)?\s+.*$", "", source.read_text()))
                env = {
                    **os.environ, "HOME": str(root), "TMUX": "",
                    "XDG_CONFIG_HOME": str(root / ".config"),
                    "XDG_DATA_HOME": str(root / ".local/share"),
                    "XDG_STATE_HOME": str(root / ".local/state"),
                }

                def tmux(*args):
                    return subprocess.run(
                        ["tmux", "-S", str(socket), *args], env=env,
                        text=True, capture_output=True, check=True,
                    ).stdout.strip()

                try:
                    tmux("-f", str(config), "new-session", "-d", "-s", "dev", "sleep 60")
                    expected = {
                        "prefix": "C-a", "mouse": "on", "history-limit": "10000",
                        "escape-time": "10", "status-position": "top",
                        "set-clipboard": "on", "allow-passthrough": "on",
                    }
                    for option, value in expected.items():
                        self.assertEqual(tmux("show-options", "-gv", option), value)
                    self.assertEqual(len(tmux("list-panes", "-t", "dev").splitlines()), 1)
                    self.assertEqual(tmux("show-hooks", "-g", "session-created"), "session-created")
                    bindings = {}
                    for line in tmux("list-keys", "-T", "prefix").splitlines():
                        words = shlex.split(line)
                        table = words.index("-T")
                        bindings[words[table + 2]] = words[table + 3:]
                    self.assertIn("confirm-before", bindings["&"])
                    self.assertNotIn("split-window", bindings.get("D", []))
                finally:
                    subprocess.run(["tmux", "-S", str(socket), "kill-server"], env=env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
