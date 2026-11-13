{
  config,
  lib,
  pkgs,
  ...
}:

{
  # SOPS-sourced password hashes replace the shared inline hashes. The
  # inline `hashedPassword` is nulled out here so only `hashedPasswordFile`
  # remains set (setting both triggers the multiple-options warning, even
  # though File wins with mutableUsers = false). Same hash values, now
  # stored in SOPS. Both secrets set `neededForUsers = true` in sops.nix,
  # so userborn can read them before it writes /etc/shadow.
  users.users = {

    root.hashedPassword = lib.mkForce null;
    root.hashedPasswordFile = config.sops.secrets.root-hashed-password.path;
    codebam.hashedPassword = lib.mkForce null;
    codebam.hashedPasswordFile = config.sops.secrets.codebam-hashed-password.path;

    makano = {
      isNormalUser = true;
      uid = 1001;
      home = "/home/makano";
      # See modules/users/subids.nix.
      subUidRanges = [
        {
          startUid = 165536;
          count = 65536;
        }
      ];
      subGidRanges = [
        {
          startGid = 165536;
          count = 65536;
        }
      ];
      description = "Makano";
      packages = [ ];
      shell = pkgs.fish;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAf5Y0VAO2dyCseCQ0gyNaTUIzNJj885bYyX03v0vSS4 makano@nixos"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFpzbhkbHB3jZPdMKuNRBjAgsslCeILJE+BmSYWcht1 makano@Dush"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEkBfTf9i6kG6P+HGWN3ghszdxQYmXzxllIlxPkwuyCo codebam@nixos-desktop" # nixos-desktop
      ];
    };
  };
}
