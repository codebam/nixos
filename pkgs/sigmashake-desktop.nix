{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  copyDesktopItems,
  makeDesktopItem,
  makeWrapper,
  wrapGAppsHook3,
  gdk-pixbuf,
  glib,
  glib-networking,
  gtk3,
  libnotify,
  libsoup_3,
  webkitgtk_4_1,
}:

stdenv.mkDerivation {
  pname = "sigmashake-desktop";
  # Vendor ships a rolling "stable" tarball with no version in the URL.
  # Date is the mtime of the binaries inside the 2025-08-04 release we hashed.
  version = "0-unstable-2025-08-04";

  src = fetchurl {
    url = "https://download.sigmashake.com/desktop/wails/stable-linux-x64-SigmaShakeDesktop.tar.gz";
    hash = "sha256-ncLnacIbqzGUSJxLHXQ7pRv4RXRXZqjBAcioITXonNU=";
  };

  sourceRoot = "SigmaShakeDesktop";

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    gdk-pixbuf
    glib
    glib-networking
    gtk3
    libnotify
    libsoup_3
    webkitgtk_4_1
  ];

  dontConfigure = true;
  dontBuild = true;
  # wrapGAppsHook3 would wrap the store binary in place; we wrap the $out/bin
  # launcher ourselves so PATH still finds the bundled `ssg` next to it.
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    dest=$out/lib/sigmashake-desktop
    mkdir -p "$dest" "$out/bin"
    cp -a SigmaShakeDesktop binaries "$dest/"
    # The Wails binary looks for ./binaries/ssg relative to its own path
    # (and also $PATH). Keep that layout, then put a wrapped launcher on PATH.
    makeWrapper "$dest/SigmaShakeDesktop" "$out/bin/SigmaShakeDesktop" \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : "$dest/binaries"

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "SigmaShakeDesktop";
      desktopName = "SigmaShake Desktop";
      comment = "AI governance and guardrails desktop app";
      exec = "SigmaShakeDesktop";
      icon = "SigmaShakeDesktop";
      categories = [
        "Development"
        "Utility"
      ];
    })
  ];

  meta = {
    description = "AI governance and guardrails desktop app";
    homepage = "https://sigmashake.com";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "SigmaShakeDesktop";
  };
}
