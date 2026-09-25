_: {
  imports = [
    ../modules/base.nix
    ../modules/darwin.nix
  ];

  dotfiles.path = "/Users/jason/src/oss/dotfiles";
  home.username = "jason";
  home.homeDirectory = "/Users/jason";
}
