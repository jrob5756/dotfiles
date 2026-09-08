{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = [
    (pkgs.symlinkJoin {
      name = "dotfiles-neovim";
      paths = [ pkgs.neovim ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram "$out/bin/nvim" \
          --set DOTFILES_NIX 1 \
          --prefix PATH : ${lib.makeBinPath (import ./editor-tools.nix pkgs)}
      '';
    })
  ];

  # Live Lua edits and lazy.nvim's lockfile stay writable outside the Nix store.
  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.path}/nvim";
}
