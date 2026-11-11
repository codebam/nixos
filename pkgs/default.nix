# Every local derivation, defined once and read by both consumers: the NixOS
# overlay in modules/system/nixpkgs.nix and the flake's `packages` output.
# Two callPackages would be two derivations for the same tool, and pinentry's
# `pinentry-program` is a store path, so they must resolve to the same one.
#
# Import with a pkgs whose `callPackage` resolves the dependencies:
#
#   import ./pkgs { pkgs = final; }        # inside an overlay
#   import ./pkgs { pkgs = ...; }          # from flake.nix
#
# `voxtype-plainify.nix` is deliberately absent: it is not a derivation, it
# returns the sed program string that home/voxtype.nix wraps itself.
# `prev` is the pre-overlay nixpkgs set. It is only needed by wrappers that
# re-export a nixpkgs package under the same attribute name, so they can name
# the original instead of recursing into the wrapper being defined.
{
  pkgs,
  prev ? pkgs,
}:
{
  # Home-manager both installs this and names it in a tmux popup binding.
  agent-overview = pkgs.callPackage ./agent-overview.nix { };

  # Vendor ships a prebuilt Wails + WebKitGTK tarball, no nixpkgs package.
  # Not installed right now; the CLI is.
  sigmashake-desktop = pkgs.callPackage ./sigmashake-desktop.nix { };

  # Named by both the system gnupg.agent and codebam's home-manager one.
  pinentry-auto = pkgs.callPackage ./pinentry-auto.nix {
    terminal = pkgs.ghostty;
  };

  # Official CLI from https://sigmashake.com/install (static Go binary).
  ssg = pkgs.callPackage ./ssg.nix { };

  # Zero-dependency C++23 CLI + MCP server that hands coding agents a ranked,
  # deterministic call-graph map of a repo. All deps vendored in-tree, so the
  # build needs no network; the binary installs with `--component ripwire`, and
  # that component also stages skills/ + hooks/ under share/ripwire, mirroring
  # upstream's install.sh.
  ripwire = pkgs.callPackage ./ripwire.nix { };

  # npm CLI (@zvec/zvec-grep) with no nixpkgs package. Since 0.3.0 the tarball
  # is a Rust native-binary wrapper: its postinstall materializes the platform
  # binary from an exact-version optional dependency, and it ships no lockfile
  # (the tag's root lockfile is the old TypeScript tree's), so the derivation
  # vendors a generated production lockfile like pkgs/cf.nix does. See
  # pkgs/zvec-grep.nix for why the install script must run.
  zvec-grep = pkgs.callPackage ./zvec-grep.nix { };

  # nspady's Google Calendar MCP server (@cocal/google-calendar-mcp): the
  # stdio server behind the google-calendar tools in home/hermes.nix. The
  # registry tarball ships a prebuilt build/ and no lockfile, so like
  # zvec-grep the derivation vendors the upstream tag's package-lock.json.
  google-calendar-mcp = pkgs.callPackage ./google-calendar-mcp.nix { };

  # Cloudflare's agentic CLI (npm `cf`, open beta): every Cloudflare API
  # operation plus Workers projects. The registry tarball ships no lockfile
  # and unpublishable devDependencies, so the derivation vendors a production
  # lockfile; see pkgs/cf.nix.
  cf = pkgs.callPackage ./cf.nix { };

  # Microsoft's Playwright MCP server, wrapped around the nixpkgs package so
  # it uses the Chromium-only browser farm instead of the all-browser farm
  # (which on older pins tries and fails to build playwright-webkit). See
  # pkgs/playwright-mcp.nix.
  playwright-mcp = pkgs.callPackage ./playwright-mcp.nix {
    base = prev.playwright-mcp;
  };

  # mcp-proxy is the stdio->HTTP bridge in front of the shared agent-memory
  # server, so a broken build here breaks every harness. Its 0.13.0 release
  # requires mcp<2 and imports APIs mcp 2.x deleted, while this pin's
  # python3Packages.mcp is 2.2.0 -- the build dies in pythonRuntimeDepsCheck
  # ("mcp<2,>=1.27.1 not satisfied by version 2.2.0"). Relaxing that check
  # would build and then fail at import, so rebuild it against a 1.x mcp
  # instead, which is what nixpkgs did upstream (NixOS/nixpkgs#578877). Both
  # halves live here because the pin predates that fix; see pkgs/mcp-1.nix.
  mcp-proxy = prev.mcp-proxy.overridePythonAttrs (_: {
    dependencies = [
      prev.python3Packages.httpx-auth
      (prev.python3Packages.callPackage ./mcp-1.nix { })
      prev.python3Packages.uvicorn
    ];
  });

  # DeepSeek Harness CLI (@deepseek-ai/dsh). The 0.2.2-rc.2 release was never
  # published to npm, so the derivation builds the release tarballs from the
  # GitHub tag and installs those; it also wraps the bin to start node with
  # --expose-internals (its HMR plugin requires it). See pkgs/dsh.nix.
  dsh = pkgs.callPackage ./dsh.nix { };

  # dsh's model-facing Nushell (`nu`) tool. It consumes the existing ctx.shell
  # provider (bash-sandbox in dsh's built-in world), so the stock bash tool and
  # execution world stay mounted; home/agents.nix copies it into $DSH_HOME next
  # to the profile's node_modules. Pinned in its own repository so it stays
  # independently publishable to npm.
  dsh-tool-nu = pkgs.callPackage ./dsh-tool-nu.nix { };

  # OpenCode's v2 CLI from npm (@opencode/cli, installed as `opencode2`): the
  # derivation pins the registry's per-platform binary tarballs directly.
  opencode-cli = pkgs.callPackage ./opencode-cli.nix { };

  # The v2 desktop that pairs with that CLI and hosts the browser the agent's
  # browser.* tools attach to. Upstream ships it as a prebuilt AppImage; see
  # pkgs/opencode-desktop-beta.nix.
  opencode-desktop-beta = pkgs.callPackage ./opencode-desktop-beta.nix { };

  # Polarium Code desktop app. The vendor ships only an AppImage and gates the
  # download behind an account, so there is no URL to pin a hash against:
  # pkgs/polariumcode wraps the AppImage kept at ~/Downloads and extracts it to
  # the user cache at first start (see that file for why it cannot be a plain
  # store fetch).
  polariumcode = pkgs.callPackage ./polariumcode { };
}
