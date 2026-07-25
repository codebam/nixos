{ pkgs, ... }:

{
  systemd.user.services.iamb-login = {
    Unit = {
      Description = "Auto-login for iamb Matrix client";
      ConditionPathExists = [
        "/run/secrets/unredacted.org"
        "!%h/.local/share/iamb/profiles/unredacted.org/session.json"
      ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "iamb-login-service" ''
        set -euo pipefail
        SECRET_PATH="/run/secrets/unredacted.org"
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
