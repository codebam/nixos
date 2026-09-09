{ config, lib, pkgs, ... }:
let
  # userborn (services.userborn.enable) replaces the perl update-users-groups
  # path, and it knows nothing about subUidRanges/subGidRanges -- it just leaves
  # /etc/subuid and /etc/subgid empty. Without those mappings rootless podman
  # fails on any image that chowns files ("no subuid ranges found for user").
  # autoSubUidGidRange is still ignored, so every user that needs subids must
  # set explicit ranges.
  renderRanges =
    field:
    lib.concatStrings (
      lib.mapAttrsToList
        (
          name: user:
          lib.concatMapStrings (
            range: "${name}:${toString range.${field}}:${toString range.count}\n"
          ) user."${if field == "startUid" then "subUidRanges" else "subGidRanges"}"
          # Skip system users with no ranges so /etc/subuid|subgid
          # contain only real mappings, not blank lines.
        )
        (lib.filterAttrs (_: user: user.subUidRanges != [ ] || user.subGidRanges != [ ]) config.users.users)
    );

  subuid = renderRanges "startUid";
  subgid = renderRanges "startGid";
in
{
  environment.etc = {
    subuid.text = subuid;
    subgid.text = subgid;
  };

  # system.etc.overlay does not always materialise these into the live /etc
  # (observed: the symlink exists in the generation and in /.host-etc but the
  # booted /etc had no subuid), which breaks rootless podman on every reboot.
  # Write them directly at boot, before any user service (podman quadlets,
  # jobscrape) can start.
  systemd.services.subuid-mappings = {
    description = "Write /etc/subuid and /etc/subgid for rootless podman";
    wantedBy = [ "multi-user.target" ];
    before = [ "default.target" ];
    after = [ "systemd-remount-fs.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "write-subuid-mappings" ''
        umask 022
        want_uid=${lib.escapeShellArg subuid}
        want_gid=${lib.escapeShellArg subgid}
        # command substitution strips the trailing newline, matching $(cat ...)
        want_uid="$(printf '%s' "$want_uid")"
        want_gid="$(printf '%s' "$want_gid")"
        # environment.etc usually already provides these (read-only). Only write
        # when the content is missing or wrong, so this never fights the
        # read-only etc-overlay entry.
        if [ "$(cat /etc/subuid 2>/dev/null)" != "$want_uid" ]; then
          rm -f /etc/subuid 2>/dev/null || true
          printf '%s' "$want_uid" > /etc/subuid 2>/dev/null || true
        fi
        if [ "$(cat /etc/subgid 2>/dev/null)" != "$want_gid" ]; then
          rm -f /etc/subgid 2>/dev/null || true
          printf '%s' "$want_gid" > /etc/subgid 2>/dev/null || true
        fi
        [ "$(cat /etc/subuid 2>/dev/null)" = "$want_uid" ] || { echo "/etc/subuid is missing or incorrect" >&2; exit 1; }
        [ "$(cat /etc/subgid 2>/dev/null)" = "$want_gid" ] || { echo "/etc/subgid is missing or incorrect" >&2; exit 1; }
      '';
    };
  };
}
