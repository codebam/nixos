{
  lib,
  stdenvNoCC,
  fetchzip,
  nodejs,
}:

stdenvNoCC.mkDerivation {
  pname = "dsh-opensandbox";
  version = "0.2.2";

  # @codebam/dsh-opensandbox 0.2.2 is the published artifact of upstream
  # `main`: 0.2.1's mount-root boundary (`mountRootFor` no longer binds an
  # arbitrary host directory), per-session workspace roots for dsh web, the
  # mount-fenced ctx.fs backend, and the human `/directory-add` family, plus
  # the dsh profile bundle declaration (`dsh.bundle.patch` ->
  # `cordis.patch.yml`) that lets the Plugins page list and switch the whole
  # world. Fetching the npm tarball means the flake runs exactly what npm
  # consumers install; `main` remains the reviewable source.
  src = fetchzip {
    url = "https://registry.npmjs.org/@codebam/dsh-opensandbox/-/dsh-opensandbox-0.2.2.tgz";
    hash = "sha256-zI2nAC7T4hIeNwYB7H+lUPrOpuq6N0PBnByTQoHyYtQ=";
  };

  nativeBuildInputs = [ nodejs ];

  # The published files are the ESM sources; there is no build step.
  dontBuild = true;

  # The npm package's runtime files plus the bundle patch. home/agents.nix
  # copies this directory into $DSH_HOME next to the profile's node_modules
  # symlink, where Node resolves the @deepseek-ai/* peers and `ws`.
  # `cordis.patch.yml` ships next to index.mjs because package.json's
  # `dsh.bundle.patch` declaration names it relative to the package root.
  installPhase = ''
    runHook preInstall
    install -d -m 0755 "$out/lib/dsh-opensandbox"
    cp -r index.mjs package.json src "$out/lib/dsh-opensandbox/"
    cp cordis.patch.yml "$out/lib/dsh-opensandbox/"
    cp LICENSE "$out/lib/dsh-opensandbox/"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    for file in index.mjs src/*.mjs; do
      ${lib.getExe nodejs} --check "$file"
    done
    # The bundle declaration in package.json must resolve from the install
    # prefix, not just from the unpacked source tree.
    test -f "$out/lib/dsh-opensandbox/cordis.patch.yml"
    runHook postInstallCheck
  '';

  meta = {
    description = "OpenSandbox-backed dsh execution world (subprocess, sandbox, and mount-fenced fs providers)";
    homepage = "https://github.com/codebam/dsh-opensandbox";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
