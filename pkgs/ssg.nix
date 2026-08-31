{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ssg";
  version = "1.1.7";

  src = fetchurl {
    url = "https://registry.npmjs.org/@sigmashake/ssg-linux-x64/-/ssg-linux-x64-${finalAttrs.version}.tgz";
    hash = "sha256-gaPvgReHDCCNd/iJuSIjR90ebhCB6MuyNpg80lu+Eco=";
  };

  sourceRoot = "package";

  dontConfigure = true;
  dontBuild = true;
  # Static Go binary: no dynamic section for patchelf, and strip would
  # drop the version string the CLI prints.
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 bin/ssg $out/bin/ssg
    cp -R public $out/bin/public

    runHook postInstall
  '';

  meta = {
    description = "SigmaShake governance CLI for AI coding agents";
    homepage = "https://sigmashake.com";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "ssg";
  };
})
