_: {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    # Private and work hosts live outside this public repository.
    includes = [ "config.local" ];
  };
}
