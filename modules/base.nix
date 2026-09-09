{ lib, ... }:
{
  # Everything every host gets, regardless of platform.
  imports = [
    ./options.nix
    ./packages.nix
    ./shell.nix
    ./starship.nix
    ./tmux.nix
    ./nvim.nix
  ];

  programs.home-manager.enable = true;

  # Pinned deliberately: this tracks the release whose state-affecting defaults
  # this configuration was written against, and is not a "current version" field.
  home.stateVersion = lib.mkDefault "24.11";
}
