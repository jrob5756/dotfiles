_: {
  # Home Manager writes only ~/.config/git/config. ~/.gitconfig stays private
  # (identity, credentials) and is read afterward, so it must not set core.pager.
  programs.git = {
    enable = true;
    lfs.enable = true;

    settings = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      fetch.prune = true;
      rerere.enabled = true;
      rebase.autoStash = true;
      branch.sort = "-committerdate";
      diff = {
        algorithm = "histogram";
        colorMoved = "default";
      };
      # Shows the common ancestor in conflicts; delta recommends it.
      merge.conflictStyle = "zdiff3";
    };

    ignores = [
      ".DS_Store"
      ".direnv/"
      "*.swp"
    ];
  };

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
