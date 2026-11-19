# Copilot CLI helper scripts, shared by modules/copilot.nix and the flake check.
pkgs: {
  # Status line: session name, terminal-tools session tags, session id.
  statusLine = pkgs.writeShellApplication {
    name = "copilot-statusline";
    runtimeInputs = [
      pkgs.jq
      pkgs.sqlite
    ];
    text = builtins.readFile ../copilot/statusline.sh;
  };

  mergeSettings = pkgs.writeShellApplication {
    name = "copilot-merge-settings";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
    ];
    text = builtins.readFile ../copilot/merge-settings.sh;
  };
}
