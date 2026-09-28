# nspady's Google Calendar MCP server (@cocal/google-calendar-mcp), the local
# stdio server behind Hermes' google-calendar MCP row (home/hermes.nix via
# home/google-calendar-mcp.nix). No nixpkgs package.
#
# The registry tarball ships a prebuilt build/ (compiled by the project's own
# scripts/build.js, which the tarball does not include) and no lockfile, so
# the derivation vendors the upstream tag's package-lock.json exactly the way
# pkgs/zvec-grep.nix does, and skips npm scripts: nothing needs compiling and
# no dependency carries an install script.
{
  lib,
  buildNpmPackage,
  fetchurl,
  fetchzip,
  makeWrapper,
  nodejs,
}:

buildNpmPackage (finalAttrs: {
  pname = "google-calendar-mcp";
  version = "2.6.3";

  src = fetchzip {
    url = "https://registry.npmjs.org/@cocal/google-calendar-mcp/-/google-calendar-mcp-${finalAttrs.version}.tgz";
    hash = "sha256-YKjtcP7Ylk4/2dOF3Udx8h8WqOJzaRQlT4jyLX/rSCE=";
  };

  packageLock = fetchurl {
    url = "https://raw.githubusercontent.com/nspady/google-calendar-mcp/v${finalAttrs.version}/package-lock.json";
    hash = "sha256-KFW+3FbElH7GQHztCK0iTwN6BPp9jMh8DJ0HYhF1OLQ=";
  };

  postPatch = ''
    cp ${finalAttrs.packageLock} package-lock.json
  '';

  npmDepsHash = "sha256-aWOLMLiDmtc5R/apz8yUxrYONGELVsEpodgc3/tM/Yg=";

  # build/ is already compiled; the TS sources and scripts/ are not in the
  # registry tarball, so `npm run build` has nothing to run against.
  dontNpmBuild = true;

  # Nothing in the dependency graph needs an install script, and npm rebuild
  # runs offline in a nix build, so keep it from trying to fetch or compile.
  npmFlags = [ "--ignore-scripts" ];
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [ makeWrapper ];

  # npm links the bin as a symlink onto build/index.js, whose shebang reads
  # `#!/usr/bin/env node`; on NixOS that resolves to nothing under Hermes'
  # minimal service environment. Replace the link with the store's node,
  # like pkgs/dsh.nix does, so the bin is self-contained.
  postInstall = ''
    rm -f "$out/bin/google-calendar-mcp"
    makeWrapper ${lib.getExe' nodejs "node"} "$out/bin/google-calendar-mcp" \
      --add-flags "$out/lib/node_modules/@cocal/google-calendar-mcp/build/index.js"
  '';

  meta = {
    description = "Google Calendar MCP server: list, search, create, update, and respond to events over stdio";
    homepage = "https://github.com/nspady/google-calendar-mcp";
    changelog = "https://github.com/nspady/google-calendar-mcp/releases";
    license = lib.licenses.mit;
    maintainers = [
      {
        name = "codebam";
        github = "codebam";
      }
    ];
    mainProgram = "google-calendar-mcp";
    platforms = lib.platforms.linux;
  };
})
