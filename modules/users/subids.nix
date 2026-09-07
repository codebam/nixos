{ config, lib, ... }:
let
  # userborn (services.userborn.enable) replaces the perl update-users-groups
  # path, and it knows nothing about subUidRanges/subGidRanges -- it just leaves
  # /etc/subuid and /etc/subgid empty. Without those mappings rootless podman
  # fails on any image that chowns files ("no subuid ranges found for user").
  # Render both files ourselves from the declared ranges. autoSubUidGidRange is
  # still ignored, so every user that needs subids must set explicit ranges.
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
in
{
  environment.etc = {
    subuid.text = renderRanges "startUid";
    subgid.text = renderRanges "startGid";
  };
}
