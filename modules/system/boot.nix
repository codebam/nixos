{ pkgs, lib, ... }:

{
  # Secure Boot. Lives here rather than inline in flake.nix so the loader
  # settings and the thing that overrides them are in one file.
  #
  # lanzaboote replaces systemd-boot's installer with one that signs each
  # generation's stub, so the systemd-boot *module* has to be off while its
  # options stay set -- lanzaboote reads configurationLimit and the loader
  # timeout out of them and writes its own loader.conf.
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
  environment.systemPackages = [ pkgs.sbctl ];

  boot = {
    initrd.systemd = {
      enable = true;
      emergencyAccess = "$6$GKIRYDCTJO3SOTfb$nZuvpwjNYh./Sxc3WFB4.Y7rGx6XcmPYhYZ.bmDGExMkouIsKf.tYefX6LEhOGLMdlQ8.ipovClQ6U8ZtQNBm0";
    };
    loader = {
      systemd-boot = {
        # mkForce, not false: nixos modules elsewhere (and the installer
        # defaults) set this, and lanzaboote asserts it is off.
        enable = lib.mkForce false;
        # No memtest86 entry: lanzaboote's installer does not emit the extra
        # loader entries systemd-boot's does, so setting it here was a no-op.
        # configurationLimit is read by lanzaboote and does apply.
        configurationLimit = 10;
      };
      timeout = 0;
      efi.canTouchEfiVariables = true;
    };

    extraModulePackages = [ ];
  };
}
