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

  # No upstream tarball: the transport and its test live here, and the three
  # protocol modules come from the pinned dsh plugin so both harness families
  # send identical control messages. Keeping one definition of the keystroke
  # and scroll vocabulary is the point of the coupling.
  dontUnpack = true;

  nativeBuildInputs = [ nodejs ];

  installPhase = ''
    runHook preInstall

    install -d -m 0755 "$out/bin" "$out/lib/mcp-viewport/src"
    install -m 0755 ${./mcp-viewport/server.mjs} "$out/lib/mcp-viewport/server.mjs"
    install -m 0644 ${./mcp-viewport/test.mjs} "$out/lib/mcp-viewport/test.mjs"
    for module in messages keys render; do
      install -m 0644 ${dsh-tool-viewport}/lib/dsh-tool-viewport/src/$module.mjs "$out/lib/mcp-viewport/src/$module.mjs"
    done

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
