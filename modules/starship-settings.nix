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
    [┌──](${palette.accent.border}) $directory$git_branch$git_status
    [│](${palette.accent.border})
    [└─](${palette.accent.border}) $character'';

  directory = {
    style = "bold ${palette.accent.directory}";
    format = "[$path ]($style)";
    truncation_length = 3;
    truncation_symbol = "…/";
  };

  git_branch = {
    symbol = "";
    style = "bold ${palette.accent.gitBranch}";
    format = "[$symbol $branch ]($style)";
  };

  git_status = {
    style = "bold ${palette.accent.gitStatus}";
    format = "[$all_status$ahead_behind]($style)";
  };

  character = {
    success_symbol = "[❯](bold ${palette.accent.success})";
    error_symbol = "[❯](bold ${palette.accent.error})";
  };
}
