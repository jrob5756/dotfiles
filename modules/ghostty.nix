{
  config,
  lib,
  pkgs,
  palette,
  ...
}:
{
  programs.ghostty = {
    enable = true;

    # macOS uses the native app installed by Homebrew; Home Manager owns its config.
    package = if pkgs.stdenv.hostPlatform.isDarwin then null else pkgs.ghostty;

    enableBashIntegration = true;
    enableZshIntegration = true;

    settings = {
      theme = "Catppuccin Mocha";

      # Ghostty sets TERM=xterm-ghostty, which most remote hosts lack, so tmux
      # and Neovim abort there with "missing or unsuitable terminal".
      # ssh-terminfo installs the entry on the remote on first connect (cached
      # per host); ssh-env degrades TERM when that is not possible. The other
      # values repeat Ghostty's defaults, which the key replaces wholesale.
      shell-integration-features = "cursor,no-sudo,title,path,ssh-env,ssh-terminfo";

      font-family = [
        palette.font.family
        "Symbols Nerd Font Mono"
      ];
      font-size = palette.font.size;

      cursor-style = "bar";
      cursor-style-blink = true;

      # macOS only applies opacity changes after a full Ghostty restart.
      background-opacity = 0.9;
      background-blur = true;
      # Also apply opacity to explicitly painted backgrounds (Neovim, tmux).
      background-opacity-cells = true;

      # Ghostty always confirms while tmux runs, but tmux keeps the sessions.
      confirm-close-surface = false;

      # Every window attaches to (or creates) the `main` tmux session. The
      # absolute path matters because GUI launches lack the Nix profile on PATH.
      command = "${lib.getExe config.programs.tmux.package} new-session -A -s main";

      mouse-hide-while-typing = true;

      # Ghostty measures scrollback in bytes, not lines.
      scrollback-limit = 10000000;
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      # Native macOS glass replaces the generic blur.
      background-blur = "macos-glass-regular";
      # Fully opaque on demand, e.g. while screen sharing.
      keybind = [ "cmd+shift+o=toggle_background_opacity" ];

      # A transparent titlebar with no buttons or title is invisible but still
      # draggable, unlike the "hidden" style.
      macos-titlebar-style = "transparent";
      macos-window-buttons = "hidden";
      macos-titlebar-proxy-icon = "hidden";
      # Ghostty trims unquoted whitespace, so the quotes must be literal.
      title = ''" "'';
      # Right Option still types characters such as é and —.
      macos-option-as-alt = "left";

      # The Mac's 2x 3840pt-wide main display wants a larger default than the
      # shared palette size.
      font-size = 16;

      window-padding-x = 10;
      # No top padding so text sits directly under the titlebar strip.
      window-padding-y = "0,8";
      window-padding-balance = true;
    };
  };
}
