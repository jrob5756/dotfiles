import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import time
import unittest


MANAGED = os.environ.get("DOTFILES_TMUX_CONFIG")


@unittest.skipUnless(MANAGED, "DOTFILES_TMUX_CONFIG must name the rendered config (nix flake check sets it)")
class RenderedOrderTests(unittest.TestCase):
    def test_status_right_is_set_before_continuum_loads(self):
        # continuum appends its autosave hook to status-right when it loads.
        lines = Path(MANAGED).read_text().splitlines()
        continuum = max(i for i, line in enumerate(lines) if "continuum.tmux" in line)
        later = [line for line in lines[continuum:] if re.match(r"^\s*set\S*\s+(-\S+\s+)*status-right\b", line)]
        self.assertEqual(later, [])


@unittest.skipUnless(shutil.which("tmux") and MANAGED, "tmux and DOTFILES_TMUX_CONFIG are required")
class TmuxTests(unittest.TestCase):
    def test_managed_config(self):
        source = Path(MANAGED)
        with tempfile.TemporaryDirectory() as temporary:
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
                    "prefix": "C-a", "mouse": "on", "history-limit": "50000",
                    "escape-time": "10", "status-position": "top",
                    "set-clipboard": "on", "allow-passthrough": "on",
                    "detach-on-destroy": "off",
                    "status-style": "bg=default,fg=#cdd6f4",
                }
                for option, value in expected.items():
                    self.assertEqual(tmux("show-options", "-gv", option), value)
                self.assertEqual(tmux("show-options", "-sv", "extended-keys"), "always")
                self.assertEqual(
                    tmux("show-options", "-sv", "extended-keys-format"), "csi-u"
                )
                tmux("source-file", str(config))
                terminal_features = tmux(
                    "show-options", "-sv", "terminal-features"
                ).splitlines()
                self.assertEqual(
                    terminal_features.count("xterm-ghostty:extkeys"), 1
                )
                root_bindings = tmux("list-keys", "-T", "root")
                self.assertRegex(
                    root_bindings,
                    r"(?m)^bind-key\s+-T root S-Enter\s+send-keys Escape Enter$",
                )
                self.assertEqual(len(tmux("list-panes", "-t", "dev").splitlines()), 1)
                self.assertEqual(tmux("show-hooks", "-g", "session-created"), "session-created")
                bindings = {}
                for line in tmux("list-keys", "-T", "prefix").splitlines():
                    words = shlex.split(line)
                    table = words.index("-T")
                    bindings[words[table + 2]] = words[table + 3:]
                self.assertIn("confirm-before", bindings["&"])
                self.assertEqual(
                    bindings["x"],
                    ["confirm-before", "-p", "kill-pane #P? (y/n)", "kill-pane"],
                )
                self.assertEqual(bindings["X"], ["kill-pane"])
                self.assertNotIn("split-window", bindings.get("D", []))
                self.assertEqual(
                    bindings["c"], ["new-window", "-c", "#{pane_current_path}"]
                )
                self.assertEqual(bindings["C-l"], ["send-keys", "C-l"])
                for key in ("s", "f"):
                    self.assertIn("display-popup", bindings[key])
                    switcher = bindings[key][-1]
                    self.assertTrue(os.access(switcher, os.X_OK), switcher)
                self.assertIn("display-popup", bindings["g"])
                self.assertTrue(bindings["g"][-1].endswith("/bin/lazygit"), bindings["g"])
                self.assertIn("if-shell", bindings["`"])
                self.assertRegex(" ".join(bindings["`"]), r"new-session -A -s scratch")
            finally:
                subprocess.run(["tmux", "-S", str(socket), "kill-server"], env=env,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


@unittest.skipUnless(shutil.which("tmux") and MANAGED, "tmux and DOTFILES_TMUX_CONFIG are required")
class CopilotResumeTests(unittest.TestCase):
    def test_save_hook_pins_copilot_panes_to_their_sessions(self):
        text = Path(MANAGED).read_text()
        hook = re.search(r"@resurrect-hook-post-save-layout '([^']+)'", text).group(1)
        self.assertIn("""@resurrect-processes '"~copilot.*--resume="'""", text)
        flagged, locked, stale = (f"{n}{n * 7}-{n * 4}-{n * 4}-{n * 4}-{n * 12}" for n in "abc")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            socket = root / "socket"
            copilot = root / "bin" / "copilot"
            copilot.parent.mkdir()
            copilot.write_text('#!/bin/sh\ntouch "$HOME/started.$$"\nsleep 60 &\ntrap \'kill $!\' EXIT HUP TERM\nwait\n')
            copilot.chmod(0o755)
            env = {**os.environ, "HOME": str(root), "TMUX": f"{socket},0,0"}

            def tmux(*args):
                return subprocess.run(["tmux", "-S", str(socket), *args], env=env,
                                      text=True, capture_output=True, check=True).stdout.strip()

            try:
                tmux("-f", "/dev/null", "new-session", "-d", "-s", "dev", "-x", "80", "-y", "24",
                     f"{copilot} --yolo --new-session-id {flagged}")
                # A /resume switch leaves stale flags; the lock names the live session.
                tmux("new-window", "-d", "-t", "dev:", f"{copilot} --yolo --resume={stale}")
                tmux("new-window", "-d", "-t", "dev:", "sleep 60")
                panes = [line.split("\t") for line in tmux(
                    "list-panes", "-a", "-F", "#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_pid}"
                ).splitlines()]
                lock = root / ".copilot/session-state" / locked / f"inuse.{panes[1][3]}.lock"
                lock.parent.mkdir(parents=True)
                lock.touch()
                for _ in range(50):
                    if len(list(root.glob("started.*"))) >= 2:
                        break
                    time.sleep(0.1)

                saved = [
                    "agency copilot --yolo --model m --resume=x",
                    "node /opt/homebrew/bin/copilot --yolo -r",
                    "sleep 60",
                ]
                save = root / "save.txt"
                prefix = lambda p: "\t".join(["pane", p[0], p[1], "1", ":*", p[2], "t", ":/tmp", "1", "x"])
                save.write_text("".join(f"{prefix(p)}\t:{c}\n" for p, c in zip(panes, saved)) + "state\tdev\t\n")
                subprocess.run([hook, str(save)], env=env, check=True)

                self.assertEqual(save.read_text().splitlines(), [
                    f"{prefix(panes[0])}\t:env -u TMUX agency copilot --yolo --model m --resume={flagged}",
                    f"{prefix(panes[1])}\t:_dotfiles_copilot --yolo --resume={locked}",
                    f"{prefix(panes[2])}\t:sleep 60",
                    "state\tdev\t",
                ])
            finally:
                subprocess.run(["tmux", "-S", str(socket), "kill-server"], env=env,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
