{ pkgs, config, lib, ... }:

let
  cfg = config.services.noizdns;
  dnstt-server = pkgs.runCommand "dnstt-server" {
    src = pkgs.fetchurl {
      url = "https://github.com/anonvector/noizdns-deploy/raw/main/bin/dnstt-server-linux-amd64";
      sha256 = "0m1s9fv1grgx2cqjg39nf9mfnzf6drzyv2780hpsr3h0q6z3jr3s";
    };
  } ''
    install -m755 $src -D $out/bin/dnstt-server
  '';

  noizdns-entrypoint = pkgs.writeShellScript "noizdns-entrypoint" ''
    if [ ! -f /etc/noizdns/server.key ]; then
      mkdir -p /etc/noizdns
      ${dnstt-server}/bin/dnstt-server -gen-key -privkey-file /etc/noizdns/server.key -pubkey-file /etc/noizdns/server.pub
    fi
    exec ${dnstt-server}/bin/dnstt-server -privkey-file /etc/noizdns/server.key -mtu 1232 "${cfg.domain}"
  '';
in {
  options.services.noizdns = {
    enable = lib.mkEnableOption "NoizDNS Service";
    domain = lib.mkOption {
      type = lib.types.str;
      default = "ww.example.com";
      description = "The tunnel domain for NoizDNS.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Podman & Quadlets
    virtualisation.podman.enable = true;

    # Disable resolved stub listener to free up port 53 on the host
    services.resolved.settings.Resolve = {
      DNSStubListener = "no";
    };

    environment.etc = {
      # Custom network with DNS disabled to avoid Aardvark DNS binding conflicts on port 53
      "containers/systemd/noizdns.network".text = ''
        [Network]
        NetworkName=noizdns
        DisableDNS=true
      '';

      "containers/systemd/noizdns.pod".text = ''
        [Pod]
        PodName=noizdns
        Network=noizdns.network
        PublishPort=53:53/udp

        [Install]
        WantedBy=multi-user.target
      '';

      "containers/systemd/noizdns-dante.container".text = ''
        [Container]
        ContainerName=noizdns-dante
        Image=docker.io/wernight/dante
        Pod=noizdns.pod
        AutoUpdate=registry

        [Install]
        WantedBy=multi-user.target
      '';

      "containers/systemd/noizdns-dnstt.container".text = ''
        [Container]
        ContainerName=noizdns-dnstt
        Image=docker.io/alpine:latest
        Pod=noizdns.pod
        Environment=TOR_PT_MANAGED_TRANSPORT_VER=1
        Environment=TOR_PT_SERVER_TRANSPORTS=dnstt
        Environment=TOR_PT_SERVER_BINDADDR=dnstt-0.0.0.0:53
        Environment=TOR_PT_ORPORT=127.0.0.1:1080
        Volume=/var/lib/noizdns:/etc/noizdns:rw
        Volume=/nix/store:/nix/store:ro
        Exec=${noizdns-entrypoint}
        AutoUpdate=registry

        [Install]
        WantedBy=multi-user.target
      '';
    };

    # Management script (using sudo podman for rootful containers)
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "noizdns" ''
        case "$1" in
          logs) sudo podman logs -f noizdns-dnstt ;;
          status) systemctl status noizdns-pod.service noizdns-dnstt.service noizdns-dante.service ;;
          restart) systemctl restart noizdns-pod.service ;;
          pubkey) sudo podman exec noizdns-dnstt cat /etc/noizdns/server.pub ;;
          *) 
            echo "Usage: noizdns {logs|status|restart|pubkey}"
            exit 1
            ;;
        esac
      '')
    ];

    # Persistence
    preservation.preserveAt."/persistent".directories = [
      { directory = "/var/lib/noizdns"; user = "root"; group = "root"; mode = "0700"; }
      "/var/lib/containers"
    ];

    # Firewall
    networking.firewall.allowedUDPPorts = [ 53 ];
  };
}
