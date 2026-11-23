# Local Matrix appservice -> DeepSeek Harness bridge. No npm dependencies:
# the service is a single Node ESM script using only node:* builtins. It is
# fed events by matrix-workers' appservice transaction push, so the Matrix
# channel needs no /sync long polling (and no long-poll Durable Object cost).
{
  lib,
  nodejs_24,
  writeShellApplication,
}:

writeShellApplication {
  name = "matrix-bridge";
  runtimeInputs = [ nodejs_24 ];
  text = ''
    exec ${lib.getExe' nodejs_24 "node"} ${./matrix-bridge/bridge.mjs} "$@"
  '';

  meta = {
    description = "Matrix appservice webhook bridge for DeepSeek Harness";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
