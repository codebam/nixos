# Antigravity CLI (`agy`): Google's terminal client for the Antigravity agent
# harness. There is nothing to build from source -- the upstream repository
# (github:google-antigravity/antigravity-cli) is release-only, carrying a
# README, CHANGELOG and examples while the CLI itself is a closed Go binary.
# So this fetches the release tarballs, the same artifact the official
# install.sh drops in ~/.local/bin, and packages them the way nixpkgs does.
#
# The pin carries antigravity-cli 1.5.13; this follows upstream 1.5.18 for the
# reason pkgs/qwen-code.nix does -- the closed binary ships fixes that are
# worth more than waiting for a nixpkgs bump. The release assets are
# version-addressed, so unlike the nixpkgs recipe (which walks the GCS
# `latest` manifest for a build id) a bump here only moves `version` and the
# two hashes.
#
# The tarball holds one dynamically linked `antigravity` binary: no assets, no
# sidecars. autoPatchelfHook rewrites its interpreter and glibc reference,
# which is what makes it runnable on NixOS at all. The CLI's own self-updater
# cannot write into the store, so version changes belong here. Its state lives
# in ~/.gemini/antigravity-cli (settings.json, conversations/, cache/), under
# the `.gemini` directory modules/system/preservation.nix already keeps across
# a root wipe.
{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:
let
  version = "1.5.18";

  sources = {
    x86_64-linux = fetchurl {
      url = "https://github.com/google-antigravity/antigravity-cli/releases/download/${version}/agy_cli_linux_x64.tar.gz";
      hash = "sha256-pJYHI+2c9bWscu1UHbjfTWJ0F5UmHrk6RoEAbMsj1a0=";
    };
    aarch64-linux = fetchurl {
      url = "https://github.com/google-antigravity/antigravity-cli/releases/download/${version}/agy_cli_linux_arm64.tar.gz";
      hash = "sha256-l3mauskboLKbd1mLYvkDuGZGHaF2gCY6GC/vLLeWqw0=";
    };
  };
in
stdenvNoCC.mkDerivation {
  pname = "antigravity-cli";
  inherit version;

  strictDeps = true;

  src =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "antigravity-cli: unsupported system ${stdenvNoCC.hostPlatform.system}");

  # The tarball's single member is `antigravity` at the root.
  sourceRoot = ".";

  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isElf [ autoPatchelfHook ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 antigravity $out/bin/agy

    runHook postInstall
  '';

  # `agy --version` prints the bare version and needs no writable HOME, so a
  # bumped tarball that stops matching `version` fails the build instead of
  # shipping quietly.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    versionOutput=$($out/bin/agy --version)
    if [ "$versionOutput" != "${version}" ]; then
      echo "agy --version printed '$versionOutput', expected '${version}'" >&2
      exit 1
    fi

    runHook postInstallCheck
  '';

  meta = {
    description = "Google's terminal client for the Antigravity agent harness";
    homepage = "https://antigravity.google/product/antigravity-cli";
    changelog = "https://github.com/google-antigravity/antigravity-cli/blob/main/CHANGELOG.md";
    license = lib.licenses.unfree;
    maintainers = [
      {
        name = "codebam";
        github = "codebam";
      }
    ];
    platforms = lib.attrNames sources;
    mainProgram = "agy";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
