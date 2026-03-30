_:

{
  boot = {
    initrd.systemd = {
      enable = true;
      emergencyAccess = "$6$GKIRYDCTJO3SOTfb$nZuvpwjNYh./Sxc3WFB4.Y7rGx6XcmPYhYZ.bmDGExMkouIsKf.tYefX6LEhOGLMdlQ8.ipovClQ6U8ZtQNBm0";
    };
    loader = {
      systemd-boot = {
        enable = true;
        memtest86.enable = true;
        configurationLimit = 10;
      };
      timeout = 0;
      efi.canTouchEfiVariables = true;
    };

    extraModulePackages = [ ];
  };
}
