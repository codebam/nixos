# @xmanrui/dsh-im: the multi-channel IM bridge for DeepSeek Harness
# (Telegram, WhatsApp, Slack, Discord, Matrix, WeChat, Feishu, ...).
#
# The registry tarball ships prebuilt lib/ but no lockfile, so the derivation
# vendors the lock generated for this exact version (see ./dsh-im/package-lock.json)
# and lets buildNpmPackage assemble the runtime dependency tree offline. The
# result is installed under the scoped name @xmanrui/dsh-im so dsh's profile
# loader can find it by package name, the same way `pnpm add` would.
{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs_24,
}:

buildNpmPackage (finalAttrs: {
  pname = "dsh-im";
  version = "5.10.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@xmanrui/dsh-im/-/dsh-im-${finalAttrs.version}.tgz";
    hash = "sha256-6VGGds9X5K+I/For9Mwtg4BzxXndwMb9JW5yuogznyU=";
  };
  sourceRoot = "package";

  postPatch = ''
    cp ${./dsh-im/package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-xSAx2Bl7SGC/viW9ZUoTmlMgp9YbTNEU+VIJv1YchgM=";

  # lib/ is prebuilt; the package's build script is for source checkouts.
  dontNpmBuild = true;
  # Native install scripts cannot run in the sandbox and nothing here needs
  # them: the heavy channel SDKs ship prebuilt JS/WASM.
  npmFlags = [ "--ignore-scripts" ];
  npmRebuildFlags = [ "--ignore-scripts" ];

  nodejs = nodejs_24;

  postInstall = ''
    # npmInstallHook uses the scoped package name from package.json on newer
    # nixpkgs, but some releases still stage it under `pname`. Accept both.
    if [ -d "$out/lib/node_modules/dsh-im" ]; then
      mkdir -p "$out/lib/node_modules/@xmanrui"
      mv "$out/lib/node_modules/dsh-im" "$out/lib/node_modules/@xmanrui/dsh-im"
    fi
    test -f "$out/lib/node_modules/@xmanrui/dsh-im/lib/index.js"
  '';

  meta = {
    description = "DeepSeek Harness bridge for Telegram and other instant messengers";
    homepage = "https://github.com/xmanrui/dsh-im";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "dsh-im";
  };
})
