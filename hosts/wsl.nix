{ ... }:
{
  imports = [
    ../modules/base.nix
    ../modules/wsl.nix
  ];

  dotfiles.path = "/home/jason/src/dotfiles";
  home.username = "jason";
  home.homeDirectory = "/home/jason";
}
