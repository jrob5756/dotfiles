# Starship prompt config

Minimal prompt with a left border, custom colors, and a git branch/status
segment. See [starship.rs](https://starship.rs/config/) for the full reference.

## Where the config lives

There is no `starship.toml` in this folder any more. Starship is the one tool in
this repo that both runs natively on Windows *and* benefits from Nix-managed
settings, so it is defined once in Nix and rendered out:

| | |
|---|---|
| Source of truth | [`modules/starship-settings.nix`](../modules/starship-settings.nix) |
| Colors | [`modules/palette.nix`](../modules/palette.nix), shared with tmux and Ghostty |
| Home Manager wiring | [`modules/starship.nix`](../modules/starship.nix) |
| Rendered output for Windows | [`generated/starship.toml`](../generated/starship.toml) |

## Changing the prompt

Edit `modules/starship-settings.nix`, then:

```shell
nix run .#render          # refresh generated/starship.toml
home-manager switch --flake .#wsl   # or .#linux / .#mac
```

`nix flake check` fails if `generated/starship.toml` has drifted from the Nix
source, so a forgotten re-render can't ship silently.

## Setup

**macOS / Linux / WSL** — nothing to do. Home Manager installs starship, writes
`~/.config/starship.toml`, and adds the shell init for both bash and zsh.

**Windows** — run `windows\bootstrap.ps1`, which symlinks
`generated/starship.toml` to `~/.config/starship.toml`. The tracked PowerShell
profile already runs `starship init powershell`. See
[`windows/README.md`](../windows/README.md).
