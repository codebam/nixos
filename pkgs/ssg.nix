{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ssg";
  version = "1.1.9";

  # The npm package @sigmashake/ssg-linux-x64 lags the release channel (1.1.8
  # at the time of writing), while the vendor's CLI CDN carries the stable
  # pointer and the current 1.1.9 artifact. The tarball root is `./ssg` plus
  # `./public/`, not the npm package's `bin/` layout.
  src = fetchurl {
    url = "https://download.sigmashake.com/cli/${finalAttrs.version}/ssg-linux-x64.tar.gz";
    hash = "sha256-NTBSdf0TAR74VmLsmdxH+zqmhW9bX0V4Z4ND6AX00VY=";
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
    cp -R public $out/bin/public

    runHook postInstall
  '';

  meta = {
    description = "SigmaShake governance CLI for AI coding agents";
    homepage = "https://sigmashake.com";
    license = lib.licenses.unfree;
    maintainers = [
      {
        name = "codebam";
        github = "codebam";
      }
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "ssg";
  };
})
