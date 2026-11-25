{
  lib,
  stdenvNoCC,
  bash,
  nodejs,
  dsh-tool-viewport,
  grim,
}:

stdenvNoCC.mkDerivation {
  pname = "mcp-viewport";
  version = "0.1.0";

  # No upstream tarball: the transport and its test live here, and the pinned
  # dsh plugin's whole src/ directory is copied in so both harness families
  # send identical control messages. Keeping one definition of the keystroke
  # and scroll vocabulary is the point of the coupling, and copying the
  # directory rather than naming modules means a module the plugin adds
  # later arrives with the pin instead of breaking this build.
  dontUnpack = true;

  nativeBuildInputs = [ nodejs ];

  installPhase = ''
    runHook preInstall

    install -d -m 0755 "$out/bin" "$out/lib/mcp-viewport/src"
    install -m 0755 ${./mcp-viewport/server.mjs} "$out/lib/mcp-viewport/server.mjs"
    install -m 0644 ${./mcp-viewport/test.mjs} "$out/lib/mcp-viewport/test.mjs"
    # The plugin ships no build step and its src/ is the published source, so
    # copy it whole: the layout and file modes are the plugin's own, and no
    # module can be forgotten here when the pinned tag adds one.
    cp -r --preserve=mode "${dsh-tool-viewport}/lib/dsh-tool-viewport/src/." "$out/lib/mcp-viewport/src/"

    # The control socket trusts only the binary the session runs, so the
    # launcher names the live system path, not a different store build. grim
    # is an ordinary client and is pinned to this closure.
    printf '#!%s\nexport MCP_VIEWPORT_BIN=%s\nexport MCP_VIEWPORT_GRIM=%s\nexec %s %s "$@"\n' \
      ${lib.getExe bash} \
      ${lib.escapeShellArg "/run/current-system/sw/bin/viewport"} \
      ${lib.escapeShellArg (lib.getExe grim)} \
      ${lib.getExe nodejs} \
      "$out/lib/mcp-viewport/server.mjs" \
      > "$out/bin/mcp-viewport"
    chmod +x "$out/bin/mcp-viewport"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${lib.getExe nodejs} "$out/lib/mcp-viewport/test.mjs"
    runHook postInstallCheck
  '';

  meta = {
    description = "MCP stdio server for computer use on a live Viewport desktop (screenshot, pointer, click, scroll, type, keys)";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
