{
  lib,
  buildNpmPackage,
  fetchNpmDeps,
  fetchzip,
  nodejs,
}:

let
  # The npm package ships a prebuilt dist/ and no lockfile, and the published
  # package.json's devDependencies point at file:../../vendor paths that only
  # exist in the upstream monorepo, so `npm ci` cannot resolve the manifest as
  # published. Installing cf never needs them; delete the block before npm
  # reads it, and vendor a production lockfile next to this file (generated
  # from the manifest with that same block removed) so fetchNpmDeps caches
  # only what cf runs with.
  patchManifest = ''
    cp ${./cf/package-lock.json} package-lock.json

    ${lib.getExe' nodejs "node"} -e '
      const fs = require("node:fs");
      const manifest = JSON.parse(fs.readFileSync("package.json", "utf8"));
      delete manifest.devDependencies;
      fs.writeFileSync("package.json", JSON.stringify(manifest, null, 2) + "\n");
    '
  '';
in
buildNpmPackage (finalAttrs: {
  pname = "cf";
  version = "1.0.0-beta.10";

  # cf is on the open beta and publishes often. When bumping: regenerate
  # pkgs/cf/package-lock.json from the new tarball (drop devDependencies as
  # above, then `npm install --package-lock-only --omit=dev`) and refresh
  # both hashes (`nix-prefetch-url --unpack` for this one; a build's
  # hash-mismatch message for the npm-deps one).
  src = fetchzip {
    url = "https://registry.npmjs.org/cf/-/cf-${finalAttrs.version}.tgz";
    hash = "sha256-xhVhC1ezcuvtCvGVf2sgBL1pD9LR2vP/pD/GKeQIxBg=";
  };

  # buildNpmPackage forwards postPatch to fetchNpmDeps but not nativeBuildInputs,
  # and fetchNpmDeps is stdenvNoCC (no node). Spell npmDeps out so patchManifest
  # can run in the fetcher too and the vendored lockfile is visible to it.
  npmDeps = fetchNpmDeps {
    name = "cf-${finalAttrs.version}-npm-deps";
    inherit (finalAttrs) src;
    nativeBuildInputs = [ nodejs ];
    postPatch = patchManifest;
    hash = "sha256-bhdS6FK38gW5POtlGBtPKQDPjvveGo4qGQAZYkXgxYw=";
  };

  postPatch = patchManifest;

  # dist/ is prebuilt by the release (tsdown-bundled) and the package has no
  # build script. Nothing needs an install script either -- miniflare/workerd,
  # blake3-wasm, and sharp ship as prebuilt platform optionalDependencies --
  # so keep npm rebuild from trying to fetch prebuilds or compile outside the
  # sandbox network.
  dontNpmBuild = true;
  npmRebuildFlags = [ "--ignore-scripts" ];

  # Assert the banner and the externalized-dependency graph: the bundle
  # imports part of its runtime from node_modules (minisearch for `cf cli
  # search`, miniflare/workerd for local dev), so a broken production install
  # fails the build instead of shipping.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    # The build sandbox points HOME at the non-existent /homeless-shelter;
    # give cf a writable one in case it probes its config directory.
    export HOME="$PWD"
    # Keep the search check offline-deterministic.
    export DO_NOT_TRACK=1

    version="$($out/bin/cf --version | head -n 1)"
    echo "cf --version: $version"
    case "$version" in
      *"cf · v${finalAttrs.version}"*) ;;
      *)
        echo "expected the version banner to name v${finalAttrs.version}" >&2
        exit 1
        ;;
    esac

    search="$($out/bin/cf cli search "create a dns record")"
    case "$search" in
      "["*"]") ;;
      *)
        echo "cf cli search did not return a JSON array:" >&2
        echo "$search" >&2
        exit 1
        ;;
    esac
    runHook postInstallCheck
  '';

  meta = {
    description = "Cloudflare's agentic CLI for the entire Cloudflare API (open beta)";
    homepage = "https://github.com/cloudflare/cf";
    changelog = "https://github.com/cloudflare/cf/releases";
    license = [
      lib.licenses.mit
      lib.licenses.asl20
    ];
    maintainers = [
      {
        name = "codebam";
        github = "codebam";
      }
    ];
    mainProgram = "cf";
    # The closure installs prebuilt platform binaries (workerd, sharp's
    # libvips) rather than compiling them.
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
