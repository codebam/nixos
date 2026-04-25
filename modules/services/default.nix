{ pkgs, ... }:
{
  imports = [
    ./noizdns.nix
  ];
  systemd.user.services.cs2-playerctl-bridge = {
    unitConfig = {
      Description = "CS2 GSI Playerctl Bridge";
      After = [ "graphical-session.target" ];
    };
    serviceConfig = {
      ExecStart =
        let
          # Creating a self-contained environment for the script
          pythonEnv = pkgs.python3.withPackages (ps: [ ps.flask ]);
          script = pkgs.writeText "bridge.py" ''
            from flask import Flask, request
            import subprocess
            import logging

            # Disable flask logging to keep journalctl clean
            log = logging.getLogger('werkzeug')
            log.setLevel(logging.ERROR)

            app = Flask(__name__)

            @app.route("/", methods=['POST'])
            def gsi_listener():
                data = request.json
                if "round" in data and "phase" in data["round"]:
                    phase = data["round"]["phase"]
                    if phase == "live":
                        subprocess.run(["${pkgs.playerctl}/bin/playerctl", "pause"], stderr=subprocess.DEVNULL)
                    elif phase in ["over", "freezetime"]:
                        subprocess.run(["${pkgs.playerctl}/bin/playerctl", "play"], stderr=subprocess.DEVNULL)
                return "", 204

            if __name__ == "__main__":
                app.run(port=3000, host="127.0.0.1")
          '';
        in
        "${pythonEnv}/bin/python ${script}";

      Restart = "on-failure";
      RestartSec = "5s";
    };
    wantedBy = [ "default.target" ];
  };
  systemd.user.services.arrpc = {
    description = "arRPC - Discord RPC Bridge";
    unitConfig = {
      Requires = [ "dbus.socket" ];
      After = [
        "dbus.socket"
        "graphical-session.target"
      ];
    };
    serviceConfig = {
      ExecStart = "${pkgs.arrpc}/bin/arrpc";
      Restart = "always";
    };
    wantedBy = [ "default.target" ];
  };
  systemd.user.services.mprisence = {
    description = "Discord Rich Presence for MPRIS";
    unitConfig = {
      Requires = [ "dbus.socket" ];
      After = [
        "dbus.socket"
        "graphical-session.target"
      ];
    };
    serviceConfig = {
      ExecStart = "${pkgs.mprisence}/bin/mprisence";
      Restart = "always";
    };
    wantedBy = [ "default.target" ];
  };
  services = {
    ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
    };
    scx = {
      enable = true;
      scheduler = "scx_lavd"; # https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_lavd/README.md
      extraArgs = [
        "--performance"
        "--no-core-compaction"
        "--no-freq-scaling"
      ];
    };
    lsfg-vk = {
      enable = true;
      ui.enable = true;
    };
    tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "both";
    };
    networkd-dispatcher = {
      enable = true;
      rules."50-tailscale" = {
        onState = [ "routable" ];
        script = ''
          NETDEV=$(ip -o route get 8.8.8.8 | cut -d ' ' -f 5)
          ${pkgs.ethtool}/bin/ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
        '';
      };
    };
    ratbagd.enable = true;
    resolved.enable = true;
    speechd.enable = true;
    udev = {
      packages = with pkgs; [
        via
        yubikey-personalization
      ];
      extraRules = ''
        KERNEL=="ntsync", MODE="0660", TAG+="uaccess"

        # MelGeek Made68 Ultra
        SUBSYSTEM=="usb", ATTR{idVendor}=="1f3a", ATTR{idProduct}=="efe8", TAG+="uaccess"
        SUBSYSTEM=="usb_device", ATTR{idVendor}=="1f3a", ATTR{idProduct}=="efe8", TAG+="uaccess"
      '';
    };
    desktopManager.plasma6.enable = false;
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
      };
      openFirewall = true;
    };
    fwupd.enable = true;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };
    udisks2.enable = true;
    gnome.gnome-keyring.enable = true;
    pcscd.enable = true;
  };
}
