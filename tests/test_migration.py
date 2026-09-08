import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(os.environ.get(
    "DOTFILES_MIGRATOR", Path(__file__).resolve().parents[1] / "scripts/migrate.py"
))
spec = importlib.util.spec_from_file_location("migrator", SCRIPT)
migrator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migrator)


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.generation = self.root / "generation"
        self.files = self.generation / "home-files"
        self.files.mkdir(parents=True)
        self.store = self.root / "store"
        self.store.mkdir()
        for name in migrator.LOADERS.values():
            self.managed(f".config/dotfiles/{name}", 'export DOTFILES_PAYLOAD=loaded\n')
        self.managed(".config/starship.toml", "managed prompt")
        self.managed(".inputrc", "managed bindings")
        self.backups = self.home / ".local/state/dotfiles/backups"

    def managed(self, name, text):
        source = self.store / name.replace("/", "-")
        source.write_text(text)
        link = self.files / name
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(source)

    def activate(self, generation):
        migrator.ensure_loaders(self.home, check=True)
        for directory, _, names in os.walk(generation / "home-files"):
            for name in names:
                source = Path(directory) / name
                target = self.home / source.relative_to(generation / "home-files")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(source)
        migrator.ensure_loaders(self.home)

    def apply(self, activate=None):
        return migrator.apply_generation(
            self.home, self.generation, self.backups, activate or self.activate
        )

    def test_targets_are_generated_files_and_legacy_entry_points(self):
        targets = migrator.generation_targets(self.generation)
        self.assertIn(".tmux.conf", targets)
        self.assertIn(".bashrc", targets)
        self.assertIn(".config/dotfiles/bashrc", targets)
        self.assertNotIn(".config", targets)

    def test_concurrent_migrations_are_rejected(self):
        with migrator.migration_lock(self.home):
            with self.assertRaisesRegex(ValueError, "Another dotfiles"):
                with migrator.migration_lock(self.home):
                    self.fail("Second migration obtained the lock")

    def test_alternate_ghostty_config_does_not_override_managed_config(self):
        self.managed(".config/ghostty/config", "managed theme")
        alternate = self.home / ".config/ghostty/config.ghostty"
        alternate.parent.mkdir(parents=True)
        alternate.write_text("old theme")
        backup = self.apply()
        self.assertFalse(alternate.exists())
        self.assertEqual((backup / "files/.config/ghostty/config.ghostty").read_text(), "old theme")
        migrator.restore(self.home, backup)
        self.assertEqual(alternate.read_text(), "old theme")

    def test_missing_generation_is_rejected_without_changes(self):
        with self.assertRaises(ValueError):
            migrator.generation_targets(self.root / "missing")
        self.assertEqual(list(self.home.iterdir()), [])

    def test_writable_loaders_and_originals_are_preserved(self):
        original = '# BEGIN Example MANAGED BLOCK\nexport CUSTOM_TOOL=yes\n# END Example MANAGED BLOCK\n'
        (self.home / ".bashrc").write_text(original)
        (self.home / ".bashrc.local").write_text("export CUSTOM_LOCAL=yes\n")
        (self.home / ".tmux.conf").write_text("old tmux")
        backup = self.apply()
        wrapper = self.home / ".bashrc"
        self.assertFalse(wrapper.is_symlink())
        self.assertTrue(os.access(wrapper, os.W_OK))
        self.assertIn(original, wrapper.read_text())
        self.assertEqual((backup / "files/.bashrc").read_text(), original)
        self.assertEqual((backup / "files/.tmux.conf").read_text(), "old tmux")
        self.assertEqual((self.home / ".bashrc.local").read_text(), "export CUSTOM_LOCAL=yes\n")
        self.assertFalse((self.home / ".tmux.conf").exists())
        self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
        self.assertEqual((backup / "manifest.json").stat().st_mode & 0o777, 0o600)

    def test_backup_contains_contents_of_symlinked_configs(self):
        source = self.root / "manual-bashrc"
        source.write_text("export PRIVATE_VALUE=preserved\n")
        (self.home / ".bashrc").symlink_to(source)
        backup = self.apply()
        self.assertTrue((backup / "files/.bashrc").is_symlink())
        self.assertEqual((backup / "snapshots/.bashrc").read_text(), source.read_text())

    def test_rollback_survives_changes_to_original_symlink_target(self):
        source = self.root / "manual-bashrc"
        source.write_text("export ORIGINAL=yes\n")
        (self.home / ".bashrc").symlink_to(source)
        backup = self.apply()
        source.write_text("export CHANGED=yes\n")
        migrator.restore(self.home, backup)
        self.assertEqual((self.home / ".bashrc").read_text(), "export ORIGINAL=yes\n")
        self.assertEqual(source.read_text(), "export CHANGED=yes\n")
        self.assertTrue((backup / "files/.bashrc").is_symlink())

    def test_nested_symlink_contents_are_snapshotted(self):
        directory = self.root / "linked-config"
        directory.mkdir()
        external = self.root / "external"
        external.write_text("original contents")
        (directory / "settings").symlink_to(external)
        target = self.home / ".config/custom"
        target.parent.mkdir()
        target.symlink_to(directory)
        self.managed(".config/custom", "new config")
        backup = self.apply()
        snapshot = backup / "snapshots/.config/custom/settings"
        self.assertFalse(snapshot.is_symlink())
        external.unlink()
        migrator.restore(self.home, backup)
        self.assertEqual((target / "settings").read_text(), "original contents")

    def test_rollback_resumes_after_journal_write_failure(self):
        (self.home / ".inputrc").write_text("original bindings")
        backup = self.apply()
        original_write = migrator.write_private
        failed = False

        def fail_once(path, text):
            nonlocal failed
            if path.name == "manifest.json" and '"restored": true' in text and not failed:
                failed = True
                raise OSError("simulated journal failure")
            return original_write(path, text)

        with mock.patch.object(migrator, "write_private", side_effect=fail_once):
            with self.assertRaises(OSError):
                migrator.restore(self.home, backup)
        migrator.restore(self.home, backup)
        self.assertEqual((self.home / ".inputrc").read_text(), "original bindings")
        self.assertEqual((backup / "files/.inputrc").read_text(), "original bindings")
        self.assertEqual(json.loads((backup / "manifest.json").read_text())["status"], "restored")

    def test_malformed_manifest_does_not_displace_current_config(self):
        (self.home / ".inputrc").write_text("original")
        backup = self.apply()
        manifest = backup / "manifest.json"
        data = json.loads(manifest.read_text())
        data["entries"][0].pop("original")
        manifest.write_text(json.dumps(data))
        before = (self.home / ".inputrc").read_text()
        with self.assertRaisesRegex(ValueError, "Invalid backup flags"):
            migrator.restore(self.home, backup)
        self.assertEqual((self.home / ".inputrc").read_text(), before)
        self.assertFalse((backup / "after-migration").exists())

    def test_missing_backup_does_not_displace_current_config(self):
        (self.home / ".inputrc").write_text("original")
        backup = self.apply()
        (backup / "files/.inputrc").unlink()
        with self.assertRaisesRegex(ValueError, "Missing original backup"):
            migrator.restore(self.home, backup)
        self.assertEqual((self.home / ".inputrc").read_text(), "managed bindings")
        self.assertFalse((backup / "after-migration").exists())

    def test_quoted_multiline_export_is_rejected_before_changes(self):
        old = 'export PRIVATE_SETTING="first\nsecond"\n'
        (self.home / ".bashrc").write_text(old)
        with self.assertRaisesRegex(ValueError, "multiline custom exports"):
            self.apply()
        self.assertEqual((self.home / ".bashrc").read_text(), old)
        self.assertFalse(self.backups.exists())

    def test_multiline_command_substitution_is_rejected_before_changes(self):
        old = "export PRIVATE_SETTING=$(\nprintf value\n)\n"
        (self.home / ".bashrc").write_text(old)
        with self.assertRaises(subprocess.CalledProcessError):
            self.apply()
        self.assertEqual((self.home / ".bashrc").read_text(), old)
        self.assertFalse(self.backups.exists())

    def test_interrupt_rolls_back(self):
        (self.home / ".bashrc").write_text("original")

        def interrupt(generation):
            self.activate(generation)
            raise KeyboardInterrupt

        with self.assertRaises(KeyboardInterrupt):
            self.apply(interrupt)
        self.assertEqual((self.home / ".bashrc").read_text(), "original")

    def test_rollback_restores_originals_and_preserves_later_edits(self):
        old = self.home / ".inputrc"
        old.write_text("original bindings")
        backup = self.apply()
        (self.home / ".bashrc").write_text(migrator.loader_text(".bashrc") + "# installer addition\n")
        migrator.restore(self.home, backup)
        self.assertEqual(old.read_text(), "original bindings")
        self.assertFalse(old.is_symlink())
        self.assertIn("installer addition", (backup / "after-migration/.bashrc").read_text())
        self.assertFalse((self.home / ".config/starship.toml").exists())
        migrator.restore(self.home, backup)

    def test_activation_failure_rolls_back(self):
        (self.home / ".bashrc").write_text("old shell\n")
        (self.home / ".tmux.conf").write_text("old tmux\n")

        def fail(generation):
            self.activate(generation)
            raise subprocess.CalledProcessError(1, "activation")

        with self.assertRaises(subprocess.CalledProcessError):
            self.apply(fail)
        self.assertEqual((self.home / ".bashrc").read_text(), "old shell\n")
        self.assertEqual((self.home / ".tmux.conf").read_text(), "old tmux\n")
        self.assertFalse((self.home / ".inputrc").exists())
        manifest = next(self.backups.glob("*/manifest.json"))
        self.assertEqual(json.loads(manifest.read_text())["status"], "restored")

    def test_existing_loaders_keep_installer_edits(self):
        migrator.ensure_loaders(self.home)
        wrapper = self.home / ".bashrc"
        original = wrapper.read_text() + "# installer addition\n"
        wrapper.write_text(original)
        backup = self.apply()
        self.assertEqual(wrapper.read_text(), original)
        self.assertFalse((backup / "files/.bashrc").exists())

    def test_unowned_shell_is_rejected_by_direct_activation_guard(self):
        (self.home / ".bashrc").write_text("private shell")
        with self.assertRaisesRegex(ValueError, "not a writable dotfiles loader"):
            migrator.ensure_loaders(self.home, check=True)
        self.assertEqual((self.home / ".bashrc").read_text(), "private shell")

    def test_symlinked_parent_is_rejected_before_any_backup(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.home / ".config").symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "symlinked parent"):
            self.apply()
        self.assertFalse(self.backups.exists())
        self.assertEqual(list(outside.iterdir()), [])

    def test_home_escape_is_rejected(self):
        for relative in ("../outside", "/etc/profile", "."):
            with self.subTest(relative=relative), self.assertRaises(ValueError):
                migrator.safe_target(self.home, relative)

    def test_wrong_home_backup_is_rejected(self):
        backup = self.apply()
        with self.assertRaisesRegex(ValueError, "does not belong"):
            migrator.restore(self.root, backup)

    def test_malformed_managed_block_aborts_before_mutation(self):
        source = "# BEGIN Example MANAGED BLOCK\nexport TEST=yes\n"
        (self.home / ".bashrc").write_text(source)
        with self.assertRaisesRegex(ValueError, "Unterminated"):
            self.apply()
        self.assertEqual((self.home / ".bashrc").read_text(), source)
        self.assertFalse(self.backups.exists())

    def test_custom_exports_survive_without_duplicate_managed_variables(self):
        old = (
            "export PRIVATE_SETTING=keep\nexport PATH=\"$HOME/custom:$PATH\"\n"
            "export EDITOR=vim\n"
            "# BEGIN Example MANAGED BLOCK\nexport INSTALLED=yes\n# END Example MANAGED BLOCK\n"
        )
        text = migrator.preserved_environment(old)
        self.assertIn("PRIVATE_SETTING=keep", text)
        self.assertIn("PATH=", text)
        self.assertNotIn("EDITOR=", text)
        self.assertEqual(text.count("export INSTALLED=yes"), 1)

    def test_loaders_source_local_overrides_last_in_both_shells(self):
        self.apply()
        for shell, name in (("bash", ".bashrc"), ("zsh", ".zshrc")):
            executable = shutil.which(shell)
            if not executable:
                continue
            with self.subTest(shell=shell):
                (self.home / (name + ".local")).write_text("export DOTFILES_PAYLOAD=local\n")
                result = subprocess.run(
                    [executable, "-f" if shell == "zsh" else "--noprofile", "-c",
                     f'. "$HOME/{name}"; printf "%s" "$DOTFILES_PAYLOAD"'],
                    env={**os.environ, "HOME": str(self.home)},
                    capture_output=True, text=True, check=True,
                )
                self.assertEqual(result.stdout, "local")
