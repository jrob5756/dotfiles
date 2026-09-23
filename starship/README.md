# Starship prompt config

Minimal prompt with a left border and custom colors. The first line shows the
directory, git branch/status, and, when relevant, the Python version and
virtualenv, the current Kubernetes context, and how long the last command took
(2 seconds or more). See [starship.rs](https://starship.rs/config/) for the
full reference.

## Where the config lives

Starship settings are defined once in Nix and rendered to two identical files.
`starship/starship.toml` preserves existing symlinks during migration;
`generated/starship.toml` is the target for new Windows installations. Neither
file should be edited by hand.

| | |
|---|---|
| Source of truth | [`modules/starship-settings.nix`](../modules/starship-settings.nix) |
| Prompt colors | [`modules/palette.nix`](../modules/palette.nix) |
| Home Manager wiring | [`modules/starship.nix`](../modules/starship.nix) |
| Rendered output for Windows | [`generated/starship.toml`](../generated/starship.toml) |
| Compatibility output | [`starship/starship.toml`](./starship.toml) |

## Changing the prompt

Edit `modules/starship-settings.nix`, then:

```shell
nix run .#render          # refresh both tracked TOML files
```

Existing manual installations see the updated file through their current
symlink; do not activate Home Manager just to change the prompt.

If the machine is **already managed by Home Manager**, also apply the settings:

```shell
home-manager switch --flake .#wsl   # or .#linux / .#mac
```

`nix flake check` compares both TOML files against the Nix source. Commit both
outputs when changing the prompt. The renderer provides GNU coreutils itself,
including on macOS.

## Setup

**Existing manual setup** — keep your current symlink to
`starship/starship.toml` until you explicitly switch to Home Manager.

**After Home Manager activation** — Home Manager installs starship, writes
`~/.config/starship.toml`, and adds the shell init for both bash and zsh.

**Windows** — run `windows\bootstrap.ps1`, which symlinks
`generated/starship.toml` to `~/.config/starship.toml`. The tracked PowerShell
profile already runs `starship init powershell`. See
[`windows/README.md`](../windows/README.md).
