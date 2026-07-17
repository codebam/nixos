{ config, pkgs, ... }:

{
  sops = {
    age = {
      keyFile = "/etc/nixos/secrets/identities/yubikey-5c.txt";
    };
    secrets = {
      "unredacted.org" = {
        sopsFile = ../secrets/passwords.enc.yaml;
      };
    };
  };

  systemd.user.services.iamb-login = {
    Unit = {
      Description = "Auto-login for iamb Matrix client";
      After = [ "sops-nix.service" ];
      Requires = [ "sops-nix.service" ];
      ConditionPathExists = "!%h/.local/share/iamb/profiles/unredacted.org/session.json";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "iamb-login-service" ''
        set -euo pipefail
        SECRET_PATH="${config.sops.secrets."unredacted.org".path}"
        if [ -f "$SECRET_PATH" ]; then
          PASSWORD=$(head -n 1 "$SECRET_PATH")
          RESPONSE=$(${pkgs.curl}/bin/curl -s -X POST -H "Content-Type: application/json" \
            -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"codebam\"},\"password\":\"$PASSWORD\"}" \
            https://matrix.unredacted.org/_matrix/client/v3/login)
          if echo "$RESPONSE" | ${pkgs.gnugrep}/bin/grep -q "access_token"; then
            mkdir -p "$HOME/.local/share/iamb/profiles/unredacted.org"
            echo "$RESPONSE" > "$HOME/.local/share/iamb/profiles/unredacted.org/session.json"
          fi
        fi
      ''}";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
