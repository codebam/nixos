{ pkgs, inputs, ... }:

{
  # The portal routing lives with the compositor, since a version of it that
  # only exists here would have to be rediscovered by anyone else using the
  # flake. Without it screen sharing fails with nothing in any log naming a
  # portal: the ScreenCast interface is never exposed at all.
  # From the rewrite rather than the C build: the two modules differ in one
  # line, which is who answers ScreenCast. The rewrite implements that
  # interface itself — the wlroots portal can only offer monitors — so its
  # module names viewport first and leaves wlr as the fallback.
  imports = [ inputs.viewport-smithay.nixosModules.portal ];
  programs.viewport.portals.enable = true;
  # The same package systemPackages installs below, named so the portal backend
  # is that one rather than whatever the flake defaults to. Without it both end
  # up in the closure, and the portal is answered by a compositor this system
  # does not run.
  programs.viewport.package =
    inputs.viewport-smithay.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # No `cargo` or `gcc` here. Both were system-wide and between them anchored
  # rustc (1.0 GB) and a full gcc (264 MB) in every generation, for toolchains
  # only ever used inside a project. `nix develop` in this flake already
  # provides the Nix ones; anything else belongs in that project's own shell.
  environment.systemPackages = with pkgs; [
    awakened-poe-trade
    # blender-hip
    # inputs.steel.packages.${pkgs.stdenv.hostPlatform.system}.default
    # inputs.lulu.packages.${pkgs.stdenv.hostPlatform.system}.default
    # The rewrite rather than the C build. Both install a binary called
    # `viewport` and would collide; the C one stays a flake input because the
    # portal routing below still comes from it.
    #
    # `.default`, so this follows whichever engine that flake recommends —
    # `.cef` today. The alternative is naming a backend (`.wpe`, `.webkitgtk`,
    # `.chromium`, `.cef`) and being held to it, which is what naming the old
    # `.viewport-smithay` attribute did: it resolved to `.wpe` and quietly kept
    # this system compiling WebKit after the default had moved away from it
    # twice.
    inputs.viewport-smithay.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
