{
  config,
  lib,
  pkgs,
  palette,
  ...
}:
let
  common = builtins.readFile ../shell/common.sh;
  environment = ''
    export NVM_DIR="$HOME/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then . "$NVM_DIR/nvm.sh"; fi
    if [ -d "$HOME/.dotnet" ]; then
      export DOTNET_ROOT="$HOME/.dotnet"
      case ":$PATH:" in *":$HOME/.dotnet:"*) ;; *) export PATH="$HOME/.dotnet:$PATH" ;; esac
    fi
  '';
  # macOS /etc/zprofile runs path_helper after the loaders put Nix on PATH. It
  # rebuilds PATH from /etc/paths.d, hoisting /opt/homebrew/bin ahead of the Nix
  # profile, so Homebrew shadows every Nix-installed tool. nix-daemon.sh cannot
  # repair this: it returns early once __ETC_PROFILE_NIX_SOURCED is exported.
  # Restore precedence from the interactive rc, which runs after path_helper.
  # Dropping an existing copy first keeps this idempotent in nested shells.
  darwinNixPath = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
    _dotfiles_path_prepend() {
      [ -d "$1" ] || return 0
      _dotfiles_rest="$PATH"
      _dotfiles_kept=""
      while [ -n "$_dotfiles_rest" ]; do
        _dotfiles_dir="''${_dotfiles_rest%%:*}"
        case "$_dotfiles_rest" in
          *:*) _dotfiles_rest="''${_dotfiles_rest#*:}" ;;
          *) _dotfiles_rest="" ;;
        esac
        if [ -n "$_dotfiles_dir" ] && [ "$_dotfiles_dir" != "$1" ]; then
          _dotfiles_kept="''${_dotfiles_kept:+$_dotfiles_kept:}$_dotfiles_dir"
        fi
      done
      export PATH="$1''${_dotfiles_kept:+:$_dotfiles_kept}"
      unset _dotfiles_rest _dotfiles_kept _dotfiles_dir
    }
    _dotfiles_path_prepend /nix/var/nix/profiles/default/bin
    _dotfiles_path_prepend "$HOME/.nix-profile/bin"
    unset -f _dotfiles_path_prepend
  '';
  # Bash does not complete aliases. On first Tab, load the target command's
  # completion through bash-completion, copy its spec onto the alias, and
  # return 124 so readline retries with it. Zsh completes aliases natively.
  bashAliasCompletion = ''
    _dotfiles_complete_alias() {
      local target spec
      case $1 in
        g) target=git ;;
        k) target=kubectl ;;
        *) return 1 ;;
      esac
      if declare -F _comp_load >/dev/null; then
        _comp_load "$target"
      elif declare -F __load_completion >/dev/null; then
        __load_completion "$target"
      fi
      spec=$(complete -p "$target" 2>/dev/null) || return 1
      eval "''${spec% *} $1"
      return 124
    }
    complete -F _dotfiles_complete_alias g k
  '';
  bat = lib.getExe config.programs.bat.package;
in
{
  home.shellAliases = {
    # GNU coreutils from Nix precedes the system ls on every host, including macOS.
    ls = "ls --color=auto";
    ll = "ls -lah";
    la = "ls -A";
    l = "ls -CF";
    ".." = "cd ..";
    "..." = "cd ../..";
    g = "git";
    gs = "git status";
    gd = "git diff";
    gl = "git log --oneline --graph --decorate -20";
    gp = "git push";
    gc = "git commit";
    ga = "git add";
    t = "tmux";
    k = "kubectl";
    kgp = "kubectl get pods";
    kga = "kubectl get all";
    mk = "minikube";
    wkgp = "watch kubectl get pods";
    c = "_dotfiles_copilot --yolo";
    p = "_dotfiles_copilot -sp";
    a = "env -u TMUX agency copilot --yolo";
  };

  home.sessionPath = map (path: "${config.home.homeDirectory}/${path}") [
    "bin"
    ".local/bin"
    ".cargo/bin"
    ".dotnet/tools"
    ".config/agency/CurrentVersion"
    ".claude-cli/CurrentVersion"
  ];
  home.sessionVariables = {
    EDITOR = "nvim";
    LANG = "en_US.UTF-8";
    DIRENV_LOG_FORMAT = "";
    DOTFILES_NIX = "1";
    NETRC = "${config.home.homeDirectory}/.netrc";
    MANPAGER = "sh -c 'col -bx | ${bat} --language=man --plain'";
    # Keep groff's formatting escapes out of the text bat highlights.
    MANROFFOPT = "-c";
  };

  programs.bash = {
    enable = true;
    bashrcExtra = ''
      . "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh"
    '';
    historyControl = [
      "ignoredups"
      "ignorespace"
    ];
    historySize = 50000;
    historyFileSize = 100000;
    initExtra = ''
      ${darwinNixPath}
      ${environment}
      HISTTIMEFORMAT='%F %T  '
      # Share history between concurrent shells (tmux panes): save each command
      # as it runs and pick up commands saved by the others.
      PROMPT_COMMAND="''${PROMPT_COMMAND:+$PROMPT_COMMAND; }history -a; history -n"
      if [ -s "$NVM_DIR/bash_completion" ]; then . "$NVM_DIR/bash_completion"; fi
      ${bashAliasCompletion}
      ${common}
      if [ -r "$HOME/.bash_aliases" ]; then . "$HOME/.bash_aliases"; fi
    '';
  };
  programs.zsh = {
    enable = true;
    dotDir = config.home.homeDirectory;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    history = {
      size = 100000;
      save = 100000;
      extended = true;
      share = true;
      ignoreDups = true;
      ignoreSpace = true;
    };
    initContent = lib.mkMerge [
      # Register the partial-accept widget before autosuggestions wraps widgets.
      (lib.mkOrder 550 ''
        forward-suggestion-word() {
          local WORDCHARS='_'
          zle .forward-word
        }
        zle -N forward-suggestion-word
        ZSH_AUTOSUGGEST_ACCEPT_WIDGETS=(end-of-line)
        ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS=(forward-suggestion-word forward-word)
      '')
      (lib.mkOrder 1000 ''
        zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
        zstyle ':completion:*' menu select
        bindkey -e
        bindkey '^[[A' history-beginning-search-backward
        bindkey '^[[B' history-beginning-search-forward
        bindkey '^[[C' forward-suggestion-word
        bindkey '^[OC' forward-suggestion-word
        bindkey '^[f' autosuggest-accept
        ${darwinNixPath}
        ${environment}
        ${common}
      '')
    ];
  };
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.bat = {
    enable = true;
    config.theme = "Catppuccin Mocha";
  };

  # Ctrl-T files and Alt-C directories, with previews; tmux popups when inside
  # tmux.
  programs.fzf =
    let
      fd = lib.getExe pkgs.fd;
    in
    {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      defaultCommand = "${fd} --type f --hidden --follow --exclude .git";
      fileWidget = {
        command = "${fd} --type f --hidden --follow --exclude .git";
        options = [ "--preview '${bat} --color=always --style=numbers --line-range=:300 {}'" ];
      };
      changeDirWidget = {
        command = "${fd} --type d --hidden --follow --exclude .git";
        options = [ "--preview '${lib.getExe pkgs.tree} -C -L 2 {} | head -200'" ];
      };
      # Atuin owns Ctrl-R.
      historyWidget.command = "";
      defaultOptions = [
        "--height=40%"
        "--layout=reverse"
        "--border"
      ];
      # Leave the background to the terminal.
      colors = with palette.catppuccin; {
        "bg+" = surface0;
        spinner = rosewater;
        hl = red;
        fg = text;
        header = red;
        info = mauve;
        pointer = rosewater;
        marker = lavender;
        "fg+" = text;
        prompt = mauve;
        "hl+" = red;
        selected-bg = surface1;
        border = surface1;
      };
      tmux = {
        enableShellIntegration = true;
        shellIntegrationOptions = [ "-p 80%,60%" ];
      };
    };

  # Ctrl-R searches a SQLite history that records cwd, exit status and duration.
  # Up keeps the shells' prefix search. Sync stays off until `atuin login`.
  programs.atuin = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    # `?` on an empty line would otherwise open Atuin's hosted AI assistant.
    flags = [
      "--disable-up-arrow"
      "--disable-ai"
    ];
    settings = {
      style = "compact";
      inline_height = 20;
      # Enter puts the command on the prompt for editing, as fzf's Ctrl-R did.
      enter_accept = false;
      update_check = false;
    };
  };

  # `, <cmd>` runs any nixpkgs program without installing it, and unknown
  # commands suggest the package that provides them.
  programs.nix-index = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };
  programs.nix-index-database.comma.enable = true;

  # `z <part-of-path>` jumps to a frequently used directory; `zi` picks one with fzf.
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  # Installers may edit the writable loaders; Nix owns only their sourced payloads.
  home.file.".bashrc".target = ".config/dotfiles/bashrc";
  home.file.".bash_profile".target = ".config/dotfiles/bash_profile";
  home.file.".profile".target = ".config/dotfiles/profile";
  home.file."./.zshrc".target = ".config/dotfiles/zshrc";
  home.file."./.zshenv".target = ".config/dotfiles/zshenv";
  home.file."./.zprofile".target = ".config/dotfiles/zprofile";
  home.file.".inputrc".source = ../bash/inputrc;

  home.activation.checkShellLoaders = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    ${pkgs.python3}/bin/python3 ${../scripts/migrate.py} --loaders check
  '';
  home.activation.ensureShellLoaders = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.python3}/bin/python3 ${../scripts/migrate.py} --loaders ensure
  '';
}
