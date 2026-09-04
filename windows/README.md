# Windows

Windows is the one platform Nix cannot manage: there is no native Nix or Home
Manager for Win32, and WSL2 is the only supported route. So Windows keeps the
original mechanism — a clone of this repo plus symlinks — while macOS, Linux and
WSL are driven by Home Manager.

That split is deliberate and does **not** need a separate branch. See the root
`README.md` for the reasoning; the short version is that Windows-vs-Unix is a
permanent axis of variation, and permanent variation belongs in directories and
modules, not in a long-lived branch nobody ever merges.

## What Windows actually consumes

| Config | Source | How |
|---|---|---|
| Neovim | `nvim/` | Symlink — plain Lua, shared verbatim with every platform |
| Starship | `generated/starship.toml` | Symlink — rendered from Nix, committed for exactly this reason |
| PowerShell profile | `windows/powershell/` | Symlink |
| Windows Terminal | `windows/windows-terminal/settings.json` | **Copy**, not symlink |

Run `windows\bootstrap.ps1` from an elevated PowerShell (or with Developer Mode
enabled) to create the links.

### Why Starship is generated

Starship is the only tool in this repo that both runs natively on Windows and
benefits from Nix-managed settings. Rather than maintain two copies, Nix is the
source of truth (`modules/starship-settings.nix`) and renders the TOML into
`generated/starship.toml`, which is committed so the Windows clone can symlink
it. `nix flake check` fails if that file goes stale; `nix run .#render` fixes it.

### Why Windows Terminal is copied, not linked

Windows Terminal rewrites `settings.json` in place every time you change
anything in its UI. Through a symlink, that would write straight back into the
repo and mix hand-edits with tracked config. Copy it instead, and re-copy after
pulling.

`settings.json` is also only partly portable — profile GUIDs, `source`-based
profiles (Ubuntu, Git, Visual Studio) and the background image paths are all
machine-specific. Treat the tracked copy as a seed to merge from, not a drop-in
replacement.

## Changes from the pre-Nix setup

- The **Ubuntu profile** now uses the `Catppuccin Mocha` scheme instead of
  `UbuntuLegit`, so the terminal matches the tmux, starship and Ghostty colours
  that come from `modules/palette.nix`. `UbuntuLegit` is still defined in
  `schemes` — change `colorScheme` back on that profile to revert.
- Fonts still differ by platform: Windows Terminal uses `FiraCode Nerd Font
  Mono` at 12, while `modules/palette.nix` sets `JetBrainsMono Nerd Font` at 13
  for Ghostty. Unify by editing both if you want them identical.

## Keeping work-specific config out of a public repo

This repository is **public**. The tracked PowerShell profile is deliberately
generic — no internal repo paths, machine names, or build tooling.

Anything work-specific belongs in `profile.local.ps1`, next to `$PROFILE`. The
tracked profile sources it at the end if present, and it is never committed.
