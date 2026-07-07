# Jason's Neovim Config

Personal [AstroNvim](https://github.com/AstroNvim/AstroNvim) v6+ configuration, tracked here so I can carry the same setup across machines (including Windows).

## Customizations over stock AstroNvim

- **`<S-Right>` / `<S-Left>`** — next/previous buffer (in addition to the default `]b`/`[b`)
- **`<S-Right>` / `<S-Left>`** — also switches Neo-tree's source tabs (Files/Buffers/Git) when focused in the explorer
- **Neo-tree git status fix** — the git status view now follows the working directory (`.` or `:cd`) instead of showing stale results from the previous directory
- **File explorer opens automatically on startup**, every time, not just when launching `nvim` on a directory
- **Seamless tmux/Neovim pane navigation** — `<C-h/j/k/l>` moves between Neovim splits *and* tmux panes with the same keys, via `vim-tmux-navigator` (pairs with `~/dotfiles/tmux/tmux.conf`)
- **C#/.NET support** — `csharp_ls` (LSP), `csharpier` (formatter), `netcoredbg` (debugger), and the `c_sharp` Treesitter parser are auto-installed via Mason (see `lua/plugins/mason.lua` and `lua/plugins/treesitter.lua`)
- **Windows-only terminal pickers** — `<Leader>tc` (cmd.exe), `<Leader>t5` (PowerShell 5), `<Leader>t7` (PowerShell 7/`pwsh`) open a floating ToggleTerm running that shell **with your profile loaded** (oh-my-posh, aliases, etc.). Use these for interactive work. No-op on macOS/Linux (see `lua/plugins/toggleterm.lua`)
- **Windows-only shell** — `vim.o.shell` is set to PowerShell 7 (falling back to Windows PowerShell) with **`-NoProfile`**. The `-NoProfile` is critical: `vim.o.shell` is used for every background `vim.fn.system("...")`/`:!` call (e.g. Neo-tree's `taskkill` job cancellation), and loading the full profile there makes each call hang for 60s+ non-interactively — freezing the editor on routine actions. With `-NoProfile` it's ~0.6s. Gated behind `has("win32")`, no-op on macOS/Linux (see `lua/plugins/astrocore.lua`)
- **Windows-only Neo-tree filter** — the live `/` filter is remapped to Neo-tree's single-shot `filter_on_submit` (type, then `<Enter>`) instead of live `fuzzy_finder`, avoiding a per-keystroke `taskkill` process spawn on Windows. macOS/Linux keep the live filter. Gated behind `has("win32")` (see `lua/plugins/neo-tree.lua`)
- **GitHub Copilot autocomplete** — `zbirenbaum/copilot.lua` wired into `blink.cmp` via the `astrocommunity.completion.blink-copilot` pack (enabled in `lua/community.lua`). Run `:Copilot auth` on first use to sign in

See `lua/plugins/astrocore.lua` (core options/mappings/autocmds), `lua/plugins/neo-tree.lua` (explorer overrides), and `lua/plugins/tmux-navigator.lua` (tmux pane integration) for the details.

## 🛠️ Installation on a new machine

See the top-level [`../README.md`](../README.md) for the full cross-platform setup guide. In short, for this tool specifically:

#### External tools required (all platforms)

Beyond Neovim itself, these are required by plugins in this config — install them the same way on every platform, not just Windows:

| Tool | Used by | macOS (brew) | Windows (winget) |
|---|---|---|---|
| `ripgrep` (`rg`) | Snacks picker live grep, telescope-style search | `brew install ripgrep` | `winget install BurntSushi.ripgrep.MSVC` |
| `fd` | Snacks picker find-files, Neo-tree's `/` filter | `brew install fd` | `winget install sharkdp.fd` |
| `lazygit` | `<Leader>gg`/`<Leader>tl` git TUI (see [toggleterm.lua](./lua/plugins/toggleterm.lua)) | `brew install lazygit` | `winget install JesseDuffield.lazygit` |
| Python 3 | `debugpy` (Mason debugger for Python) | preinstalled or `brew install python` | `winget install Python.Python.3.12` (the Microsoft Store `python`/`python3` alias stubs do **not** count and will break Mason installs) |
| Node.js | `copilot.lua` (Copilot autocomplete) | `brew install node` | `winget install OpenJS.NodeJS.LTS` |

Missing `fd`/`ripgrep` is the most common cause of a "frozen"-feeling Neo-tree filter or file picker — without them, Neo-tree falls back to slow platform-native tools (e.g. `where /r` on Windows) that spawn a fresh process per keystroke.

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

Windows (PowerShell) — requires Developer Mode enabled, or running as Administrator:

```powershell
New-Item -ItemType SymbolicLink -Path "$env:LOCALAPPDATA\nvim" -Target "$env:USERPROFILE\dotfiles\nvim"
```

#### Start Neovim

```shell
nvim
```

Plugins install automatically on first launch via [lazy.nvim](https://github.com/folke/lazy.nvim), pinned to the versions in `lazy-lock.json` for reproducibility across machines.
