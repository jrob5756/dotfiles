# Jason's Dotfiles

Personal configuration files, tracked here so I can set up a new machine (macOS, Linux, or Windows) quickly and consistently.

## Contents

| Folder | Tool | Notes |
|---|---|---|
| [`nvim/`](./nvim) | [Neovim](https://neovim.io/) ([AstroNvim](https://github.com/AstroNvim/AstroNvim) v6+) | See `nvim/README.md` for customizations and setup |
| [`tmux/`](./tmux) | [tmux](https://github.com/tmux/tmux) | Terminal multiplexer, prefix remapped to `Ctrl-a`, seamless pane navigation with Neovim via `vim-tmux-navigator` |
| [`zsh/`](./zsh) | [zsh](https://www.zsh.org/) | Interactive shell — history, completion, key bindings, aliases, plugins; also initializes the Starship prompt (macOS/Linux, or WSL on Windows) |
| [`wezterm/`](./wezterm) | [WezTerm](https://wezterm.org/) | Cross-platform terminal (macOS/Linux/Windows) — the one terminal config meant to work identically everywhere, including Windows |
| [`starship/`](./starship) | [Starship](https://starship.rs/) | Cross-platform shell prompt — minimal, left-bordered, with git branch/status |

More folders (ghostty, git, etc.) will be added here as I configure them.

## Setup

Every tool's config lives in its own subfolder here and gets linked (or copied, on Windows) into the location that tool expects. Assumes you already have `git` and a package manager (Homebrew on macOS/Linux, `winget` on Windows) installed.

### macOS / Linux

1. **Clone this repo**

   ```shell
   git clone https://github.com/jrob5756/dotfiles ~/dotfiles
   ```

2. **Install the tools**

   ```shell
   # macOS (Homebrew)
   brew install neovim tmux starship
   brew install --cask wezterm

   # Linux — use your distro's package manager, e.g.:
   sudo apt install neovim tmux          # starship and wezterm aren't in most default repos;
                                          # see https://starship.rs/guide/#-installation and
                                          # https://wezterm.org/installation.html
   ```

3. **Symlink each config into place**

   ```shell
   ln -s ~/dotfiles/nvim ~/.config/nvim
   ln -s ~/dotfiles/tmux/tmux.conf ~/.tmux.conf
   ln -s ~/dotfiles/zsh/zshrc ~/.zshrc
   ln -s ~/dotfiles/wezterm/wezterm.lua ~/.wezterm.lua
   mkdir -p ~/.config
   ln -s ~/dotfiles/starship/starship.toml ~/.config/starship.toml
   ```

4. **Install tmux's plugin manager (TPM) and its plugins**

   ```shell
   git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
   ```

   Launch tmux, then press `prefix` (`Ctrl-a`) + `I` (capital i) to fetch and install the plugins declared in `tmux.conf`.

5. **Wire up starship in your shell**

   If you symlinked the zsh config above, this is already done — `zsh/zshrc`
   ends with `eval "$(starship init zsh)"`. For any other shell, add the
   equivalent init line yourself, e.g.:

   ```shell
   eval "$(starship init zsh)"
   ```

6. **Verify it worked**

   - `nvim` opens with the file explorer already showing, and plugins finish installing automatically on first launch (via lazy.nvim)
   - Launch WezTerm — Catppuccin Mocha theme and JetBrains Mono font should be visible
   - Open a new terminal (or `tmux new`) and confirm the prompt shows the left-bordered starship style with git branch/status
   - Inside tmux, `Ctrl-a |` splits a pane, and `Ctrl-h/j/k/l` moves between tmux panes *and* Neovim splits seamlessly (once inside `nvim`)

### Windows

`tmux` has **no native Windows build at all** — it depends on Unix domain sockets and pty handling that only exist on Unix-like systems. There's no way around this outside of WSL (see the WSL section below). Neovim, WezTerm, and Starship, on the other hand, all run natively on Windows with no such caveat.

1. **Clone this repo**

   ```powershell
   git clone https://github.com/jrob5756/dotfiles $env:USERPROFILE\dotfiles
   ```

2. **Install the natively-Windows tools via winget**

   ```powershell
   winget install Neovim.Neovim
   winget install wez.wezterm
   winget install Starship.Starship
   ```

3. **Symlink each config into place**

   Creating symlinks on Windows requires Developer Mode enabled (Settings → Privacy & Security → For developers), or running PowerShell as Administrator. Updates from `git pull` apply immediately, no re-copying needed.

   ```powershell
   New-Item -ItemType SymbolicLink -Path "$env:LOCALAPPDATA\nvim" -Target "$env:USERPROFILE\dotfiles\nvim"
   New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.wezterm.lua" -Target "$env:USERPROFILE\dotfiles\wezterm\wezterm.lua"
   New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.config" | Out-Null
   New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.config\starship.toml" -Target "$env:USERPROFILE\dotfiles\starship\starship.toml"
   ```

4. **Wire up starship in your shell**

   Add to your PowerShell `$PROFILE`:

   ```powershell
   Invoke-Expression (&starship init powershell)
   ```

5. **tmux, via WSL**

   Since tmux can't run outside WSL on Windows, install and configure it inside a WSL distro — at that point it's just Linux, so follow the **macOS/Linux steps above (2-4)** for tmux specifically, from within the WSL shell:

   ```powershell
   wsl --install                         # if WSL isn't already set up
   ```

   Then, inside the WSL shell:

   ```shell
   sudo apt update && sudo apt install tmux
   git clone https://github.com/jrob5756/dotfiles ~/dotfiles   # a separate clone, inside WSL's own filesystem
   ln -s ~/dotfiles/tmux/tmux.conf ~/.tmux.conf
   git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
   ```

   Then launch `tmux` from inside WSL and press `prefix` (`Ctrl-a`) + `I` to install plugins, same as macOS/Linux.

6. **Native Windows fallback for multiplexing (no WSL)**

   If you're working in a native Windows terminal session (PowerShell/cmd running directly, not inside a WSL shell), tmux isn't reachable there at all — not even a limited version. For that context, use **WezTerm's own built-in pane and tab multiplexing** instead (its native split-pane and tab keybindings, no config changes needed here). It's a different key scheme than tmux's `Ctrl-a`-prefixed commands, but serves the same practical purpose: multiple panes/sessions in one window.

7. **Verify it worked**

   - `nvim` opens correctly from `%LOCALAPPDATA%\nvim`, explorer auto-opens, plugins install on first launch
   - WezTerm launches with the Catppuccin Mocha theme and correct font
   - PowerShell prompt shows the starship style
   - Inside a WSL shell, `tmux` starts and `Ctrl-a |` splits a pane as expected
   - Outside WSL, WezTerm's native pane splitting works as the tmux substitute

### Keeping configs in sync

- **macOS/Linux/Windows (symlinked)**: a `git pull` inside `dotfiles` is all you need — every tool immediately sees the updated config, since the symlink always points at the live repo content.

See each subfolder's own README for tool-specific customization details (`nvim/README.md`, `tmux/README.md`, `wezterm/README.md`, `starship/README.md`).
