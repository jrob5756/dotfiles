# Starship prompt settings, as a plain attrset.
#
# Kept separate from modules/starship.nix because two consumers need it:
#   * Home Manager, via programs.starship.settings (Linux/macOS/WSL)
#   * flake.nix, which renders it to generated/starship.toml for Windows, where
#     starship runs under PowerShell and Nix cannot reach
#
# Editing this file therefore requires re-rendering; `nix run .#render` does it
# and `nix flake check` fails if generated/starship.toml has drifted.
palette: {
  command_timeout = 1000;
  add_newline = true;

  format = ''
    [┌──](${palette.accent.border}) $directory$git_branch$git_status$python$kubernetes$cmd_duration
    [│](${palette.accent.border})
    [└─](${palette.accent.border}) $character'';

  directory = {
    style = "bold ${palette.accent.directory}";
    format = "[$path ]($style)";
    truncation_length = 3;
    truncation_symbol = "…/";
  };

  git_branch = {
    symbol = "";
    style = "bold ${palette.accent.gitBranch}";
    format = "[$symbol $branch ]($style)";
  };

  git_status = {
    style = "bold ${palette.accent.gitStatus}";
    format = "([$all_status$ahead_behind ]($style))";
  };

  # Shown only in Python projects; includes the active virtualenv.
  python = {
    symbol = " ";
    style = "bold ${palette.accent.python}";
    format = "[$symbol$version( \\($virtualenv\\)) ]($style)";
  };

  # Starship ships this disabled; shown only when a kubeconfig has a current context.
  kubernetes = {
    disabled = false;
    symbol = "☸ ";
    style = "bold ${palette.accent.kubernetes}";
    format = "[$symbol$context( \\($namespace\\)) ]($style)";
  };

  cmd_duration = {
    min_time = 2000;
    style = palette.accent.duration;
    format = "[took $duration ]($style)";
  };

  character = {
    success_symbol = "[❯](bold ${palette.accent.success})";
    error_symbol = "[❯](bold ${palette.accent.error})";
  };
}
