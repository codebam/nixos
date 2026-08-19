{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ssg";
  # Pinned to the linux-x64 default in https://sigmashake.com/install.
  version = "1.1.2";

  src = fetchurl {
    url = "https://download.sigmashake.com/cli/${finalAttrs.version}/ssg-linux-x64.tar.gz";
    hash = "sha256-DzNNajtH71vhfvmH7uM5p6YFuiRIAuqB/SycmtVNUqA=";
  };

  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;
  # Static Go binary: no dynamic section for patchelf, and strip would
  # drop the version string the CLI prints.
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 ssg $out/bin/ssg

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
