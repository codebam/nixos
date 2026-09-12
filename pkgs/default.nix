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
{ pkgs }:
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
  # build needs no network; the binary installs with `--component ripwire` and
  # skills/ + hooks/ are staged under share/ripwire (v0.3.8's CMake predates
  # upstream's own asset install rules), mirroring upstream's install.sh.
  ripwire = pkgs.callPackage ./ripwire.nix { };

  # npm CLI (@zvec/zvec-grep) with no nixpkgs package. The registry tarball
  # ships a prebuilt dist/ but no lockfile, so the derivation pins the upstream
  # tag's package-lock.json and skips install scripts; every native dependency
  # (zvec, onnxruntime, ripgrep, llama.cpp, sharp) arrives prebuilt.
  zvec-grep = pkgs.callPackage ./zvec-grep.nix { };

  # DeepSeek Harness CLI (@deepseek-ai/dsh). The registry tarball has no
  # lockfile and an unpublished devDependencies block, so the derivation
  # vendors a production lockfile and wraps the bin to start node with
  # --expose-internals (its HMR plugin requires it). See pkgs/dsh.nix.
  dsh = pkgs.callPackage ./dsh.nix { };

  # OpenCode's beta CLI from npm (@opencode/cli, command `opencode2`): the
  # derivation pins the registry's per-platform binary tarballs directly.
  opencode-cli = pkgs.callPackage ./opencode-cli.nix { };

  # The beta desktop that pairs with that CLI and hosts the browser the agent's
  # browser.* tools attach to. Only the AppImage exists upstream; see
  # pkgs/opencode-desktop-beta.nix.
  opencode-desktop-beta = pkgs.callPackage ./opencode-desktop-beta.nix { };

  # Polarium Code desktop app. The vendor ships only an AppImage and gates the
  # download behind an account, so there is no URL to pin a hash against:
  # pkgs/polariumcode wraps the AppImage kept at ~/Downloads and extracts it to
  # the user cache at first start (see that file for why it cannot be a plain
  # store fetch).
  polariumcode = pkgs.callPackage ./polariumcode { };
}
