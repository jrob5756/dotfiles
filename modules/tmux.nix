{
  config,
  lib,
  pkgs,
  ...
}:
let
  sessionSwitcher = pkgs.writeShellApplication {
    name = "tmux-session-switcher";
    runtimeInputs = [
      config.programs.tmux.package
      pkgs.fzf
      pkgs.coreutils
      pkgs.gnused
    ];
    text = ''
      # Most recently used first.
      tab=$'\t'
      sessions=$(tmux list-sessions -F "#{session_activity}''${tab}#{session_name}''${tab}#{session_windows} windows#{?session_attached, (attached),}" |
        sort -rn | cut -f2-)
      status=0
      out=$(printf '%s\n' "$sessions" | fzf --reverse --no-multi --print-query \
        --delimiter="$tab" --prompt='session> ' \
        --header='enter: switch  |  new name + enter: create') || status=$?
      # 130 is Esc/Ctrl-C; 1 means no match, which still prints the query.
      if [ "$status" -ne 0 ] && [ "$status" -ne 1 ]; then exit 0; fi
      query=$(sed -n 1p <<<"$out")
      target=$(sed -n 2p <<<"$out" | cut -f1)
      target=''${target:-$query}
      [ -n "$target" ] || exit 0
      tmux has-session -t "=$target" 2>/dev/null || tmux new-session -d -s "$target" -c "$HOME"
      tmux switch-client -t "=$target"
    '';
  };

  windowSwitcher = pkgs.writeShellApplication {
    name = "tmux-window-switcher";
    runtimeInputs = [
      config.programs.tmux.package
      pkgs.fzf
      pkgs.coreutils
    ];
    text = ''
      # Every window in every session, most recently active first. The hidden
      # first field is the switch target; the preview shows the window's contents.
      tab=$'\t'
      windows=$(tmux list-windows -a -F "#{window_activity}''${tab}#{session_name}:#{window_index}''${tab}#{session_name}''${tab}#{window_index}: #{window_name}''${tab}#{pane_current_path}" |
        sort -rn | cut -f2-)
      pick=$(printf '%s\n' "$windows" | fzf --reverse --no-multi \
        --delimiter="$tab" --with-nth=2.. --prompt='window> ' \
        --preview='tmux capture-pane -ep -t {1}' --preview-window='right,55%') || exit 0
      tmux switch-client -t "=$(cut -f1 <<<"$pick")"
    '';
  };
in
{
  programs.tmux = {
    enable = true;

    prefix = "C-a";
    mouse = true;
    baseIndex = 1;
    keyMode = "vi";
    escapeTime = 10;
    historyLimit = 50000;
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

    extraConfig = builtins.readFile ../tmux/settings.conf + ''

      # prefix s: fuzzy session switcher; typing a new name creates that session.
      bind s display-popup -E -w 60% -h 50% -T ' sessions ' ${lib.getExe sessionSwitcher}
      # prefix f: fuzzy window switcher across all sessions, with a preview.
      bind f display-popup -E -w 85% -h 70% -T ' windows ' ${lib.getExe windowSwitcher}
    '';
  };
}
