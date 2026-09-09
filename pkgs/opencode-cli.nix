{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  # x64 only: upstream also ships a -baseline binary for CPUs without AVX2.
  useBaseline ? false,
}:

let
  inherit (stdenv.hostPlatform) system;

  variants = {
    "x86_64-linux" = {
      npmName = "linux-x64";
      hash = "sha256-WxCtciL29EKqI+rBQRYq/J+Mq/AMXQJYMdB3aWPn4Xc=";
      baselineHash = "sha256-gsXNLhsOBSoqXwtSrgXlEQkZ56LzfcttPj7x1ku2lmk=";
    };
    "aarch64-linux" = {
      npmName = "linux-arm64";
      hash = "sha256-YgVUf1sdHRNowa0djyiHR2HQuqiQFX4ap8nxga8Wsjs=";
    };
  };

  variant =
    variants.${system} or (throw "opencode-cli: no @opencode/cli binary package for ${system}");

  pkgSuffix = if useBaseline then "${variant.npmName}-baseline" else variant.npmName;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "opencode-cli";
  version = "0.0.0-beta-19378";

  # The @opencode/cli npm wrapper (upstream command: `opencode2`) ships no
  # runnable code: bin/opencode2.exe is a stub and its postinstall copies the
  # bun-compiled single-file executable out of a platform optionalDependency
  # (@opencode/cli-<os>-<arch>). Pin those tarballs directly and skip the npm
  # layer; nothing else in the closure is interpreted at runtime.
  src = fetchurl {
    url = "https://registry.npmjs.org/@opencode/cli-${pkgSuffix}/-/cli-${pkgSuffix}-${finalAttrs.version}.tgz";
    hash = if useBaseline then variant.baselineHash else variant.hash;
  };

  sourceRoot = "package";

  # The shipped binary asks for the FHS ld.so; autoPatchelf rewrites it to
  # NixOS's and resolves its glibc-only needs (libc, libm, libdl, libpthread).
  nativeBuildInputs = [ autoPatchelfHook ];

  # `bun build --compile` parks a 4-byte absolute pointer to the `.bun` section's
  # vaddr in the alignment slack just after `.data.rel.ro` -- outside every
  # section, so it belongs to no symbol and no relocation. stdenv's fixup `strip`
  # rewrites the file from section contents, zeroing that slack (and clipping the
  # tail off the last PT_LOAD). Without the pointer Bun never finds its embedded
  # graph and silently degrades into the plain `bun` CLI: `opencode2 --version`
  # answers `1.4.2`, `--help` prints Bun's usage, exit status stays 0.
  # patchelf survives because it shifts whole pages instead of repacking gaps.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/opencode2 "$out/bin/opencode2"
    runHook postInstall
  '';

  # Upstream smoke-tests the binary the same way, which proves nothing: the
  # payload-free binary still exits 0, because it is really `bun --version`.
  # Assert the banner so a damaged graph fails the build instead of shipping.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    # The beta opens a log file under $HOME/.local/share/opencode before it
    # answers even `--version`, and the build sandbox points HOME at the
    # non-existent /homeless-shelter.
    export HOME="$PWD"
    version="$($out/bin/opencode2 --version)"
    echo "opencode2 --version: $version"
    if [ "$version" != "opencode2 v${finalAttrs.version}" ]; then
      echo "expected 'opencode2 v${finalAttrs.version}'; a bare bun version here" \
        "means the embedded module graph was damaged during the build (see dontStrip)"
      exit 1
    fi
    runHook postInstallCheck
  '';

  # npm republishes a new beta-<build> essentially daily:
  #   curl -s 'https://registry.npmjs.org/@opencode%2Fcli' | jq -r '."dist-tags".beta'
  # then bump `version` and re-hash every platform tarball (nix hash file on
  # the downloaded .tgz, or nix-prefetch-url on its registry URL).

  meta = {
    description = "AI coding agent terminal CLI (npm @opencode/cli beta channel)";
    homepage = "https://github.com/anomalyco/opencode";
    changelog = "https://github.com/anomalyco/opencode/releases";
    license = lib.licenses.mit;
    mainProgram = "opencode2";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
