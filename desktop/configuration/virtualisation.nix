_:
{
  virtualisation.oci-containers.containers = {
    "flaresolverr" = {
      image = "ghcr.io/flaresolverr/flaresolverr:latest";
      ports = [ "8191:8191" ];
      extraOptions = [ 
        "--network=host"
      ];
      environment = {
        LOG_LEVEL = "info";
        TZ = "America/Toronto";
      };
    };
  };
}
