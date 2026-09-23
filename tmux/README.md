# tmux config

Prefix key is remapped to **`Ctrl-a`** (from the default `Ctrl-b`).

## Highlights

- **`Ctrl-h/j/k/l`** — move between tmux panes *and* Neovim splits with the same keys (seamless, no prefix needed), via `vim-tmux-navigator`. Mirrors the window navigation already set up in the `nvim/` config.
- **Mouse support on** — click to select a pane, drag borders to resize, scroll to scroll a pane's history.
- **`prefix |`** / **`prefix \`** / **`prefix _`** / **`prefix -`** — split the current pane right / left / down / up, opening in the current pane's directory (the `|` vsplit matches the mapping in the nvim config). Unshifted keys put the new pane above or to the left; shifted keys put it below or to the right.
- **`prefix c`** — new windows also open in the current pane's directory.
- **`prefix s`** — fuzzy session switcher in a popup (most recently used first). Type the name of a session that doesn't exist and press Enter to create it. The built-in tree view is still on `prefix w`.
- **`prefix f`** — fuzzy window switcher across all sessions (most recently active first), with a live preview of the highlighted window. Replaces tmux's built-in find-window.
- **Closing a session doesn't exit tmux**: `detach-on-destroy off` moves you to another session when the last window of the current one closes.
- **Catppuccin status bar** on the terminal background: session badge on the left (turns red while the prefix is pending), windows in the middle, `ZOOM` when a pane is zoomed, then time and host.
- **50,000 lines of scrollback** per pane.
- **Obvious active pane**: the active pane gets a heavy, bold blue border with arrow indicators. Inactive borders are muted, and default text in inactive panes is dimmed. Backgrounds stay `terminal`, so transparency is preserved.
- **`prefix r`** — reload config without restarting tmux.
- **Sessions survive reboots** — `tmux-resurrect` + `tmux-continuum` auto-save every 15 minutes and auto-restore when the tmux server next starts. See [Session persistence](#session-persistence) below.
- Copy mode uses vi-style keys (`v` to start selection, `y` to yank) since that matches Neovim muscle memory better than tmux's Emacs-style defaults.

## Setup

Home Manager handles all of this — `home-manager switch --flake .#<host>`
installs tmux, pins the plugins, and writes `~/.config/tmux/tmux.conf`. There is
no TPM install and no `prefix + I` step; plugins are present on first launch.

See the root [`README.md`](../README.md) for the full bootstrap.

### What lives where

`modules/tmux.nix` owns the package, the plugins, and the settings the Home
Manager module models directly — prefix, mouse, base index, key mode, escape
time, history limit, and terminal type. It also builds the `prefix s` session
and `prefix f` window switcher scripts, since those bindings need Nix store
paths. Everything else —
the bindings, status bar, pane navigation, and copy-mode setup — stays in
`settings.conf` in tmux's own syntax and is read in as `extraConfig`.

Don't set any of the Nix-owned values in `settings.conf`: they would be applied
twice and the two copies would drift.

### Reloading

`prefix + r` re-sources `~/.config/tmux/tmux.conf`. That picks up edits to
`settings.conf` only after a `home-manager switch`, since the installed file is a
copy in the Nix store. Changes to plugins or the Nix-owned settings always need
a switch.

### Existing manual installations

`tmux/tmux.conf` is a complete compatibility snapshot, including TPM, for old
`~/.tmux.conf` symlinks. It is not consumed by Home Manager. It mirrors
`settings.conf` except for the `prefix s` and `prefix f` switchers, which are
managed only. The migration backs up that old entry point so the XDG configuration can
take over. Do not delete TPM or restart a working server just to prepare the
migration.

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
- Auto-restore needs *something* to start the tmux server. On WSL the server dies with the distro, so it restores on your next manual `tmux`, not at boot.
- Shell history, environment variables, and in-flight command state are not part of the snapshot — only the layout and the scrollback text.

## Notes

- `vim-tmux-navigator` requires the matching side to be set up in Neovim too (a plugin, not just the `<C-h/j/k/l>` mappings already in `nvim/lua/plugins/astrocore.lua`) for the pane-vs-split detection to work perfectly. If `<C-h/j/k/l>` ever stops crossing between tmux and Neovim seamlessly, that's the first thing to check.
