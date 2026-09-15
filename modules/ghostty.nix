{
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

      background-opacity = 1;

      # Ghostty measures scrollback in bytes, not lines.
      scrollback-limit = 10000000;
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      macos-titlebar-style = "transparent";
      macos-option-as-alt = true;
    };
  };
}
