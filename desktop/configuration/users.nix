{ config, pkgs, ... }:

{
  # SOPS-sourced password hashes take precedence over the shared inline
  # hashes (users.mutableUsers = false precedence: ... ->
  # hashedPassword -> ... -> hashedPasswordFile). Reuses the same hash
  # values already in modules/users/default.nix, now stored in SOPS.
  users.users = {

    root.hashedPasswordFile = config.sops.secrets.root-hashed-password.path;
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
