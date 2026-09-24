# Host paths that are credentials or host control surfaces. The OpenSandbox
# server forces these read-only if a client binds them directly, refuses a bind
# whose source directory contains one, and the dsh plugin uses the same list as
# its ctx.fs protected-path fence. Keep every consumer on this one definition:
# a drift here is a host-read escape.
#
# allowedHostPaths is the other half of the same contract: the server rejects
# binds whose source is outside every prefix. The generated server config
# (home/opensandbox.nix [storage]) and the Hermes backend plugin's workspace
# pre-check (home/hermes-opensandbox.nix) both consume it, so a workspace one
# accepts is the one the other mounts.
{ home }:
rec {
  readonlyHostPaths = [
    "/nix/store"
    "/etc/nix"
    "/nix/var/nix"
    "/run/user/1000/gnupg"
    "${home}/.gnupg"
    "${home}/.ssh"
    "${home}/.dsh"
    "${home}/.config/git"
    "${home}/.config/gh"
    "${home}/.config/sops"
    "${home}/.config/dsh-sandbox"
  ];

  allowedHostPaths = [
    home
    "/persistent"
    "/tmp"
    "/nix/store"
    "/etc/nix"
    "/nix/var/nix"
    "/run/user/1000/gnupg"
  ];
}
