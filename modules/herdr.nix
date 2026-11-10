{ lib, pkgs, ... }:
let
  herdr = lib.getExe pkgs.herdr;

  # Ctrl-h/j/k/l: the herdr side of vim-tmux-navigator. Editors and fzf get the
  # key; anything else moves herdr focus. Neovim hands focus back to herdr at
  # its own edge (nvim/lua/plugins/tmux-navigator.lua).
  navigate = pkgs.writeShellApplication {
    name = "herdr-navigate";
    runtimeInputs = [
      pkgs.herdr
      pkgs.jq
    ];
    text = ''
      direction=$1
      key=$2
      pane=''${HERDR_ACTIVE_PANE_ID:?}
      if herdr pane process-info --pane "$pane" |
        jq -e '[.result.process_info.foreground_processes[].name]
          | any(test("^g?(view|l?n?vim?x?|fzf)(diff)?$"))' >/dev/null; then
        herdr pane send-keys "$pane" "$key"
      else
        herdr pane focus --pane "$pane" --direction "$direction"
      fi
    '';
  };

  # tmux's `split-window -b`: herdr only splits right or down, so split and
  # swap the new pane back over the original.
  splitBefore = pkgs.writeShellApplication {
    name = "herdr-split-before";
    runtimeInputs = [
      pkgs.herdr
      pkgs.jq
    ];
    text = ''
      split=$1
      back=$2
      pane=$(herdr pane split --pane "''${HERDR_ACTIVE_PANE_ID:?}" --direction "$split" --focus |
        jq -r .result.pane.pane_id)
      herdr pane swap --pane "$pane" --direction "$back"
    '';
  };

  # tmux's `new-window -c "#{pane_current_path}"`. herdr's own new_tab action
  # stops at a name prompt first.
  newTab = pkgs.writeShellApplication {
    name = "herdr-new-tab";
    runtimeInputs = [
      pkgs.herdr
      pkgs.jq
    ];
    text = ''
      pane=''${HERDR_ACTIVE_PANE_ID:?}
      read -r workspace cwd < <(herdr pane list |
        jq -r --arg p "$pane" '.result.panes[] | select(.pane_id == $p)
          | [.workspace_id, (.foreground_cwd // .cwd)] | @tsv')
      herdr tab create --workspace "$workspace" --cwd "$cwd" --focus >/dev/null
    '';
  };

  shell = key: command: description: {
    inherit key command description;
    type = "shell";
  };
  popup = key: command: description: {
    inherit key command description;
    type = "popup";
  };
  nav =
    key: direction:
    shell key "${lib.getExe navigate} ${direction} ${key}" "focus ${direction} (vim-aware)";
in
{
  xdg.configFile."herdr/agent-detection/copilot.toml".source = ../herdr/agent-detection/copilot.toml;

  # Herdr follows the tmux keymap in modules/tmux.nix and tmux/settings.conf:
  # workspaces stand in for sessions and tabs for windows.
  xdg.configFile."herdr/config.toml".source = (pkgs.formats.toml { }).generate "herdr-config.toml" {
    onboarding = false;
    theme = {
      name = "terminal";
      auto_switch = false;
    };
    keys = {
      prefix = "ctrl+a";

      # Panes
      split_vertical = [
        "prefix+%"
        "prefix+|"
      ];
      split_horizontal = [
        ''prefix+"''
        "prefix+_"
      ];
      close_pane = [
        "prefix+x"
        "prefix+shift+x"
      ];
      focus_pane_left = [
        "prefix+h"
        "prefix+left"
      ];
      focus_pane_down = [
        "prefix+j"
        "prefix+down"
      ];
      focus_pane_up = [
        "prefix+k"
        "prefix+up"
      ];
      focus_pane_right = [
        "prefix+l"
        "prefix+right"
      ];
      swap_pane_up = [
        "prefix+shift+k"
        "prefix+{"
      ];
      swap_pane_down = [
        "prefix+shift+j"
        "prefix+}"
      ];
      cycle_pane_next = [
        "prefix+o"
        "prefix+tab"
      ];
      last_pane = "prefix+;";
      resize_pane_left = "prefix+ctrl+left";
      resize_pane_down = "prefix+ctrl+down";
      resize_pane_up = "prefix+ctrl+up";
      resize_pane_right = "prefix+ctrl+right";
      resize_mode = "prefix+shift+r";

      # Tabs (tmux windows); n, p, 1..9, z and [ keep herdr's tmux-like defaults.
      new_tab = "prefix+shift+c";
      close_tab = "prefix+&";
      rename_tab = "prefix+,";

      # Workspaces (tmux sessions)
      workspace_picker = "prefix+s";
      goto = [
        "prefix+f"
        "prefix+w"
      ];
      rename_workspace = "prefix+$";
      previous_workspace = "prefix+(";
      next_workspace = "prefix+)";
      detach = "prefix+d";

      reload_config = "prefix+r";
      settings = "prefix+shift+s";
      open_notification_target = "prefix+shift+o";

      command = [
        (nav "ctrl+h" "left")
        (nav "ctrl+j" "down")
        (nav "ctrl+k" "up")
        (nav "ctrl+l" "right")
        # Ctrl-l belongs to navigation; prefix Ctrl-l still clears the screen.
        (shell "prefix+ctrl+l" ''${herdr} pane send-keys "$HERDR_ACTIVE_PANE_ID" ctrl+l'' "clear screen")
        (shell "prefix+c" (lib.getExe newTab) "new tab in the pane's directory")
        (shell "prefix+\\" "${lib.getExe splitBefore} right left" "split left")
        (shell "prefix+-" "${lib.getExe splitBefore} down up" "split above")
        (shell "prefix+!" ''${herdr} pane move "$HERDR_ACTIVE_PANE_ID" --new-tab --focus''
          "break pane into a tab"
        )
        (
          (popup "prefix+g" (lib.getExe pkgs.lazygit) "lazygit")
          // {
            width = "90%";
            height = "90%";
          }
        )
        (
          (popup "prefix+`" ''exec "''${SHELL:-sh}"'' "scratch shell")
          // {
            width = "80%";
            height = "75%";
          }
        )
      ];
    };
  };
}
