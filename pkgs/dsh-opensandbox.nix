{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nodejs,
}:

stdenvNoCC.mkDerivation {
  pname = "dsh-opensandbox";
  version = "0.1.0-unstable-2026-09-15";

  # @codebam/dsh-opensandbox is published to npm from its own repository; this
  # host pins the revision that revalidates a cached sandbox against the
  # lifecycle server, so a server-reaped sandbox (its TTL expired) is replaced
  # instead of every later command failing on the dead execd endpoint.
  src = fetchFromGitHub {
    owner = "codebam";
    repo = "dsh-opensandbox";
    rev = "59d51bb40e28bb832abbec4a19616556365e8a47";
    hash = "sha256-6c+TGowy5MjGvPofVp7uH2hwmqXfmOXlNd9U3nJLowQ=";
  };

  # dsh 0.1.6 changed the provider seams this plugin implements: confine
  # became cancellable-async, SubprocessRuntime gained terminalEnvironment,
  # SubprocessTerminalHandle gained resize and terminalType, and a missing
  # executable must throw SubprocessExecutableNotFoundError so the new Web
  # terminal's shell discovery can skip absent candidates. Drop this patch
  # when upstream main carries the same changes and bump rev instead.
  patches = [ ./dsh-opensandbox-dsh016.patch ];

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
    description = "OpenSandbox-backed dsh execution world (subprocess + sandbox providers)";
    homepage = "https://github.com/codebam/dsh-opensandbox";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
