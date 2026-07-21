_:

{
  xdg = {
    enable = true;
    mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = "firedragon.desktop";
        "x-scheme-handler/http" = "firedragon.desktop";
        "x-scheme-handler/https" = "firedragon.desktop";
        "x-scheme-handler/about" = "firedragon.desktop";
      };
    };
  };
}
