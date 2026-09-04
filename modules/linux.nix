{ ... }:
{
  # A Linux machine with a real desktop session, so it gets Ghostty as its
  # terminal. WSL does not — see modules/wsl.nix.
  imports = [ ./ghostty.nix ];

  home.homeDirectory = "/home/jason";
}
