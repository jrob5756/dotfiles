# WezTerm config

Cross-platform terminal config, since [WezTerm](https://wezterm.org/) runs natively on macOS, Linux, **and** Windows (unlike Ghostty, which has no native Windows support). Intended to be the single terminal config used across every machine, including the Windows one.

## Highlights

- **Catppuccin Mocha** color scheme, JetBrains Mono font with Nerd Font fallback for icons (matches the icons used in Neovim/Neo-tree/AstroNvim's UI).
- No custom leader-key bindings — tmux's `Ctrl-a` prefix (see `tmux/tmux.conf`) handles pane/window multiplexing. WezTerm's own tabs are left available for keeping separate tmux sessions visually distinct (e.g. work vs. personal), without needing to nest tmux-inside-tmux or juggle two prefix keys.

## Setup

### macOS

```shell
brew install --cask wezterm
ln -s ~/dotfiles/wezterm/wezterm.lua ~/.wezterm.lua
```

### Linux

Install via your package manager or the [official instructions](https://wezterm.org/installation.html), then:

```shell
ln -s ~/dotfiles/wezterm/wezterm.lua ~/.wezterm.lua
```

### Windows

Install via `winget install wez.wezterm`, then symlink (requires Developer Mode enabled, or PowerShell running as Administrator):

```powershell
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.wezterm.lua" -Target "$env:USERPROFILE\dotfiles\wezterm\wezterm.lua"
```

If symlinks aren't an option, copy the file instead — just remember to re-copy after future `git pull`s:

```powershell
Copy-Item ~\dotfiles\wezterm\wezterm.lua ~\.wezterm.lua
```

## Notes

- Requires a [Nerd Font](https://www.nerdfonts.com/) (or a font + fallback, as configured here) for icons to render correctly — matches the same font requirement Neovim's UI already has.
- If you don't have `JetBrains Mono` installed, WezTerm will fall back to its own default monospace font; install it (`brew install --cask font-jetbrains-mono`) to get the intended look.
