{ config, ... }:

{
  # FlareSolverr solves Cloudflare / DDoS-Guard interstitials by driving a
  # headless Chrome and handing back the resulting HTML and cookies. It is a
  # plain HTTP service, not an MCP server: the agent talks to it with curl,
  # guided by the flaresolverr skill in hermes-agent.nix.
  #
  # Containerised rather than packaged because the upstream image pins its own
  # Chrome/undetected-chromedriver pair. That pairing is the whole product —
  # a nixpkgs Chrome of a different version defeats the detection bypass — and
  # keeping it in the image also keeps ~500MB of browser out of the system
  # closure.
  virtualisation.oci-containers = {
    backend = "podman";
    containers.flaresolverr = {
      # Pinned by digest, not just tag: a tag can be moved upstream, and this
      # container runs a browser against hostile pages.
      image = "ghcr.io/flaresolverr/flaresolverr:v3.5.0@sha256:139dfee1c6f89249c8d665d1333a42e8ec74ec0a86bc6bb1c8461e10d3a66a47";
      autoStart = true;

      # Loopback only. There is no authentication on the API, and its whole
      # purpose is fetching arbitrary attacker-controlled URLs.
      ports = [ "127.0.0.1:8191:8191" ];

      environment = {
        LOG_LEVEL = "info";
        LOG_HTML = "false";
        # Kill a solver session after this long rather than leaking a Chrome.
        BROWSER_TIMEOUT = "40000";
        TZ = config.time.timeZone;
      };

      extraOptions = [
        # Chrome dies on the default 64MB /dev/shm.
        "--shm-size=1g"
        # No added capabilities on purpose. The image already starts Chrome
        # with --no-sandbox, so SYS_ADMIN and an unconfined seccomp profile
        # buy nothing and would weaken the one boundary between a browser
        # rendering hostile pages and this host.
        #
        # A page that spins up tabs should not take the desktop with it.
        "--memory=2g"
        "--cpus=2"
      ];
    };
  };

  # Impermanence: without this the image is re-pulled on every boot.
  preservation.preserveAt."/persistent".directories = [ "/var/lib/containers" ];
}
