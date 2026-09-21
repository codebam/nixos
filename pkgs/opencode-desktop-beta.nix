{
  lib,
  appimageTools,
  fetchurl,
  makeWrapper,
  stdenv,
}:

# OpenCode's v2 desktop client. nixpkgs' `opencode-desktop` still builds the
# 1.18.x tree, which has no browser host; upstream's 2.0.x desktop AppImage is
# the build that pairs with `opencode2` and carries `experimental.browser`, the
# feature the agent's browser.* tools attach to. Pin the prebuilt AppImage and
# let appimageTools provide the FHS the bundled Electron and the 200 MB
# `opencode-cli` sidecar expect.
#
# The attribute and command keep their historical `-beta` name even though
# upstream promoted this build to 2.0.x. The AppImage reuses the v1 app id, so
# the desktop entry is installed as ai.opencode.desktop.beta.desktop (nixpkgs'
# 1.18.x `opencode-desktop` owns ai.opencode.desktop.desktop) and the icons
# carry the same `.beta` suffix.
let
  inherit (stdenv.hostPlatform) system;

  version = "2.0.12";

  variants = {
    "x86_64-linux" = {
      appimageName = "linux-x86_64";
      hash = "sha256-RA+wAPrnVgaZMdoK6wkDsh4SHCufO14zuwerOP6p8dk=";
    };
    "aarch64-linux" = {
      appimageName = "linux-arm64";
      hash = "sha256-j1NoMFgk3ROQcOnX7/hw4dyt6z4vGrcDqJA0A/ub5sg=";
    };
  };

  variant = variants.${system} or (throw "opencode-desktop-beta: no AppImage for ${system}");

  src = fetchurl {
    url = "https://opencode.ai/files/bin/${version}/opencode-desktop-${variant.appimageName}.AppImage";
    inherit (variant) hash;
  };

  appimageContents = appimageTools.extract {
    pname = "opencode-desktop-beta";
    inherit version src;
  };
in
appimageTools.wrapType2 {
  pname = "opencode-desktop-beta";
  inherit version src;

  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    wrapProgram $out/bin/opencode-desktop-beta \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true --wayland-text-input-version=3}}"

    install -m 444 -D ${appimageContents}/ai.opencode.desktop.desktop \
      $out/share/applications/ai.opencode.desktop.beta.desktop
    substituteInPlace $out/share/applications/ai.opencode.desktop.beta.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox' 'Exec=opencode-desktop-beta --no-sandbox' \
      --replace-fail 'Icon=ai.opencode.desktop' 'Icon=ai.opencode.desktop.beta' \
      --replace-fail 'Name=OpenCode' 'Name=OpenCode (v2)'

    mkdir -p $out/share
    # The AppImage's icon tree is mode 0555/0444; plain `cp -r` preserves those
    # directory modes, which makes the renames below fail with EACCES.
    cp -r --no-preserve=mode ${appimageContents}/usr/share/icons $out/share/
    for icon in $out/share/icons/hicolor/*/apps/ai.opencode.desktop.png; do
      [ -e "$icon" ] || continue
      mv "$icon" "''${icon%.png}.beta.png"
    done
  '';

  meta = {
    description = "OpenCode desktop client (v2 AppImage; pairs with opencode2 and hosts the integrated browser)";
    homepage = "https://opencode.ai";
    license = lib.licenses.mit;
    maintainers = [
      {
        name = "codebam";
        github = "codebam";
      }
    ];
    mainProgram = "opencode-desktop-beta";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
