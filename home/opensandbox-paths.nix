# Host paths that are credentials or host control surfaces. The OpenSandbox
# server forces these read-only if a client binds them directly, refuses a bind
# whose source directory contains one, and the dsh plugin uses the same list as
# its ctx.fs protected-path fence. Keep both consumers on this one definition:
# a drift here is a host-read escape.
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
}
