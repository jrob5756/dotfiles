import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest


ADD = os.environ.get("DOTFILES_DEVBOX_ADD")
FORWARD = os.environ.get("DOTFILES_DEVTUNNEL_FORWARD")
BASH = shutil.which("bash")


class Temp(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls"

    def executable(self, name, body, interpreter=BASH):
        path = self.bin / name
        path.write_text(f"#!{interpreter}\n{body}", encoding="utf-8")
        path.chmod(0o755)
        return path

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def free_listener(self):
        """A local port with something listening, as a forwarding devtunnel would have."""
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen()
        self.addCleanup(server.close)
        return server.getsockname()[1]


@unittest.skipUnless(ADD, "DOTFILES_DEVBOX_ADD must name the built script (nix flake check sets it)")
class DevboxAddTests(Temp):
    def setUp(self):
        super().setUp()
        self.home = self.root / "home"
        (self.home / ".ssh").mkdir(parents=True)
        (self.home / ".ssh/id_ed25519").write_text("key")
        self.tunnels = {}
        self.executable("devtunnel", f"""
echo "devtunnel $*" >> '{self.log}'
case "$1" in
  user) echo "Logged in as fixture" ;;
  show) exec '{sys.executable}' -c 'import json, sys; t = json.load(open(sys.argv[1])).get(sys.argv[2])
if t is None: sys.exit(1)
print(json.dumps({{"tunnel": t}}))' '{self.root / "tunnels.json"}' "$2" ;;
  *) exit 1 ;;
esac
""")
        self.executable("launchctl", f"echo \"launchctl $*\" >> '{self.log}'\n[ \"$1\" != print ]")
        self.executable("ssh-keygen", f"echo \"ssh-keygen $*\" >> '{self.log}'")
        self.ssh_output, self.ssh_status = "CPC-FIXTURE", 0
        self.env = {**os.environ, "HOME": str(self.home), "PATH": f"{self.bin}:{os.environ['PATH']}",
                    "DEVBOX_FORWARD": "/fixture/devtunnel-forward", "DEVBOX_ADD_WAIT": "2"}

    def tunnel(self, name, ports, owner="CPC-FIXTURE", hosts=1):
        self.tunnels[name] = {"tunnelId": f"{name}.use", "hostConnections": hosts,
                              "description": f"SSH to {owner}", "ports": [{"portNumber": p} for p in ports]}
        (self.root / "tunnels.json").write_text(json.dumps(self.tunnels))

    def add(self, *args):
        self.executable("ssh", f"echo \"ssh $*\" >> '{self.log}'\necho '{self.ssh_output}'\nexit {self.ssh_status}")
        return subprocess.run([ADD, *args], env=self.env, capture_output=True, text=True)

    def conf(self, name):
        return (self.home / f".ssh/devboxes/{name}.conf").read_text()

    def plist(self, name):
        return self.home / f"Library/LaunchAgents/dotfiles.devtunnel.{name}.plist"

    def test_adds_a_box_with_the_tunnel_port_and_starts_its_agent(self):
        port = self.free_listener()
        self.tunnel("box-8", [port])
        result = self.add("box-8", "DOMAIN\\user")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        conf = self.conf("box-8")
        for line in ("Host box-8", "HostName 127.0.0.1", f"Port {port}", "User DOMAIN\\user", "HostKeyAlias box-8"):
            self.assertIn(line, conf)
        plist = self.plist("box-8").read_text()
        self.assertIn(f"<string>/fixture/devtunnel-forward</string>\n    <string>{self.bin / 'devtunnel'}</string>"
                      f"\n    <string>box-8</string>\n    <string>{port}</string>", plist)
        self.assertIn(f"launchctl bootstrap gui/{os.getuid()} {self.plist('box-8')}", self.calls())
        self.assertIn("Ready: ssh box-8 reached CPC-FIXTURE.", result.stdout)
        self.assertEqual(oct((self.home / ".ssh/devboxes").stat().st_mode & 0o777), "0o700")

    def test_reuses_another_boxs_user_and_skips_the_login_without_a_host(self):
        self.tunnel("box-7", [2223])
        self.tunnel("box-8", [2224], hosts=0)
        self.assertEqual(self.add("box-7", "DOMAIN\\user").returncode, 0)
        result = self.add("box-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("User DOMAIN\\user", self.conf("box-8"))
        self.assertIn("no host right now", result.stdout)
        self.assertNotIn("ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 box-8 hostname",
                         self.calls())

    def test_needs_a_user_for_the_first_box(self):
        self.tunnel("box-8", [2224], hosts=0)
        result = self.add("box-8")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pass the remote user", result.stderr)

    def test_refuses_a_port_another_box_uses(self):
        self.tunnel("box-7", [2223], hosts=0)
        self.tunnel("box-8", [2223], hosts=0)
        self.assertEqual(self.add("box-7", "u").returncode, 0)
        result = self.add("box-8")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("port 2223 is already used by box-7", result.stderr)
        self.assertFalse(self.plist("box-8").exists())

    def test_refuses_tunnels_without_exactly_one_port(self):
        self.tunnel("box-8", [2222, 2223], hosts=0)
        result = self.add("box-8", "u")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exactly one port", result.stderr)

    def test_explains_how_to_create_a_missing_tunnel(self):
        result = self.add("box-9", "u")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("setup.ps1 -Name box-9 -Apply", result.stderr)

    def test_reports_a_changed_host_key(self):
        self.tunnel("box-8", [self.free_listener()])
        self.ssh_output, self.ssh_status = "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!", 255
        result = self.add("box-8", "u")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ssh-keygen -R box-8", result.stdout)

    def test_remove_stops_the_agent_and_forgets_the_box(self):
        self.tunnel("box-8", [2224], hosts=0)
        self.assertEqual(self.add("box-8", "u").returncode, 0)
        result = self.add("--remove", "box-8")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.plist("box-8").exists())
        self.assertFalse((self.home / ".ssh/devboxes/box-8.conf").exists())
        self.assertIn(f"launchctl bootout gui/{os.getuid()}/dotfiles.devtunnel.box-8", self.calls())
        self.assertIn(f"ssh-keygen -R box-8 -f {self.home / '.ssh/known_hosts'}", self.calls())


@unittest.skipUnless(FORWARD, "DOTFILES_DEVTUNNEL_FORWARD must name the built script (nix flake check sets it)")
class DevtunnelForwardTests(Temp):
    def forward(self, mode, port):
        devtunnel = self.executable("devtunnel", f"""
import os, socket, sys, time
open({str(self.root / 'child.pid')!r}, "w").write(str(os.getpid()))
mode = {mode!r}
if mode == "exit":
    sys.exit(3)
if mode == "idle":
    time.sleep(60)
server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", {port}))
server.listen()
while True:
    conn, _ = server.accept()
    conn.sendall(b"SSH-2.0-fixture\\r\\n")
    conn.close()
""", interpreter=sys.executable)
        env = {**os.environ, "DEVTUNNEL_FORWARD_GRACE": "0.5", "DEVTUNNEL_FORWARD_INTERVAL": "0.3",
               "DEVTUNNEL_FORWARD_MISSES": "2"}
        return subprocess.Popen([FORWARD, str(devtunnel), "box-8", str(port)], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    def child_alive(self):
        pid = int((self.root / "child.pid").read_text())
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        return True

    def unused_port(self):
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            return probe.getsockname()[1]

    def test_restarts_when_the_client_stops_forwarding(self):
        proc = self.forward("idle", self.unused_port())
        output, _ = proc.communicate(timeout=20)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("not forwarding port", output)
        time.sleep(0.2)
        self.assertFalse(self.child_alive())

    def test_restarts_when_the_client_exits(self):
        proc = self.forward("exit", self.unused_port())
        output, _ = proc.communicate(timeout=20)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("devtunnel connect exited (3)", output)

    def test_keeps_a_forwarding_client_and_stops_it_on_term(self):
        proc = self.forward("listen", self.unused_port())
        time.sleep(3)
        self.assertIsNone(proc.poll(), proc.stdout.read() if proc.poll() is not None else "")
        proc.send_signal(signal.SIGTERM)
        proc.communicate(timeout=10)
        self.assertEqual(proc.returncode, 0)
        time.sleep(0.2)
        self.assertFalse(self.child_alive())


if __name__ == "__main__":
    unittest.main()
