_: {
  # WSL runs no desktop session, so this host gets no Ghostty: the terminal is
  # Windows Terminal, running on the Windows side where Nix cannot reach. See
  # windows/README.md.

  # Windows Terminal's "duplicate tab/pane" reuses the cwd reported via OSC 9;9,
  # which expects a Windows path — hence wslpath rather than $PWD directly.
  programs.bash.initExtra = ''
    PROMPT_COMMAND=''${PROMPT_COMMAND:+"$PROMPT_COMMAND; "}'printf "\e]9;9;%s\e\\" "$(wslpath -w "$PWD")"'
  '';
  programs.zsh.initContent = ''
    _dotfiles_wsl_cwd() { printf '\e]9;9;%s\e\\' "$(wslpath -w "$PWD")"; }
    precmd_functions+=(_dotfiles_wsl_cwd)
  '';
}
