# Windows

Native Windows consumes this checkout directly; Nix/Home Manager manages the
Unix/WSL side separately. Run these commands **on Windows**, not inside WSL.
Nothing in the bootstrap installs applications, changes execution policy, or
copies private configuration into this public repository.

## Prerequisites

Use the existing `winget` package workflow from PowerShell:

```powershell
$packages = @(
    'Microsoft.PowerShell', 'Git.Git', 'Neovim.Neovim', 'Starship.Starship',
    'BurntSushi.ripgrep.MSVC', 'sharkdp.fd', 'JesseDuffield.lazygit',
    'OpenJS.NodeJS.LTS', 'Python.Python.3.12'
)
foreach ($package in $packages) {
    winget install --exact --id $package --source winget
    if ($LASTEXITCODE -ne 0) { throw "winget failed for $package; resolve this before continuing." }
}
```

If winget reports an already-installed/up-to-date package with a nonzero exit,
verify it and rerun for the remaining packages; do not suppress every error.
Close the shell and open **PowerShell 7.4 or newer** afterward to refresh `PATH`. Git and a
C/C++ compiler usable by Neovim's native plugins are needed; see
[`nvim/README.md`](../nvim/README.md) for editor prerequisites and checks. Real
Python must resolve on PATH, not the Microsoft Store alias stub.

Optional terminal: `winget install --exact --id Microsoft.WindowsTerminal --source winget`.
Install the `FiraCode Nerd Font Mono` font separately if using the seed. Claude
and your custom Agency installation are separate prerequisites for `c` and `a`;
bootstrap does not install or configure either. `c` calls
`claude --dangerously-skip-permissions`; `a` retains `agency copilot --yolo`.
Both bypass normal approval prompts, so use only in trusted environments.

Enable Windows Developer Mode to create symlinks as your normal user. An
elevated PowerShell 7 running as **the same user** is an alternative. Do not
run as another administrator account: its home/profile would be different.

## Inspect, then migrate

Close Neovim and other processes that may write the destination configs.
From the checkout in a Windows PowerShell 7 console:

```powershell
pwsh -NoProfile -File .\windows\bootstrap.ps1
pwsh -NoProfile -File .\windows\bootstrap.ps1 -Apply
```

The first command is a read-only preflight. It validates all required sources
and destination parent paths, displays changes, and writes nothing. Missing
targets, unsupported destinations, and errors stop the run rather than reporting
success. The apply command stages **all** replacement files/links before moving
any originals, so missing symlink privileges cannot destroy working configs.
Correct Neovim/Starship symlinks and an existing writable loader are no-ops.

| Config | Source | Installation |
|---|---|---|
| Neovim | `nvim/` | Symlink at `%LOCALAPPDATA%\nvim` |
| Starship | `generated/starship.toml` | Symlink at `%USERPROFILE%\.config\starship.toml` |
| PowerShell | `windows/powershell/Microsoft.PowerShell_profile.ps1` | Writable file at the PowerShell 7 console `$PROFILE`, dot-sourcing public defaults and private overrides |
| Windows Terminal | `windows/windows-terminal/settings.json` | Untouched unless explicitly selected; copied, never linked |

Bootstrap does not migrate Windows PowerShell 5.1 or VS Code's separate profile.
Override `-ProfilePath` only with the intended absolute PowerShell 7 profile
path. `-HomePath` and `-LocalAppDataPath` allow explicit destination roots.
Parent directories that are symlinks/junctions are rejected to prevent writing
through into unintended locations; ordinary OneDrive cloud folders are allowed.
Destinations and the backup root must be on the same volume for atomic moves.

### Private PowerShell configuration

An existing real profile (or an unrelated readable profile symlink) is preserved
byte-for-byte in `$PROFILE.local.ps1`. If that name is already occupied, bootstrap
uses `$PROFILE.local.<unique-id>.ps1` instead, keeping both files.
The original file/link is also moved into the private rollback backup.
A link to this checkout's public profile is replaced with a writable loader
without copying those public defaults into a private override.

The loader runs public defaults, the preserved old profile, an existing
`$PROFILE.local.ps1` when separate, and finally `profile.local.ps1` beside
`$PROFILE`. Private overrides therefore win, including any old aliases or
prompt initialization. Keep machine/work settings in these private files, not
the tracked profile. Tools that modify `$PROFILE` can edit the writable loader;
rerunning bootstrap leaves those edits intact. The preserved file remains in
the same directory so `$PSScriptRoot`-relative imports still work, but code that
depends on its exact script filename may need a private adjustment.

## Backup and rollback

Every apply creates a timestamped, uniquely named backup under
`%LOCALAPPDATA%\dotfiles\backups`, **outside the repository**. The backup directory
has inheritance disabled and grants the current Windows user full control.
Its `manifest.json` records destinations, original file/link locations,
replacement fingerprints, and transaction progress. A migration lock prevents
overlapping apply/rollback operations using the same backup root.

The command prints the exact manifest path and rollback command:

```powershell
pwsh -NoProfile -File .\windows\bootstrap.ps1 -Rollback 'C:\Users\YOU\AppData\Local\dotfiles\backups\TIMESTAMP-ID\manifest.json'
```

Use the actual printed path, not the placeholder above. `-BackupRoot` selects
another absolute backup root outside the checkout if needed. Keep manifests
private, never edit them or run rollback against an untrusted manifest.

Failures trigger automatic rollback and a terminating error. Explicit rollback
restores original files and symlinks and removes new files and empty directories
created by that transaction. It refuses to overwrite configurations edited
since apply: move those edits somewhere safe, then retry. Rollbacks should run
newest-first. Originals remain in the private backup, and restoration is journaled
so it can be retried after interruption. If rollback itself fails, keep the entire
backup and follow the printed error; `Entries[].Backup` identifies each original
for recovery. Do not delete backups until the migrated setup is verified.
Staging requires enough disk space for replacement/private profile copies.

### Windows Terminal is a deliberate seed

Keep your machine's current Terminal profiles by default. Merge selected seed
settings manually using the Terminal settings editor; GUIDs, generated profile
sources, executable paths, and available fonts vary between machines.

Only if you intentionally want to **replace the complete stable-package settings
file**, close Terminal and run from a separate PowerShell console:

```powershell
pwsh -NoProfile -File .\windows\bootstrap.ps1 -IncludeWindowsTerminal
pwsh -NoProfile -File .\windows\bootstrap.ps1 -Apply -IncludeWindowsTerminal
```

This explicit replacement participates in the same backup/rollback transaction.
Preview/unpackaged Terminal locations are not guessed; a missing stable-package
directory is an error. Terminal rewrites its settings in place, so a symlink
would risk writing into the public checkout.

The Ubuntu seed keeps **UbuntuLegit**. Image basenames (`thor.png`, `hulk.png`,
`venom.png`, `deadpool.png`) are retained under
`%OneDriveCommercial%\Pictures\img\cmd`; that environment variable must resolve
to your business OneDrive root, or adjust the path in your private Terminal
settings. No images are copied. The retained Catppuccin scheme is optional.

### Shared Starship settings

The committed generated TOML lets native Windows consume the shared Starship
settings without requiring Nix. See the root README and
[`starship/README.md`](../starship/README.md) for regeneration and validation.

## Validation

Repository checks: `python -m unittest discover -s tests -p 'test_windows*.py'`.
Native migration tests run only when Windows and `pwsh` are available, using
isolated fixture checkouts/homes under `tests/`; they never touch the real
Windows profile. Symlink tests require Developer Mode or elevation. Syntax-only
or Linux checks do not verify Windows ACLs, filesystem behavior, or installed
applications. After applying on Windows, open a new PowerShell 7 session and
check `$PROFILE`, `Get-Command c,a,starship,nvim,git,rg,fd,lazygit,node,python`,
`starship --version`, and Neovim `:checkhealth`.
