{
  config,
  lib,
  pkgs,
  palette,
  ...
}:
let
  c = palette.catppuccin;

  # Backs the prefix ` popup. Hidden from both switchers.
  scratchSession = "scratch";

  theme = ''
    # Preserve the outer terminal's background and transparency; dim only inactive panes' default text.
    set -g window-style 'fg=${c.overlay1},bg=terminal'
    set -g window-active-style 'fg=terminal,bg=terminal'

    # Make the active pane obvious.
    set -g pane-border-lines heavy
    set -g pane-border-indicators arrows
    set -g pane-border-style 'fg=${c.surface1}'
    set -g pane-active-border-style 'fg=${c.blue},bold'

    # Status bar on the terminal background. The session badge turns red while
    # the prefix is pending.
    set -g status-style 'bg=default,fg=${c.text}'
    set -g status-left-length 40
    set -g status-left '#[fg=${c.base},bold]#{?client_prefix,#[bg=${c.red}],#[bg=${c.blue}]} #S #[default] '
    set -g status-right-length 60
    set -g status-right '#[fg=${c.yellow}]#{?window_zoomed_flag,ZOOM ,}#[fg=${c.overlay1}]%a %H:%M #[fg=${c.base},bg=${c.lavender},bold] #h '
    setw -g window-status-separator '''
    setw -g window-status-format '#[fg=${c.overlay1}] #I:#W '
    setw -g window-status-current-format '#[fg=${c.base},bg=${c.mauve},bold] #I:#W '
    setw -g window-status-activity-style 'fg=${c.yellow}'
    set -g message-style 'bg=${c.surface0},fg=${c.text}'
    set -g message-command-style 'bg=${c.surface0},fg=${c.text}'
    setw -g mode-style 'bg=${c.surface1},fg=${c.text}'
    set -g popup-border-style 'fg=${c.blue}'
    set -g popup-border-lines rounded
  '';

  sessionSwitcher = pkgs.writeShellApplication {
    name = "tmux-session-switcher";
    runtimeInputs = [
      config.programs.tmux.package
      config.programs.zoxide.package
      pkgs.fzf
      pkgs.coreutils
      pkgs.gnused
    ];
    text = ''
      # Sessions, most recently used first, then zoxide's directories that no
      # session is rooted in. Field 1 is the kind, field 2 the target.
      tab=$'\t'
      declare -A rooted=()
      entries=()
      while IFS=$tab read -r _ name path info; do
        rooted[$path]=1
        entries+=("session''${tab}$name''${tab} $name  $info")
      done < <(tmux list-sessions -f '#{!=:#{session_name},${scratchSession}}' \
        -F "#{session_activity}''${tab}#{session_name}''${tab}#{session_path}''${tab}#{session_windows} windows#{?session_attached, (attached),}" |
        sort -rn)
      while IFS= read -r dir; do
        [ -n "''${rooted[$dir]:-}" ] || entries+=("dir''${tab}$dir''${tab} ''${dir/#"$HOME"/\~}")
      done < <(zoxide query --list 2>/dev/null || true)

      status=0
      # Enter picks the highlighted entry; Ctrl-O creates a session named by the
      # query even when it fuzzy-matches something.
      out=$(printf '%s\n' "''${entries[@]}" | fzf --reverse --no-multi --print-query \
        --expect=ctrl-o --delimiter="$tab" --with-nth=3 --prompt='session> ' \
        --header='enter: switch or open directory  |  ctrl-o: new session named as typed') || status=$?
      # 130 is Esc/Ctrl-C; 1 means no match, which still prints the query.
      if [ "$status" -ne 0 ] && [ "$status" -ne 1 ]; then exit 0; fi
      query=$(sed -n 1p <<<"$out")
      key=$(sed -n 2p <<<"$out")
      pick=$(sed -n 3p <<<"$out")
      kind=$(cut -f1 <<<"$pick")
      target=$(cut -f2 <<<"$pick")
      if [ -z "$pick" ] || [ "$key" = ctrl-o ]; then
        kind=session
        target=$query
      fi
      [ -n "$target" ] || exit 0

      if [ "$kind" = dir ]; then
        dir=$target
        # tmux rewrites . and : in session names; do it up front so lookups match.
        name=$(basename "$dir" | tr '.:' '__')
        # Listed directories have no session rooted in them, so an existing
        # session with this name belongs to another directory.
        if tmux has-session -t "=$name" 2>/dev/null; then
          name="$(basename "$(dirname "$dir")" | tr '.:' '__')-$name"
        fi
      else
        name=$target
        dir=$HOME
      fi
      tmux has-session -t "=$name" 2>/dev/null || tmux new-session -d -s "$name" -c "$dir"
      tmux switch-client -t "=$name"
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
      windows=$(tmux list-windows -a -f '#{!=:#{session_name},${scratchSession}}' -F "#{window_activity}''${tab}#{session_name}:#{window_index}''${tab}#{session_name}''${tab}#{window_index}: #{window_name}''${tab}#{pane_current_path}" |
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
        # prefix F: hint-label SHAs, paths, URLs, IPs and similar on screen;
        # typing a hint copies it. Copying goes through tmux, so set-clipboard
        # forwards it as OSC 52 on every host, including WSL and over SSH.
        plugin = fingers;
        extraConfig = ''
          set -g @fingers-main-action 'tmux load-buffer -w -'
        '';
      }
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

    extraConfig = ''
      # prefix s: fuzzy session switcher; typing a new name creates that session.
      bind s display-popup -E -w 60% -h 50% -T ' sessions ' ${lib.getExe sessionSwitcher}
      # prefix f: fuzzy window switcher across all sessions, with a preview.
      bind f display-popup -E -w 85% -h 70% -T ' windows ' ${lib.getExe windowSwitcher}
      # prefix g: lazygit for the current pane's directory.
      bind g display-popup -E -w 90% -h 90% -d '#{pane_current_path}' -T ' lazygit ' ${lib.getExe pkgs.lazygit}
      # prefix `: toggle a persistent scratch shell. The popup attaches a second
      # client to a hidden session, so its shell survives closing the popup.
      bind '`' if-shell -F '#{==:#{session_name},${scratchSession}}' {
        detach-client
      } {
        display-popup -E -w 80% -h 75% -d '#{pane_current_path}' -T ' scratch ' 'tmux new-session -A -s ${scratchSession}'
      }
    '';
  };

  # Plugins load between Home Manager's base options and extraConfig. The theme
  # must come before them: continuum hooks its autosave into status-right when it
  # loads, so setting status-right afterwards silently disables autosave.
  xdg.configFile."tmux/tmux.conf".text = lib.mkOrder 600 (
    builtins.readFile ../tmux/settings.conf + "\n" + theme
  );
}
