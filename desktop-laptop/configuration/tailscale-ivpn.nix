{ pkgs, ... }:
let
  # Tailscale marks its own (already-encrypted) WireGuard packets with
  # 0x80000 and installs `ip rule 5210 fwmark 0x80000 lookup main` so they do
  # not re-enter tailscale0. That rule outranks the ones wg-quick adds for
  # ivpn, so with ivpn up tailscale's UDP still leaves via the physical
  # interface -- outside the tunnel, and straight into ivpn's killswitch,
  # which drops everything not leaving via wgivpn. Result: tailscale is dead
  # while ivpn is connected, rather than merely leaking around it.
  tsFwmark = "0x80000/0xff0000";
  # Ahead of tailscale's own 5210, so it wins while wgivpn exists.
  rulePriority = "5100";

  # wg-quick picks the table from the interface's fwmark (0xca6c = 51820 for
  # ivpn), but that is an implementation detail of the daemon's generated
  # config, so read it back rather than hardcoding it.
  script = pkgs.writeShellScript "tailscale-via-ivpn" ''
    set -u
    PATH=${pkgs.iproute2}/bin:$PATH

    findTable() {
      ip -$1 route show default dev wgivpn table all 2>/dev/null |
        ${pkgs.gawk}/bin/awk '{ for (i = 1; i < NF; i++) if ($i == "table") { print $(i + 1); exit } }'
    }

    case "$1" in
      up)
        # The device unit fires when wg-quick creates the link, which is
        # before it installs the routes. Wait for the default route to show
        # up rather than adding a rule that points at an empty table.
        for _ in $(seq 50); do
          table=$(findTable 4)
          [ -n "$table" ] && break
          sleep 0.1
        done
        [ -n "$table" ] || { echo "no default route via wgivpn; leaving routing alone"; exit 0; }

        ip rule add priority ${rulePriority} fwmark ${tsFwmark} lookup "$table"
        table6=$(findTable 6)
        [ -n "$table6" ] && ip -6 rule add priority ${rulePriority} fwmark ${tsFwmark} lookup "$table6"
        ;;
      down)
        ip rule del priority ${rulePriority} fwmark ${tsFwmark} 2>/dev/null
        ip -6 rule del priority ${rulePriority} fwmark ${tsFwmark} 2>/dev/null
        ;;
    esac
    exit 0
  '';
in
{
  # Sends tailscale's marked packets into ivpn's routing table for as long as
  # wgivpn exists. Nothing is needed for the fallback: when ivpn is down the
  # rule is gone (and even if it lingered, the table is empty and the lookup
  # falls through to tailscale's own rule 5210 -> main), so routing is exactly
  # what it was before.
  systemd.services.tailscale-via-ivpn = {
    description = "Route tailscale through the ivpn tunnel while it is up";
    bindsTo = [ "sys-subsystem-net-devices-wgivpn.device" ];
    after = [ "sys-subsystem-net-devices-wgivpn.device" ];
    wantedBy = [ "sys-subsystem-net-devices-wgivpn.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${script} up";
      ExecStop = "${script} down";
    };
  };

  # Routing tailscale into the tunnel is only half of it: ivpn's killswitch
  # also drops traffic on tailscale0 itself, so reaching tailnet peers from
  # this host needs the CGNAT range as a user exception. The setting lives in
  # /etc/opt/ivpn/mutable/settings.json (preserved), and re-applying it is
  # idempotent. IPv6 tailnet addresses (fd7a:115c:a1e0::/48) need no rule --
  # ivpn's ip6tables chains already accept FD00::/8.
  #
  # Not covered: MagicDNS. ivpn's DNS chain drops port 53 to anything but the
  # resolver it pushed, and it is evaluated before the user exceptions, so
  # 100.100.100.100 stays blocked and *.ts.net names do not resolve while
  # connected. Peer IPs still work.
  systemd.services.ivpn-tailscale-exception = {
    description = "Allow the tailnet range through ivpn's killswitch";
    after = [ "ivpn-service.service" ];
    requires = [ "ivpn-service.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.ivpn}/bin/ivpn firewall -exceptions 100.64.0.0/10";
    };
  };
}
