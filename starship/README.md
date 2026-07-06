# Starship prompt config

Minimal prompt with a left border, custom colors, and a git branch/status segment. See [starship.rs](https://starship.rs/config/) for the full config reference.

## Setup

### 1. Install starship

macOS: `brew install starship`
Linux/Windows: see the [official install instructions](https://starship.rs/guide/#-installation)

### 2. Symlink the config

macOS/Linux:

```shell
mkdir -p ~/.config
ln -s ~/dotfiles/starship/starship.toml ~/.config/starship.toml
```

Windows (PowerShell) — symlinks need Developer Mode, so a plain copy is simpler:

```powershell
Copy-Item ~\dotfiles\starship\starship.toml "$env:USERPROFILE\.config\starship.toml"
```

### 3. Initialize in your shell

Add to `~/.zshrc` (or the equivalent for your shell):

```shell
eval "$(starship init zsh)"
```

For PowerShell, add to your `$PROFILE`:

```powershell
Invoke-Expression (&starship init powershell)
```
