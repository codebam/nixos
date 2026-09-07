{ pkgs, ... }:
{
  systemd = {
    # systemd-networkd-wait-online is disabled outright in
    # modules/system/networking.nix, so the ExecStart/TimeoutStartSec override
    # that used to live here never applied to anything.
    network.networks."50-tailscale".linkConfig.RequiredForOnline = "no";
    user = {
      services = {
        pipewire-pulse.environment = {
          LADSPA_PATH = "/tmp:/run/current-system/sw/lib/ladspa";
        };
        polkit-gnome-authentication-agent-1 = {
          description = "polkit-gnome-authentication-agent-1";
          # wantedBy implies the pull-in; a separate wants was redundant.
          wantedBy = [ "sway-session.target" ];
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
