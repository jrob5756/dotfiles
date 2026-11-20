{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./copilot-packages.nix pkgs) statusLine mergeSettings sessionTools;

  # The only settings.json keys Nix owns; Copilot keeps writing the rest.
  settings = {
    statusLine = {
      command = "${config.home.homeDirectory}/.copilot/statusline.sh";
      # Re-run every 5s so tags added outside the session show up.
      refreshInterval = 5;
    };
  };
in
{
  home.packages = [ sessionTools ];

  home.file.".copilot/statusline.sh" = {
    source = lib.getExe statusLine;
    # Replaces the hand-written script from before this module.
    force = true;
  };

  home.activation.copilotSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe mergeSettings} ${lib.escapeShellArg (builtins.toJSON settings)}
  '';
}
