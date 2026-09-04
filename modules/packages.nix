{ pkgs, ... }:
{
  # Tools previously installed per-machine via apt, brew, or `uv tool install`.
  # Pinning them here is what makes a new machine reproducible from the flake.
  home.packages = with pkgs; [
    # Core CLI
    ripgrep
    fd
    jq
    tree
    curl
    wget
    unzip

    # Git
    git
    gh
    lazygit
    delta

    # Editor support
    tree-sitter

    # Python toolchain — Mason cannot build these here (no python3-venv), which
    # is why nvim/lua/plugins/mason.lua filters them out and expects them on PATH.
    uv
    basedpyright
    ruff

    # Lua toolchain for the Neovim config itself
    lua-language-server
    stylua
    selene
  ];
}
