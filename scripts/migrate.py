#!/usr/bin/env python3
"""Build and reversibly adopt a Home Manager generation for the current user."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import filecmp
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile


MARKER = "# dotfiles-shell-loader v1"
LOADERS = {
    ".bashrc": "bashrc",
    ".zshrc": "zshrc",
    ".profile": "profile",
    ".bash_profile": "bash_profile",
    ".zshenv": "zshenv",
    ".zprofile": "zprofile",
}


def present(path):
    return path.exists() or path.is_symlink()


def safe_target(home, relative):
    relative = Path(relative)
    if relative.is_absolute() or ".." in relative.parts or relative == Path("."):
        raise ValueError(f"Unsafe home-relative target: {relative}")
    target = home / relative
    for parent in target.parents:
        if parent == home:
            break
        if parent.is_symlink():
            raise ValueError(f"Refusing symlinked parent directory: {parent}")
        if parent.exists() and not parent.is_dir():
            raise ValueError(f"Parent is not a directory: {parent}")
    return target


@contextmanager
def migration_lock(home):
    path = safe_target(home, ".local/state/dotfiles/migrate.lock")
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise ValueError("Another dotfiles migration or rollback is running") from exc
        yield
    finally:
        os.close(fd)


def write_private(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".dotfiles-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def managed_blocks(text):
    lines = text.splitlines(keepends=True)
    blocks = []
    current = []
    for line in lines:
        if re.match(r"^# BEGIN .+ MANAGED BLOCK\s*$", line):
            if current:
                raise ValueError("Nested installer-managed shell blocks")
            current = [line]
        elif current:
            current.append(line)
            if re.match(r"^# END .+ MANAGED BLOCK\s*$", line):
                start_name = current[0].strip().replace("# BEGIN ", "", 1)
                end_name = line.strip().replace("# END ", "", 1)
                if start_name != end_name:
                    raise ValueError("Mismatched installer-managed shell block")
                blocks.append("".join(current))
                current = []
    if current:
        raise ValueError("Unterminated installer-managed shell block")
    return "\n".join(blocks)


def preserved_environment(text):
    blocks = managed_blocks(text)
    outside_blocks = text
    for block in re.findall(r"(?ms)^# BEGIN .+? MANAGED BLOCK\n.*?^# END .+? MANAGED BLOCK[^\n]*\n?", text):
        outside_blocks = outside_blocks.replace(block, "")
    managed_variables = {"EDITOR", "LANG", "DIRENV_LOG_FORMAT", "NVM_DIR", "DOTNET_ROOT", "NETRC"}
    exports = []
    for line in outside_blocks.splitlines():
        match = re.match(r"^export ([A-Za-z_][A-Za-z0-9_]*)=", line)
        if match and match[1] not in managed_variables:
            if line.endswith("\\"):
                raise ValueError("Move multiline custom exports into the corresponding .local file before migration")
            try:
                shlex.split(line)
            except ValueError as exc:
                raise ValueError("Move multiline custom exports into the corresponding .local file before migration") from exc
            exports.append(line)
    return blocks + "\n" + "\n".join(exports) + "\n"


def loader_text(name, preserved=""):
    return (
        f"{MARKER}\n"
        'for _dotfiles_nix in /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh '
        '"$HOME/.nix-profile/etc/profile.d/nix.sh"; do\n'
        '    if [ -r "$_dotfiles_nix" ]; then . "$_dotfiles_nix"; break; fi\n'
        "done\nunset _dotfiles_nix\n"
        + preserved
        + f'\nif [ ! -r "$HOME/.config/dotfiles/{LOADERS[name]}" ]; then\n'
        + f'    printf "%s\\n" "dotfiles: missing managed {name}; run the migration command" >&2\n'
        + "    return 1\nfi\n"
        + f'. "$HOME/.config/dotfiles/{LOADERS[name]}"\n'
        + f'if [ -r "$HOME/{name}.local" ]; then . "$HOME/{name}.local"; fi\n'
    )


def is_loader(path):
    return (
        path.is_file()
        and not path.is_symlink()
        and path.read_text(encoding="utf-8").startswith(MARKER + "\n")
    )


def ensure_loaders(home, check=False):
    for name in LOADERS:
        path = safe_target(home, name)
        if present(path) and not is_loader(path):
            raise ValueError(f"{path} is not a writable dotfiles loader; run nix run .#migrate -- --apply")
    if not check:
        for name in LOADERS:
            path = home / name
            if not present(path):
                write_private(path, loader_text(name))


def generation_targets(generation):
    root = generation / "home-files"
    if not root.is_dir():
        raise ValueError(f"No home-files directory in {generation}")
    targets = []
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in list(dirs):
            path = Path(directory) / name
            if path.is_symlink():
                targets.append(str(path.relative_to(root)))
                dirs.remove(name)
        targets.extend(str((Path(directory) / name).relative_to(root)) for name in files)
    legacy = {".tmux.conf"}
    ghostty = [
        Path(target).parent for target in targets
        if Path(target).parent.name == "ghostty" and Path(target).name in {"config", "config.ghostty"}
    ]
    for directory in ghostty:
        legacy.update(str(directory / name) for name in ("config", "config.ghostty"))
    if ghostty and sys.platform == "darwin":
        legacy.update(
            f"Library/Application Support/com.mitchellh.ghostty/{name}"
            for name in ("config", "config.ghostty")
        )
    return sorted(set(targets) | set(LOADERS) | legacy)


def read_manifest(backup, home):
    data = json.loads((backup / "manifest.json").read_text())
    if not isinstance(data, dict) or data.get("version") != 1 or data.get("home") != str(home):
        raise ValueError("Backup does not belong to this home directory")
    if data.get("status") not in {"preparing", "activating", "complete", "restored"}:
        raise ValueError("Invalid backup status")
    if not isinstance(data.get("entries"), list):
        raise ValueError("Invalid backup entries")
    paths = set()
    for entry in data["entries"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            raise ValueError("Invalid backup entry")
        safe_target(home, entry["path"])
        if type(entry.get("original")) is not bool or type(entry.get("prepared")) is not bool:
            raise ValueError("Invalid backup flags")
        if "restored" in entry and type(entry["restored"]) is not bool:
            raise ValueError("Invalid restored flag")
        relative = Path(entry["path"])
        if any(relative == other or relative in other.parents or other in relative.parents for other in paths):
            raise ValueError("Duplicate or overlapping backup targets")
        paths.add(relative)
        if entry["original"] and entry["prepared"] and not present(backup / "files" / relative):
            raise ValueError(f"Missing original backup: {relative}")
    previous = data.get("previous_generation")
    if previous is not None:
        if not isinstance(previous, str) or Path(previous).parent != Path("/nix/store") or not previous.endswith("-home-manager-generation"):
            raise ValueError("Invalid previous Home Manager generation")
        if data["status"] in {"activating", "complete"} and not (Path(previous) / "activate").is_file():
            raise ValueError("Previous Home Manager generation is unavailable")
    return data


def same_contents(left, right):
    try:
        left = left.resolve(strict=True)
        right = right.resolve(strict=True)
    except (OSError, RuntimeError):
        return False
    if left.is_file() and right.is_file():
        return filecmp.cmp(left, right, shallow=False)
    if left.is_dir() and right.is_dir():
        left_names = {path.name for path in left.iterdir()}
        right_names = {path.name for path in right.iterdir()}
        return left_names == right_names and all(
            same_contents(left / name, right / name) for name in left_names
        )
    return False


def displace_current(path, backup, relative):
    if not present(path):
        return
    displaced = backup / "after-migration" / relative
    if present(displaced):
        retry = Path(tempfile.mkdtemp(prefix="recovery-", dir=backup))
        displaced = retry / relative
    displaced.parent.mkdir(parents=True, exist_ok=True)
    os.replace(path, displaced)


def restore(home, backup):
    data = read_manifest(backup, home)
    if data["status"] == "restored":
        print(f"Already restored: {backup}")
        return
    for entry in reversed(data["entries"]):
        if entry.get("restored"):
            continue
        saved = backup / "files" / entry["path"]
        if not entry.get("prepared") and not present(saved):
            continue
        path = safe_target(home, entry["path"])
        if entry["original"]:
            path.parent.mkdir(parents=True, exist_ok=True)
            snapshot = backup / "snapshots" / entry["path"]
            use_snapshot = saved.is_symlink() and snapshot.exists() and not same_contents(saved, snapshot)
            source = snapshot if use_snapshot else saved
            stage = Path(tempfile.mkdtemp(prefix=".dotfiles-restore-", dir=path.parent))
            try:
                replacement = stage / "entry"
                if source.is_symlink():
                    replacement.symlink_to(os.readlink(source))
                elif source.is_dir():
                    shutil.copytree(source, replacement, symlinks=True)
                else:
                    shutil.copy2(source, replacement)
                displace_current(path, backup, entry["path"])
                os.replace(replacement, path)
            finally:
                shutil.rmtree(stage)
            if use_snapshot:
                print(f"Restored snapshot instead of changed symlink target: {path}")
        else:
            displace_current(path, backup, entry["path"])
        entry["prepared"] = False
        entry["restored"] = True
        write_private(backup / "manifest.json", json.dumps(data, indent=2) + "\n")
    previous = data.get("previous_generation")
    if previous and data["status"] in {"activating", "complete"}:
        subprocess.run([str(Path(previous) / "activate")], check=True)
    data["status"] = "restored"
    write_private(backup / "manifest.json", json.dumps(data, indent=2) + "\n")
    print(f"Restored configuration. Nix itself remains installed. Backup: {backup}")


def plan_generation(home, generation):
    targets = generation_targets(generation)
    preserved = {}
    entries = []
    for name in targets:
        path = safe_target(home, name)
        if name in LOADERS and is_loader(path):
            continue
        if name in LOADERS and path.is_file():
            preserved[name] = preserved_environment(path.read_text(encoding="utf-8"))
            shell = "zsh" if name in {".zshrc", ".zshenv", ".zprofile"} else "bash"
            executable = shutil.which(shell) or shutil.which("bash")
            if not executable:
                raise ValueError(f"{shell} is required to validate the preserved shell setup")
            subprocess.run(
                [executable, "-n"], input=loader_text(name, preserved[name]),
                text=True, check=True,
            )
        entries.append({"path": name, "original": present(path), "prepared": False})
    return entries, preserved


def apply_generation(home, generation, backup_root, activate=None):
    entries, preserved = plan_generation(home, generation)
    safe_target(home, str(backup_root.relative_to(home)) + "/probe")
    backup_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup_root.chmod(0o700)
    backup = Path(tempfile.mkdtemp(
        prefix=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-"), dir=backup_root
    ))
    profile = home / ".local/state/nix/profiles/home-manager"
    previous = profile.resolve() if (profile / "activate").is_file() else None
    data = {
        "version": 1, "home": str(home), "generation": str(generation),
        "previous_generation": str(previous) if previous else None,
        "status": "preparing", "entries": entries,
    }
    write_private(backup / "manifest.json", json.dumps(data, indent=2) + "\n")
    print(f"Backup: {backup}", flush=True)
    try:
        if activate is None:
            for label, store_path in (("generation", generation), ("previous-generation", previous)):
                if store_path is not None:
                    subprocess.run(
                        ["nix-store", "--add-root", str(backup / label), "--indirect", "--realise", str(store_path)],
                        check=True,
                    )
        # Snapshot all linked contents before moving any live configuration.
        for entry in entries:
            path = home / entry["path"]
            if path.is_symlink() and path.exists():
                snapshot = backup / "snapshots" / entry["path"]
                snapshot.parent.mkdir(parents=True, exist_ok=True)
                if path.is_dir():
                    shutil.copytree(path, snapshot, symlinks=False)
                else:
                    shutil.copy2(path, snapshot)
        for entry in entries:
            path = home / entry["path"]
            if entry["original"]:
                saved = backup / "files" / entry["path"]
                saved.parent.mkdir(parents=True, exist_ok=True)
                os.replace(path, saved)
            entry["prepared"] = True
            write_private(backup / "manifest.json", json.dumps(data, indent=2) + "\n")
        for name in LOADERS:
            path = home / name
            if not present(path):
                write_private(path, loader_text(name, preserved.get(name, "")))
        data["status"] = "activating"
        write_private(backup / "manifest.json", json.dumps(data, indent=2) + "\n")
        if activate:
            activate(generation)
        else:
            subprocess.run([str(generation / "activate")], check=True)
    except (OSError, ValueError, subprocess.CalledProcessError, KeyboardInterrupt):
        print(f"Activation failed; restoring from {backup}", file=sys.stderr)
        restore(home, backup)
        raise
    data["status"] = "complete"
    write_private(backup / "manifest.json", json.dumps(data, indent=2) + "\n")
    print(f"Migration complete. Roll back with: python3 scripts/migrate.py --rollback {backup}")
    return backup


def nix_output(*args):
    return subprocess.check_output(["nix", *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", choices=("wsl", "linux", "mac"))
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--rollback", type=Path)
    parser.add_argument("--loaders", choices=("check", "ensure"), help=argparse.SUPPRESS)
    args = parser.parse_args()
    home = Path.home().resolve()
    if args.loaders:
        ensure_loaders(home, check=args.loaders == "check")
        return
    if os.geteuid() == 0:
        raise ValueError("Run migration as your normal user, not with sudo")
    if args.rollback:
        with migration_lock(home):
            restore(home, args.rollback.resolve())
        return
    if not shutil.which("nix"):
        raise ValueError("Install Nix first, then open a new terminal and retry")
    host = args.host
    if host is None:
        host = "mac" if sys.platform == "darwin" else "linux"
        if sys.platform.startswith("linux") and "microsoft" in Path("/proc/version").read_text().lower():
            host = "wsl"
    repo = args.repo.resolve()
    if not (repo / "flake.lock").is_file():
        raise ValueError(f"No pinned flake at {repo}; run from the dotfiles checkout")
    git_root = Path(subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", "--show-toplevel"], text=True
    ).strip()).resolve()
    if git_root != repo:
        raise ValueError("Run migration from the root of the dotfiles Git checkout")
    flake = f"git+{repo.as_uri()}#homeConfigurations.{host}"
    expected_home = nix_output("eval", "--no-update-lock-file", "--raw", flake + ".config.home.homeDirectory")
    expected_repo = nix_output("eval", "--no-update-lock-file", "--raw", flake + ".config.dotfiles.path")
    if Path(expected_home) != home or Path(expected_repo).resolve() != repo:
        raise ValueError(f"Update hosts/{host}.nix for home {home} and checkout {repo} before migration")
    print(f"Building {host} before changing any configuration...", flush=True)
    generation = Path(nix_output(
        "build", "--no-update-lock-file", "--no-link", "--print-out-paths", flake + ".activationPackage"
    ))
    targets = generation_targets(generation)
    plan_generation(home, generation)
    for name in targets:
        path = safe_target(home, name)
        print(f"{'Preserve loader' if name in LOADERS and is_loader(path) else 'Back up' if present(path) else 'Create'}: {path}")
    if not args.apply:
        print("Preview only. Apply with: nix run .#migrate -- --apply")
        return
    with migration_lock(home):
        apply_generation(home, generation, home / ".local/state/dotfiles/backups")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("dotfiles migration: interrupted", file=sys.stderr)
        sys.exit(130)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"dotfiles migration: {exc}", file=sys.stderr)
        sys.exit(1)
