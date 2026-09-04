{ lib, config, ... }:
{
  options.dotfiles.path = lib.mkOption {
    type = lib.types.str;
    default = "${config.home.homeDirectory}/src/dotfiles";
    description = ''
      Absolute path to the working clone of this repository.

      Used for out-of-store symlinks, which point at the live checkout rather
      than the Nix store so edits take effect without a rebuild. Override this
      per host when the clone does not live at ~/src/dotfiles.
    '';
  };
}
