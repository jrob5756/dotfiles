{ config, pkgs, ... }:
{
  programs.tmux = {
    enable = true;

    prefix = "C-a";
    mouse = true;
    baseIndex = 1;
    keyMode = "vi";
    escapeTime = 10;
    historyLimit = 10000;
    terminal = "tmux-256color";
    focusEvents = true;

    # tmux-sensible would silently re-set several of the values above.
    sensibleOnTop = false;

    plugins = with pkgs.tmuxPlugins; [
      vim-tmux-navigator
      {
        plugin = resurrect;
        extraConfig = ''
          if-shell 'test -d "${config.home.homeDirectory}/.tmux/resurrect" && ! test -d "${config.xdg.dataHome}/tmux/resurrect"' {
            set -g @resurrect-dir "${config.home.homeDirectory}/.tmux/resurrect"
          } {
            set -g @resurrect-dir "${config.xdg.dataHome}/tmux/resurrect"
          }
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

    extraConfig = builtins.readFile ../tmux/settings.conf;
  };
}
