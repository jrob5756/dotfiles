# tmux config

Prefix key is remapped to **`Ctrl-a`** (from the default `Ctrl-b`).

## Highlights

- **`Ctrl-h/j/k/l`** — move between tmux panes *and* Neovim splits with the same keys (seamless, no prefix needed), via `vim-tmux-navigator`. Mirrors the window navigation already set up in the `nvim/` config.
- **Mouse support on** — click to select a pane, drag borders to resize, scroll to scroll a pane's history.
- **`prefix |`** / **`prefix \`** / **`prefix _`** / **`prefix -`** — split the current pane right / left / down / up, opening in the current pane's directory (the `|` vsplit matches the mapping in the nvim config). Unshifted keys put the new pane above or to the left; shifted keys put it below or to the right.
- **`tmux new -s dev`** — opens a ready-made dev layout: `nvim` (left ~70%) + Copilot (right ~30%). See [Dev layout](#dev-layout) below.
- **`prefix r`** — reload config without restarting tmux.
- **Sessions survive reboots** — `tmux-resurrect` + `tmux-continuum` auto-save every 15 minutes and auto-restore when the tmux server next starts. See [Session persistence](#session-persistence) below.
- Copy mode uses vi-style keys (`v` to start selection, `y` to yank) since that matches Neovim muscle memory better than tmux's Emacs-style defaults.

## Dev layout

Start a session named `dev` to get an editor + assistant layout automatically:

```shell
tmux new -s dev
```

This opens two panes in the directory you launched from:

- **left, ~70%** — `nvim`
- **right, ~30%** — the `a` alias (GitHub Copilot CLI)

with focus on the nvim pane. It's driven by a `session-created` hook that's
**guarded by the session name**, so *only* the `dev` session triggers it — a
plain `tmux`, `tmux new`, or any other `-s NAME` stays a normal single pane.

- **`prefix D`** builds the same layout on demand in whatever window you're in
  (handy if you're already in another session).
- If a `dev` session already exists, `tmux new -s dev` errors; use
  `tmux new-session -A -s dev` to connect to it or create it.

**Requirements:** this relies on two things from your environment (not from this
repo):

- `nvim` on your `PATH`.
- an **`a` shell alias** for Copilot, defined for interactive shells (e.g. in
  `~/.zshrc`). The panes launch their commands via `send-keys` into an
  interactive shell precisely so this alias resolves — a `split-window "a"`
  would run under `sh -c` and never source your rc.

To tweak: change `dev` in the `#{==:#{session_name},dev}` check to rename the
trigger, swap `-h` for `-v` to stack the panes, or adjust `-l 30%` for a
different split ratio (all in `tmux.conf`).

## Setup

Home Manager handles all of this — `home-manager switch --flake .#<host>`
installs tmux, pins the plugins, and writes `~/.config/tmux/tmux.conf`. There is
no TPM install and no `prefix + I` step; plugins are present on first launch.

See the root [`README.md`](../README.md) for the full bootstrap.

### What lives where

`modules/tmux.nix` owns the package, the plugins, and the settings the Home
Manager module models directly — prefix, mouse, base index, key mode, escape
time, history limit, and terminal type. Everything else — the bindings, the
`dev` layout hook, pane navigation, and copy-mode setup — stays in `tmux.conf`
in tmux's own syntax and is read in as `extraConfig`.

Don't set any of the Nix-owned values in `tmux.conf`: they would be applied
twice and the two copies would drift.

### Reloading

`prefix + r` re-sources `~/.config/tmux/tmux.conf`. That picks up edits to
`tmux.conf` only after a `home-manager switch`, since the installed file is a
copy in the Nix store. Changes to plugins or the Nix-owned settings always need
a switch.

## Session persistence

`tmux-resurrect` snapshots the tmux environment — sessions, windows, panes, their layouts, working directories, and scrollback contents — to `~/.local/share/tmux/resurrect/`. `tmux-continuum` drives it on a timer so you don't have to think about it.

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
