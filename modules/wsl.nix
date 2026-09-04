{ pkgs, ... }:
{
  # WSL runs no desktop session, so this host gets no Ghostty: the terminal is
  # Windows Terminal, running on the Windows side where Nix cannot reach. See
  # windows/README.md.

  home.homeDirectory = "/home/jason";

  # Neovim's clipboard (unnamedplus) has no X/Wayland selection to talk to under
  # plain WSL, so bridge to the Windows clipboard instead.
  home.packages = [ pkgs.wl-clipboard ];

  programs.bash.initExtra = ''
    # Windows Terminal's "duplicate tab/pane" reuses the cwd reported via OSC 9;9,
    # which expects a Windows path — hence wslpath rather than $PWD directly.
    PROMPT_COMMAND=''${PROMPT_COMMAND:+"$PROMPT_COMMAND; "}'printf "\e]9;9;%s\e\\" "$(wslpath -w "$PWD")"'
  '';
}
