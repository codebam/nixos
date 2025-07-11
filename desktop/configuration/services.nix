{ pkgs
, config
, ...
}:

{
  services = {
    sunshine = {
      enable = true;
      openFirewall = true;
      autoStart = true;
      applications = {
        apps = [
          {
            name = "Steam";
            cmd = "${pkgs.steam}/bin/steam";
            auto-detach = "true";
          }
          {
            name = "Steam Big Picture";
            cmd = "${pkgs.steam}/bin/steam -gamepadui";
            auto-detach = "true";
          }
        ];
      };
    };
    ddclient = {
      enable = true;
      protocol = "duckdns";
      domains = [ "codebam" ];
      passwordFile = config.age.secrets.duckdns-token.path;
    };
    scx = {
      enable = true;
    };
    nginx = {
      enable = true;
      virtualHosts = {
        "ai.seanbehan.ca" = {
          enableACME = true;
          addSSL = true;
          locations = {
            "/" = {
              proxyPass = "http://localhost:8080/";
              proxyWebsockets = true;
            };
          };
        };
      };
    };
    pipewire = {
      configPackages = [
        (pkgs.writeTextDir "share/pipewire/pipewire.conf.d/10-high-sample-rate.conf" ''
          context.properties = {
            default.clock.allowed-rates = [ 192000 384000 768000 ]
            default.clock.rate = 192000
          }
        '')
      ];
    };
    hardware.openrgb = {
      enable = true;
    };
    open-webui = {
      enable = false;
      port = 8080;
      environment = {
        ANONYMIZED_TELEMETRY = "False";
        DO_NOT_TRACK = "True";
        SCARF_NO_ANALYTICS = "True";
        ENABLE_WEB_SEARCH = "True";
        WEB_SEARCH_ENGINE = "searxng";
        SEARXNG_QUERY_URL = "http://localhost:8081/search?q=<query>";
      };
    };
    searx = {
      enable = true;
      environmentFile = config.age.secrets.searx-secret.path;
      settings = {
        server = {
          secret_key = "$''{SECRET_KEY}";
          bind_address = "0.0.0.0";
          port = 8081;
        };
        search = {
          autocomplete = "google";
          formats = [
            "html"
            "json"
          ];
        };
      };
    };
    ollama = {
      enable = true;
      host = "0.0.0.0";
      acceleration = "rocm";
      environmentVariables = {
        HSA_OVERRIDE_GFX_VERSION = "11.0.0";
      };
    };
  };
}
