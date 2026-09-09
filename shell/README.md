# Shared shell helpers

`common.sh` is sourced by both manual shell configs and embedded by Home Manager.
It contains custom dotfiles helpers, not installer-managed configuration.

`c` and `p` use the same Copilot binary discovery as `cup`, including versioned
installations without a PATH shim. `a` invokes the separately installed Agency
CLI. On native Windows, `c` remains the user's Claude shortcut.

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
