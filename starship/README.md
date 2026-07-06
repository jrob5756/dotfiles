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

Windows (PowerShell) — requires Developer Mode enabled, or running as Administrator:

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.config" | Out-Null
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.config\starship.toml" -Target "$env:USERPROFILE\dotfiles\starship\starship.toml"
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
