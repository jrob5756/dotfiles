# Windows

Native Windows consumes this checkout directly; Nix/Home Manager manages the
Unix/WSL side separately. Run these commands **on Windows**, not inside WSL.
Nothing in the bootstrap installs applications, changes execution policy, or
copies private configuration into this public repository. The opt-in
[Dev Box SSH server](#ssh-into-a-dev-box) is separate and does install
OpenSSH and the devtunnel CLI.

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
If using the seed, install JetBrainsMono Nerd Font
(`winget install --exact --id DEVCOM.JetBrainsMonoNerdFont --source winget`,
which installs machine-wide). Windows lists it as `JetBrainsMono NF`, which is
the face name the seed uses. The seed's default profile, **Ubuntu (tmux)**,
opens WSL straight into tmux, reattaching to the most recent session if the
server is running; the plain **Ubuntu** profile starts without tmux. Claude
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

## SSH into a Dev Box

`devbox-ssh/setup.ps1` lets another machine SSH into a Microsoft Dev Box **as
your own account**; the client side is in the root README's
[SSH over dev tunnels](../README.md#ssh-over-dev-tunnels-macos). It is opt-in,
separate from bootstrap, and refuses to run unless the computer name starts
with `CPC-` (`-Force` overrides).

The built-in `sshd` service logs users in through a domain controller, which
Microsoft-hosted Dev Boxes cannot reach, and Microsoft Entra accounts cannot use
key authentication. Instead, `sshd` runs as you inside your logon session, so it
can only log in you and sessions get your full token (SSO, DPAPI, cached
credentials). It listens on loopback only; a dev tunnel that only your account
can connect to carries the traffic.

```powershell
pwsh -NoProfile -File .\windows\devbox-ssh\setup.ps1
pwsh -NoProfile -File .\windows\devbox-ssh\setup.ps1 -Apply -AuthorizedKeysFile C:\path\to\client.pub
```

The first command previews; `-Apply` prompts for elevation once when needed and,
on first use, opens a dev tunnels sign-in window. It sets up:

| What | Where |
|---|---|
| OpenSSH Server, with the built-in `sshd` service stopped and disabled | Windows capability (elevated) |
| PowerShell 7 as the OpenSSH default shell | `HKLM\SOFTWARE\OpenSSH` (elevated) |
| `DevBox SSH` logon task running `supervisor.ps1` hidden; it restarts `sshd` and `devtunnel host` if they exit and renews the tunnel daily | Task Scheduler (elevated) |
| devtunnel CLI, sign-in, and tunnel `<username>-devbox` with port 2222 | winget (user scope), dev tunnels service |
| `sshd_config`, host key, supervisor copy, and `authorized_keys` | `%USERPROFILE%\.ssh\devbox-sshd`, readable only by you, SYSTEM and Administrators |

`authorized_keys` is private and never overwritten: edit it directly or add keys
with `-AuthorizedKeysFile`. `-TunnelId` and `-Port` override the defaults; tunnel
IDs are global, so choose another if creation fails. Rerunning is safe. When the
config, supervisor or task changes, it restarts `sshd` and the tunnel host, which
drops SSH sessions open through the tunnel. `-Apply` prints the host key
fingerprint to check on the client's first connection.

- It only works while you have a logon session. Disconnecting from the desktop
  is fine; after a restart, sign in once.
- A new Dev Box has a new host key, so remove the old entry on the client
  (`ssh-keygen -R <name>`). Host each tunnel ID from one machine at a time.
- `ssh <name> 'command'` relies on the profile skipping PSReadLine when stdin is
  redirected; otherwise PowerShell never exits.

`-Uninstall` previews and `-Uninstall -Apply` unregisters the task, stops the
processes and deletes the generated files. It keeps `authorized_keys`, OpenSSH
Server (service disabled), the default shell and the tunnel
(`devtunnel delete <id>` removes it).

## Validation

Repository checks: `python -m unittest discover -s tests -p 'test_windows*.py'`.
Native migration tests run only when Windows and `pwsh` are available, using
isolated fixture checkouts/homes under `tests/`; they never touch the real
Windows profile. Symlink tests require Developer Mode or elevation. Syntax-only
or Linux checks do not verify Windows ACLs, filesystem behavior, or installed
applications. After applying on Windows, open a new PowerShell 7 session and
check `$PROFILE`, `Get-Command c,a,starship,nvim,git,rg,fd,lazygit,node,python`,
`starship --version`, and Neovim `:checkhealth`.
The Dev Box SSH tests only run the read-only preview; after `-Apply`, connect
from the client to verify it.
