_:

{
  networking = {
    hostName = "nixos-desktop";
    firewall.allowedTCPPorts = [
      25575 # RCON port
    ];
    firewall.allowedUDPPorts = [
      8211 # PalWorld port
      27015 # Steam query port
    ];
  };
}
