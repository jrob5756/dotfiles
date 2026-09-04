{ starshipSettings, ... }:
{
  # Settings live in modules/starship-settings.nix because Windows needs the
  # same prompt rendered out to generated/starship.toml — see flake.nix.
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = starshipSettings;
  };
}
