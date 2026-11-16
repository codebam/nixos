{
  lib,
  appimageTools,
  fetchurl,
  stdenv,
}:

# Qwen Code Desktop at the desktop-v0.27.4 release tag -- a separate tag
# line from the CLI's v0.27.4 (pkgs/qwen-code.nix), though this build bundles
# the same 0.27.4 CLI as its runtime sidecar. It is a Wails + WebKitGTK app,
# not Electron: the AppImage carries its own GTK/WebKit stack plus a 339 MB
# qwen-code runtime with a private node, so let appimageTools provide the FHS
# all of that expects rather than patchelf-ing the bundle piecemeal.
#
# Hashes are the release's own SHA256SUMS.txt. The linuxdeploy AppRun hook
# forces GDK_BACKEND=x11 (upstream crashes the WebKitGTK Wayland backend),
# so the window runs under XWayland and needs no ozone flags.
let
  inherit (stdenv.hostPlatform) system;

  version = "0.27.4";

  variants = {
    "x86_64-linux" = {
      appimageArch = "amd64";
      hash = "sha256-5jyB0rqiukcXUF0qhhQ07P2Z/0ewnWuk3MXAaBG/f9Y=";
    };
    "aarch64-linux" = {
      appimageArch = "aarch64";
      hash = "sha256-jthlwwp8gCz9hWqCpPaGyl2PpFpuANd7LfUigHswyfA=";
    };
  };

  variant = variants.${system} or (throw "qwen-code-desktop: no AppImage for ${system}");

  src = fetchurl {
    url = "https://github.com/QwenLM/qwen-code/releases/download/desktop-v${version}/Qwen-Code-Desktop_${version}_${variant.appimageArch}.AppImage";
    inherit (variant) hash;
  };

  appimageContents = appimageTools.extract {
    pname = "qwen-code-desktop";
    inherit version src;
  };
in
appimageTools.wrapType2 {
  pname = "qwen-code-desktop";
  inherit version src;

  # linuxdeploy bundled libgcrypt/libsecret but assumed libgpg-error lives
  # on the host; neither the AppImage nor the default FHS env carries it, so
  # the loader dies at startup without this.
  extraPkgs = pkgs: [ pkgs.libgpg-error ];

  extraInstallCommands = ''
    # The upstream entry already names the wrapped bin and icon; only the
    # file name changes (upstream ships it with spaces in it).
    install -m 444 -D "${appimageContents}/usr/share/applications/Qwen Code Desktop.desktop" \
      $out/share/applications/qwen-code-desktop.desktop

    mkdir -p $out/share
    # The AppImage's icon tree is mode 0555/0444; plain `cp -r` preserves
    # those directory modes and breaks later writes into it.
    cp -r --no-preserve=mode ${appimageContents}/usr/share/icons $out/share/
  '';

  meta = {
    description = "Qwen Code desktop shell for the Web Shell (Wails AppImage, bundles the qwen CLI runtime)";
    homepage = "https://github.com/QwenLM/qwen-code";
    license = lib.licenses.asl20;
    maintainers = [
      {
        name = "codebam";
        github = "codebam";
      }
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "qwen-code-desktop";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
