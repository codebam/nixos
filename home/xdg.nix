_:

{
  xdg = {
    enable = true;
    # gh replaces the symlink with a real file whenever it writes config.yml,
    # which otherwise aborts the next activation. See programs.gh in programs.nix.
    configFile."gh/config.yml".force = true;
    mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = "chromium.desktop";
        "x-scheme-handler/http" = "chromium.desktop";
        "x-scheme-handler/https" = "chromium.desktop";
        "x-scheme-handler/about" = "chromium.desktop";
      };
    };
  };
}
