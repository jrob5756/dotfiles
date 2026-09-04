{ config, pkgs, ... }:
{
  home.packages = [ pkgs.neovim ];

  # Deliberately an out-of-store symlink rather than a managed copy.
  #
  # AstroNvim is a Lua framework whose plugins are managed by lazy.nvim, which
  # writes lazy-lock.json back into the config directory on every :Lazy update.
  # A read-only Nix store path makes that write fail, so the config must stay a
  # live, writable checkout. This also keeps nvim/ usable on Windows, where it is
  # symlinked straight out of a second clone and Nix cannot reach at all.
  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.path}/nvim";
}
