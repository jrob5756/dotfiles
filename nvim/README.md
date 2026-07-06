# Jason's Neovim Config

Personal [AstroNvim](https://github.com/AstroNvim/AstroNvim) v6+ configuration, tracked here so I can carry the same setup across machines (including Windows).

## Customizations over stock AstroNvim

- **`<S-Right>` / `<S-Left>`** — next/previous buffer (in addition to the default `]b`/`[b`)
- **`<S-Right>` / `<S-Left>`** — also switches Neo-tree's source tabs (Files/Buffers/Git) when focused in the explorer
- **Neo-tree git status fix** — the git status view now follows the working directory (`.` or `:cd`) instead of showing stale results from the previous directory
- **File explorer opens automatically on startup**, every time, not just when launching `nvim` on a directory
- **Seamless tmux/Neovim pane navigation** — `<C-h/j/k/l>` moves between Neovim splits *and* tmux panes with the same keys, via `vim-tmux-navigator` (pairs with `~/dotfiles/tmux/tmux.conf`)

See `lua/plugins/astrocore.lua` (core options/mappings/autocmds), `lua/plugins/neo-tree.lua` (explorer overrides), and `lua/plugins/tmux-navigator.lua` (tmux pane integration) for the details.

## 🛠️ Installation on a new machine

See the top-level [`../README.md`](../README.md) for the full cross-platform setup guide. In short, for this tool specifically:

#### Back up any existing Neovim config/state (only needed if migrating from another setup)

```shell
mv ~/.config/nvim ~/.config/nvim.bak
mv ~/.local/share/nvim ~/.local/share/nvim.bak
mv ~/.local/state/nvim ~/.local/state/nvim.bak
mv ~/.cache/nvim ~/.cache/nvim.bak
```

#### Symlink this folder into the Neovim config location

macOS/Linux:

```shell
ln -s ~/dotfiles/nvim ~/.config/nvim
```

Windows (PowerShell) — symlinks need Developer Mode enabled; without it, clone/copy the whole `dotfiles` repo and copy this folder's contents into `%LOCALAPPDATA%\nvim` instead:

```powershell
New-Item -ItemType SymbolicLink -Path "$env:LOCALAPPDATA\nvim" -Target "$env:USERPROFILE\dotfiles\nvim"
```

#### Start Neovim

```shell
nvim
```

Plugins install automatically on first launch via [lazy.nvim](https://github.com/folke/lazy.nvim), pinned to the versions in `lazy-lock.json` for reproducibility across machines.
