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
  # Mirrors the `lookup main suppress_prefixlength 0` rule wg-quick installs
  # at 5208, which the rule above would otherwise skip. Without it, a marked
  # packet to a directly connected network (the LAN) is sent into the tunnel
  # instead of out the local interface, so a tailscale peer on this subnet
  # cannot be reached directly.
  lanRulePriority = "5099";

  # wg-quick picks the table from the interface's fwmark (0xca6c = 51820 for
  # ivpn), but that is an implementation detail of the daemon's generated
  # config, so read it back rather than hardcoding it.
  script = pkgs.writeShellScript "tailscale-via-ivpn" ''
    set -euo pipefail
    PATH=${pkgs.iproute2}/bin:${pkgs.jq}/bin:$PATH
    family="$2"

    findTable() {
      ip -N -j -"$family" route show default dev wgivpn table all |
        jq -r '[.[] | select(.table != null) | .table] | unique |
          if length == 0 then "" elif length == 1 then .[0]
          else error("multiple wgivpn default routing tables") end'
    }

    # Only touch our exact selectors, including the old table after a flap.
    # Listing first makes absent rules a no-op without hiding netlink failures.
    removeRules() {
      local priority="$1" tables table
      tables=$(ip -N -j -"$family" rule show | jq -r --argjson priority "$priority" '
        .[] | select(.priority == $priority and .src == "all" and
          .fwmark == "0x80000" and .fwmask == "0xff0000" and .table != null) |
        select(if $priority == ${lanRulePriority} then
          .table == "254" and .suppress_prefixlen == 0
        else .suppress_prefixlen == null end) |
        select(del(.priority, .src, .fwmark, .fwmask, .table, .suppress_prefixlen) == {}) |
        .table') || return 1
      while IFS= read -r table; do
        [ -n "$table" ] || continue
        if [ "$priority" = ${lanRulePriority} ]; then
          ip -"$family" rule del priority "$priority" fwmark ${tsFwmark} lookup "$table" suppress_prefixlength 0 || return 1
        else
          ip -"$family" rule del priority "$priority" fwmark ${tsFwmark} lookup "$table" || return 1
        fi
      done <<< "$tables"
    }

    cleanup() {
      local status=0
      removeRules ${rulePriority} || status=1
      removeRules ${lanRulePriority} || status=1
      return "$status"
    }

    case "$1" in
      up)
        # The device can appear before either family has its route. Missing
        # IPv6 is retryable too: this configuration does not prove it is
        # permanently disabled, and IPv4 must not wait for it.
        table=$(findTable)
        if [ -z "$table" ]; then
          echo "no IPv$family default route via wgivpn" >&2
          exit 1
        fi
        cleanup
        ip -"$family" rule add priority ${lanRulePriority} fwmark ${tsFwmark} lookup main suppress_prefixlength 0
        ip -"$family" rule add priority ${rulePriority} fwmark ${tsFwmark} lookup "$table"
        ;;
      down)
        cleanup
        ;;
      *)
        echo "unknown action: $1" >&2
        exit 2
        ;;
    esac
  '';

  routeService = family: {
    description = "Route tailscale IPv${family} through the ivpn tunnel while it is up";
    bindsTo = [ "sys-subsystem-net-devices-wgivpn.device" ];
    after = [ "sys-subsystem-net-devices-wgivpn.device" ];
    wantedBy = [ "sys-subsystem-net-devices-wgivpn.device" ];
    # Stop retrying if a route is genuinely absent; a later device cycle or
    # manual start can try again after the interval (or after reset-failed).
    unitConfig = {
      StartLimitIntervalSec = 120;
      StartLimitBurst = 12;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 5;
      ExecStart = "${script} up ${family}";
      ExecStop = "${script} down ${family}";
      # ExecStop is not run if ExecStart fails partway through.
      ExecStopPost = "${script} down ${family}";
    };
  };

  # `ivpn` is only a client for the daemon and works once the daemon has
  # published its connection-info. A rebuild restarts ivpn-service and this
  # unit at the same time, and `after` only guarantees the daemon's process was
  # forked -- not that it is ready to answer -- so a single invocation races it
  # and dies with "connection-info not exists". Retry the (idempotent) command
  # until the daemon accepts it.
  applyException = pkgs.writeShellScript "ivpn-tailscale-exception" ''
    set -u
    for _ in $(seq 60); do
      ${pkgs.ivpn}/bin/ivpn firewall -exceptions 100.64.0.0/10 && exit 0
      sleep 0.5
    done
    echo "ivpn daemon did not become ready; giving up" >&2
    exit 1
  '';
in
{
  systemd.services = {
    # Sends tailscale's marked packets into ivpn's routing table for as long as
    # wgivpn exists. Nothing is needed for the fallback: when ivpn is down the
    # rules are gone (and even if they lingered, the table is empty and the lookup
    # falls through to tailscale's own rule 5210 -> main), so routing is exactly
    # what it was before.
    tailscale-via-ivpn = routeService "4";
    tailscale-via-ivpn-ipv6 = routeService "6";

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
    ivpn-tailscale-exception = {
      description = "Allow the tailnet range through ivpn's killswitch";
      after = [ "ivpn-service.service" ];
      requires = [ "ivpn-service.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 5;
        ExecStart = applyException;
      };
    };
  };
}
