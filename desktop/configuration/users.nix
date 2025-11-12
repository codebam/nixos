{ pkgs, ... }:

{
  users.users.makano = {
    isNormalUser = true;
    home = "/home/makano";
    description = "Makano";
    packages = [ ];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAf5Y0VAO2dyCseCQ0gyNaTUIzNJj885bYyX03v0vSS4 makano@nixos"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFpzbhkbHB3jZPdMKuNRBjAgsslCeILJE+BmSYWcht1 makano@Dush"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEkBfTf9i6kG6P+HGWN3ghszdxQYmXzxllIlxPkwuyCo codebam@nixos-desktop" # nixos-desktop
    ];
  };
}
