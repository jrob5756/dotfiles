import ctypes
import json
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

    def invoke(self, *args, computer="CPC-FIXTURE", devtunnel=True, env=None, name="fixture-devbox", port=2299):
        # A missing devtunnel keeps the preview offline; an unused port avoids matching a live sshd.
        parameters = ["-HomePath", str(self.home), *args]
        if name:
            parameters += ["-Name", name]
        if port:
            parameters += ["-Port", str(port)]
        if devtunnel is True:
            parameters += ["-DevTunnelPath", str(self.home / "missing/devtunnel.exe")]
        elif devtunnel:
            parameters += ["-DevTunnelPath", str(devtunnel)]
        return subprocess.run(
            [PWSH, "-NoProfile", "-File", str(SCRIPT), *parameters],
            capture_output=True, text=True, env=dict(os.environ, COMPUTERNAME=computer, **(env or {})),
        )

    def fake_devtunnel(self, tunnels):
        """A signed-in devtunnel CLI that knows {id: (description, [ports])} and changes nothing."""
        data = self.home.parent / "tunnels.json"
        data.write_text(json.dumps({k: {"description": d, "ports": p} for k, (d, p) in tunnels.items()}))
        script = self.home.parent / "devtunnel.ps1"
        script.write_text(r"""
$tunnels = Get-Content -Raw '%s' | ConvertFrom-Json -AsHashtable
switch ($args[0]) {
    'user' { 'Logged in as fixture'; exit 0 }
    'list' {
        @{ tunnels = @($tunnels.Keys | ForEach-Object {
            @{ tunnelId = "$_.use"; hostConnections = 1; description = $tunnels[$_].description } }) } |
            ConvertTo-Json -Depth 5
        exit 0
    }
    'show' {
        $id = $args[1] -replace '\.use$'
        if (-not $tunnels.ContainsKey($id)) { "Tunnel not found: $id"; exit 1 }
        @{ tunnel = @{ tunnelId = "$id.use"; hostConnections = 1; description = $tunnels[$id].description
            ports = @($tunnels[$id].ports | ForEach-Object { @{ portNumber = $_ } }) } } | ConvertTo-Json -Depth 5
        exit 0
    }
}
exit 1
""" % data)
        return script

    def rendered_port(self, result):
        return [line.strip() for line in result.stdout.splitlines() if line.strip().startswith("Port ")]

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

    def test_first_setup_requires_a_name(self):
        if subprocess.run(["schtasks", "/query", "/tn", "DevBox SSH"], capture_output=True).returncode == 0:
            self.skipTest("an installed DevBox SSH task supplies the name")
        result = self.invoke(name=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("-Name", result.stdout + result.stderr)

    def test_rerun_keeps_the_installed_port(self):
        state = self.home / ".ssh/devbox-sshd"
        state.mkdir(parents=True)
        (state / "sshd_config").write_text("Port 2301\r\n")
        result = self.invoke(port=None)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.rendered_port(result), ["Port 2301"])

    def test_new_box_gets_the_lowest_port_no_other_box_uses(self):
        devtunnel = self.fake_devtunnel({
            "box-a": ("SSH to CPC-A", [2222]),
            "box-b": ("SSH to CPC-B", [2223]),
            "unrelated": ("web app", [2224]),
        })
        result = self.invoke(devtunnel=devtunnel, name="box-new", port=None)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.rendered_port(result), ["Port 2224"])
        self.assertIn("create tunnel box-new; add port 2224 to tunnel box-new", result.stdout)

    def test_refuses_another_computers_tunnel_unless_forced(self):
        devtunnel = self.fake_devtunnel({"fixture-devbox": ("SSH to CPC-OTHER", [2299])})
        result = self.invoke(devtunnel=devtunnel)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("belongs to CPC-OTHER", result.stdout + result.stderr)
        forced = self.invoke("-Force", devtunnel=devtunnel)
        self.assertEqual(forced.returncode, 0, forced.stdout + forced.stderr)
        self.assertIn("describe tunnel fixture-devbox as this computer's", forced.stdout)

    def test_removes_ports_clients_would_also_forward(self):
        devtunnel = self.fake_devtunnel({"fixture-devbox": ("SSH to CPC-FIXTURE", [2222, 2299])})
        result = self.invoke(devtunnel=devtunnel)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("remove port(s) 2222 from tunnel fixture-devbox", result.stdout)
        self.assertNotIn("add port", result.stdout)

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
