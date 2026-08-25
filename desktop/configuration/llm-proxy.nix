{
  config,
  pkgs,
  lib,
  ...
}:

let
  # aiohttp only. A tokeniser would be the one other dependency worth having,
  # but pulling transformers in for a single number is not worth the closure --
  # see estimate_tokens in the script for what is done instead.
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.aiohttp ]);

  port = 8080;

  # Funnel allows 443, 8443 and 10000, and 443 is not available on this host:
  # the codebam.tplinkdns.com and music.codebam.ca vhosts listen on 0.0.0.0:443,
  # which sweeps in the tailscale address, and tailscaled then cannot bind
  # 100.x:443 to terminate funnel TLS. The failure is quiet in the worst way --
  # `tailscale funnel status` reports the funnel on while the journal logs
  # "localListener failed to listen on 100.101.46.50:443 ... address already in
  # use" and the endpoint answers nobody.
  #
  # Pinning nginx to one address would free 443, but the WAN address is dynamic
  # (hence the DDNS name) and the LAN address comes from DHCP. Note the tailnet
  # vhost carrying cockpit and the servarr UIs is on port 80, so it is not the
  # one in the way; disabling cockpit does not help.
  #
  # Cost of 8443: some restrictive networks block non-standard HTTPS ports
  # outbound, so a visitor may fail where you succeed. 10000 fares no better.
  funnelPort = 8443;

  # 03:00-11:00 America/Toronto, which is 07:00-15:00 UTC: the European working
  # day. The window is when the desktop is otherwise idle, so the card is not
  # being fought over by a compositor under load.
  windowStart = 3;
  windowEnd = 11;

  tailscale = lib.getExe pkgs.tailscale;

  # Whether the funnel opens on its own -- at boot, and from the 03:00 timer.
  #
  # Keep this false until the endpoint has been verified from outside the
  # tailnet (see the comment on llm-funnel-up below). Switching with it true
  # publishes the machine the moment activation runs, and the Let's Encrypt
  # certificate that issues on first serve is written to Certificate
  # Transparency logs, where it cannot be withdrawn. `tailscale funnel` by hand
  # still works with this false; only the automation is held back.
  funnelAtBoot = false;

  # Exits non-zero outside the window, which systemd's ExecCondition treats as
  # "skip this unit" rather than "this unit failed". That is what makes both
  # Persistent=true on the timer and the boot trigger safe: a 03:00 trigger
  # replayed at 13:00 finds the condition false and does nothing.
  #
  # A script rather than an inline bash -c because the unit file would need
  # both nix indented-string escaping and systemd %-escaping to survive, and
  # getting either wrong fails silently in the direction of "funnel never
  # opened". 10# is there because date +%H zero-pads and bash reads 08 and 09
  # as invalid octal.
  inWindow = pkgs.writeShellScript "llm-funnel-in-window" ''
    h=$((10#$(${pkgs.coreutils}/bin/date +%H)))
    [ "$h" -ge ${toString windowStart} ] && [ "$h" -lt ${toString windowEnd} ]
  '';
in
{
  # Puts ollama in front of strangers without letting them reach ollama.
  #
  # ollama has no authentication and will pull and delete models for whoever
  # reaches the port, which is why it is bound to 127.0.0.1 in ./services.nix.
  # This proxy is what may be exposed instead: it authenticates, allowlists two
  # endpoints, and -- the part that matters most -- rewrites the request body
  # so a caller cannot set num_ctx.
  #
  # That last one is not theoretical. The measured table in ./services.nix has
  # 224k running at a tenth speed while ollama still reports 100% GPU, and the
  # 256k probe OOM-killed llama-server and left a thread wedged in amdgpu's
  # kfd_process_notifier_release_internal holding 22 GiB of VRAM through a
  # service restart -- the card only came back on reboot. A client-supplied
  # context size is a reboot someone else gets to schedule.
  systemd.services.llm-proxy = {
    description = "Sanitising reverse proxy for ollama";
    after = [
      "network.target"
      "ollama.service"
    ];
    wants = [ "ollama.service" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      PROXY_HOST = "127.0.0.1";
      PROXY_PORT = toString port;
      OLLAMA_URL = "http://127.0.0.1:11434";

      # The :160k tag, not :latest. ./services.nix has the reasoning: 192k fits
      # but leaves less slack than the compositor wants, and 224k is the trap.
      PROXY_MODEL = "qwen3.8:160k";

      # Under the model's 160k so there is room for the reply, and under it by
      # enough to absorb the estimator's error in the wrong direction.
      PROXY_MAX_PROMPT_TOKENS = "120000";
      PROXY_MAX_OUTPUT_TOKENS = "8192";

      # OLLAMA_NUM_PARALLEL is 1, so this is the honest number. Raising it here
      # without raising it there just moves the queue.
      PROXY_SLOTS = "1";
      PROXY_QUEUE_TIMEOUT = "300";
      PROXY_RATE_LIMIT = "60";

      PROXY_TZ = "America/Toronto";
      PROXY_WINDOW_START = toString windowStart;
      PROXY_WINDOW_END = toString windowEnd;
      PROXY_WINDOW = "1";
    };

    serviceConfig = {
      ExecStart = "${pythonEnv}/bin/python ${./scripts/llm-proxy.py}";
      Restart = "on-failure";
      RestartSec = 5;

      # systemd reads the credential as root and hands it to the DynamicUser,
      # so the sops secret stays root-owned 0400 and there is no static account
      # to chown to -- same arrangement as litellm.nix and nix-serve.nix.
      LoadCredential = [ "keys:${config.sops.secrets.llm-proxy-keys.path}" ];

      DynamicUser = true;
      # It talks to loopback and reads one credential. Nothing else.
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

  # The funnel is the real boundary; the proxy's own window check is a second
  # gate for the case where these failed to fire.
  #
  # Funnel, not serve, because the point is that a visitor needs no tailscale
  # of their own. The cost of that choice: funnel is public and unauthenticated
  # at the transport layer, and its Let's Encrypt certificate is published to
  # Certificate Transparency logs, so the hostname is enumerable within minutes
  # of first being served. The proxy's bearer check is the only thing between
  # the internet and the card -- treat it that way.
  systemd.services.llm-funnel-up = {
    description = "Open the public funnel to llm-proxy";
    after = [
      "llm-proxy.service"
      "tailscaled.service"
    ];
    wants = [ "llm-proxy.service" ];
    # Also at boot, so a machine that came up at 05:00 is not dark until the
    # next 03:00 trigger. The ExecCondition below is what keeps that safe.
    wantedBy = lib.optionals funnelAtBoot [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Skips the unit (exit 0, not failed) outside the window, which is what
      # makes Persistent=true on the timer and the boot trigger both harmless:
      # a replayed 03:00 trigger fired at 13:00 does nothing. 10# because
      # date +%H is zero-padded and bash would read 08 and 09 as octal.
      ExecCondition = [ "${inWindow}" ];
      # Verify against `tailscale funnel --help` on 1.102.2 before trusting a
      # timer with it: the serve/funnel flag surface has changed repeatedly
      # across releases and a silent no-op here reads as "nobody showed up".
      ExecStart = "${tailscale} funnel --bg --https=${toString funnelPort} http://127.0.0.1:${toString port}";
      ExecStop = "${tailscale} funnel --https=${toString funnelPort} off";
    };
  };

  systemd.services.llm-funnel-down = {
    description = "Close the public funnel to llm-proxy";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${tailscale} funnel --https=${toString funnelPort} off";
    };
  };

  systemd.timers.llm-funnel-up = {
    wantedBy = lib.optionals funnelAtBoot [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* ${lib.fixedWidthNumber 2 windowStart}:00:00";
      Persistent = true;
    };
  };

  # Left enabled even when funnelAtBoot is false: if a hand-run funnel is still
  # open at 11:00 it should still close, and closing something already closed
  # is a no-op.
  systemd.timers.llm-funnel-down = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* ${lib.fixedWidthNumber 2 windowEnd}:00:00";
      Persistent = false;
    };
  };

  # One bearer key per line, blank lines and # comments ignored. Rotation is
  # editing the secret and restarting the unit; revocation is deleting a line.
  #
  #   sops set secrets/secrets.yaml '["llm-proxy-keys"]' \
  #     "$(printf 'sk-%s\nsk-%s\n' "$(openssl rand -hex 24)" "$(openssl rand -hex 24)" | jq -Rs .)"
  sops.secrets.llm-proxy-keys = { };
}
