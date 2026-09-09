pkgs:
with pkgs;
[
  git
  ripgrep
  fd
  lazygit
  curl
  gnutar
  unzip
  nodejs
  (python3.withPackages (python: [ python.debugpy ]))
  basedpyright
  ruff
  lua-language-server
  stylua
  selene
  tree-sitter
  gnumake
  stdenv.cc
  dotnet-sdk
  csharp-ls
  csharpier
]
++ lib.optionals stdenv.hostPlatform.isLinux [ netcoredbg ]
