{
  lib,
  stdenvNoCC,
  fetchzip,
  nodejs,
}:

stdenvNoCC.mkDerivation {
  pname = "dsh-opensandbox";
  version = "0.2.1-unstable-2026-09-18";

  # @codebam/dsh-opensandbox 0.2.0 is the published artifact of the
  # `security/mount-boundary` branch: the mount-root boundary (`mountRootFor`
  # no longer binds an arbitrary host directory), the mount-fenced ctx.fs
  # backend, and the human `/directory-add` family. Fetching the npm tarball
  # means the flake runs exactly what npm consumers install; the GitHub branch
  # remains the reviewable source until it is merged upstream.
  src = fetchzip {
    url = "https://registry.npmjs.org/@codebam/dsh-opensandbox/-/dsh-opensandbox-0.2.0.tgz";
    hash = "sha256-l/zsy2o6k8VBiO5zSyA30B1+iUyCgF9FenszUaQ1t7k=";
  };

  # npm 0.2.0 had a single configured workspace root; dsh web sessions in any
  # other project then failed with "path is outside the sandbox mount roots".
  # This is the local 0.2.1 delta until @codebam/dsh-opensandbox@0.2.1 is
  # published to npm: it adds workspaceParents/protectedPaths, per-session
  # sandbox roots, and the session-aware ctx.fs fence. Drop the patch and pin
  # the npm 0.2.1 tarball once the release exists.
  patches = [ ./dsh-opensandbox-per-session.patch ];

  nativeBuildInputs = [ nodejs ];

  # The published files are the ESM sources; there is no build step.
  dontBuild = true;

  # Only the npm package's runtime files are needed. home/agents.nix copies
  # this directory into $DSH_HOME next to the profile's node_modules symlink,
  # where Node resolves the @deepseek-ai/* peers and `ws`.
  installPhase = ''
    runHook preInstall
    install -d -m 0755 "$out/lib/dsh-opensandbox"
    cp -r index.mjs package.json src "$out/lib/dsh-opensandbox/"
    cp LICENSE "$out/lib/dsh-opensandbox/"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    for file in index.mjs src/*.mjs; do
      ${lib.getExe nodejs} --check "$file"
    done
    runHook postInstallCheck
  '';

  meta = {
    description = "OpenSandbox-backed dsh execution world (subprocess, sandbox, and mount-fenced fs providers)";
    homepage = "https://github.com/codebam/dsh-opensandbox";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
