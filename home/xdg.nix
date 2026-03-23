_:

{
  xdg = {
    enable = true;
    mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = "google-chrome-unstable.desktop";
        "x-scheme-handler/http"  = "google-chrome-unstable.desktop";
        "x-scheme-handler/https" = "google-chrome-unstable.desktop";
        "x-scheme-handler/about" = "google-chrome-unstable.desktop";
      };
    };
  };
}
