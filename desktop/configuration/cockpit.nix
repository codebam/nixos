{ pkgs, lib, ... }:

let
  port = 9090;
  urlRoot = "/cockpit";
  tailnetHost = "nixos-desktop.tail7d7a2.ts.net";
in
{
  # Cockpit is a root-capable web console: its whole purpose is running
  # privileged commands and handing out a root terminal. It gets the same
  # treatment as every other admin UI on this host -- loopback bind, reached
  # only through the tailnet nginx vhost, which carries the allow/deny.
  services.cockpit = {
    enable = true;
    inherit port;

    # Moot with the loopback socket below, but leave it false so re-adding a
    # 0.0.0.0 bind cannot quietly open the port at the same time.
    openFirewall = false;

    plugins = [
      # Containers page: the flaresolverr container from flaresolverr.nix
      # (root podman, via virtualisation.oci-containers) plus whatever the
      # rootless per-user podman in home.nix is running. Both sockets are
      # already socket-activated by the podman module -- system podman.socket
      # and the user one -- so both sets show up without further wiring.
      pkgs.cockpit-podman
      pkgs.cockpit-files
    ];
    # Not installed on purpose: cockpit-machines needs libvirtd, which this
    # host does not run, and cockpit-zfs needs ZFS -- everything here is btrfs.
    # An installed plugin with no backing daemon is a dead menu entry that
    # looks like a broken page.

    settings = {
      WebService = {
        # Served under a subpath of the tailnet vhost, sharing nginx's port 80
        # with lidarr and prowlarr. Cockpit has to be told its own prefix or
        # every asset and websocket URL it generates points at the vhost root.
        UrlRoot = urlRoot;

        # nginx reaches cockpit-ws over loopback in plain HTTP. Without this
        # cockpit answers every unencrypted request with a redirect to its own
        # https:// URL and the proxy never gets a page. This is not a downgrade
        # of the transport: the browser-to-nginx hop is tailscale's, which is
        # encrypted, and the nginx-to-cockpit hop never leaves the host.
        AllowUnencrypted = true;

        # recommendedProxySettings sets both of these. Without ProtocolHeader
        # cockpit assumes the client spoke whatever nginx spoke to it, and
        # without ForwardedForHeader every login is logged as 127.0.0.1.
        ProtocolHeader = "X-Forwarded-Proto";
        ForwardedForHeader = "X-Forwarded-For";

        # No SSH-out from the login page. This is what CVE-2026-4631 was
        # about; the module also defaults it off, but it is worth being
        # explicit on a box whose ssh keys unlock the other hosts.
        LoginTo = false;
      };

      Session = {
        # Minutes. A logged-in cockpit tab is a root shell someone walked away
        # from.
        IdleTimeout = 15;
      };
    };

    # The banner advertises https://<hostname>:9090/, which is wrong on both
    # counts here -- nothing listens on 9090 off-loopback and the path is
    # /cockpit. A motd that lies is worse than no motd.
    showBanner = false;

    # Must match the Origin the browser actually sends, or cockpit rejects the
    # websocket handshake with "received request from bad Origin". Port 80, so
    # no port suffix. The module adds https://localhost:9090 on its own.
    allowed-origins = [ "http://${tailnetHost}" ];
  };

  # The module's socket unit takes only a port number, which binds 0.0.0.0 --
  # and 0.0.0.0 is not a closed door on this host, because tailscale0 and
  # virbr0 are in firewall.trustedInterfaces and are accepted before any port
  # rule is consulted. Same reasoning as ollama and the servarr apps. The
  # empty string first is upstream's idiom for clearing the unit file's own
  # ListenStream before adding ours.
  systemd.sockets.cockpit.listenStreams = lib.mkForce [
    ""
    "127.0.0.1:${toString port}"
  ];

  # Merges into the tailnet-only vhost defined in services.nix. The allow/deny
  # lives on the server block there, so it covers this location too.
  services.nginx.virtualHosts.${tailnetHost}.locations.${urlRoot} = {
    # No trailing slash on either side: cockpit is expecting to see /cockpit
    # in the request path because of UrlRoot, so nginx must pass the URI
    # through unrewritten.
    proxyPass = "http://127.0.0.1:${toString port}";
    proxyWebsockets = true;
    extraConfig = ''
      # The terminal and the journal follower are long-lived websockets that
      # sit idle between keystrokes; the default 60s read timeout drops them
      # and cockpit shows "disconnected" on an otherwise healthy session.
      proxy_read_timeout 1d;
      proxy_send_timeout 1d;

      # Cockpit streams (logs, terminal output, container stats). Buffering
      # holds that back until nginx has a full buffer, which reads as lag.
      proxy_buffering off;
    '';
  };

  # Privilege escalation, for the record: cockpit's first choice is
  # `sudo -A cockpit-bridge --privileged`, and there is no sudo on this host
  # (security.sudo.enable = false). It falls through to its polkit bridges --
  # systemd StartTransientUnit, then pkexec -- which do work here. The polkit
  # rule in modules/security/default.nix only grants wheel passwordless for
  # local *and* active sessions, and a browser session is neither, so
  # "Administrative access" prompts for the account password. That is the
  # intended behaviour, not a misconfiguration: it is the same reason an SSH
  # session has to authenticate.
}
