{ pkgs, lib, ... }:

{
  # A second Navidrome client, because cliamp locks up. termsonic has no
  # environment-variable configuration path -- server, user and password come
  # from one TOML file -- so the file itself is a sops template rendered in
  # desktop/configuration/sops.nix and named here by its path.
  #
  # Named `-config` explicitly rather than letting termsonic find
  # ~/.config/termsonic.toml: the rendered file lives on tmpfs under
  # /run/secrets and must not be copied into $HOME. The in-app config editor
  # (the last tab) cannot save against it, which only costs the colour
  # settings; stylix does not theme termsonic either way.
  home.packages = [
    (pkgs.writeShellApplication {
      name = "termsonic";
      text = ''
        exec ${lib.getExe pkgs.termsonic} \
          -config /run/secrets/rendered/termsonic.toml "$@"
      '';
      meta.description = "termsonic, pointed at the local Navidrome with credentials from sops";
    })
  ];
}
