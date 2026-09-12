{
  lib,
  stdenv,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  appimageTools,
  coreutils,

  # Libraries the AppImage needs but does not ship, plus the ones it *does*
  # ship that must still come from nixpkgs. The bundled libwayland/libX11 are a
  # second copy from a different build, and handing mesa a wl_display that was
  # allocated by another libwayland makes EGL fail with BAD_PARAMETER ("Could
  # not create default EGL display"), which takes the WebKit web process with
  # it. Putting the nixpkgs copies first makes the app, WebKit and mesa share a
  # single instance of each.
  libgbm,
  libglvnd,
  mesa,
  wayland,
  libx11,
  libxcb,
  fontconfig,
  freetype,
  fribidi,
  harfbuzz,
  zlib,
  expat,
  libdrm,
  libgpg-error,
  krb5,
  e2fsprogs,
  gmp,
  libXi,
  libxkbcommon,
  libXScrnSaver,
  libXtst,
  xkeyboard-config,

  # The vendor ships only an AppImage, and it is behind an account-gated
  # download (polarium.dev/api/agent/download needs a ticket), so there is no
  # URL to fetchurl and nothing to pin a hash against. The launcher therefore
  # runs the AppImage the user already has, extracted to the user cache on
  # first start. Override POLARIUMCODE_APPIMAGE or these for a different file.
  appimageDir ? "$HOME/Downloads",
  appimageName ? "PolariumCode_0.3.3_linux-x86_64.AppImage",
}:

let
  runtimeLibs = lib.makeLibraryPath [
    libgbm
    libglvnd
    mesa
    wayland
    libx11
    libxcb
    fontconfig
    freetype
    fribidi
    harfbuzz
    zlib
    expat
    libdrm
    libgpg-error
    krb5
    e2fsprogs
    gmp
    libXi
    libxkbcommon
    libXScrnSaver
    libXtst
  ];
in
stdenv.mkDerivation {
  pname = "polariumcode";
  version = "0.3.3";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    makeWrapper
    copyDesktopItems
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cat > $out/bin/polariumcode <<'LAUNCHER'
    #!/usr/bin/env bash
    set -euo pipefail

    image="''${POLARIUMCODE_APPIMAGE:-@appimageDir@/@appimageName@}"
    if [ ! -f "$image" ]; then
      printf 'polariumcode: no AppImage at %s\n' "$image" >&2
      printf 'Set POLARIUMCODE_APPIMAGE to the file to run.\n' >&2
      exit 1
    fi

    # Extract once per content hash into the user cache. The build cannot do
    # this: the AppImage is not in the store, only on this machine.
    hash="$(sha256sum "$image" | cut -d' ' -f1)"
    cachedir="''${XDG_CACHE_HOME:-$HOME/.cache}/polariumcode"
    appdir="$cachedir/$hash"
    if [ ! -x "$appdir/usr/bin/polariumcode-app" ]; then
      tmp="$appdir.tmp.$$"
      rm -rf "$tmp"
      mkdir -p "$(dirname "$tmp")"
      appimage-exec.sh -x "$tmp" "$image" >/dev/null
      rm -rf "$appdir"
      mv "$tmp" "$appdir"
    fi

    # The app opens its login URL with xdg-open. Whatever xdg-open launches --
    # the browser, or the portal helper that launches it -- must NOT inherit
    # the AppImage's private environment below: with the bundled Ubuntu
    # libraries on LD_LIBRARY_PATH the browser dies before it starts
    # ("libz.so.1: cannot open shared object file"), which is why sign-in never
    # opened a tab. Put a shim first on PATH that drops those and calls the
    # real opener. Resolve the real one now, before the shim dir is on PATH.
    real_xdg_open="$(command -v xdg-open 2>/dev/null || true)"
    if [ -n "$real_xdg_open" ]; then
      mkdir -p "$cachedir/bin"
      cat > "$cachedir/bin/xdg-open" <<SHIM
    #!/bin/sh
    # Hand the URL to the system opener with the AppImage's private environment
    # removed, so the browser it starts is a normal, working browser.
    unset LD_LIBRARY_PATH GIO_EXTRA_MODULES
    unset GDK_PIXBUF_MODULE_FILE GTK_IM_MODULE_FILE GTK_PATH GTK_EXE_PREFIX GTK_DATA_PREFIX
    unset GSETTINGS_SCHEMA_DIR GDK_BACKEND
    unset APPDIR APPIMAGE OWD
    exec "$real_xdg_open" "\$@"
    SHIM
      chmod +x "$cachedir/bin/xdg-open"
      export PATH="$cachedir/bin:$PATH"
    fi

    # The AppImage's own AppRun forces GDK_BACKEND=x11 and puts the bundled
    # libraries first, which is what breaks it on this machine. Run the payload
    # directly instead, with the layout the gtk plugin expects and with the
    # AppImage's private helper processes still resolvable (WebKit looks for
    # them relative to usr/, so the working directory has to be usr/).
    export APPIMAGE="$image" OWD="$PWD"
    export APPDIR="$appdir"
    export GTK_DATA_PREFIX="$appdir"
    export GTK_EXE_PREFIX="$appdir/usr"
    export GTK_PATH="$appdir/usr/lib/x86_64-linux-gnu/gtk-3.0"
    export GTK_IM_MODULE_FILE="$appdir/usr/lib/x86_64-linux-gnu/gtk-3.0/3.0.0/immodules.cache"
    export GDK_PIXBUF_MODULE_FILE="$appdir/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders.cache"
    export GIO_EXTRA_MODULES="$appdir/usr/lib/x86_64-linux-gnu/gio/modules"
    export GSETTINGS_SCHEMA_DIR="$appdir/usr/share/glib-2.0/schemas"
    export XDG_DATA_DIRS="$appdir/usr/share:''${XDG_DATA_DIRS:-/usr/share}"
    export XKB_CONFIG_ROOT="@xkb@/share/X11/xkb"
    export LD_LIBRARY_PATH="@runtimeLibs@:$appdir/usr/lib:''${LD_LIBRARY_PATH:-}"

    cd "$appdir/usr"
    exec "$appdir/usr/bin/polariumcode-app" "$@"
    LAUNCHER

    substituteInPlace $out/bin/polariumcode \
      --replace-fail '@appimageDir@' '${appimageDir}' \
      --replace-fail '@appimageName@' '${appimageName}' \
      --replace-fail '@xkb@' '${xkeyboard-config}' \
      --replace-fail '@runtimeLibs@' '${runtimeLibs}'
    chmod +x $out/bin/polariumcode

    wrapProgram $out/bin/polariumcode \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          appimageTools.appimage-exec
        ]
      }

    install -Dm644 ${./PolariumCode.png} \
      $out/share/icons/hicolor/256x256/apps/polariumcode.png

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "polariumcode";
      desktopName = "PolariumCode";
      comment = "Polarium Code desktop app";
      exec = "polariumcode %U";
      icon = "polariumcode";
      categories = [ "Development" ];
      startupWMClass = "polariumcode-app";
    })
  ];

  meta = {
    description = "Polarium Code desktop app, launched from the vendor's AppImage";
    homepage = "https://polarium.dev";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "polariumcode";
    platforms = [ "x86_64-linux" ];
  };
}
