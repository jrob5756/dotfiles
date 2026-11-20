import ctypes
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "windows/devbox-ssh/setup.ps1"
PWSH = shutil.which("pwsh")


@unittest.skipUnless(os.name == "nt" and PWSH, "Native Windows and PowerShell 7 required")
class DevBoxSshPreviewTests(unittest.TestCase):
    def setUp(self):
        fixture = tempfile.TemporaryDirectory(prefix=".devbox-ssh-fixture-", dir=ROOT / "tests")
        self.addCleanup(fixture.cleanup)
        self.home = Path(fixture.name) / "home"
        self.home.mkdir()

    def invoke(self, *args, computer="CPC-FIXTURE", devtunnel=True, env=None):
        # A missing devtunnel keeps the preview offline; an unused port avoids matching a live sshd.
        parameters = ["-HomePath", str(self.home), "-TunnelId", "fixture-devbox", "-Port", "2299", *args]
        if devtunnel:
            parameters += ["-DevTunnelPath", str(self.home / "missing/devtunnel.exe")]
        return subprocess.run(
            [PWSH, "-NoProfile", "-File", str(SCRIPT), *parameters],
            capture_output=True, text=True, env=dict(os.environ, COMPUTERNAME=computer, **(env or {})),
        )

    def home_contents(self):
        return sorted(str(path.relative_to(self.home)) for path in self.home.rglob("*"))

    def test_preview_is_read_only_and_renders_a_loopback_key_only_config(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.home_contents(), [])
        self.assertIn("Inspection only; nothing changed.", result.stdout)
        config = [line.strip() for line in result.stdout.split("sshd_config to write:", 1)[1].splitlines()]
        self.assertIn("Port 2299", config)
        self.assertEqual(
            [line for line in config if line.startswith("ListenAddress")],
            ["ListenAddress 127.0.0.1", "ListenAddress ::1"],
        )
        self.assertIn("PasswordAuthentication no", config)
        self.assertIn("KbdInteractiveAuthentication no", config)

    def test_refuses_machines_that_are_not_dev_boxes_unless_forced(self):
        result = self.invoke(computer="DESKTOP-FIXTURE")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("-Force", result.stdout + result.stderr)
        forced = self.invoke("-Force", computer="DESKTOP-FIXTURE")
        self.assertEqual(forced.returncode, 0, forced.stdout + forced.stderr)
        self.assertEqual(self.home_contents(), [])

    def test_preview_works_before_devtunnel_is_installed(self):
        system = os.path.join(os.environ["SystemRoot"], "System32")
        result = self.invoke(devtunnel=False, env={"PATH": system, "LOCALAPPDATA": str(self.home)})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Inspection only; nothing changed.", result.stdout)
        self.assertEqual(self.home_contents(), [])

    def test_preview_offers_to_trust_symlinks_ssh_sessions_cannot_follow(self):
        config = self.home / ".config"
        config.mkdir()
        (config / "target.toml").write_text("format = '$directory'\n")
        try:
            (config / "starship.toml").symlink_to(config / "target.toml")
        except OSError:
            self.skipTest("Creating symlinks needs Developer Mode or elevation")
        (self.home / "nvim").mkdir()  # a real directory, not a link
        result = self.invoke(env={"LOCALAPPDATA": str(self.home)})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        steps = [line for line in result.stdout.splitlines() if "follow them" in line]
        # Links created elevated (as on CI runners) are trusted, so there is nothing to re-create.
        if ctypes.windll.shell32.IsUserAnAdmin():
            self.assertEqual(steps, [], result.stdout)
            return
        self.assertEqual(len(steps), 1, result.stdout)
        self.assertIn(str(config / "starship.toml"), steps[0])
        self.assertNotIn(str(self.home / "nvim"), steps[0])


if __name__ == "__main__":
    unittest.main()
