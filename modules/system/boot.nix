_:

{
  boot = {
    initrd.systemd = {
      enable = true;
      emergencyAccess = "$6$TIP8YR83obmkq8T2$T3lYdPbPj9wysMznNlS5J0qHo2eyTr43aF/ZWSMWHdNRob4dkBB0s3KpBLUgYRTyPZxbb1ZgeqCrrx.DEEkQX1";
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
