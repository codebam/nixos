# Shared values for the agentic-inbox email MCP (the "@Email agent MCP").
# Imported by home/agents.nix (dsh registration and the .dsh/AGENTS.md
# guardrail) and home/hermes.nix (Hermes registration and its system-prompt
# policy), so the bridge path, endpoint, server name, and send authorization
# rule cannot drift between the two harnesses.
{ config, pkgs }:

{
  # The stdio -> Streamable HTTP bridge built in the agentic-inbox checkout.
  # It runs `wrangler auth token` itself, so no Cloudflare credential is
  # stored in this file or in the Nix store. First run, from that checkout:
  #   npx wrangler login
  # The OAuth token lands in ~/.config/.wrangler, which
  # modules/system/preservation.nix preserves across the root wipe.
  bridge = "${config.home.homeDirectory}/Documents/git/agentic-inbox/scripts/mcp-bridge.mjs";

  # Launcher shared by Hermes' service and dsh's stdio MCP client. Node is
  # addressed by store path, and its bin directory is prepended to PATH so a
  # project-local `wrangler` with a `#!/usr/bin/env node` shebang (or an
  # `npx` fallback) still resolves when the harness unit starts with a
  # minimal environment.
  runner = builtins.toString (
    pkgs.writeShellScript "agentic-inbox-mcp" ''
      export PATH=${pkgs.nodejs_latest}/bin:$PATH
      exec ${pkgs.nodejs_latest}/bin/node "$@"
    ''
  );

  # Streamable HTTP endpoint of the deployed Worker. Keep this in sync with
  # the Worker route / custom domain in agentic-inbox's wrangler.jsonc.
  url = "https://email.codebam.ca/mcp";

  # The MCP server name is the tool namespace in both harnesses. Hermes
  # sanitizes the hyphen, so its tools are `mcp__agentic_inbox__*`; dsh's
  # public names are `mcp__agentic-inbox__*`.
  name = "agentic-inbox";

  # Rendered into each harness's standing instructions. The agentic-inbox
  # server also advertises its own instructions, but Hermes ignores that
  # InitializeResult field and dsh only injects it when the server connects,
  # so the send guardrail has to live in the harness prompt as well.
  policy = ''
    ## Email authorization (agentic-inbox MCP)

    The `agentic-inbox` MCP server can read, draft, and send email. Reading,
    listing, searching, and drafting are always allowed. Sending is not: never
    call `send_email` (or its prefixed `mcp__...__send_email` form), or any
    tool whose name or description sends, replies to, or forwards mail, unless
    the user has explicitly authorized that exact message in the current
    conversation (for example, "send it" after you show the draft).
    Authorization for an earlier message, a standing request to draft, or
    approval of a different draft does not authorize a send. Do not use a
    shell, browser, or another tool to work around this rule. If the
    Wrangler-authenticated bridge is unavailable, report that and ask the
    user to run `wrangler login`; do not search for or use another
    credential. When in doubt, show the draft and ask; do not send.
  '';
}
