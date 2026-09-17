{
  config,
  pkgs,
  ...
}:

let
  # The checkout the running system was built from. /etc/nixos is an
  # environment.etc symlink to this path (modules/system/environment.nix);
  # using the real path gives `nix flake` a lock file to rewrite without
  # walking through /etc's overlay, and matches programs.nh.flake.
  flakeDir = "/persistent/etc/nixos";

  flake = "${flakeDir}#${config.networking.hostName}";

  # ExecStartPost for nixos-upgrade. NixOS itself treats a switch as needing a
  # reboot when the booted and built kernel/initrd differ
  # (system.autoUpgrade.allowReboot uses that check); this desktop wants to be
  # told about kernel and firmware changes specifically, so it compares the
  # kernel, its modules, and the firmware. Firmware is compared by a
  # fingerprint of the symlinks in the firmware buildEnv (file name plus the
  # package it comes from, not the store hash): comparing the buildEnv's store
  # path alone would report an update whenever nixpkgs rebuilds it, even when
  # the firmware files did not change.
  rebootRequired = pkgs.writeShellScript "nixos-reboot-required" ''
    set -eu

    readlink=${pkgs.coreutils}/bin/readlink
    find=${pkgs.findutils}/bin/find
    sort=${pkgs.coreutils}/bin/sort
    sha256sum=${pkgs.coreutils}/bin/sha256sum
    cut=${pkgs.coreutils}/bin/cut
    sed=${pkgs.gnused}/bin/sed
    mkdir=${pkgs.coreutils}/bin/mkdir
    rm=${pkgs.coreutils}/bin/rm

    changed_kernel=0
    changed_firmware=0

    for part in kernel kernel-modules; do
      booted="$($readlink -f "/run/booted-system/$part" 2>/dev/null || true)"
      current="$($readlink -f "/run/current-system/$part" 2>/dev/null || true)"
      [ "$booted" = "$current" ] || changed_kernel=1
    done

    # Keep each firmware file's relative name plus the package name it comes
    # from, but drop the store hash. A pure rebuild of an unchanged package
    # moves its store path and would otherwise look like a firmware update;
    # a version bump changes the package name, and added/removed files change
    # the set of relative names.
    firmware_fingerprint() {
      if [ ! -e "$1" ]; then
        echo missing
        return 0
      fi
      "$find" -H "$1" -type l -printf '%P %l\n' 2>/dev/null \
        | "$sed" -E 's#^(.*) /nix/store/[0-9a-z]+-([^/]+)/.*$#\1 \2#' \
        | LC_ALL=C "$sort" \
        | "$sha256sum" \
        | "$cut" -d ' ' -f 1
    }

    booted_firmware="$(firmware_fingerprint /run/booted-system/firmware)"
    current_firmware="$(firmware_fingerprint /run/current-system/firmware)"
    [ "$booted_firmware" = "$current_firmware" ] || changed_firmware=1

    marker=/run/nixos-upgrade/reboot-required

    if [ "$changed_kernel" -eq 0 ] && [ "$changed_firmware" -eq 0 ]; then
      # The running generation already contains this one's kernel and firmware.
      $rm -f "$marker"
      exit 0
    fi

    if [ "$changed_kernel" -eq 1 ] && [ "$changed_firmware" -eq 1 ]; then
      body="Kernel and firmware updates were installed. Reboot to use them."
    elif [ "$changed_kernel" -eq 1 ]; then
      body="A kernel update was installed. Reboot to use it."
    else
      body="A firmware update was installed. Reboot to use it."
    fi

    $mkdir -p /run/nixos-upgrade
    printf '%s\n' "$body" > "$marker"
    ${pkgs.coreutils}/bin/chmod 0644 "$marker"
  '';
in
{
  system.autoUpgrade = {
    enable = true;
    inherit flake;

    operation = "switch";

    # The schedule the desktop used when this was last enabled: sometime in
    # the first ten minutes of the day, caught up on the next boot if the
    # machine was off (persistent defaults to true).
    dates = "daily";
    randomizedDelaySec = "10min";

    # The notification below is the reboot mechanism; never reboot under the
    # user's hands.
    allowReboot = false;

    # --upgrade is a no-op for flake systems in nixos-rebuild-ng and only
    # logs a warning; preStart moves the lock instead.
    upgrade = false;
  };

  systemd.services.nixos-upgrade = {
    # nixos-rebuild switch honours flake.lock; --refresh alone re-checks
    # caches but does not move a locked input. Update every input first.
    preStart = ''
      ${config.nix.package}/bin/nix flake update --flake ${flakeDir}

      # pkgs/ is a second flake with its own lock, and the root flake's
      # lock-sync check requires both to name the same nixpkgs revision.
      # Refresh it from the lock just written; a sync failure must not hold
      # back the actual system rebuild, so it is only a warning.
      ${config.nix.package}/bin/nix flake update \
        --flake ${flakeDir}/pkgs \
        --reference-lock-file ${flakeDir}/flake.lock \
        || echo "warning: could not synchronise pkgs/flake.lock" >&2
    '';

    # Only a successful switch has a new generation to inspect.
    postStart = "${rebootRequired}";
  };
}
