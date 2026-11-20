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

  # `session-browser` (fzf browser of Copilot CLI sessions) and `session-tags`.
  # They call each other, so one package puts both on each other's PATH. The
  # scripts stay in libexec so $0 is the script itself: the browser re-runs $0
  # from fzf bindings and `session-tags --help` prints its own header.
  sessionTools = pkgs.stdenvNoCC.mkDerivation {
    name = "copilot-session-tools";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    # patchShebangs points the scripts at this bash, not macOS's bash 3.2.
    buildInputs = [ pkgs.bash ];
    installPhase = ''
      runHook preInstall
      for name in session-browser session-tags; do
        install -Dm755 ${../copilot}/$name.sh $out/libexec/$name
        makeWrapper $out/libexec/$name $out/bin/$name --prefix PATH : ${
          pkgs.lib.makeBinPath [
            (placeholder "out")
            pkgs.fzf
            pkgs.jq
            pkgs.sqlite
            pkgs.tmux
          ]
        }
      done
      runHook postInstall
    '';
    meta.mainProgram = "session-browser";
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
