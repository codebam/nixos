{
  lib,
  fetchurl,
  fetchzip,
  buildNpmPackage,
}:

buildNpmPackage (finalAttrs: {
  pname = "zvec-grep";
  version = "0.2.1";

  # The published tarball ships a prebuilt dist/ but no package-lock.json,
  # so grab the lockfile the upstream tag has and copy it in via postPatch
  # (buildNpmPackage forwards the patch hooks to fetchNpmDeps as well).
  src = fetchzip {
    url = "https://registry.npmjs.org/@zvec/zvec-grep/-/zvec-grep-${finalAttrs.version}.tgz";
    hash = "sha256-Z4aPTvNbjt+U4I6AykKlLi54y0js0fewciD+BRoe6Sg=";
  };

  packageLock = fetchurl {
    url = "https://raw.githubusercontent.com/zvec-ai/zvec-grep/v${finalAttrs.version}/package-lock.json";
    hash = "sha256-n4cC+0MAi51msVYB9Iep2TZkK0GXD4pqBHASYmkDviQ=";
  };

  postPatch = ''
    cp ${finalAttrs.packageLock} package-lock.json
  '';

  npmDepsHash = "sha256-pc04qzhnYaS0xpQAYwN6HEG8oPEqoBIBMVKC1OZ0L+8=";

  # dist/ is already compiled; npm run build would need the TS sources.
  dontNpmBuild = true;

  # Everything native (zvec bindings, onnxruntime, ripgrep, llama.cpp, sharp)
  # ships as prebuilt platform optionalDependencies, so no install scripts
  # need to run -- and node-llama-cpp's postinstall would try to hit the
  # network from the sandbox otherwise.
  npmFlags = [ "--ignore-scripts" ];

  meta = {
    description = "Agent-friendly hybrid workspace search across code and non-code content";
    homepage = "https://github.com/zvec-ai/zvec-grep";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "zg";
  };
})
