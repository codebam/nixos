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
          pythonEnv = pkgs.python3.withPackages (ps: [ ps.flask ]);
          script = pkgs.writeText "bridge.py" ''
            from flask import Flask, request
            import subprocess
            import sys

            app = Flask(__name__)

            MY_STEAM_ID = "76561198064631737"

            class State:
                is_alive = None # Use None so first packet always triggers
                mode = None

            state = State()

            @app.route("/", methods=['POST'])
            def gsi_listener():
                data = request.json
                
                # Extract info
                player = data.get("player", {})
                current_id = player.get("steamid")
                health = player.get("state", {}).get("health")
                
                # Update mode if present in packet
                map_data = data.get("map")
                if map_data and "mode" in map_data:
                    state.mode = map_data.get("mode")
                
                # Log raw data for debugging
                print(f"DEBUG: Received Packet - ID: {current_id}, Health: {health}, Mode: {state.mode}", file=sys.stderr)

                # Only active in casual mode
                if state.mode != "casual":
                    if state.is_alive is True:
                        print(f"ACTION: Mode is {state.mode}, not casual. Resuming music.", file=sys.stderr)
                        subprocess.run(["${pkgs.playerctl}/bin/playerctl", "play"], stderr=subprocess.DEVNULL)
                    state.is_alive = None
                    return "", 204

                # Ignore packets that don't have the data we need
                if current_id is None or health is None:
                    print("DEBUG: Skipping partial packet (missing ID or Health)", file=sys.stderr)
                    return "", 204

                # Decision Logic
                currently_alive = (current_id == MY_STEAM_ID and health > 0)

                if currently_alive != state.is_alive:
                    state.is_alive = currently_alive
                    if currently_alive:
                        print("ACTION: You are ALIVE. Pausing music.", file=sys.stderr)
                        subprocess.run(["${pkgs.playerctl}/bin/playerctl", "pause"], stderr=subprocess.DEVNULL)
                    else:
                        print(f"ACTION: You are DEAD/SPECTATING (ID: {current_id}, Health: {health}). Playing music.", file=sys.stderr)
                        subprocess.run(["${pkgs.playerctl}/bin/playerctl", "play"], stderr=subprocess.DEVNULL)
                
                return "", 204

            if __name__ == "__main__":
                # Run with threaded=True to handle rapid GSI updates better
                app.run(port=3000, host="127.0.0.1", threaded=True)
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
