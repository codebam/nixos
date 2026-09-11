{
  lib,
  bashInteractive,
  buildNpmPackage,
  fetchNpmDeps,
  fetchzip,
  makeWrapper,
  nodejs,
}:

let
  # The npm package ships only lib/*.js and package.json; there is no build
  # script, and every native dependency (node-pty, koffi,
  # node-addon-require-builtin) carries its .node in the tarball or in a
  # platform package. So this is an install-only derivation.
  patchManifest = ''
    cp ${./dsh/package-lock.json} package-lock.json

    # The published package.json declares devDependencies on internal
    # @deepseek-ai packages that were never pushed to npm
    # (e.g. dsh-experimental-agent-team), so `npm ci` aborts with ETARGET
    # while resolving the manifest. Installing dsh as a dependency never
    # needs them; delete the block before npm reads it.
    ${lib.getExe' nodejs "node"} -e '
      const fs = require("node:fs");
      const manifest = JSON.parse(fs.readFileSync("package.json", "utf8"));
      delete manifest.devDependencies;
      fs.writeFileSync("package.json", JSON.stringify(manifest, null, 2) + "\n");
    '
  '';
in
buildNpmPackage (finalAttrs: {
  pname = "dsh";
  version = "0.1.5-rc.2";

  src = fetchzip {
    url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${finalAttrs.version}.tgz";
    hash = "sha256-LxvNi+tq8RyezVfMbxoIMxjV5ozp1gLRaxGgReS6R2s=";
  };

  # buildNpmPackage forwards postPatch to fetchNpmDeps but not nativeBuildInputs,
  # and fetchNpmDeps is stdenvNoCC (no node). Spell npmDeps out so patchManifest
  # can run in the fetcher too and the vendored lockfile is visible to it.
  npmDeps = fetchNpmDeps {
    name = "dsh-${finalAttrs.version}-npm-deps";
    inherit (finalAttrs) src;
    nativeBuildInputs = [ nodejs ];
    postPatch = patchManifest;
    hash = "sha256-6+guZX7uLZ/mBzVZvjyYDIyDAankhi/OdFw3DA2KCtY=";
  };

  postPatch = patchManifest;

  # lib/ is prebuilt and the package has no build script.
  dontNpmBuild = true;

  # Nothing needs an install script, and npm rebuild runs offline in the
  # sandbox, so keep it from trying to fetch prebuilds or compile.
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [ makeWrapper ];

  # The web profile sets `patchReload: live`, which makes the launcher mount
  # cordis-plugin-hmr. HMR reaches Node's internal ESM loader through
  # --expose-internals, and its native fallback (node-addon-require-builtin)
  # cannot read V8 internals on Node >= 26. Start node with the flag HMR
  # checks for, which works on every supported Node line.
  #
  # The persistent-shell PTY backend (`dsh-terminal-bash`) defaults its bash
  # executable to /bin/bash, which NixOS does not ship. Every shell call in a
  # preset that mounts the persistent shell therefore dies as "PTY backend
  # startup and cleanup both failed" (the fork execs a missing file, then the
  # rollback's terminate reports its own failure), and the `minimal` preset's
  # only built-in tool is that persistent shell. The one-shot executor already
  # resolves `bash` from PATH, so name the store bash here too; `--replace-fail`
  # keeps an upstream rename from silently restoring the broken default.
  postInstall = ''
    terminal_bash="$out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-terminal-bash/lib/index.js"
    chmod u+w "$terminal_bash"
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
    minimal="$out/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-presets/presets/minimal/agent.cordis.yml"
    chmod u+w "$minimal"
    awk '{ print } /^    prefix: You are a helpful software engineer assistant\.$/ { print "    suffix: Your working directory is {{cwd}}." }' "$minimal" > "$minimal.tmp"
    mv "$minimal.tmp" "$minimal"

    rm -f "$out/bin/dsh"
    makeWrapper ${lib.getExe' nodejs "node"} "$out/bin/dsh" \
      --add-flags "--expose-internals $out/lib/node_modules/@deepseek-ai/dsh/lib/bin.js"
  '';

  meta = {
    description = "DeepSeek Harness CLI: profile boot, plugin management, and the browser UI";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    changelog = "https://github.com/deepseek-ai/deepseek-harness/releases";
    license = lib.licenses.mit;
    mainProgram = "dsh";
    # The closure installs prebuilt .node addons (node-pty, koffi,
    # node-addon-require-builtin) rather than compiling them.
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
