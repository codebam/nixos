{ pkgs, lib, ... }:
{
  systemd = {
    services = {
      systemd-networkd-wait-online.serviceConfig = {
        ExecStart = [
          "" # This clears the default command arguments
          "${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online --any"
        ];
        TimeoutStartSec = "15s";
      };
    };
    network.networks."50-tailscale".linkConfig.RequiredForOnline = "no";
    user = {
      services = {
        pipewire-pulse.environment = {
          LADSPA_PATH = "/tmp:/run/current-system/sw/lib/ladspa";
        };
        polkit-gnome-authentication-agent-1 = {
          description = "polkit-gnome-authentication-agent-1";
          wantedBy = [ "sway-session.target" ];
          wants = [ "sway-session.target" ];
          after = [ "sway-session.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
            Restart = "on-failure";
            RestartSec = 1;
            TimeoutStopSec = 10;
          };
        };
      };
    };
  };
}
