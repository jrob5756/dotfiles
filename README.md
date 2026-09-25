# Jason's Dotfiles

One repository for WSL, native Linux, Apple Silicon macOS, and native Windows.
Home Manager owns the Unix tools and configuration. Windows uses the separate
PowerShell bootstrap. There are no per-platform Git branches.

## Choose your workflow

| Situation | Start here |
|---|---|
| Setting up a new computer or WSL distro | [Get started on a fresh machine](#get-started-on-a-fresh-machine) |
| Adopting this setup on a machine with existing configs | [Onboard an existing machine](#onboard-an-existing-machine) |
| Applying changes from this repository to configured machines | [Roll out repository updates](#roll-out-repository-updates) |

Before setting up another machine, commit and push the configuration you want
it to receive. A clone or pull cannot include another checkout's uncommitted
changes. The commands below assume the setup is available on the branch you
use; if it is not yet on the default branch, clone or check out the branch
containing it first.

## Ownership

| Configuration | Source of truth | Installed as |
|---|---|---|
| Packages and host settings | `modules/`, `hosts/`, `flake.lock` | Home Manager generation |
| Bash and Zsh behavior | `modules/shell.nix`, `shell/common.sh` | Nix payloads behind writable startup loaders |
| Git pager (delta) | `modules/git.nix` | `~/.config/git/config`; `~/.gitconfig` stays private |
| tmux settings and plugins | `modules/tmux.nix`, `tmux/settings.conf` | `~/.config/tmux/tmux.conf`, pinned plugins |
| Starship | `modules/starship-settings.nix` | Home Manager on Unix; generated TOML on Windows |
| Neovim | `nvim/` | Live, writable symlink to Lua files |
| Ghostty | `modules/ghostty.nix` | Linux package and config; macOS config |
| Windows Terminal and PowerShell | `windows/` | Backed-up, explicit Windows deployment |

Machines still using the old manual Bash, Zsh, or tmux symlinks must run the
[migration](#wsl--linux--macos-migration) before pulling past the removal of
those files. The old Starship path remains supported.

## Get started on a fresh machine

### WSL, native Linux, or Apple Silicon macOS

Install Git and curl before cloning. On WSL or Ubuntu, also generate the
`en_US.UTF-8` locale that the managed shell sets (`sudo locale-gen en_US.UTF-8`);
otherwise system programs such as `/usr/bin/perl`, which fzf's `Ctrl-R` uses,
print locale warnings. On macOS, also install Homebrew and its
Command Line Tools prerequisites. On Windows, create/start a WSL2 distro first
if you want the Linux environment; run these steps **inside WSL**, not in
native PowerShell.

```sh
mkdir -p ~/src &&
git clone https://github.com/jrob5756/dotfiles ~/src/dotfiles &&
cd ~/src/dotfiles
```

Choose the matching host configuration and adjust its username, home directory,
and checkout path before activation:

| Machine | Host file | Nix system |
|---|---|---|
| WSL2 on x86-64 | `hosts/wsl.nix` | `x86_64-linux` |
| Native x86-64 Linux desktop | `hosts/linux.nix` | `x86_64-linux` |
| Apple Silicon Mac | `hosts/mac.nix` | `aarch64-darwin` |

Then follow [WSL / Linux / macOS migration](#wsl--linux--macos-migration):
install Nix, install the native Mac app/fonts if applicable, preview, and apply.
The same migration command handles a fresh home and existing OS-provided
startup files.
Keep the checkout in place afterward: Neovim uses it directly.

### Native Windows

Install PowerShell 7.4+, Git, and the application prerequisites listed in
[windows/README.md](windows/README.md#prerequisites). Enable Developer Mode
for symlinks, or use an elevated PowerShell as the same user.

From PowerShell 7:

```powershell
New-Item -ItemType Directory -Force -Path C:\src | Out-Null
git clone https://github.com/jrob5756/dotfiles C:\src\dotfiles
if ($LASTEXITCODE -ne 0) { throw 'Clone failed; resolve that before continuing.' }
Set-Location C:\src\dotfiles
pwsh -NoProfile -File .\windows\bootstrap.ps1
```

Review the preview, then apply:

```powershell
pwsh -NoProfile -File .\windows\bootstrap.ps1 -Apply
```

Open a new PowerShell session afterward. The bootstrap deploys configuration;
it does not install applications. Windows Terminal settings remain unchanged
unless explicitly selected. Native Windows and WSL have separate homes and
checkouts; onboard each environment separately if you use both.

## Onboard an existing machine

Start by protecting what is already there. Close applications that write their
configuration, especially Neovim and Windows Terminal. Do not delete existing
configs, plugin data, or the old checkout.

If this repository is already cloned, inspect it before updating:

```sh
git status --short
git branch --show-current
```

If there are changes, preserve and reconcile them first. Do not overwrite the
checkout, reset it, or automatically stash changes just to make onboarding
proceed. This includes changes written by `:Lazy update` and shell installers.
Once clean, update the intended branch with `git pull --ff-only`; stop and
resolve any divergence rather than forcing it. If there is no checkout yet,
use the clone instructions for a fresh machine.

### WSL / Linux / macOS

Check the selected `hosts/*.nix` file against this machine, install Nix if
needed, and follow the [migration procedure below](#wsl--linux--macos-migration).
Use `nix run .#migrate` to preview and `nix run .#migrate -- --apply` to adopt
existing files and links. **Do not start with `home-manager switch` on an
unmigrated home**: the migration establishes the writable loaders and handles
conflicting files first.

Keep custom functions and private settings in the matching
[local override files](#shell-installers-and-private-settings). Existing local
files are preserved. Review other custom startup code before cutover: the
migrator preserves installer-managed blocks and supported exports, not every
arbitrary command from an old shell configuration.

The migration creates its own backups before replacing configuration. Keep the
printed backup path until the new setup is working; the
[rollback procedure](#roll-back) restores the previous configuration.

### Native Windows

Use the existing checkout only after preserving its local changes. Install any
missing [Windows prerequisites](windows/README.md#prerequisites), then run the
same preview and `-Apply` commands shown above.

The bootstrap preserves the old PowerShell profile privately and backs up
replaced files and links. It does not merge or clean up the Git checkout for
you. Existing private overrides continue to take precedence over public
defaults. Retain the printed manifest for
[Windows rollback](windows/README.md#backup-and-rollback).

## WSL / Linux / macOS migration

### 1. Install Nix once

Run the installer yourself; it requests administrator privileges. Do not run
the subsequent dotfiles migration with `sudo`.

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Open a new terminal after installation. WSL uses its Linux Nix installation,
not a native Windows installation. WSL's systemd integration should be enabled.

### 2. Use this checkout

```sh
cd ~/src/dotfiles
```

The fresh-machine or existing-machine steps above establish this checkout.
`hosts/wsl.nix`,
`hosts/linux.nix`, and `hosts/mac.nix` contain the username, home directory,
and checkout path. Change those if they differ on that machine.

On **macOS**, also install the native Ghostty app and fonts using Homebrew:

```sh
brew install --cask ghostty font-jetbrains-mono-nerd-font font-symbols-only-nerd-font
```

Homebrew must already be installed for that command. Home Manager manages the
Ghostty config but not its signed macOS app. Linux gets Ghostty and fonts from
Nix. WSL uses Windows Terminal and does not install Ghostty.
The migration also backs up alternate `config.ghostty` files and the native
macOS Ghostty configs, if present, so they do not override Home Manager's config.

### 3. Preview, then apply

```sh
nix run .#migrate
nix run .#migrate -- --apply
```

The host is detected automatically; pass `--host wsl`, `--host linux`, or
`--host mac` after `--` to choose explicitly. Nix reads Git-tracked files,
including uncommitted edits. Register newly created source files with
`git add -N <file>` before using them; no commit is required. Avoid `path:.`,
which can copy ignored private files into the Nix store. Keep private
overrides outside the checkout, as described below.

The migration:

1. Uses the locked Home Manager and builds the complete generation **before**
   changing configuration.
2. Checks the configured home and checkout path, and rejects symlinked parent
   directories rather than writing through them.
3. Moves conflicting files and symlinks into a private timestamped backup under
   `~/.local/state/dotfiles/backups/`. Symlinked config contents are also saved
   under `snapshots/`.
4. Preserves installer-managed shell blocks and custom top-level exports in
   writable startup loaders. Shared settings such as editor, locale, NVM, .NET,
   and `NETRC` come from the managed module.
5. Moves the old `~/.tmux.conf` aside, installs the generation, and restores the
   saved configuration if activation fails.

Existing `*.local` files are not replaced. Other custom shell code remains in
the backup; put additional machine-specific functions in the relevant local
file rather than replaying an entire old rc over the managed configuration.
Multiline exported assignments must be moved there before migration.

Open a new terminal after migration. Existing shells and tmux sessions are not
killed. To use the new tmux config in an existing server:

```sh
tmux source-file ~/.config/tmux/tmux.conf
```

If the existing tmux server uses an older binary, start the Nix version on a
separate socket without closing any old panes: `tmux -L nix new`.

### Roll back

The migration prints the exact backup directory and recovery command:

```sh
python3 scripts/migrate.py --rollback /absolute/path/to/the/backup
```

Rollback restores saved configuration and preserves displaced post-migration
files under `after-migration/`. If a previous Home Manager generation was
active, it is reactivated. Nix itself and newly downloaded packages remain
installed; this is configuration rollback, not a Nix uninstaller.
If an old symlink's source changed after backup, rollback restores its saved
contents as a regular file/directory rather than modifying the checkout.
Backups pin the relevant Nix generations against garbage collection. Retain
them while rollback is needed; removing a backup releases those pins.

## Shell installers and private settings

The root startup files (`~/.bashrc`, `~/.zshrc`, and login-shell entry points)
are writable loaders. They source Nix-managed payloads from
`~/.config/dotfiles/`, then optional matching local files:

```text
~/.bashrc.local
~/.zshrc.local
~/.profile.local
~/.bash_profile.local
~/.zshenv.local
~/.zprofile.local
```

Installers may continue appending managed blocks to the normal startup files.
Home Manager does not replace those loaders on subsequent switches. Do not
point installers at the read-only files in `~/.config/dotfiles/`.

Agency and Claude CLI installations, credentials, NVM versions, and user-local
.NET installations remain external. The shell preserves their conventional
paths and NVM initialization. `a`, `c`, `p`, and `cup` are custom dotfiles
helpers, not installer requirements; see [shell/README.md](shell/README.md).

This repository is public. Keep private exports, credentials, internal
functions, and machine-only paths in local files outside the checkout.

## Windows

Use the separate instructions in [windows/README.md](windows/README.md).
Do not overwrite a dirty Windows clone to synchronize it with the WSL clone:
preserve its changes first. Windows Terminal settings deployment is opt-in.

## Roll out repository updates

An update has two parts: **publish it from the editing machine**, then
**pull and apply it on each receiving machine**. Git synchronization alone
does not rebuild Home Manager or update already-running applications.

### 1. Prepare and publish the change

Make changes in the sources listed in [Ownership](#ownership), not in generated
TOML or installed Nix-store files. Register new source files with
`git add -N <file>` so Nix can see them.

For a Starship settings or prompt-color change, regenerate both tracked
outputs before checking or publishing:

```sh
nix run .#render
```

For Nix changes, format the tree, then run the repository gates (these include
`statix` and `deadnix` lints):

```sh
nix fmt
nix flake check
```

Stage only the intended files, including both generated TOML files when they
change. Commit and push to the shared branch, or merge through a pull request,
and let CI pass before rolling the change out to other machines.

Dependency updates are deliberate source changes: run `nix flake update` on the
editing machine, review and commit `flake.lock`, then publish it. A weekly
workflow also opens a `flake.lock` update PR, and Dependabot bumps the pinned
GitHub Actions. Do **not** run
`nix flake update` on every receiving machine; they should consume the same
committed versions. Likewise, publish intended Neovim plugin updates through
`nvim/lazy-lock.json`.

### 2. Synchronize each receiving checkout

From the checkout on each machine, inspect the working tree and branch:

```sh
git status --short
git branch --show-current
```

Continue only after preserving/reconciling local changes and selecting the
branch containing the update:

```sh
git pull --ff-only
```

These Git commands apply to both Unix shells and PowerShell. Update the Windows
and WSL clones separately. Keep host-specific edits committed where appropriate,
and private machine settings outside the repo so routine pulls stay manageable.
If an update adds native prerequisites, install those separately using the
platform setup instructions. A Home Manager switch does not upgrade the macOS
Homebrew app, and the Windows bootstrap does not install or upgrade winget apps.

**Neovim and native Windows config links point at the live checkout.** A pull
can therefore change the files they read immediately. Close those applications
before pulling if you need a controlled cutover.

### 3. Apply the update on WSL / Linux / macOS

On a machine that has already completed migration:

```sh
home-manager switch --flake .#wsl
```

Use `.#linux` or `.#mac` for the other hosts. This is the normal update command;
do not rerun first-time migration for every commit. Open a new terminal afterward
to load new shell settings and use new package versions.

For tmux setting changes, reload the installed configuration:

```sh
tmux source-file ~/.config/tmux/tmux.conf
```

A configuration reload does not replace an existing tmux server's binary. If
tmux itself changed, use `tmux -L nix new` when that socket is unused, or choose
another unused socket name, to start the new version without killing old panes.
Reload Ghostty's configuration or restart the app when its settings change.
Restart Neovim for Lua changes; when `lazy-lock.json` changes, use `:Lazy restore`
to align installed plugins with the committed lockfile, then restart.

If a switch reports conflicting unmanaged files or an incompatible shell
loader, stop rather than forcing replacements. Preview and rerun the
[migration command](#wsl--linux--macos-migration) to back up and adopt those
paths. Preserve custom loader edits in local overrides first.

### 4. Apply the update on native Windows

After pulling, restart Neovim and open a new PowerShell session. The Neovim
config and generated Starship file are linked to the checkout; the writable
PowerShell loader sources the public profile from it. These changes do not
normally require reinstalling links. Use `:Lazy restore` after plugin-lock
changes, just as on Unix.

For bootstrap or link-layout changes, inspect and apply the bootstrap again:

```powershell
pwsh -NoProfile -File .\windows\bootstrap.ps1
pwsh -NoProfile -File .\windows\bootstrap.ps1 -Apply
```

Existing correct links and writable loaders are intentionally preserved. The
bootstrap does not rewrite custom loader edits or upgrade applications; follow
any specific loader-migration instructions accompanying such a change and
update native applications separately with their package manager.

Windows Terminal settings are a **copy**, not a link, and never update merely
because you pulled. Prefer merging selected changes into your private settings.
To replace the full stable-package settings file intentionally, close Terminal,
use a separate PowerShell console, and run:

```powershell
pwsh -NoProfile -File .\windows\bootstrap.ps1 -IncludeWindowsTerminal
pwsh -NoProfile -File .\windows\bootstrap.ps1 -Apply -IncludeWindowsTerminal
```

This replacement is backed up. It can replace machine-specific profiles and
GUIDs, so review the preview and the
[Terminal deployment notes](windows/README.md#windows-terminal-is-a-deliberate-seed)
before applying.

### What needs applying?

| Changed files | Receiving-machine action |
|---|---|
| `modules/`, `hosts/`, `flake.nix`, `flake.lock`, `shell/common.sh`, `bash/inputrc` | Home Manager switch on Unix, then a new shell |
| `tmux/settings.conf` or tmux module settings | Home Manager switch, then tmux config reload; a new server for binary updates |
| Starship Nix settings and generated TOML | Publish both rendered files; Unix switches Home Manager, Windows reads the pulled TOML on the next prompt |
| `nvim/` Lua | Restart Neovim on every platform |
| `nvim/lazy-lock.json` | `:Lazy restore`, then restart Neovim |
| Public PowerShell profile | Open a new PowerShell session; private overrides still win |
| Bootstrap scripts or installation paths | Preview the relevant migration/bootstrap; ordinary settings changes do not require migration |
| Windows Terminal seed | Explicit merge or opt-in copy; pulling alone does nothing |
| Documentation or CI configuration only | Read the updated instructions; no runtime activation is needed |

### Recover from a bad rollout

For managed Unix settings, list previous generations with
`home-manager generations` and run the `activate` executable in the selected
generation's printed store directory. For an onboarding/cutover problem, use
the migration backup's rollback command instead.

On Windows, use the manifest from the relevant bootstrap transaction to undo
its replacements. Neither a Home Manager rollback nor restoring a Windows link
reverts the contents of the live Git checkout: publish a corrective/revert
commit for shared Lua, PowerShell, or generated-file changes and roll it out.
Do not use a destructive reset to discard local edits.

The checks build each native host generation, exercise Bash/Zsh helpers and
migration rollback, parse Lua without loading plugins, and compare both
Starship outputs. CI runs the native Linux and Apple Silicon macOS gates.

Neovim's Lua configuration remains writable so edits and `lazy-lock.json`
updates work normally. It is not part of Home Manager's immutable rollback:
use Git for Neovim configuration history. Nix supplies the editor toolchain;
non-Nix installations use the behavior documented in [nvim/README.md](nvim/README.md).
