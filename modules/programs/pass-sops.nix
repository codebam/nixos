{ pkgs, ... }:
let
  pass-sops = pkgs.writeScriptBin "pass" ''
    #!${pkgs.python3.withPackages (ps: [ ps.pyyaml ps.pyotp ])}/bin/python3
    ${builtins.readFile ./pass-sops.py}
  '';
in
{
  environment.systemPackages = [ pass-sops ];
}
