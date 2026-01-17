_:

{
  xdg = {
    enable = true;
    mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = "chromium-browser.desktop";
        "x-scheme-handler/http"  = "chromium-browser.desktop";
        "x-scheme-handler/https" = "chromium-browser.desktop";
        "x-scheme-handler/about" = "chromium-browser.desktop";
      };
    };
  };
}
