# tmux config

Prefix key is remapped to **`Ctrl-a`** (from the default `Ctrl-b`).

## Highlights

- **`Ctrl-h/j/k/l`** — move between tmux panes *and* Neovim splits with the same keys (seamless, no prefix needed), via `vim-tmux-navigator`. Mirrors the window navigation already set up in the `nvim/` config.
- **Mouse support on** — click to select a pane, drag borders to resize, scroll to scroll a pane's history.
- **`prefix |`** / **`prefix -`** — split panes vertically/horizontally, opening in the current pane's directory (matches the `|` vsplit mapping in the nvim config).
- **`prefix r`** — reload config without restarting tmux.
- Copy mode uses vi-style keys (`v` to start selection, `y` to yank) since that matches Neovim muscle memory better than tmux's Emacs-style defaults.

## Setup

### 1. Install tmux

macOS: `brew install tmux`
Linux: use your package manager (`apt install tmux`, `pacman -S tmux`, etc.)
Windows: tmux doesn't run natively — use it inside WSL.

### 2. Symlink the config

```shell
ln -s ~/dotfiles/tmux/tmux.conf ~/.tmux.conf
```

### 3. Install TPM (Tmux Plugin Manager)

```shell
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

### 4. Install plugins

Launch tmux, then press `prefix` + `I` (capital i) to fetch and install the plugins listed in `tmux.conf` (currently just `vim-tmux-navigator`).

## Notes

- `vim-tmux-navigator` requires the matching side to be set up in Neovim too (a plugin, not just the `<C-h/j/k/l>` mappings already in `nvim/lua/plugins/astrocore.lua`) for the pane-vs-split detection to work perfectly. If `<C-h/j/k/l>` ever stops crossing between tmux and Neovim seamlessly, that's the first thing to check.
