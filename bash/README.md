# Bash

New installations use `modules/shell.nix` through the
[migration command](../README.md#wsl--linux--macos-migration).

`inputrc` remains the source for the history-prefix Up/Down bindings and is
installed as `~/.inputrc` by Home Manager. Keep it LF-terminated.

Managed Bash retains completion, the shared aliases and updater, NVM
initialization, user-local tool paths, and WSL directory reporting.
`~/.bash_aliases` is still sourced when present. Machine-specific overrides
belong in `~/.bashrc.local`, loaded after the managed payload.

The root `~/.bashrc` stays writable for installer-managed blocks. Home Manager
owns `~/.config/dotfiles/bashrc`, not that root loader.
