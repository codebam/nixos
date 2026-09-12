{
  lib,
  appimageTools,
  fetchurl,
  makeWrapper,
  stdenv,
}:

# OpenCode's beta desktop client. nixpkgs' `opencode-desktop` builds the
# released 1.18.x tree, which has no browser host; the beta AppImage is the
# build that pairs with `opencode2` and carries `experimental.browser`, the
# feature the agent's browser.* tools attach to. Upstream publishes no source
# for it (the version is a CI build number, not a git tag), so pin the
# prebuilt AppImage and let appimageTools provide the FHS the bundled Electron
# and the 200 MB `opencode-cli` sidecar expect.
let
  inherit (stdenv.hostPlatform) system;

  version = "0.0.0-beta-19378";

  variants = {
    "x86_64-linux" = {
      appimageName = "linux-x86_64";
      hash = "sha256-F9KSY+OW331Vni1hkIE3juA32E+rlkzYRkGZYx1esFc=";
    };
    "aarch64-linux" = {
      appimageName = "linux-arm64";
      hash = "sha256-e2Kr9kZD8jlb1m7xHsoOoJgGKjnQwZiEdmEOF49D9js=";
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

    install -m 444 -D ${appimageContents}/ai.opencode.desktop.beta.desktop \
      $out/share/applications/ai.opencode.desktop.beta.desktop
    substituteInPlace $out/share/applications/ai.opencode.desktop.beta.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox' 'Exec=opencode-desktop-beta --no-sandbox'

    mkdir -p $out/share
    cp -r ${appimageContents}/usr/share/icons $out/share/
  '';

  meta = {
    description = "OpenCode desktop client (beta channel; pairs with opencode2 and hosts the integrated browser)";
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
