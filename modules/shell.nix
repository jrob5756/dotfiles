{
  config,
  lib,
  pkgs,
  ...
}:
let
  # `-u TMUX` strips the TMUX env var only for this process (a no-op outside
  # tmux). Copilot CLI checks $TMUX directly and disables its accent theme /
  # highlight as a tmux-compatibility fallback regardless of actual terminal
  # capabilities (TERM/TERM_PROGRAM/COLORTERM don't matter) — this restores it.
  copilotAliases = {
    c = "env -u TMUX copilot --yolo";
    p = "env -u TMUX copilot -sp";
    a = "env -u TMUX agency copilot --yolo";
  };

  # Defined once and applied to both shells. Previously duplicated in bash/bashrc
  # and zsh/zshrc, where `ll` and `l` had already drifted to different flags.
  sharedAliases = {
    ll = "ls -lah";
    la = "ls -A";
    l = "ls -lah";
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
  }
  // copilotAliases;

  common = builtins.readFile ../shell/common.sh;

  # Home Manager installs the rc files as read-only symlinks into the Nix store,
  # so anything that rewrites them in place — Agency and claude-cli both append
  # a "MANAGED BLOCK" — fails. Sourcing a writable sibling gives those tools a
  # target that survives a rebuild. Untracked; see .gitignore.
  localHatch = shell: ''
    # Writable escape hatch for tools that edit rc files in place.
    [ -f "$HOME/.${shell}rc.local" ] && . "$HOME/.${shell}rc.local"
  '';
in
{
  home.shellAliases = sharedAliases;

  programs.bash = {
    enable = true;
    historyControl = [
      "ignoredups"
      "ignorespace"
    ];
    historySize = 10000;
    historyFileSize = 20000;

    initExtra = ''
      ${common}

      ${localHatch "bash"}
    '';
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;

    history = {
      size = 10000;
      save = 10000;
      share = true;
      ignoreDups = true;
      ignoreSpace = true;
    };

    initContent = lib.mkMerge [
      # Must run before the autosuggestions plugin wraps its widgets, otherwise
      # the partial-accept list below is read too late to take effect.
      (lib.mkOrder 550 ''
        # Accept only the NEXT WORD of the autosuggestion. Default WORDCHARS treats
        # /, ., -, = as part of a word, so stock forward-word swallows an entire
        # path/URL in one press. Narrowing WORDCHARS locally makes it stop at each
        # segment. NOTE: the widget name must NOT start with "_" — zsh-autosuggestions
        # ignores all widgets matching "_*" when wrapping partial-accept widgets.
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
        bindkey '^[[A' history-beginning-search-backward   # Up → search history from cursor
        bindkey '^[[B' history-beginning-search-forward    # Down → reverse history search
        bindkey '^[[C' forward-suggestion-word             # Right → accept next word of suggestion
        bindkey '^[OC' forward-suggestion-word             # Right (application-cursor mode)
        bindkey '^[f'  autosuggest-accept                  # Alt-f → accept FULL suggestion

        ${common}

        ${localHatch "zsh"}
      '')
    ];
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    LANG = "en_US.UTF-8";
    # direnv's per-directory load/unload chatter, silenced.
    DIRENV_LOG_FORMAT = "";
  };
}
