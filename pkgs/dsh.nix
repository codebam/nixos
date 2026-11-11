{
  lib,
  stdenv,
  stdenvNoCC,
  bashInteractive,
  cacert,
  fetchFromGitHub,
  fetchPnpmDeps,
  makeWrapper,
  nodejs,
  pnpm_11,
  pnpmConfigHook,
}:

let
  pname = "dsh";
  version = "0.2.2-rc.2";

  # 0.2.2-rc.2's GitHub release is out, but the manual `Release publish (dsh)`
  # workflow that uploads its tarballs to npm had not run when this pin was
  # written, so there is no `@deepseek-ai/dsh@0.2.2-rc.2` tarball to install
  # (npm's newest is 0.2.2-rc.1). Build the release tarballs from the tag here
  # instead: the same `build:official` + `release:pack` stages the publish
  # workflow runs, then an ordinary npm install of the packed output.
  #
  # Pin the commit rather than the tag: the tag is what the release page names,
  # the commit is what it points at. Bumping the version means re-deriving four
  # hashes: src, pnpmDeps, and the install outputHash below; build each with an
  # empty hash and copy the "got: sha256-..." value out of the mismatch.
  rev = "ddac96760b6edf8fa0fe17cbdcf0b512f4c12b2c";

  src = fetchFromGitHub {
    owner = "deepseek-ai";
    repo = "deepseek-harness";
    inherit rev;
    hash = "sha256-lbRmFifO6+8YKn8kaR7gQzKeUQh9YBFu9wH/dWJ+3MA=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 5;
    hash = "sha256-8GQ1IYvDx7FTlZCgYRZHomjDMZ8kJCK4BqIy1QAiG8Y=";
  };

  # The upstream release-publish workflow's `pack` job, reproduced: build the
  # official artifacts, pack the `dsh` and `vendor` release families, and pack
  # the Landlock entry that `dsh-sandbox-local` depends on. Reproducing it
  # rather than inventing an install keeps the package on the exact bytes the
  # npm publish would have uploaded.
  packs = stdenv.mkDerivation {
    pname = "${pname}-packs";
    inherit version src pnpmDeps;

    nativeBuildInputs = [
      nodejs
      pnpm_11
      pnpmConfigHook
    ];

    env = {
      DSH_TELEMETRY_DISABLED = "1";
      # There is no .git in the unpacked source. The client build record embeds
      # the commit, and the build scripts fall back to this variable when the
      # worktree has no Git metadata.
      DSH_CLIENT_COMMIT_HASH = rev;
    };

    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR

      # --serial keeps the gate graph well under the build's memory budget;
      # the pack step is I/O bound and runs its own bounded concurrency.
      pnpm run build:official --serial
      pnpm run release:pack --family dsh --out dist/npm --concurrency 8
      pnpm run release:pack --family vendor --out dist/npm-vendor --concurrency 8
      pnpm --dir native/system run build:ts
      pnpm --dir native/system/packages/entry pack --pack-destination "$PWD/dist/npm-landlock"

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r dist $out/dist
      runHook postInstall
    '';

    meta.description = "Packed npm tarballs for the dsh ${version} release";
  };

  # npm consumes the packed tarballs, and every third-party dependency of those
  # tarballs (commander, zod, koffi, ...) still comes from the registry. That
  # install is the one network stage, so it is a fixed-output derivation: the
  # hash pins the installed tree while the sandbox is allowed the network.
  install = stdenvNoCC.mkDerivation {
    pname = "${pname}-npm-install";
    inherit version;

    nativeBuildInputs = [
      nodejs
      cacert
    ];

    impureEnvVars = lib.fetchers.proxyImpureEnvVars;

    # No src: everything comes from the packed output. The default unpack
    # phase would otherwise fail looking for $src.
    dontUnpack = true;

    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      export npm_config_cache=$TMPDIR/npm-cache
      export npm_config_loglevel=warn

      mkdir app
      tar -xzf ${packs}/dist/npm/deepseek-ai-dsh-${version}.tgz -C app --strip-components=1
      node ${./dsh/gen-consumer.mjs} app \
        ${packs}/dist/npm ${packs}/dist/npm-vendor ${packs}/dist/npm-landlock

      # --ignore-scripts: every native dependency ships prebuilt (node-pty,
      # koffi via its @koromix platform package, node-addon-system via the
      # Landlock entry), and the only install script that matters on this
      # package, subprocess-local's spawn-helper chmod, is macOS-only.
      #
      # --before pins the registry ranges to what existed when the tag was cut,
      # so a later rebuild resolves the same versions even after upstream
      # publishes newer releases; without it the fixed-output hash would drift.
      ( cd app && npm install --omit=dev --ignore-scripts --no-audit --no-fund --package-lock=false \
          --before=2026-11-11T02:32:18.000Z )

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      mv app $out/app
      # npm's hidden lockfile records the throwaway install, not the payload.
      rm -f $out/app/node_modules/.package-lock.json
      # The manifest's file: URLs name the packed-tarball store paths. Replace
      # them with the versions npm installed: a fixed-output derivation may not
      # reference other store paths.
      node ${./dsh/finalize-manifest.mjs} $out/app
      runHook postInstall
    '';

    # The install tree is data: no shebang/ELF rewriting here, because the
    # rewritten interpreter paths would be store references. The wrapping
    # derivation runs the normal fixup on its own copy instead.
    dontFixup = true;

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-RhnVXBJ+TqfB3va3Z0Fq6rkmbDG8E5TLlx3BcJbaVQ4=";

    meta.description = "Installed npm tree for dsh ${version}";
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  # nodejs lets the fixup phase rewrite the install tree's `#!/usr/bin/env node`
  # shebangs to the store Node; makeWrapper builds the launcher.
  nativeBuildInputs = [
    makeWrapper
    nodejs
  ];

  # No src: the tree to patch and wrap is the fixed-output install above.
  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/node_modules/@deepseek-ai $out/bin
    cp -r ${install}/app $out/lib/node_modules/@deepseek-ai/dsh
    chmod -R u+w $out/lib/node_modules/@deepseek-ai/dsh

    # The base bundle mounts @deepseek-ai/dsh-hmr (the `hmr` row, enabled
    # wherever a profile composes), and the HMR service refuses to start
    # without --expose-internals on the node argv. HMR reads Node's internal
    # modules through that flag first and falls back to
    # node-addon-require-builtin; dsh-app-boot's profile resolution goes
    # straight through the addon, and that addon cannot read V8 internals on
    # Node >= 26 or against Nix's Node builds. Start node with the flag HMR
    # checks for, and read those internals through createRequire in
    # dsh-app-boot instead of the addon -- the exposed-internals require path
    # works on every supported Node line.
    #
    # The persistent-shell PTY backend (`dsh-terminal-bash`) defaults its bash
    # executable to /bin/bash, which NixOS does not ship. Every shell call in a
    # preset that mounts the persistent shell therefore dies as "PTY backend
    # startup and cleanup both failed" (the fork execs a missing file, then the
    # rollback's terminate reports its own failure), and the `minimal` preset's
    # only built-in tool is that persistent shell. The one-shot executor already
    # resolves `bash` from PATH, so name the store bash here too; `--replace-fail`
    # keeps an upstream rename from silently restoring the broken default.
    for app_boot in \
      "$out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-app-boot/lib/index.js" \
      "$out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-app-boot/lib/worker/profile-resolution-bootstrap.js"
    do
      substituteInPlace "$app_boot" \
        --replace-fail 'createRequire(import.meta.url)("node-addon-require-builtin")' \
          'createRequire(import.meta.url)' \
        --replace-fail 'addon.requireBuiltin(' \
          'addon('
    done

    terminal_bash="$out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-terminal-bash/lib/index.js"
    substituteInPlace "$terminal_bash" \
      --replace-fail 'const DEFAULT_BASH_SHELL = "/bin/bash";' \
        "const DEFAULT_BASH_SHELL = \"${lib.getExe bashInteractive}\";"

    # `minimal` also suppresses runtime context and fixes its persona to one
    # line, so nothing tells the model where the session's workspace is. Its
    # second tool is the zvec-grep index, whose `root` must be a daemon-visible
    # absolute path, and a session with no cwd guesses roots (/workspace, /app,
    # /home, ...) and reports the index missing even though one exists at the
    # workspace. State the cwd the way `standard` does; drop this block to keep
    # the preset's shipped training prompt byte-for-byte.
    #
    # 0.2.x moved the shipped presets out of dsh-agent-presets: each is now a
    # `@deepseek-ai/dsh-agent-preset` declaration row in dsh-web-app's
    # presets/<id>.patch.yml, and `minimal`'s persona row lives in
    # presets/minimal.patch.yml. Insert the suffix line after the prefix line,
    # matching that file's indentation.
    minimal="$out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-web-app/presets/minimal.patch.yml"
    awk '{ print } /^              prefix: You are a helpful software engineer assistant\.$/ { print "              suffix: Your working directory is {{cwd}}." }' "$minimal" > "$minimal.tmp"
    mv "$minimal.tmp" "$minimal"

    makeWrapper ${lib.getExe' nodejs "node"} "$out/bin/dsh" \
      --add-flags "--expose-internals $out/lib/node_modules/@deepseek-ai/dsh/lib/bin.js"

    runHook postInstall
  '';

  meta = {
    description = "DeepSeek Harness CLI: profile boot, plugin management, and the browser UI";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    changelog = "https://github.com/deepseek-ai/deepseek-harness/releases";
    license = lib.licenses.mit;
    maintainers = [
      {
        name = "codebam";
        github = "codebam";
      }
    ];
    mainProgram = "dsh";
    # The install ships prebuilt addons and binaries from npm packages
    # (node-pty, koffi, node-addon-system's Landlock launcher) rather than
    # compiling them in this derivation.
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    # The source build's fixed-output hashes are host-specific, and this flake
    # only defines x86_64 hosts.
    platforms = [ "x86_64-linux" ];
  };
}
