# Neovim

Personal [AstroNvim](https://github.com/AstroNvim/AstroNvim) v6 configuration shared by Linux, WSL, macOS, and native Windows.

## Behavior and mappings

- `<S-Right>` / `<S-Left>` and `]b` / `[b]` select the next/previous buffer. In Neo-tree, shifted arrows switch Files/Buffers/Git sources.
- Neo-tree opens at startup, and its git status follows the current working directory.
- `<C-h/j/k/l>` navigates Neovim splits and tmux panes using `vim-tmux-navigator`.
- `yA` copies the whole file without moving the cursor. `unnamedplus` also sends normal yanks, deletes, and changes to the system clipboard.
- `n` / `N` center search results and open folds containing matches.
- Python uses basedpyright, Ruff, and debugpy. Lua uses lua-language-server and StyLua. C# uses csharp-ls, CSharpier, and netcoredbg when available.
- Conform owns formatting (`<Leader>lf` or `:Format`) and format-on-save. `<Leader>uf` / `<Leader>uF` toggle buffer/global autoformatting.
- Copilot completion is integrated with blink.cmp. Run `:Copilot auth` to sign in.
- On native Windows, `<Leader>tc`, `<Leader>t5`, and `<Leader>t7` open interactive cmd, Windows PowerShell, and PowerShell 7 terminals with profiles loaded. Background shell calls use PowerShell with `-NoProfile` to avoid blocking on interactive startup.
- Native Windows Neo-tree filtering submits with Enter instead of spawning cancellation processes on each keystroke. Linux and macOS keep live filtering.

## Installation and tool ownership

Follow the [repository setup guide](../README.md) for installation and migration. Back up an existing Neovim configuration before replacing it; do not delete editor state or plugin data to switch configurations.

### Nix-managed Linux, WSL, and macOS

Home Manager links this directory and installs external tools. The Nix `nvim` wrapper sets `DOTFILES_NIX=1` and prepends the editor toolchain to PATH, including when launched from a GUI. Managed shells also export the marker; restart existing shells after activation.

In these sessions, Mason does not automatically install or update tools, add its binaries to PATH, or activate its previously installed language servers/debuggers. Executable tools on PATH are used instead. Missing tools must be added to the Nix environment rather than installed with `:Mason`. Existing Mason data can remain on disk.

| Executables | Purpose |
|---|---|
| `git`, `rg`, `fd`, `lazygit` | Plugin downloads, searching, file navigation, Git UI |
| `node` | Copilot and Node-based language tools |
| `python3` or `python`, `basedpyright-langserver`, `ruff`, `debugpy-adapter` | Python editing, formatting, and debugging |
| `lua-language-server`, `stylua` | Lua editing and formatting |
| `selene` | Lua linting in projects containing `selene.toml` |
| `tree-sitter`, C compiler (`cc`), `make`, `curl`, `tar` | Treesitter parser generation, compilation, and downloads |
| `dotnet` with an SDK, `csharp-ls`, `csharpier` | C# editing and formatting |
| `netcoredbg` (Linux only) | C# debugging, subject to package/platform availability |

Language servers are explicitly enabled only when their executables are found on PATH. Python interpreter overrides from project configuration are preserved; active `VIRTUAL_ENV` and `CONDA_PREFIX` interpreters take precedence over the pinned toolchain's Python. If no interpreter is found, basedpyright is allowed to discover one instead of receiving an empty path.

C# requires an SDK, not just a .NET runtime. Check `dotnet --list-sdks`. Without an SDK, `csharp_ls` is disabled and opening a C# file displays a warning. netcoredbg launches a compiled DLL selected at debugger startup; build the project first.

The managed macOS environment does not provide netcoredbg, so C# debugging is unsupported there unless a compatible adapter is supplied separately on PATH. C# editing and formatting remain available. Neovim does not fall back to Mason to install the missing debugger in Nix sessions.

### Native Windows and other non-Nix installations

Do not set `DOTFILES_NIX=1` on manual installations. Mason installs missing configured language tools and prefers tools already on PATH. Python packages are not globally excluded: Mason can install basedpyright, Ruff, and debugpy if they are missing. C# language-server and formatter installation is skipped when no .NET SDK is detected.

Install these prerequisites before starting Neovim:

| Dependency | Windows example |
|---|---|
| Neovim | `winget install Neovim.Neovim` |
| Git | `winget install Git.Git` |
| ripgrep | `winget install BurntSushi.ripgrep.MSVC` |
| fd | `winget install sharkdp.fd` |
| lazygit | `winget install JesseDuffield.lazygit` |
| Node.js LTS | `winget install OpenJS.NodeJS.LTS` |
| Python with pip and venv | Install a current supported Python from python.org or winget; disable conflicting Microsoft Store execution aliases |
| .NET SDK | Install an SDK supported by the current csharp-ls/CSharpier releases and your project |
| C compiler | Install a supported compiler and launch Neovim with it on PATH, such as a Visual Studio Developer PowerShell |
| `curl`, `tar` | Verify they are available on PATH for parser downloads |

Manual Linux/macOS installations need equivalent prerequisites through their system package manager. Some Linux distributions package Python's `venv` support separately. Install it rather than disabling Python tooling globally.

To link the configuration on native Windows, enable Developer Mode or use an elevated PowerShell. The destination must not already exist:

```powershell
New-Item -ItemType SymbolicLink -Path "$env:LOCALAPPDATA\nvim" -Target "$env:USERPROFILE\dotfiles\nvim"
```

For a manual Linux/macOS installation, link the checkout's `nvim` directory to `${XDG_CONFIG_HOME:-$HOME/.config}/nvim` after backing up the destination.

## Plugins, parsers, and clipboard

Lazy.nvim installs plugins on first launch using `lazy-lock.json`. This is separate from external-tool ownership. AstroCore/nvim-treesitter installs parsers, including Lua, Vim, C#, Python, and TOML; **Mason only supplies the tree-sitter CLI on manual installations, not parsers**. Parser installation requires a working compiler and network access.

Clipboard provider selection remains Neovim's native autodetection:

- Wayland/WSLg: `wl-copy` and `wl-paste`, with a working `WAYLAND_DISPLAY`.
- X11: `xclip`, with a working `DISPLAY`.
- macOS: `pbcopy` / `pbpaste`.
- Native Windows: Neovim's Windows clipboard provider.

Run `:checkhealth vim.provider` if clipboard access fails. Terminal-only/SSH environments require a supported provider or terminal-supported OSC 52; this configuration does not force OSC 52 writes or replace a working desktop clipboard.

## Isolated validation

From the repository root, syntax-check without loading the configuration or installing plugins:

```sh
nvim --headless -u NONE -i NONE --noplugin \
  -c 'lua for _, f in ipairs(vim.fn.glob("nvim/**/*.lua", false, true)) do assert(loadfile(f)) end' \
  -c 'qa!'
```

Run the mocked tool-ownership checks without loading plugins:

```sh
nvim --headless -u NONE -i NONE --noplugin -l nvim/tests/toolchain.lua
```
