{ pkgs, lib, ... }:
{
  systemd = {
    user = {
      services = {
        # noisetorch = {
        #   description = "NoiseTorch Noise Cancelling Daemon";
        #   wantedBy = [ "graphical-session.target" ];
        #   after = [
        #     "pipewire.service"
        #     "pulseaudio.service"
        #   ]; # Ensure audio is running first

        #   serviceConfig = {
        #     Type = "simple";
        #     ExecStart = "${pkgs.noisetorch}/bin/noisetorch -i";
        #     Restart = "on-failure";
        #     RestartSec = 3;
        #   };
        # };
        pipewire-pulse.environment = {
          LADSPA_PATH = "/tmp:/run/current-system/sw/lib/ladspa";
        };
        agenix = {
          serviceConfig = {
            Environment = "PATH=$PATH:${lib.makeBinPath [ pkgs.age-plugin-yubikey ]} ${pkgs.rage}/bin/rage";
          };
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
