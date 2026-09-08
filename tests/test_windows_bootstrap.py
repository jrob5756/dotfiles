import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
WINDOWS = Path(os.environ.get("DOTFILES_WINDOWS_ROOT", ROOT / "windows"))
PWSH = shutil.which("pwsh")
if os.environ.get("REQUIRE_PWSH") == "1" and not PWSH:
    raise RuntimeError("PowerShell is required for these checks")


class WindowsSeedTests(unittest.TestCase):
    def test_terminal_preserves_user_scheme_and_images(self):
        settings = json.loads((WINDOWS / "windows-terminal/settings.json").read_text())
        profiles = settings["profiles"]["list"]
        ubuntu = next(profile for profile in profiles if profile["name"] == "Ubuntu")
        self.assertEqual(ubuntu["colorScheme"], "UbuntuLegit")
        images = [profile["backgroundImage"] for profile in profiles if "backgroundImage" in profile]
        self.assertEqual(
            [image.rsplit("\\", 1)[-1] for image in images],
            ["thor.png", "hulk.png", "venom.png", "thor.png", "deadpool.png"],
        )
        self.assertTrue(all(image.startswith("%OneDriveCommercial%\\") for image in images))

    def test_cli_aliases_retain_the_requested_commands(self):
        profile = (WINDOWS / "powershell/Microsoft.PowerShell_profile.ps1").read_text()
        self.assertIn("function c { claude --dangerously-skip-permissions @args }", profile)
        self.assertIn("function a { agency copilot --yolo @args }", profile)

    @unittest.skipUnless(PWSH, "PowerShell executable unavailable")
    def test_powershell_parser(self):
        for path in WINDOWS.rglob("*.ps1"):
            command = (
                "$tokens = $null; $errors = $null; "
                "[System.Management.Automation.Language.Parser]::ParseFile("
                f"'{str(path).replace(chr(39), chr(39) * 2)}', [ref]$tokens, [ref]$errors) | Out-Null; "
                "if ($errors.Count) { $errors | Out-String | Write-Error; exit 1 }"
            )
            result = subprocess.run([PWSH, "-NoProfile", "-Command", command], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


@unittest.skipUnless(os.name == "nt" and PWSH, "Native Windows and PowerShell 7 required")
class WindowsMigrationTests(unittest.TestCase):
    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory(prefix=".windows-fixture-", dir=ROOT / "tests")
        self.addCleanup(self.fixture.cleanup)
        self.root = Path(self.fixture.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        shutil.copytree(ROOT / "windows", self.repo / "windows", ignore=shutil.ignore_patterns(".validation"))
        (self.repo / "nvim").mkdir()
        (self.repo / "nvim/init.lua").write_text("return {}\n")
        (self.repo / "generated").mkdir()
        (self.repo / "generated/starship.toml").write_text('format = "$directory"\n')
        self.home = self.root / "home"
        self.home.mkdir()
        self.local = self.home / "AppData/Local"
        self.local.mkdir(parents=True)
        self.profile = self.home / "Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
        self.profile.parent.mkdir(parents=True)
        self.original = b"$env:PRIVATE_FIXTURE = 'retained'\r\n"
        self.profile.write_bytes(self.original)
        self.backups = self.root / "backups"
        self.script = self.repo / "windows/bootstrap.ps1"

    def invoke(self, *args, prefix=""):
        parameters = [
            str(self.script), "-HomePath", str(self.home),
            "-LocalAppDataPath", str(self.local), "-ProfilePath", str(self.profile),
            "-BackupRoot", str(self.backups), *args,
        ]
        if prefix:
            quote = lambda value: "'" + value.replace("'", "''") + "'"
            command = prefix + "\n& " + quote(parameters[0])
            for argument in parameters[1:]:
                command += " " + (argument if argument.startswith("-") else quote(argument))
            return subprocess.run([PWSH, "-NoProfile", "-Command", command], capture_output=True, text=True)
        return subprocess.run([PWSH, "-NoProfile", "-File", *parameters], capture_output=True, text=True)

    def require_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def manifest(self):
        return next(self.backups.glob("*/manifest.json"))

    def seed_conflicts(self):
        nvim = self.local / "nvim"
        nvim.mkdir()
        (nvim / "init.lua").write_text("private fixture")
        starship = self.home / ".config/starship.toml"
        starship.parent.mkdir()
        starship.write_text("private prompt fixture")

    def assert_originals(self):
        self.assertEqual(self.profile.read_bytes(), self.original)
        self.assertFalse((self.local / "nvim").is_symlink())
        self.assertEqual((self.local / "nvim/init.lua").read_text(), "private fixture")
        self.assertEqual((self.home / ".config/starship.toml").read_text(), "private prompt fixture")

    def test_default_is_read_only(self):
        before = sorted(str(path.relative_to(self.root)) for path in self.root.rglob("*"))
        self.require_success(self.invoke())
        self.assertEqual(before, sorted(str(path.relative_to(self.root)) for path in self.root.rglob("*")))
        self.assertEqual(self.profile.read_bytes(), self.original)

    def test_missing_source_fails_without_writes(self):
        (self.repo / "generated/starship.toml").unlink()
        result = self.invoke("-Apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.backups.exists())
        self.assertEqual(self.profile.read_bytes(), self.original)

    def test_apply_noop_and_explicit_rollback(self):
        self.seed_conflicts()
        canonical = Path(str(self.profile) + ".local.ps1")
        canonical.write_text("$env:EXISTING_LOCAL_FIXTURE = 1\n")
        self.require_success(self.invoke("-Apply"))
        manifest = self.manifest()
        self.assertTrue((self.local / "nvim").is_symlink())
        self.assertFalse(self.profile.is_symlink())
        self.assertIn("writable PowerShell loader", self.profile.read_text())
        preserved = next(self.profile.parent.glob("*.local.*.ps1"))
        self.assertEqual(preserved.read_bytes(), self.original)
        self.require_success(self.invoke("-Apply"))
        self.assertEqual(len(list(self.backups.glob("*/manifest.json"))), 1)
        self.require_success(self.invoke("-Rollback", str(manifest)))
        self.assert_originals()
        self.assertTrue(canonical.exists())
        self.assertFalse(preserved.exists())
        self.require_success(self.invoke("-Rollback", str(manifest)))

    def test_symlink_failure_keeps_working_configs(self):
        self.seed_conflicts()
        prefix = """
function New-Item {
    [CmdletBinding()]
    param([string] $ItemType, [string] $Path, [string] $Target, [switch] $Force)
    if ($ItemType -eq 'SymbolicLink') { throw 'Fixture: symlink privilege denied' }
    Microsoft.PowerShell.Management\\New-Item @PSBoundParameters
}
"""
        result = self.invoke("-Apply", prefix=prefix)
        self.assertNotEqual(result.returncode, 0)
        self.assert_originals()
        self.assertEqual(json.loads(self.manifest().read_text(encoding="utf-8-sig"))["State"], "RolledBack")

    def test_install_failure_rolls_back_prior_changes(self):
        self.seed_conflicts()
        prefix = """
function Move-Item {
    [CmdletBinding()]
    param([string] $LiteralPath, [string] $Destination, [switch] $Force)
    if ($LiteralPath -like '*.dotfiles-*' -and $Destination -like '*starship.toml') {
        throw 'Fixture: replacement failed'
    }
    Microsoft.PowerShell.Management\\Move-Item @PSBoundParameters
}
"""
        result = self.invoke("-Apply", prefix=prefix)
        self.assertNotEqual(result.returncode, 0)
        self.assert_originals()
        self.assertEqual(json.loads(self.manifest().read_text(encoding="utf-8-sig"))["State"], "RolledBack")

    def test_rollback_refuses_to_destroy_new_profile_edits(self):
        self.require_success(self.invoke("-Apply"))
        self.profile.write_text(self.profile.read_text() + "$env:NEW_FIXTURE = 1\n")
        result = self.invoke("-Rollback", str(self.manifest()))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("NEW_FIXTURE", self.profile.read_text())
        self.assertTrue((self.local / "nvim").is_symlink())

    def test_rollback_can_resume_after_journal_failure(self):
        self.seed_conflicts()
        self.require_success(self.invoke("-Apply"))
        manifest = self.manifest()
        prefix = """
$global:FixtureJournalFailure = $false
function Move-Item {
    [CmdletBinding()]
    param([string] $LiteralPath, [string] $Destination, [switch] $Force)
    if ($LiteralPath -like '*manifest.json.new' -and -not $global:FixtureJournalFailure) {
        $data = Get-Content -LiteralPath $LiteralPath -Raw | ConvertFrom-Json
        if (@($data.Entries | Where-Object State -EQ 'Restored').Count) {
            $global:FixtureJournalFailure = $true
            throw 'Fixture: interrupted rollback journal'
        }
    }
    Microsoft.PowerShell.Management\\Move-Item @PSBoundParameters
}
"""
        result = self.invoke("-Rollback", str(manifest), prefix=prefix)
        self.assertNotEqual(result.returncode, 0)
        self.require_success(self.invoke("-Rollback", str(manifest)))
        self.assert_originals()
        data = json.loads(manifest.read_text(encoding="utf-8-sig"))
        self.assertTrue(all(Path(entry["Backup"]).exists()
                            for entry in data["Entries"] if entry["HadOriginal"]))

    def test_missing_backup_rejects_rollback_before_changes(self):
        self.seed_conflicts()
        self.require_success(self.invoke("-Apply"))
        manifest = self.manifest()
        data = json.loads(manifest.read_text(encoding="utf-8-sig"))
        entry = next(entry for entry in data["Entries"] if entry["Path"] == str(self.profile))
        Path(entry["Backup"]).unlink()
        before = self.profile.read_bytes()
        result = self.invoke("-Rollback", str(manifest))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.profile.read_bytes(), before)
        self.assertTrue((self.local / "nvim").is_symlink())

    def test_terminal_is_opt_in_and_restoreable(self):
        terminal = self.local / "Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
        terminal.parent.mkdir(parents=True)
        terminal.write_text('{"fixture": true}')
        self.require_success(self.invoke("-Apply"))
        self.assertEqual(terminal.read_text(), '{"fixture": true}')
        self.require_success(self.invoke("-Apply", "-IncludeWindowsTerminal"))
        manifests = sorted(self.backups.glob("*/manifest.json"))
        self.assertEqual(len(manifests), 2)
        self.assertIn("profiles", json.loads(terminal.read_text()))
        self.require_success(self.invoke("-Rollback", str(manifests[-1])))
        self.assertEqual(terminal.read_text(), '{"fixture": true}')


if __name__ == "__main__":
    unittest.main()
