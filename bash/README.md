# bash config

Interactive bash setup (used on WSL) — the Debian/Ubuntu default `~/.bashrc`
plus a personal block (marked `# <jr> ... # </jr>`) with aliases, a Copilot
plugin updater, and the Starship prompt init.

## Highlights

- **Aliases** — `k`/`kgp`/`kga` (kubectl), `mk` (minikube), `wkgp` (watch pods),
  `a` (Copilot).
- **`cup`** — updates all `@jason-tools` Copilot plugins (parallels the
  PowerShell alias of the same name).
- **WSL working-directory sync** — `PROMPT_COMMAND` emits an OSC 9;9 sequence
  so new tabs/panes in Windows Terminal open in the same directory.
- **Starship** — prompt is initialized from here (`eval "$(starship init
  bash)"`), same as the zsh config.

## Setup

### Symlink the config

```shell
ln -s ~/dotfiles/bash/bashrc ~/.bashrc
```

Then start a new shell (or `source ~/.bashrc`).

## Notes

- **WSL-specific bits.** The `PROMPT_COMMAND` directory-sync line calls
  `wslpath`, which only exists inside WSL — remove it on native Linux/macOS.
- **Tool-managed blocks.** Agency maintains its own `# BEGIN … MANAGED BLOCK …
  END` section in this file and will keep editing it in place through the
  symlink, same as noted in `zsh/README.md`.
