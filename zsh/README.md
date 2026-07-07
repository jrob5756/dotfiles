# zsh config

My interactive shell setup: history, completion, key bindings, aliases, and the
two plugins I rely on. The Starship prompt is initialized from here too (see
[`starship/`](../starship)).

## Highlights

- **`t`** — alias for `tmux`.
- **`dev`** — open (or switch to) the `dev` tmux session, which auto-builds the
  editor + Copilot layout (`nvim` left ~70%, `a` alias right ~30%). It's a
  function, not a bare alias, so it works from *inside* tmux too — a plain
  `tmux new -s dev` refuses to nest. See [`tmux/README.md`](../tmux/README.md#dev-layout).
- **Partial autosuggestion accept** — `Right` accepts the *next word* of a
  zsh-autosuggestion (via a custom `forward-suggestion-word` widget that narrows
  `WORDCHARS` so it stops at each path/URL segment instead of swallowing the
  whole line). `Alt-f` (Ghostty's Cmd+Right) accepts the full suggestion.
- **History search on arrows** — `Up`/`Down` search history from what's already
  typed (`history-beginning-search-*`), not just the previous command.
- **Shared, de-duped history** — 10k entries, `SHARE_HISTORY`, ignore dups and
  leading-space commands.
- **Aliases** — `ls`/`ll`/`la`/`l`, `..`/`...`, git shortcuts (`g`, `gs`, `gd`,
  `gl`, `gp`, `gc`, `ga`), and Copilot (`c`, `p`, `a`).
- **Plugins** — `zsh-autosuggestions` and `zsh-syntax-highlighting`.

## Setup

### 1. Install zsh and its plugins

zsh ships with macOS. Install the two plugins (and Starship for the prompt):

```shell
# macOS (Homebrew)
brew install zsh-autosuggestions zsh-syntax-highlighting starship

# Linux — use your package manager, or clone the plugins to a known path and
# adjust the two `source` lines near the bottom of zshrc accordingly.
```

`direnv` is also used (`eval "$(direnv hook zsh)"`); install it if you want that
line to work (`brew install direnv`).

### 2. Symlink the config

```shell
ln -s ~/dotfiles/zsh/zshrc ~/.zshrc
```

This brings the aliases, key bindings, plugin sourcing, **and** the Starship
init — so once linked, there's no separate "wire up Starship" step for zsh.

Then start a new shell (or `source ~/.zshrc`).

## Notes

- **Not for native Windows.** Like tmux, zsh is a macOS/Linux shell; on Windows
  it only applies inside WSL. Native Windows uses PowerShell, which wires up
  Starship via `$PROFILE` instead (see the root README).
- **Machine-specific bits.** The plugin `source` lines use Homebrew's
  `/opt/homebrew/share/...` paths, and a few `PATH` entries are absolute
  (`/Users/jason/...`). These are macOS-specific; adjust them if you sync this
  file to another machine.
- **Tool-managed blocks.** Some tools (Agency, claude-cli) maintain their own
  `# BEGIN … MANAGED BLOCK … END` sections in this file and will keep editing it
  in place through the symlink. That's expected — the edits just show up as
  normal changes in the repo.
