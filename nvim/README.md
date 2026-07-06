# Jason's Neovim Config

Personal [AstroNvim](https://github.com/AstroNvim/AstroNvim) v6+ configuration, tracked here so I can carry the same setup across machines (including Windows).

## Customizations over stock AstroNvim

- **`<S-Right>` / `<S-Left>`** — next/previous buffer (in addition to the default `]b`/`[b`)
- **`<S-Right>` / `<S-Left>`** — also switches Neo-tree's source tabs (Files/Buffers/Git) when focused in the explorer
- **Neo-tree git status fix** — the git status view now follows the working directory (`.` or `:cd`) instead of showing stale results from the previous directory
- **File explorer opens automatically on startup**, every time, not just when launching `nvim` on a directory

See `lua/plugins/astrocore.lua` (core options/mappings/autocmds) and `lua/plugins/neo-tree.lua` (explorer overrides) for the details.

## 🛠️ Installation on a new machine

#### Back up any existing Neovim config/state (only needed if migrating from another setup)

```shell
mv ~/.config/nvim ~/.config/nvim.bak
mv ~/.local/share/nvim ~/.local/share/nvim.bak
mv ~/.local/state/nvim ~/.local/state/nvim.bak
mv ~/.cache/nvim ~/.cache/nvim.bak
```

#### Clone this repo into the Neovim config location

macOS/Linux:

```shell
git clone https://github.com/jrob5756/nvim ~/.config/nvim
```

Windows (PowerShell):

```powershell
git clone https://github.com/jrob5756/nvim $env:LOCALAPPDATA\nvim
```

#### Start Neovim

```shell
nvim
```

Plugins install automatically on first launch via [lazy.nvim](https://github.com/folke/lazy.nvim), pinned to the versions in `lazy-lock.json` for reproducibility across machines.
