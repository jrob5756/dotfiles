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
            runtimeInputs = [
              pkgs.git
              pkgs.coreutils
            ];
            text = ''
              root=$(git rev-parse --show-toplevel)
              install -Dm644 ${starshipToml pkgs} "$root/generated/starship.toml"
              install -Dm644 ${starshipToml pkgs} "$root/starship/starship.toml"
              echo "rendered generated/starship.toml and starship/starship.toml"
            '';
          };
          migrate = pkgs.writeShellApplication {
            name = "dotfiles-migrate";
            runtimeInputs = [
              pkgs.python3
              pkgs.git
              pkgs.bash
              pkgs.zsh
            ];
            text = ''
              exec python3 ${./scripts/migrate.py} "$@"
            '';
          };
        in
        {
          render = {
            type = "app";
            program = "${render}/bin/render";
          };
          migrate = {
            type = "app";
            program = "${migrate}/bin/dotfiles-migrate";
          };
        }
      );

      # Keep both new and pre-migration config links on the same generated prompt.
      checks = forAllSystems (
        pkgs:
        {
          editor-tools =
            pkgs.runCommand "editor-tools" { nativeBuildInputs = import ./modules/editor-tools.nix pkgs; }
              ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                export DOTNET_CLI_TELEMETRY_OPTOUT=1
                export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
                for tool in git rg fd lazygit curl tar node python3 debugpy-adapter \
                  basedpyright-langserver ruff lua-language-server stylua selene \
                  tree-sitter cc make dotnet csharp-ls csharpier; do
                  command -v "$tool" >/dev/null
                done
                ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux "command -v netcoredbg >/dev/null"}
                python3 -c 'import debugpy'
                test -n "$(dotnet --list-sdks)"
                touch "$out"
              '';
          windows-syntax =
            pkgs.runCommand "windows-syntax"
              {
                nativeBuildInputs = [
                  pkgs.python3
                  pkgs.powershell
                ];
              }
              ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                export DOTFILES_WINDOWS_ROOT=${./windows}
                export REQUIRE_PWSH=1
                export PYTHONDONTWRITEBYTECODE=1
                python3 -m unittest discover -s ${./tests} -p 'test_windows*.py'
                touch "$out"
              '';
          tmux-config =
            pkgs.runCommand "tmux-config"
              {
                nativeBuildInputs = [
                  pkgs.python3
                  pkgs.tmux
                ];
              }
              ''
                export DOTFILES_TMUX_CONFIG=${
                  pkgs.writeText "tmux-managed.conf"
                    self.homeConfigurations.${
                      if pkgs.stdenv.hostPlatform.isDarwin then "mac" else "wsl"
                    }.config.xdg.configFile."tmux/tmux.conf".text
                }
                export PYTHONDONTWRITEBYTECODE=1
                python3 -m unittest discover -s ${./tests} -p 'test_tmux.py'
                touch "$out"
              '';
          migration =
            pkgs.runCommand "migration"
              {
                nativeBuildInputs = [
                  pkgs.python3
                  pkgs.bash
                  pkgs.zsh
                ];
              }
              ''
                export DOTFILES_MIGRATOR=${./scripts/migrate.py}
                export PYTHONDONTWRITEBYTECODE=1
                python3 -m unittest discover -s ${./tests} -p 'test_migration.py'
                touch "$out"
              '';
          lua-syntax = pkgs.runCommand "lua-syntax" { nativeBuildInputs = [ pkgs.neovim-unwrapped ]; } ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            export NVIM_LOG_FILE=/dev/null
            nvim --headless -u NONE -i NONE -n --noplugin \
              -c 'lua for _, p in ipairs(vim.fn.glob("${./nvim}/**/*.lua", false, true)) do assert(loadfile(p)) end' \
              -c 'qa!'
            touch "$out"
          '';
          nvim-toolchain =
            pkgs.runCommand "nvim-toolchain" { nativeBuildInputs = [ pkgs.neovim-unwrapped ]; }
              ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                export NVIM_LOG_FILE=/dev/null
                cd ${./.}
                nvim --headless -u NONE -i NONE --noplugin -l nvim/tests/toolchain.lua
                touch "$out"
              '';
          shell-helpers =
            pkgs.runCommand "shell-helpers"
              {
                nativeBuildInputs = [
                  pkgs.python3
                  pkgs.bash
                  pkgs.zsh
                  pkgs.git
                ];
              }
              ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                export REQUIRE_ZSH=1
                export DOTFILES_COMMON=${./shell/common.sh}
                export PYTHONDONTWRITEBYTECODE=1
                python3 -m unittest discover -s ${./tests} -p 'test_shell.py'
                touch "$out"
              '';
          nix-lint =
            pkgs.runCommand "nix-lint"
              {
                nativeBuildInputs = [
                  pkgs.statix
                  pkgs.deadnix
                ];
              }
              ''
                cd ${./.}
                statix check --config ${./statix.toml} .
                deadnix --fail .
                touch "$out"
              '';
          starship-drift = pkgs.runCommand "starship-drift" { } ''
            if ! diff -u ${./generated/starship.toml} ${starshipToml pkgs}; then
              echo "generated/starship.toml is stale — run: nix run .#render" >&2
              exit 1
            fi
            if ! diff -u ${./starship/starship.toml} ${starshipToml pkgs}; then
              echo "starship/starship.toml is stale — run: nix run .#render" >&2
              exit 1
            fi
            touch "$out"
          '';
        }
        // lib.mapAttrs' (
          name: _: lib.nameValuePair "home-${name}" self.homeConfigurations.${name}.activationPackage
        ) (lib.filterAttrs (_: host: host.system == pkgs.stdenv.hostPlatform.system) hosts)
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.nixfmt-tree
            pkgs.statix
            pkgs.deadnix
            pkgs.home-manager
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
