# Zsh

New installations use `modules/shell.nix` through the
[migration command](../README.md#wsl--linux--macos-migration).
The tracked `zshrc` is only a pre-migration compatibility file.

The managed setup provides shared history, completion, autosuggestions,
syntax highlighting, common aliases and `cup`. Right accepts one word of an
autosuggestion; Alt-f accepts the full suggestion. Up/Down search history by
the current prefix.

Home Manager supplies the plugins without hardcoded Homebrew source paths.
The root `~/.zshrc` remains writable for installers and sources the managed
payload at `~/.config/dotfiles/zshrc`. Put machine-specific overrides in
`~/.zshrc.local`; it runs after the managed aliases and plugin initialization.

Zsh configuration is generated on all Unix hosts, but the migration does not
change your account's login shell.
