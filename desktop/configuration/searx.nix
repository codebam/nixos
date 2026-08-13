{ config, ... }:

{
  # Loopback-only SearXNG. JSON API is on so agents can search without a
  # browser; there is no public vhost and the port is not in allowedTCPPorts.
  sops.templates."searx.env" = {
    content = ''
      SEARX_SECRET_KEY=${config.sops.placeholder.searx-secret}
    '';
    restartUnits = [ "searx.service" ];
  };

  services.searx = {
    enable = true;
    redisCreateLocally = false;
    configureUwsgi = false;
    configureNginx = false;
    openFirewall = false;
    environmentFile = config.sops.templates."searx.env".path;
    settings = {
      use_default_settings = true;
      general = {
        instance_name = "searxng";
        enable_metrics = false;
      };
      server = {
        bind_address = "127.0.0.1";
        port = 8081;
        secret_key = "$SEARX_SECRET_KEY";
        limiter = false;
        public_instance = false;
        method = "GET";
      };
      search = {
        safe_search = 0;
        autocomplete = "";
        default_lang = "en";
        formats = [
          "html"
          "json"
        ];
      };
    };
  };
}
