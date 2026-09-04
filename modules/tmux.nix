{ pkgs, ... }:
{
  # tmux has no Windows build at all, so this module can be fully declarative
  # with no portable-file counterpart to keep in sync.
  #
  # The bespoke bindings, hooks and copy-mode setup stay in tmux/tmux.conf and
  # are read in as extraConfig: they are pure tmux syntax with no Nix values to
  # interpolate, so embedding them in a Nix string would cost syntax
  # highlighting and standalone `tmux source-file` testing to gain nothing.
  # Everything Nix genuinely improves on — package pinning and plugins — is
  # expressed as options here and removed from that file.
  programs.tmux = {
    enable = true;

    prefix = "C-a";
    mouse = true;
    baseIndex = 1;
    keyMode = "vi";
    escapeTime = 10;
    historyLimit = 10000;
    terminal = "tmux-256color";

    # tmux-sensible would silently re-set several of the values above.
    sensibleOnTop = false;

    # Replaces TPM: plugins are pinned by the flake lock and present on first
    # launch, so there is no `prefix + I` install step on a new machine.
    plugins = with pkgs.tmuxPlugins; [
      vim-tmux-navigator
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-strategy-nvim 'session'
        '';
      }
      {
        # Must load after resurrect — continuum drives it.
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-save-interval '15'
          set -g @continuum-restore 'on'
        '';
      }
    ];

    extraConfig = builtins.readFile ../tmux/tmux.conf;
  };
}
