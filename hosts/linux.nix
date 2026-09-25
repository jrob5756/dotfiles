_: {
  imports = [
    ../modules/base.nix
    ../modules/linux.nix
  ];

  dotfiles.path = "/home/jason/src/dotfiles";
  home.username = "jason";
  home.homeDirectory = "/home/jason";
}
