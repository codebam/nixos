{ pkgs, inputs, ... }:
{
  environment.systemPackages = [
    inputs.sops-pass.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
