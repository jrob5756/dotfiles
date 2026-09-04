# Single source of truth for colours.
#
# Consumed by the Nix-managed tools (ghostty, tmux, starship). Tools Nix can't
# reach — Neovim's Lua config and Windows Terminal — carry their own copy; see
# windows/README.md for the Windows Terminal scheme derived from this.
{
  # Catppuccin Mocha base.
  mocha = {
    base = "#1e1e2e";
    mantle = "#181825";
    crust = "#11111b";
    surface0 = "#313244";
    surface1 = "#45475a";
    overlay0 = "#6c7086";
    subtext0 = "#a6adc8";
    text = "#cdd6f4";
    blue = "#89b4fa";
    lavender = "#b4befe";
    sapphire = "#74c7ec";
    sky = "#89dceb";
    teal = "#94e2d5";
    green = "#a6e3a1";
    yellow = "#f9e2af";
    peach = "#fab387";
    maroon = "#eba0ac";
    red = "#f38ba8";
    mauve = "#cba6f7";
    pink = "#f5c2e7";
  };

  # Prompt accents, kept at their hand-tuned values rather than snapped to the
  # nearest Mocha shade so the starship prompt looks unchanged after migrating.
  accent = {
    border = "#6C7A96";
    directory = "#A3C4E0";
    gitBranch = "#5EC4FF";
    gitStatus = "#EC6A77";
    success = "#B5D99C";
    error = "#EC6A77";
  };

  font = {
    family = "JetBrainsMono Nerd Font";
    size = 13;
  };
}
