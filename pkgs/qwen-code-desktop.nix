{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  autoPatchelfHook,
  cargo-tauri,
  nodejs_22,
  pkg-config,
  wrapGAppsHook3,
  glib-networking,
  libsoup_3,
  openssl,
  webkitgtk_4_1,
  ada,
  c-ares,
  libuv,
  llhttp,
  simdjson,
  sqlite,
  uvwasi,
  qwen-code,
}:

# Qwen Code Desktop at the desktop-v0.28.0 release tag, built from source.
# The prebuilt AppImage this replaces bundled its own WebKitGTK, which died
# at startup with EGL_BAD_PARAMETER against the host graphics drivers; this
# build links nixpkgs' webkitgtk_4_1 instead, so the shell uses the same
# graphics stack as every other GTK app on the system.
#
# The shell is a thin Tauri 2 wrapper: it spawns `qwen serve` from a bundled
# runtime and opens the daemon-served Web Shell. The runtime is assembled
# from the CLI this flake already builds plus nodejs_22 (.nvmrc major 22):
# qwen-code's share/qwen-code is exactly the dist/ + production node_modules
# layout the upstream prepare-runtime.js stages into lib/, node-pty prebuilds
# included. The desktop release line lags the CLI line -- desktop-v0.28.0
# (2026-11-17) is still the newest desktop release, three days older than CLI
# v0.28.3 -- so the shell tag stays at the latest desktop release while the
# bundled runtime follows the flake's CLI. That is the same deliberate reuse
# as before, just with versions that no longer coincide, and manifest.json
# records both (qwenCodeVersion/qwenCodeCommit name the runtime, not the
# shell tag). v0.28.3's release notes claim no breaking changes for the
# serve/Web Shell contract.
# cargo-tauri.hook bundles a deb whose usr/lib/<productName>/runtime/qwen-code
# layout is what Tauri's resource_dir() resolves against the installed bin,
# so no QWEN_DESKTOP_RUNTIME_DIR override is needed. The home-manager wrapper
# disables the updater: a /nix/store copy cannot apply updates.
let
  version = "0.28.0";

  # The bundled CLI runtime's commit (v0.28.3); upstream's manifest.json
  # carries it as qwenCodeCommit. The desktop shell's own tag points at the
  # desktop-v0.28.0 commit only because the desktop line has not caught up.
  commit = "99fcf89892f1a3a8027c75468546c7e7be906245";

  desktopTarget =
    {
      "x86_64-linux" = "linux-x64";
      "aarch64-linux" = "linux-arm64";
    }
    .${stdenv.hostPlatform.system};
in
rustPlatform.buildRustPackage {
  pname = "qwen-code-desktop";
  inherit version;

  src = fetchFromGitHub {
    owner = "QwenLM";
    repo = "qwen-code";
    tag = "desktop-v${version}";
    hash = "sha256-OrIaWuLstQS+LZCgNzK+h4ianRd+/TigdA6nszzntek=";
  };

  cargoRoot = "packages/desktop/src-tauri";
  buildAndTestSubdir = "packages/desktop/src-tauri";
  cargoHash = "sha256-Py3Q0yRt/8WWfY69zHe9jXB6QVrs2H3yIKn9gWXhh8U=";

  # cargoCheckHook re-runs tauri-build's build script in the host target dir
  # (target/release, not the --target one the build used), where its copy of
  # the ~1 GB runtime resources dies with EACCES. The tauri build and deb
  # bundle themselves succeed; nixpkgs' other Tauri packages disable checks
  # for the same class of check-context failure.
  doCheck = false;

  # The hook's own postFixup hook would run after the checksum stamping below
  # and invalidate it again; run it explicitly at the top of postFixup instead.
  dontAutoPatchelf = true;

  postPatch = ''
    # The release workflow stamps the tag version into the conf; the checked-in
    # 0.0.1 is a dev placeholder. createUpdaterArtifacts needs the upstream
    # signing key we do not have, and the store copy cannot self-update anyway.
    substituteInPlace packages/desktop/src-tauri/tauri.conf.json \
      --replace-fail '"version": "0.0.1"' '"version": "${version}"' \
      --replace-fail '"createUpdaterArtifacts": true' '"createUpdaterArtifacts": false'

    # The window is built in code (the conf's windows list is empty), and
    # tao's GTK backend draws a light HeaderBar ribbon on Wayland: client-side
    # decorations that ignore xdg-decoration and duplicate the compositor's
    # own frame. Drop them on Linux; macOS keeps its overlay titlebar. The
    # replacement's continuation lines sit four spaces past the block's common
    # indent so Nix's stripping leaves them at Rust's four.
    substituteInPlace packages/desktop/src-tauri/src/main.rs \
      --replace-fail '    let window = window_builder.build()?;' '    #[cfg(target_os = "linux")]
        let window_builder = window_builder.decorations(false);
        let window = window_builder.build()?;'
  '';

  nativeBuildInputs = [
    autoPatchelfHook
    cargo-tauri.hook
    pkg-config
    wrapGAppsHook3
  ];

  buildInputs = [
    glib-networking
    libsoup_3
    openssl
    webkitgtk_4_1
    # The prebuilt node addons in the CLI's node_modules (node-pty, sharp,
    # libvips) ship with an empty RPATH and need libstdc++. buildRustPackage
    # does not run autoPatchelfHook on its own, so it is in nativeBuildInputs
    # and resolves them from here during fixup.
    stdenv.cc.cc.lib
    # nixpkgs' node links these shared libs. auto-patchelf rebuilds node's
    # RPATH from what it can find rather than keeping the original, so they
    # must be findable here or the rewritten RPATH drops them and node dies.
    # This pin's versions are the ones nodejs_22 was built against.
    ada
    c-ares
    libuv
    llhttp
    simdjson
    sqlite
    uvwasi
  ];

  # Assemble the runtime the Tauri bundle lists under bundle.resources before
  # the hook pushd's into cargoRoot. Mirrors scripts/prepare-runtime.js minus
  # the build (qwen-code already built it) and the node download (nodejs_22).
  preBuild = ''
    runtimeRoot=packages/desktop/runtime/qwen-code
    mkdir -p "$runtimeRoot/bin" "$runtimeRoot/lib" "$runtimeRoot/node"
    cp -a ${qwen-code}/share/qwen-code/. "$runtimeRoot/lib/"
    cp -a ${nodejs_22}/. "$runtimeRoot/node/"
    # cp -a preserves the store's 0444/0555 modes; tauri-build copies the
    # resources during the build script and needs a writable tree.
    chmod -R u+w "$runtimeRoot"
    cp LICENSE "$runtimeRoot/LICENSE"
    cp packages/desktop/NOTICE "$runtimeRoot/NOTICE"

    cat > "$runtimeRoot/bin/qwen" <<'LAUNCHER'
    #!/usr/bin/env sh
    set -e
    ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
    exec "$ROOT/node/bin/node" "$ROOT/lib/cli-entry.js" "$@"
    LAUNCHER
    chmod 755 "$runtimeRoot/bin/qwen"

  '';

  # fixupPhase strips and patchelfs the runtime ELFs after the deb unpacks,
  # so stamp manifest.json and checksums.json onto the installed tree, not
  # the staged one -- upstream's patchelf-immutable-runtime.sh exists because
  # rewriting the ELFs invalidates checksums taken before the rewrite.
  postFixup = ''
    autoPatchelf -- "$out"

    RUNTIME_ROOT="$out/lib/Qwen Code Desktop/runtime/qwen-code" \
    DESKTOP_VERSION="${version}" \
    QWEN_VERSION="${qwen-code.version}" \
    QWEN_COMMIT="${commit}" \
    DESKTOP_TARGET="${desktopTarget}" \
    ${nodejs_22}/bin/node -e '
      const fs = require("node:fs");
      const path = require("node:path");
      const crypto = require("node:crypto");
      const root = process.env.RUNTIME_ROOT;
      const walk = (dir) =>
        fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
          e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]
        ).sort();
      const checksums = {};
      for (const file of walk(root)) {
        const rel = path.relative(root, file).split(path.sep).join("/");
        if (rel === "checksums.json") continue;
        checksums[rel] = crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
      }
      fs.writeFileSync(path.join(root, "checksums.json"), JSON.stringify(checksums, null, 2) + "\n");
      fs.writeFileSync(path.join(root, "manifest.json"), JSON.stringify({
        name: "@qwen-code/qwen-code",
        desktopVersion: process.env.DESKTOP_VERSION,
        qwenCodeVersion: process.env.QWEN_VERSION,
        qwenCodeCommit: process.env.QWEN_COMMIT,
        target: process.env.DESKTOP_TARGET,
        node: "v" + process.versions.node,
        builtAt: new Date().toISOString(),
      }, null, 2) + "\n");
    '
  '';

  postInstall = ''
    # Tauri names the deb entry after the product name, spaces included;
    # install it under the identifier the icon and WMClass already use.
    if [ -f "$out/share/applications/Qwen Code Desktop.desktop" ]; then
      mv "$out/share/applications/Qwen Code Desktop.desktop" \
        $out/share/applications/qwen-code-desktop.desktop
    fi
  '';

  meta = {
    description = "Qwen Code desktop shell for the Web Shell (Tauri, built from source with the qwen CLI runtime)";
    homepage = "https://github.com/QwenLM/qwen-code";
    license = lib.licenses.asl20;
    maintainers = [
      {
        name = "codebam";
        github = "codebam";
      }
    ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    mainProgram = "qwen-code-desktop";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
