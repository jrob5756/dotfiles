{ lib, pkgs, ... }:
{
  home.packages =
    with pkgs;
    [
      jq
      tree
      wget
      coreutils
      gh
      delta
      kubectl
      (lib.lowPrio minikube)
      uv
    ]
    ++ import ./editor-tools.nix pkgs
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      pkgs.procps
      pkgs.wl-clipboard
      pkgs.xclip
      pkgs.nerd-fonts.jetbrains-mono
      pkgs.nerd-fonts.symbols-only
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.watch ];
  fonts.fontconfig.enable = pkgs.stdenv.hostPlatform.isLinux;
  home.sessionVariables = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
  };
}
