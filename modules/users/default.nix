{ pkgs, ... }:
{
  users = {
    mutableUsers = false;
    users = {
      codebam = {
        isNormalUser = true;
        home = "/home/codebam";
        description = "Sean Behan";
        extraGroups = [
          "wheel"
          "networkmanager"
          "libvirtd"
          "video"
          "uinput"
          "wireshark"
          "pipewire"
          "gamemode"
        ];
        hashedPassword = "$6$TIP8YR83obmkq8T2$T3lYdPbPj9wysMznNlS5J0qHo2eyTr43aF/ZWSMWHdNRob4dkBB0s3KpBLUgYRTyPZxbb1ZgeqCrrx.DEEkQX1";
        packages = [ ];
        shell = pkgs.fish;
        linger = true;
        openssh.authorizedKeys.keys = [
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCo4kxTz34eDK4j/Zazo7AjiUKrMQIFL/PFZ21ipqcjAUjcMK72c7/DL2OqKANJAkYsXD39+wFvjvzoHwBRJ3YciWRxulT+I0yIDwoOYWyWgYWAO/f2pUcPVjcwj4LQ6aoVeINkTqKYrXVbw9t8pJ8R34X7J46kgKW/G4rPKlC7ipAbS0O0dXt95p5SgKx5i4Cn5H/EAumuL3FxweSviPYW53FmXEtaZzkoUbAbBrh6vnWopNZVqBy7ZhS11ca3KVPNv3EEZ6mLQYsvIGhn163S5YLdJfDCXHJ+umFUAO1kqLxSeUqYHyJ5Iz29/64oaviM2ECPEros3gYVE2XR5GDhHU7oGqQ8wiho8KQS2nL/tIBi7eP6hwi0Ho5InXM8O0XhDfq+/WRNCJrEzakrtHygqO+DxM06QlOS1g74MHca+1ZGarY7l2+eKkuoddUPoMoGqRlRFrMH77IwXhYv616iUMz3cXLfbEOVlrZ7FDwJvql0k9ZeDzQMnz66chwHUydlY1waqenr6Qu48a2g9JfXSb0zB2fYBBlV+5wX1YCaZ8fHTi5QA5RK0bFT2EPXvuFdTHBppDbG5HVZI4dIZQ/urY2XVc8hZ6v90A0PW/zGYArG5r3kntWb7e58C2cwY/19y0s/aZu01tepZsBLHsK/ZrpTzgrcwaunaP0Sxl+lwQ== cardno:9_082_676" # yubikey-5c
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDCNeFVxzMGKcckiXZBmDkLsB8yE7zmT88V5GgjJpkkEYnyk7lvJb+zRWYbAW0k5j+Tf1iNWIUy5EFCm5wfqq57PwhaR8TlMmClQQaRUDWotmqkYVKRiFjFIklUMAcmWVjhxqWtJdo8iBX7+S2i74z4ivku6xI+ifQ8Xr5OoNONYJvVa/nfakCWjFLQ51+RnXNEcEV76v/dfG482uvhqubZgjgfYfuWHSUZC65D6LstTrEa/DtAUc/47unFAMm5U9L4C33m7RKS/JllXW47cT0KJBUywYcc6+euzPdQhAVGj8fUKxjRHWIYcuhTSjrDYVgXwasjnHKOmRxlyClSFTD7 cardno:15_606_805" # yubikey-5c-nfc
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFm8MinRasfhAbMOkQhz+/yXgKBgV1N2J98dlLJ70daz" # servercat
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL7yDL3drFmgNAFIaTgoamlGaTBiKdm+eIK8q3JJTpKh codebam@nixos-steamdeck" # nixos-steamdeck
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnwv9Ifx6b82N/oRMCAKYi0vWCDyue9Mkf2Fh8lLidm codebam@nixos-laptop" # nixos-laptop
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEkBfTf9i6kG6P+HGWN3ghszdxQYmXzxllIlxPkwuyCo codebam@nixos-desktop" # nixos-desktop
        ];
      };
    };
  };
}
