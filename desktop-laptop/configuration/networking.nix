_:

{
  networking.networkmanager.unmanaged = [
    "type:wifi"
    "type:ethernet"
  ];

  systemd.network.networks = {
    "40-wlan" = {
      matchConfig.Type = "wlan";
      networkConfig.DHCP = "yes";
    };
    "40-ether" = {
      matchConfig.Type = "ether";
      networkConfig.DHCP = "yes";
    };
  };
}
