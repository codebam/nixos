# One registration for the Viewport computer-use MCP server, imported by
# home/agents.nix (qwen, opencode, pi) so the server name, argv and standing
# guidance cannot drift between harnesses. dsh keeps its native `viewport`
# plugin instead; this is the bridge for the others.
{ pkgs }:

let
  name = "viewport";
  argv = [ "${pkgs.mcp-viewport}/bin/mcp-viewport" ];
in
{
  inherit name argv;

  # Typing is a batch of up to 4000 control messages; the server's own batch
  # budget caps at five minutes, so the client timeout has to reach that far.
  timeoutMs = 300000;

  guidance = ''
    ## Viewport desktop control (viewport MCP)

    The `viewport` MCP server drives the actual desktop this harness runs on.
    The tool is named `viewport`: `mcp__viewport__viewport` in Qwen Code and
    pi, `viewport_viewport` in opencode (pi registers it through the lazy
    `mcp` proxy, so `mcp({ search: "viewport" })` first).

    Its screenshots are the live screen and its clicks, wheel turns and
    keystrokes land in the real session a person is sitting at. Screenshot
    first, act in small steps, screenshot again to check, and keep the user
    told what you are about to do to their screen. Coordinates are layout
    pixels of the whole desktop, (0, 0) at the screenshot's top-left corner.
    If no Viewport session is running, the tool reports the client's own error;
    say so rather than reaching for another input path.
  '';
}
