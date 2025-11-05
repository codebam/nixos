{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    steamdeck-firmware
    (pkgs.kodi-wayland.withPackages (
      kodiPkgs: with kodiPkgs; [
        inputstream-adaptive
      ]
    ))
    protonup-qt
    maliit-keyboard
    maliit-framework
  ];
}
