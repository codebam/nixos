{
  lib,
  fetchzip,
  buildNpmPackage,
  makeWrapper,
  nodejs,
  autoPatchelfHook,
  stdenv,
}:

buildNpmPackage (finalAttrs: {
  pname = "zvec-grep";
  version = "0.3.0";

  # Since 0.3.0 the published tarball is a wrapper around a Rust native
  # binary: bin/zg.exe is a stub shell script and the postinstall
  # (install.cjs) materializes the real binary from the exact-version
  # platform optional dependency (@zvec/zvec-grep-linux-x64-gnu and friends,
  # which carry bin/zg plus lib/ runtime libraries and a checksums.json the
  # installer verifies). The tarball ships no package-lock.json and the
  # v0.3.0 tag's root lockfile is still the old TypeScript tree's (0.2.1,
  # dist/cli/index.js), so vendor a generated production lockfile next to
  # this file (from the tarball manifest with
  # `npm install --package-lock-only --omit=dev --ignore-scripts`) and copy
  # it in via postPatch (buildNpmPackage forwards the patch hooks to
  # fetchNpmDeps as well).
  src = fetchzip {
    url = "https://registry.npmjs.org/@zvec/zvec-grep/-/zvec-grep-${finalAttrs.version}.tgz";
    hash = "sha256-/bU2Wzq+6gftfEsh29w1IVM7JL3wPE48IYcqEjfuGEE=";
  };

  postPatch = ''
    cp ${./zvec-grep/package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-p0V/GfntIfMjT4Njl9osE8aAkV/kk31I1MVSHKJZ9X0=";

  # The native binary is prebuilt in the platform optional dependency; there
  # is nothing to compile here.
  dontNpmBuild = true;

  # Unlike 0.2.x, the install script MUST run: it is what replaces the
  # bin/zg.exe stub with the real binary (see above). Keep it offline and
  # deterministic instead: `cpu` skips the NVIDIA detection and the CUDA
  # component downloads it would otherwise attempt, and
  # ZG_INSTALL_SKIP_AGENT_UPGRADE opts out of the postinstall migration of
  # user-level agent launch configurations, which has no business running
  # (or depending on $HOME) in a store build.
  env = {
    ZG_INSTALL_ACCELERATOR = "cpu";
    ZG_INSTALL_SKIP_AGENT_UPGRADE = "1";
  };

  npmFlags = [ "--legacy-peer-deps" ];

  # The materialized zg.exe is a prebuilt ELF asking for the FHS ld.so;
  # autoPatchelf rewrites it to NixOS's (its other needs are the bundled
  # lib/ libraries, found through its $ORIGIN/../lib RPATH, plus the C++
  # runtime, supplied here).
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [ stdenv.cc.cc ];

  # The install script's materialized payload does not survive the install
  # hook: its copy step only carries the package.json `files` entries (bin/,
  # install.cjs, ...) into $out, so the lib/ runtime libraries and the
  # native-install.json receipt the installer writes beside bin/zg.exe are
  # dropped and the binary cannot find libzvec_c_api.so ($ORIGIN/../lib).
  # Re-run the installer against the installed tree, after the hook has
  # copied it, so bin/, lib/ and the receipt land in $out together.
  postInstall = ''
    meta="$out/lib/node_modules/@zvec/zvec-grep"
    chmod -R u+w "$meta"
    (cd "$meta" && ${lib.getExe' nodejs "node"} install.cjs)

    # npm's bin wrapper execs node on bin/zg.exe, which is an ELF binary
    # since 0.3.0 (it was a JS entry point in 0.2.x). Replace it with a
    # wrapper that execs the binary directly.
    rm -f "$out/bin/zg"
    makeWrapper "$meta/bin/zg.exe" "$out/bin/zg"
  '';

  # The node-wrapper break above shipped silently as a build that succeeded
  # and a `zg` that died in Node's parser; assert the real binary answers.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$PWD"
    version="$($out/bin/zg --version | head -n 1)"
    echo "zg --version: $version"
    case "$version" in
      "${finalAttrs.version}"|*"zvec-grep ${finalAttrs.version}"*) ;;
      *)
        echo "expected zg --version to name ${finalAttrs.version}" >&2
        exit 1
        ;;
    esac
    runHook postInstallCheck
  '';

  meta = {
    description = "Native semantic and lexical code search CLI";
    homepage = "https://github.com/zvec-ai/zvec-grep";
    license = lib.licenses.asl20;
    maintainers = [
      {
        name = "codebam";
        github = "codebam";
      }
    ];
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "zg";
  };
})
