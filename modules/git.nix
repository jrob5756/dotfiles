{ ... }:
{
  # Home Manager writes only ~/.config/git/config. ~/.gitconfig stays private
  # (identity, credentials) and is read afterward, so it must not set core.pager.
  programs.git.enable = true;

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
      dark = true;
      syntax-theme = "Catppuccin Mocha";
    };
  };
}
