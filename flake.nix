{
  description = "jrob5756's dotfiles — Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      palette = import ./modules/palette.nix;
      starshipSettings = import ./modules/starship-settings.nix palette;

      # Every machine this repo knows how to build, and the platform it runs on.
      # `wsl` and `linux` share a system but differ in modules (clipboard, interop).
      hosts = {
        wsl = {
          system = "x86_64-linux";
        };
        linux = {
          system = "x86_64-linux";
        };
        mac = {
          system = "aarch64-darwin";
        };
      };

      systems = lib.unique (lib.mapAttrsToList (_: h: h.system) hosts);
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      starshipTomlRaw = pkgs: (pkgs.formats.toml { }).generate "starship-raw.toml" starshipSettings;

      # The header is part of the generated artifact rather than something added
      # by hand, so re-rendering can't silently drop the do-not-edit warning.
      starshipHeader =
        pkgs:
        pkgs.writeText "starship-header.toml" ''
          # GENERATED FILE — DO NOT EDIT.
          #
          # Rendered from modules/starship-settings.nix by `nix run .#render`.
          # Committed because Windows consumes it directly: starship runs under
          # PowerShell there and Nix has no native Windows support, so the Windows
          # clone symlinks this file to ~/.config/starship.toml.
          #
          # `nix flake check` fails if this has drifted from the Nix source.
        '';

      starshipToml =
        pkgs:
        pkgs.runCommand "starship.toml" { } ''
          cat ${starshipHeader pkgs} ${starshipTomlRaw pkgs} > "$out"
        '';
    in
    {
      homeConfigurations = lib.mapAttrs (
        name:
        { system }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = {
            inherit palette starshipSettings;
            hostName = name;
          };
          modules = [ (./hosts + "/${name}.nix") ];
        }
      ) hosts;

      packages = forAllSystems (pkgs: {
        starship-toml = starshipToml pkgs;
        default = starshipToml pkgs;
      });

      # `nix run .#render` refreshes every Nix-generated artifact that has to be
      # committed because a non-Nix platform consumes it. Windows symlinks
      # generated/starship.toml out of its own clone of this repo.
      apps = forAllSystems (
        pkgs:
        let
          render = pkgs.writeShellApplication {
            name = "render";
            runtimeInputs = [ pkgs.git ];
            text = ''
              root=$(git rev-parse --show-toplevel)
              install -Dm644 ${starshipToml pkgs} "$root/generated/starship.toml"
              echo "rendered generated/starship.toml"
            '';
          };
        in
        {
          render = {
            type = "app";
            program = "${render}/bin/render";
          };
        }
      );

      # Guards the one hand-committed artifact against silently going stale.
      checks = forAllSystems (pkgs: {
        starship-drift = pkgs.runCommand "starship-drift" { } ''
          if ! diff -u ${./generated/starship.toml} ${starshipToml pkgs}; then
            echo "generated/starship.toml is stale — run: nix run .#render" >&2
            exit 1
          fi
          touch "$out"
        '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.nixfmt
            pkgs.statix
            pkgs.home-manager
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
