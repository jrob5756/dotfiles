# tmux config

Prefix key is remapped to **`Ctrl-a`** (from the default `Ctrl-b`).

## Highlights

- **`Ctrl-h/j/k/l`** — move between tmux panes *and* Neovim splits with the same keys (seamless, no prefix needed), via `vim-tmux-navigator`. Mirrors the window navigation already set up in the `nvim/` config.
- **Mouse support on** — click to select a pane, drag borders to resize, scroll to scroll a pane's history.
- **`prefix |`** / **`prefix \`** / **`prefix _`** / **`prefix -`** — split the current pane right / left / down / up, opening in the current pane's directory (the `|` vsplit matches the mapping in the nvim config). Unshifted keys put the new pane above or to the left; shifted keys put it below or to the right.
- **`prefix c`** — new windows also open in the current pane's directory.
- **`prefix s`** — fuzzy session switcher in a popup: sessions (most recently used first), then zoxide's directories. Picking a directory opens a session named after it, rooted there, or switches to it if it already exists. Enter on a name that matches nothing creates a session in `~`; **Ctrl-O** creates one named exactly as typed even when it fuzzy-matches an entry. The built-in tree view is still on `prefix w`.
- **`prefix f`** — fuzzy window switcher across all sessions (most recently active first), with a live preview of the highlighted window. Replaces tmux's built-in find-window.
- **`prefix g`** — lazygit in a popup, for the current pane's directory.
- **`` prefix ` ``** — toggle a scratch shell in a popup. It's a hidden `scratch` session, so the shell and its history survive closing the popup. Neither switcher lists it.
- **`prefix F`** — tmux-fingers: labels SHAs, paths, URLs, IPs, UUIDs and similar on screen with short hints; typing a hint copies the match. `prefix J` jumps the copy-mode cursor to a match instead. Copies go through tmux (`load-buffer -w`), so they reach the system clipboard over OSC 52 on every host.
- **Closing a session doesn't exit tmux**: `detach-on-destroy off` moves you to another session when the last window of the current one closes.
- **Catppuccin status bar** (colours from `modules/palette.nix`) on the terminal background: session badge on the left (turns red while the prefix is pending), windows in the middle, `ZOOM` when a pane is zoomed, then time and host.
- **50,000 lines of scrollback** per pane.
- **Obvious active pane**: the active pane gets a heavy, bold blue border with arrow indicators. Inactive borders are muted, and default text in inactive panes is dimmed. Backgrounds stay `terminal`, so transparency is preserved.
- **`prefix r`** — reload config without restarting tmux.
- **Sessions survive reboots** — `tmux-resurrect` + `tmux-continuum` auto-save every 15 minutes and auto-restore when the tmux server next starts. See [Session persistence](#session-persistence) below.
- **Ghostty opens straight into tmux**: each Ghostty window runs `tmux new-session -A -s main`, attaching to the `main` session or creating it. Launching Ghostty therefore starts the server and triggers auto-restore.
- Copy mode uses vi-style keys (`v` to start selection, `y` to yank) since that matches Neovim muscle memory better than tmux's Emacs-style defaults.

## Setup

Home Manager handles all of this — `home-manager switch --flake .#<host>`
installs tmux, pins the plugins, and writes `~/.config/tmux/tmux.conf`. There is
no TPM install and no `prefix + I` step; plugins are present on first launch.

See the root [`README.md`](../README.md) for the full bootstrap.

### What lives where

`modules/tmux.nix` owns the package, the plugins, and the settings the Home
Manager module models directly — prefix, mouse, base index, key mode, escape
time, history limit, and terminal type. It also renders the colour theme from
`modules/palette.nix` and builds the `prefix s` session and `prefix f` window
switcher scripts and the lazygit and scratch popups, since those bindings need
Nix store paths. The remaining
bindings, terminal features, and copy-mode setup stay in `settings.conf` in
tmux's own syntax.

`settings.conf` and the theme are placed **before** the plugins in the
generated file. tmux-continuum hooks its autosave into `status-right` when it
loads, so anything that sets `status-right` after the plugins silently disables
autosave. `tests/test_tmux.py` guards that ordering.

Don't set any of the Nix-owned values in `settings.conf`: they would be applied
twice and the two copies would drift.

### Reloading

`prefix + r` re-sources `~/.config/tmux/tmux.conf`. That picks up edits to
`settings.conf` only after a `home-manager switch`, since the installed file is a
copy in the Nix store. Changes to plugins or the Nix-owned settings always need
a switch.

## Session persistence

`tmux-resurrect` snapshots the tmux environment — sessions, windows, panes, their layouts, working directories, and scrollback contents — to `~/.local/share/tmux/resurrect/`. `tmux-continuum` drives it on a timer so you don't have to think about it.

The managed config explicitly selects that XDG location. If only the older
`~/.tmux/resurrect/` directory exists, it keeps using it instead. Existing
snapshots are not moved or deleted; when both directories exist, XDG wins.

- **`prefix Ctrl-s`** — save a snapshot now.
- **`prefix Ctrl-r`** — restore the last snapshot.
- Auto-save runs every 15 minutes (`@continuum-save-interval`).
- Auto-restore (`@continuum-restore on`) fires when the tmux *server* starts, so the first `tmux` after a reboot brings the old sessions back.

Caveats worth knowing:

- Only the shell processes are recreated by default; arbitrary long-running programs inside panes are not resumed unless added to `@resurrect-processes`. Neovim is the exception here — `@resurrect-strategy-nvim session` restores it when a `Session.vim` exists in the pane's working directory.
- Auto-restore needs *something* to start the tmux server. Ghostty does this on launch; on WSL the server dies with the distro, so it restores on your next manual `tmux`, not at boot.
- Shell history, environment variables, and in-flight command state are not part of the snapshot — only the layout and the scrollback text.

## Notes

- `vim-tmux-navigator` takes over `Ctrl-l`, so the shell's clear-screen moves to **`prefix Ctrl-l`**.
- `vim-tmux-navigator` requires the matching side to be set up in Neovim too (a plugin, not just the `<C-h/j/k/l>` mappings already in `nvim/lua/plugins/astrocore.lua`) for the pane-vs-split detection to work perfectly. If `<C-h/j/k/l>` ever stops crossing between tmux and Neovim seamlessly, that's the first thing to check.
