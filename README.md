# Jason's Dotfiles

Personal configuration files, tracked here so I can set up a new machine (macOS,
Linux, WSL, or Windows) quickly and consistently.

macOS, Linux and WSL are managed declaratively with [Nix](https://nixos.org/)
and [Home Manager](https://nix-community.github.io/home-manager/). Windows has
no native Nix, so it keeps the original clone-and-symlink approach.

## Layout

| Path | What |
|---|---|
| [`flake.nix`](./flake.nix) | Inputs, host configurations, the render app, and the drift check |
| [`modules/`](./modules) | Home Manager modules — one per tool, plus per-platform deltas |
| [`hosts/`](./hosts) | One file per machine: `wsl`, `linux`, `mac` |
| [`nvim/`](./nvim) | [Neovim](https://neovim.io/) ([AstroNvim](https://github.com/AstroNvim/AstroNvim) v6+) — plain Lua, shared by every platform |
| [`tmux/`](./tmux) | tmux bindings and hooks in tmux's own syntax; packages and plugins come from `modules/tmux.nix` |
| [`shell/`](./shell) | Shell functions shared by bash and zsh |
| [`starship/`](./starship) | Docs only — the prompt is defined in `modules/starship-settings.nix` |
| [`generated/`](./generated) | Nix-rendered files that are committed because Windows consumes them |
| [`windows/`](./windows) | Windows Terminal, PowerShell profile, and the bootstrap script |

## How platform differences are handled

Everything lives on one branch. Windows-vs-Unix is a *permanent* axis of
variation, and a branch models divergence that is meant to end — you merge it
and delete it. A "Windows branch" would never be merged, so it would just be a
directory with the wrong name, and every shared Neovim change would have to be
cherry-picked across both forever.

Instead, each tool is placed according to what consumes its config:

| Tool | Runs on | Managed as |
|---|---|---|
| tmux, bash, zsh | Unix only | **Full Nix** — no Windows counterpart to keep in sync |
| Ghostty | macOS, Linux | **Full Nix** — no Windows build exists |
| Neovim | everywhere | **Plain Lua** — see below |
| Starship | everywhere | **Nix source, rendered + committed** |
| Windows Terminal, PowerShell | Windows only | **Plain files** — Nix can never reach them |

Two rules fall out of that:

**Neovim stays plain Lua.** Generating it from Nix would mean writing Lua inside
Nix strings — no type checking, no LSP, and no upstream snippet would apply.
More concretely, lazy.nvim writes `lazy-lock.json` back into its config
directory, which a read-only Nix store path makes impossible. Home Manager
therefore points at the live checkout with `mkOutOfStoreSymlink`, so edits take
effect with no rebuild, and Windows symlinks the same folder.

**Starship is generated and committed.** It is the only tool that both runs
natively on Windows and benefits from Nix-managed settings, so Nix is the source
of truth and `generated/starship.toml` is the build output. `nix flake check`
fails if that file goes stale. Any future tool in the same position follows the
same pattern — treat Nix as a build system whose outputs are committed, not just
an installer.

## Setup — macOS / Linux / WSL

### 1. Install Nix

The [Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer)
handles WSL and systemd cleanly and ships a real uninstaller:

```shell
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Open a new shell afterwards so the daemon and profile are picked up.

### 2. Clone this repo

```shell
git clone https://github.com/jrob5756/dotfiles ~/src/dotfiles
cd ~/src/dotfiles
```

The path matters: `dotfiles.path` in `hosts/*.nix` points at the live checkout
for out-of-store symlinks. Override it there if you clone somewhere else.

### 3. Activate

```shell
nix run home-manager/master -- switch --flake .#wsl    # or .#linux / .#mac
```

After the first activation, `home-manager` is on PATH, so later runs are just:

```shell
home-manager switch --flake .#wsl
```

### 4. Verify

- `tmux` starts with the `Ctrl-a` prefix, and `prefix + I` is **not** needed —
  plugins are pinned by the flake
- `nvim` opens with the explorer showing and finishes installing plugins
- The prompt shows the left-bordered starship style
- `Ctrl-h/j/k/l` moves between tmux panes *and* Neovim splits

## Setup — Windows

See [`windows/README.md`](./windows/README.md). In short:

```powershell
git clone https://github.com/jrob5756/dotfiles C:\src\dotfiles
pwsh -File C:\src\dotfiles\windows\bootstrap.ps1
```

That symlinks Neovim, starship, and the PowerShell profile. Windows Terminal's
`settings.json` is copied rather than linked, because it rewrites the file in
place whenever you change something in its UI.

tmux has no native Windows build — it depends on Unix domain sockets and pty
handling. Use it inside WSL, or use Windows Terminal's own panes.

## Day-to-day

| Task | Command |
|---|---|
| Apply config changes | `home-manager switch --flake .#<host>` |
| Update pinned inputs | `nix flake update` then switch |
| Re-render generated files | `nix run .#render` |
| Validate before committing | `nix flake check` |
| Format Nix files | `nix fmt` |
| Roll back | `home-manager generations` then run the listed activation |

Editing `nvim/` needs no rebuild — it is an out-of-store symlink to this
checkout.

## Escape hatches

Home Manager installs `~/.bashrc` and `~/.zshrc` as read-only symlinks into the
Nix store, so anything that rewrites them in place — Agency and claude-cli both
append a `MANAGED BLOCK` — will fail. Both rc files source a writable sibling at
the end:

- `~/.bashrc.local`
- `~/.zshrc.local`

Point those tools there, and put machine-specific `PATH` entries and secrets in
the same place. They are outside the repo and never committed. On Windows the
equivalent is `profile.local.ps1` next to `$PROFILE`.

## Note on this being a public repo

This repository is public. Keep work-specific paths, internal repo and service
names, machine names, and credentials out of it — use the escape-hatch files
above.
