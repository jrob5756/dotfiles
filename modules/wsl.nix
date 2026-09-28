{ pkgs, ... }:
let
  # Hands URLs and files to the Windows default handler. rundll32 is invoked
  # directly rather than through cmd.exe, so `&` in URLs needs no quoting.
  wslOpen = pkgs.writeShellApplication {
    name = "wsl-open";
    text = ''
      if [ "$#" -ne 1 ]; then
        echo "usage: wsl-open <url-or-path>" >&2
        exit 2
      fi
      target=$1
      case $target in
        file://*)
          path=''${target#file://}
          path=''${path#localhost}
          # Decode %XX escapes before handing the path to wslpath.
          target=$(wslpath -w "$(printf '%b' "''${path//%/\\x}")")
          ;;
        *://* | mailto:*) ;;
        *) target=$(wslpath -w "$target") ;;
      esac
      exec "$(wslpath 'C:\Windows\System32\rundll32.exe')" url.dll,FileProtocolHandler "$target"
    '';
  };
in
{
  # WSL runs no desktop session, so this host gets no Ghostty: the terminal is
  # Windows Terminal, running on the Windows side where Nix cannot reach. See
  # windows/README.md.

  # `gh ... --web`, `gh auth login`, Python's webbrowser and xdg-open callers
  # open in the Windows browser.
  home.packages = [
    wslOpen
    (pkgs.writeShellScriptBin "xdg-open" ''exec ${wslOpen}/bin/wsl-open "$@"'')
  ];
  home.sessionVariables.BROWSER = "${wslOpen}/bin/wsl-open";

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
