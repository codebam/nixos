{
  config,
  pkgs,
  ...
}:

let
  # The name TP-Link's DDNS keeps current. Read only -- see the module docstring
  # in ./scripts/cloudflare-ddns.py for why the address is mirrored from here
  # rather than detected locally.
  source = "codebam.tplinkdns.com";

  # Both names were CNAMEs to `source`, which put TP-Link's nameservers in
  # Let's Encrypt's resolution path for every renewal. LE measured SERVFAIL
  # against them on names that Google and Cloudflare resolve fine, which
  # blocked issuance; as A records in Cloudflare's own zone, validation never
  # has to ask TP-Link anything.
  #
  # codebam.tplinkdns.com itself cannot be rescued this way -- it validates
  # against those same nameservers by definition.
  targets = [
    "llm.codebam.ca"
    "music.codebam.ca"
  ];
in
{
  systemd.services.cloudflare-ddns = {
    description = "Mirror the router's DDNS address into Cloudflare";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = {
      DDNS_SOURCE = source;
      DDNS_ZONE = "codebam.ca";
      DDNS_TARGETS = builtins.concatStringsSep "," targets;
      # Short, because the whole point is tracking an address that changes
      # without warning. Cheap: the record is only written when it differs.
      DDNS_TTL = "300";
    };

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python ${./scripts/cloudflare-ddns.py}";

      # systemd reads the credential as root and hands it to the DynamicUser,
      # so the sops secret stays root-owned 0400 and there is no static account
      # to chown to -- same arrangement as llm-proxy.nix and litellm.nix.
      LoadCredential = [ "token:${config.sops.secrets.cloudflare-dns-token.path}" ];

      DynamicUser = true;
      # It resolves one name and talks to one API. Nothing else.
      CapabilityBoundingSet = [ "" ];
      AmbientCapabilities = [ "" ];
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        # getaddrinfo talks to systemd-resolved over a unix socket.
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
        "~@resources"
      ];
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
    };
  };

  systemd.timers.cloudflare-ddns = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Five minutes is the resolution on how long a name can point at a dead
      # address after the ISP moves it. The run is a no-op when nothing changed.
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      Persistent = true;
    };
  };

  # Scoped at creation to Zone:DNS:Edit on codebam.ca alone, so the worst it
  # can do is edit records in that one zone.
  sops.secrets.cloudflare-dns-token = { };
}
