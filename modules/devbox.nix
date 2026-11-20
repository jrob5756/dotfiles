# SSH into Dev Boxes over dev tunnels: `devbox-add <name>` (see the README).
{ config, pkgs, ... }:
let
  devbox = import ./devbox-packages.nix {
    inherit pkgs;
    forwardPath = "${config.home.profileDirectory}/bin/devtunnel-forward";
  };
in
{
  home.packages = [
    devbox.devboxAdd
    devbox.devtunnelForward
  ];
}
