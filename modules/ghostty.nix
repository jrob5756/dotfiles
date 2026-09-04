{
  lib,
  pkgs,
  palette,
  ...
}:
{
  # Ghostty is the terminal on macOS and Linux. Windows has no Ghostty build, so
  # that host uses Windows Terminal instead — see windows/README.md. Nothing here
  # needs a Windows counterpart, which is why this module is fully declarative.
  programs.ghostty = {
    enable = true;

    # On macOS Ghostty ships as a signed .app installed outside Nix; nixpkgs has
    # no working darwin build, so manage the config only and let the app provide
    # the binary.
    package = if pkgs.stdenv.hostPlatform.isDarwin then null else pkgs.ghostty;

    enableBashIntegration = true;
    enableZshIntegration = true;

    settings = {
      theme = "catppuccin-mocha";

      # Repeated font-family keys are Ghostty's fallback chain, in order.
      font-family = [
        palette.font.family
        "Symbols Nerd Font Mono"
      ];
      font-size = palette.font.size;

      cursor-style = "bar";
      cursor-style-blink = true;

      background-opacity = 1;

      # Ghostty counts scrollback in bytes, not lines, unlike tmux's
      # history-limit. ~10 MB is roughly the old WezTerm 10k-line setting.
      scrollback-limit = 10000000;
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      macos-titlebar-style = "transparent";
      macos-option-as-alt = true;
    };
  };
}
