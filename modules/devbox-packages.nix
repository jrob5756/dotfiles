# Dev Box SSH client helpers, shared by modules/devbox.nix and the flake check.
# forwardPath is where launchd agents find devtunnel-forward; it must outlive a generation.
{ pkgs, forwardPath }:
rec {
  devtunnelForward = pkgs.writeShellApplication {
    name = "devtunnel-forward";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.lsof
    ];
    text = builtins.readFile ../devbox/devtunnel-forward.sh;
  };

  devboxAdd = pkgs.writeShellApplication {
    name = "devbox-add";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.lsof
    ];
    text = ''
      DEVBOX_FORWARD="''${DEVBOX_FORWARD:-${forwardPath}}"
    ''
    + builtins.readFile ../devbox/devbox-add.sh;
  };
}
