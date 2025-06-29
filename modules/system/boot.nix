_:

{
  boot = {
    initrd.systemd = {
      enable = true;
    };
    loader = {
      systemd-boot = {
        enable = true;
        memtest86.enable = true;
        configurationLimit = 50;
      };
      timeout = 0;
      efi.canTouchEfiVariables = true;
    };

    extraModulePackages = [ ];
  };
}
