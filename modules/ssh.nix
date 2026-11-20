_: {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    # Private and work hosts live outside this public repository; devbox-add
    # writes one file per Dev Box under devboxes/.
    includes = [
      "config.local"
      "devboxes/*.conf"
    ];
  };
}
