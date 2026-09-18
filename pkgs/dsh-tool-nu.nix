{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nodejs,
}:

stdenvNoCC.mkDerivation {
  pname = "dsh-tool-nu";
  version = "0.1.0";

  # @codebam/dsh-tool-nu is published to npm from its own repository; this
  # host pins the reviewed revision so the profile copies exactly the plugin
  # sources it was tested with. The hash is the tag's unpacked-tree hash
  # (nix-prefetch-url --unpack, converted to SRI) and was precomputed from the
  # pushed v0.1.0 tag. This plugin has
  # no dsh-version patch: it uses only the stable ctx.shell request/render
  # surface that dsh 0.1.6-alpha.2 exposes.
  src = fetchFromGitHub {
    owner = "codebam";
    repo = "dsh-tool-nu";
    rev = "v0.1.0";
    hash = "sha256-ojc6O8Ai/r+f1fS5IQc8BoMsmk8/BqOD9WbWTxRLP7c=";
  };

  nativeBuildInputs = [ nodejs ];

  # The published files are the ESM sources; there is no build step.
  dontBuild = true;

  # home/agents.nix copies this directory into $DSH_HOME next to the profile's
  # node_modules symlink, where Node resolves the @deepseek-ai/* peers.
  installPhase = ''
    runHook preInstall
    install -d -m 0755 "$out/lib/dsh-tool-nu"
    cp -r index.mjs package.json src "$out/lib/dsh-tool-nu/"
    cp LICENSE "$out/lib/dsh-tool-nu/"
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
    description = "Model-facing Nushell (nu) tool for the DeepSeek Harness over the existing ctx.shell world";
    homepage = "https://github.com/codebam/dsh-tool-nu";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
