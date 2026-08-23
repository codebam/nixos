{ pkgs, lib, ... }:

{
  # Navidrome credentials reach cliamp as environment variables rather than as
  # a `[navidrome]` block in ~/.config/cliamp/config.toml. The password is a
  # sops secret, so it cannot live in a store-readable file, and cliamp writes
  # that config back itself (the browser's album sort order is saved on every
  # change), so a read-only store symlink is not an option either. cliamp only
  # falls back to NAVIDROME_* when the config block is unset, which it is.
  home.packages = [
    (pkgs.writeShellApplication {
      name = "cliamp";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        pass_file=/run/secrets/navidrome-password

        # Missing or still unreadable (first boot after adding the secret):
        # start anyway, minus the Navidrome provider, rather than refusing to
        # play local files and radio.
        if [ -r "$pass_file" ]; then
          NAVIDROME_URL="http://localhost:4533/navidrome"
          NAVIDROME_USER="codebam"
          NAVIDROME_PASS=$(head -n 1 "$pass_file")
          export NAVIDROME_URL NAVIDROME_USER NAVIDROME_PASS
        fi

        exec ${lib.getExe pkgs.cliamp} "$@"
      '';
      meta.description = "cliamp, pointed at the local Navidrome with credentials from sops";
    })
  ];
}
