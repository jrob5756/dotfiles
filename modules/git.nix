_: {
  # Home Manager writes only ~/.config/git/config. ~/.gitconfig stays private
  # (identity, credentials) and is read afterward, so it must not set core.pager.
  programs.git = {
    enable = true;
    lfs.enable = true;

    settings = {
      init.defaultBranch = "main";
      push = {
        autoSetupRemote = true;
        followTags = true;
      };
      fetch.prune = true;
      # Git refuses to pull diverged branches until a strategy is chosen.
      pull.rebase = true;
      rerere.enabled = true;
      rebase = {
        autoStash = true;
        autoSquash = true;
        # Moves branches stacked on the one being rebased along with it.
        updateRefs = true;
      };
      branch.sort = "-committerdate";
      tag.sort = "version:refname";
      column.ui = "auto";
      # Shows the diff below the message while writing it.
      commit.verbose = true;
      help.autocorrect = "prompt";
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
      "**/.claude/settings.local.json"
      ".envrc"
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
