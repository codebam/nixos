{ pkgs, inputs, ... }:

{
  # The session module rather than the hand-rolled portal wiring this file
  # used to carry: `enable` installs the package, the display-manager session
  # entry, seatd, polkit, the lock screen's PAM policy and the portal routing
  # — ScreenCast answered by the compositor itself, wlr the fallback — in one
  # place upstream, where anyone else using the flake gets the same.
  imports = [ inputs.viewport.nixosModules.default ];

  programs.viewport = {
    enable = true;

    # The bootstrap config stays the user's: home/viewport.nix writes
    # ~/.config/viewport/config.json (the stylix wallpaper, the screenshot
    # bindings, the OLED gradient). --config names the one file the
    # compositor reads, so a generated one would shadow it, not merge with it.
    userConfig = true;

    # The chromium backend's engine, named: nixpkgs' Google Chrome rather
    # than chromium — same Blink, same DevTools protocol. The wrapper sets
    # VIEWPORT_CHROMIUM_BIN with --set-default, so the environment can still
    # override it at runtime.
    chromiumBinary = "${pkgs.google-chrome}/bin/google-chrome-stable";
  };

  # No `cargo` or `gcc` here. Both were system-wide and between them anchored
  # rustc (1.0 GB) and a full gcc (264 MB) in every generation, for toolchains
  # only ever used inside a project. `nix develop` in this flake already
  # provides the Nix ones; anything else belongs in that project's own shell.
  environment.systemPackages = [
    # blender-hip
    # inputs.steel.packages.${pkgs.stdenv.hostPlatform.system}.default
    # inputs.lulu.packages.${pkgs.stdenv.hostPlatform.system}.default
    # Viewport itself is installed by the module above.
  ];
}
