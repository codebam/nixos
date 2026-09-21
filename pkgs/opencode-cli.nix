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
      hash = "sha256-Knm+suJDgssr27cJI328IvSYz1KhBtAppqOjJDdgx4s=";
      baselineHash = "sha256-rHUvYQWO4a2AuTE+LiuUGE2LDocZjEjOXvQ1DSjnpPs=";
    };
    "aarch64-linux" = {
      npmName = "linux-arm64";
      hash = "sha256-M/Dd6fDwVbajZl0pA3G8/Ixj2s6t56U1xLlNOG8r2Rc=";
    };
  };

  variant =
    variants.${system} or (throw "opencode-cli: no @opencode/cli binary package for ${system}");

  pkgSuffix = if useBaseline then "${variant.npmName}-baseline" else variant.npmName;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "opencode-cli";
  version = "2.0.12";

  # The @opencode/cli npm wrapper (upstream command: `opencode`, with an
  # `opencode2` alias) ships no runnable code: bin/opencode.exe is a stub and
  # the postinstall copies the bun-compiled single-file executable out of a
  # platform optionalDependency (@opencode/cli-<os>-<arch>). Pin those tarballs
  # directly and skip the npm layer; nothing else in the closure is interpreted
  # at runtime.
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
    # The 2.0 line renamed the payload from bin/opencode2 to bin/opencode;
    # keep installing it as `opencode2` so this package exposes the command the
    # repo wraps (and `bin/opencode` stays nixpkgs' v1 package).
    install -Dm755 bin/opencode "$out/bin/opencode2"
    runHook postInstall
  '';

  # Upstream smoke-tests the binary the same way, which proves nothing: the
  # payload-free binary still exits 0, because it is really `bun --version`.
  # Assert the banner so a damaged graph fails the build instead of shipping.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    # The binary opens a log file under $HOME/.local/share/opencode before it
    # answers even `--version`, and the build sandbox points HOME at the
    # non-existent /homeless-shelter.
    export HOME="$PWD"
    version="$($out/bin/opencode2 --version)"
    echo "opencode2 --version: $version"
    if [ "$version" != "opencode v${finalAttrs.version}" ]; then
      echo "expected 'opencode v${finalAttrs.version}'; a bare bun version here" \
        "means the embedded module graph was damaged during the build (see dontStrip)"
      exit 1
    fi
    runHook postInstallCheck
  '';

  # npm publishes new releases on the `latest` dist-tag every few days:
  #   curl -s 'https://registry.npmjs.org/@opencode%2Fcli' | jq -r '."dist-tags".latest'
  # then bump `version` and re-hash every platform tarball (nix hash file on
  # the downloaded .tgz, or nix-prefetch-url on its registry URL). Check the
  # tarball's bin/ name, too: the 2.0 line ships bin/opencode. The beta
  # channel's last publish was 0.0.0-beta-19507, so `latest` is the channel to
  # track now.

  meta = {
    description = "AI coding agent terminal CLI (npm @opencode/cli, v2 line)";
    homepage = "https://github.com/anomalyco/opencode";
    changelog = "https://github.com/anomalyco/opencode/releases";
    license = lib.licenses.mit;
    maintainers = [
      {
        name = "codebam";
        github = "codebam";
      }
    ];
    mainProgram = "opencode2";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
