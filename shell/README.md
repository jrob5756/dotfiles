# Shared shell helpers

`common.sh` is embedded into the Bash and Zsh payloads by Home Manager.
It contains custom dotfiles helpers, not installer-managed configuration.

## Interactive features (Home Manager)

`modules/shell.nix` and `modules/git.nix` add these to Bash and Zsh:

| Feature | Use |
|---|---|
| atuin | `Ctrl-R` searches a SQLite history that records each command's directory, exit status and duration. Enter puts the pick on the prompt for editing rather than running it. Up/Down keep the shell's own prefix search. Nothing syncs unless you run `atuin login`. Import older history with `atuin import auto`. |
| fzf | `Ctrl-T` inserts a file path with a `bat` preview; `Alt-C` cds into a subdirectory with a tree preview. Opens as a tmux popup inside tmux. Uses `fd`, so hidden files are included and `.git` is skipped. |
| zoxide | `z <part of path>` jumps to a directory you've visited; `zi` picks one with fzf. Its directories also appear in tmux's `prefix s` switcher. |
| nix-index + comma | `, <command>` runs any nixpkgs program once without installing it. Typing a command that isn't installed suggests the package that provides it. The database is prebuilt and pinned in `flake.lock`. |
| bat | Syntax-highlighted `cat` (Catppuccin Mocha); also the `man` pager. |
| Alias completion | Tab completes `g` like `git` and `k` like `kubectl` in Bash too (Zsh does this natively). |
| Browser (WSL) | `BROWSER` and an `xdg-open` shim point at `wsl-open`, which hands URLs and files to the Windows default app, so `gh ... --web` and `gh auth login` work. |
| Bash history | 50,000 entries in memory and 100,000 on disk, with timestamps (`history` shows them). Every command is saved as it runs and read by other open shells at their next prompt, so tmux panes share history. |
| Zsh history | 100,000 entries with timestamps, shared live between open shells. |
| delta | Git's pager: syntax-highlighted diffs with line numbers for `git diff`, `git show`, `git log -p`, and `git add -p`. Output shorter than a screen prints directly; longer output opens in `less`. Use `n`/`N` to jump between files. |

Git also enables `rebase.updateRefs` (rebasing a branch moves branches stacked
on it), `rebase.autoSquash`, `commit.verbose`, `push.followTags`,
`help.autocorrect=prompt`, version-sorted tags and columnar branch lists.

Home Manager writes delta's settings to `~/.config/git/config`. Your private
`~/.gitconfig` is read after it and wins, so it must not set `core.pager`.

`c` and `p` use the same Copilot binary discovery as `cup`, including versioned
installations without a PATH shim. `a` invokes the separately installed Agency
CLI. On native Windows, `c` remains the user's Claude shortcut.

## Zsh

Zsh configuration is generated on all Unix hosts, but the migration does not
change your account's login shell. It provides shared history, completion,
autosuggestions, syntax highlighting, the common aliases and `cup`. Right
accepts one word of an autosuggestion; Alt-f accepts the full suggestion.
Up/Down search history by the current prefix. Home Manager supplies the plugins
without hardcoded Homebrew paths. The root `~/.zshrc` stays writable for
installers; put machine-specific overrides in `~/.zshrc.local`.

## `cup`

Requires Git and Python 3. Home Manager installs both; manual installations must
provide them on `PATH`.

`cup` finds Copilot on `PATH`, or selects the naturally highest executable version
under `~/.copilot-cli/`. It reads directory marketplaces from
`${COPILOT_CONFIG_DIR:-$HOME/.copilot}/settings.json`, pulls their backing Git
worktrees with `--ff-only`, refreshes marketplace catalogs, and updates installed
plugins. Marketplace directories may be repository roots, linked worktrees, or
subdirectories inside worktrees.

A missing settings file or no directory marketplaces is valid: catalog and
installed-plugin updates still run. Malformed or unreadable settings abort
before any updates. Missing directories, non-Git directories, dirty worktrees,
Git errors, and CLI errors produce diagnostics and a nonzero final status.
Independent updates continue after a per-marketplace failure. Nothing is
stashed, reset, committed, or force-pulled.

## Regression coverage

Run `python3 -m unittest discover -s tests -p 'test_shell.py'`.
The cases run in Bash and, when available, Zsh, using temporary homes, local Git
remotes, and a fake Copilot executable. No real plugins or repositories are
updated. `nix flake check` runs both shells.
