# Jason's Dotfiles

Personal configuration files, tracked here so I can set up a new machine (macOS, Linux, or Windows) quickly and consistently.

## Contents

| Folder | Tool | Notes |
|---|---|---|
| [`nvim/`](./nvim) | [Neovim](https://neovim.io/) ([AstroNvim](https://github.com/AstroNvim/AstroNvim) v6+) | See `nvim/README.md` for customizations and setup |
| [`tmux/`](./tmux) | [tmux](https://github.com/tmux/tmux) | Terminal multiplexer, prefix remapped to `Ctrl-a`, seamless pane navigation with Neovim via `vim-tmux-navigator` |
| [`wezterm/`](./wezterm) | [WezTerm](https://wezterm.org/) | Cross-platform terminal (macOS/Linux/Windows) — the one terminal config meant to work identically everywhere, including Windows |
| [`starship/`](./starship) | [Starship](https://starship.rs/) | Cross-platform shell prompt — minimal, left-bordered, with git branch/status |

More folders (shell, ghostty, git, etc.) will be added here as I configure them.

## Setup

Each tool's config is symlinked from its expected location into this repo, so the tool's config directory always points back here. For example:

```shell
git clone https://github.com/jrob5756/dotfiles ~/dotfiles
ln -s ~/dotfiles/nvim ~/.config/nvim   # macOS/Linux
```

On Windows, symlink (or clone directly) into the tool's native config path instead (e.g. `%LOCALAPPDATA%\nvim` for Neovim).

See each subfolder's own README for tool-specific installation steps.
