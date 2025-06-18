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
    (wrapRetroArch {
      cores = with libretro; [
        genesis-plus-gx # Sega
        snes9x # SNES
        beetle-psx-hw # PlayStation
        dolphin # GameCube / Wii
        stella # Atari 2600
        mame # MAME
        mame2000 # MAME
        mame2003 # MAME
        mame2015 # MAME
        mame2016 # MAME
        neocd # Neo ?
        fbneo # Neo ?
        mupen64plus # Nintendo 64
        nestopia # Nintendo NES
        mgba # Game Boy Advance
        fuse # ZX Spectrum
        melonds # Nintendo DS
        desmume # Nintendo DS
        desmume2015 # Nintendo DS
      ];
    })
  ];
}
