_:

{
  services = {
    mako = {
      enable = true;
      settings = {
        layer = "overlay";
      };
    };
    podman = {
      enable = true;
      containers = {
        open-webui = {
          autoStart = true;
          autoUpdate = "registry";
          description = "open-webui container";
          image = "ghcr.io/open-webui/open-webui:main";
          ports = [
            "8080:8080"
          ];
          volumes = [
            "open-webui-data:/app/backend/data"
          ];
          environment = {
            ENV = "prod";
            OLLAMA_BASE_URL = "http://host.containers.internal:11434";
            SEARXNG_QUERY_URL = "http://host.containers.internal:8081/search?q=<query>";
          };
        };
      };
    };
  };
}
