# AGENTS.md — NixOS flake (codebam)

Personal NixOS + home-manager flake for three hosts: `nixos-desktop`,
`nixos-laptop`, `nixos-steamdeck`. `README.md` is the human map of hosts,
services, and layout; this file is the working contract for agents. Keep it
short — the harness injects it into every session in this repository, and a
broader file is dropped before a more specific one when the budget is hit.

## Hard rules

- **Never switch, boot, or test the system.** Do not run `nh os switch`,
  `nixos-rebuild switch`, `nixos-rebuild boot`, or `nixos-rebuild test`.
  Build and report; activation is the human's call.
- **Verify with a build before claiming success.** Evaluate and build a host
  without activating it:
  `nixos-rebuild build --flake .#nixos-desktop` (also `.#nixos-laptop`,
  `.#nixos-steamdeck`). `nix flake check` is the full gate — it builds `lint`
  and every host — but it is slow; use it when the change is broad.
- **Format and lint what you touch.** `nix fmt` runs nixfmt-tree. The `lint`
  check runs `deadnix --fail .` and `statix check .`; leave both clean.
- **Secrets never go into the store or into git.** Values live in the
  SOPS-encrypted `secrets/secrets.yaml`, keys in `.sops.yaml`. Read or edit with
  `sops secrets/secrets.yaml`; never decrypt into a tracked file.
- **`mutableUsers = false`.** Users, groups, and passwords are declarative. A
  manual `useradd`/`passwd` does not survive and is the wrong fix.
- Leave generated or machine-local paths alone: `.direnv/`, `cache/`, `result`,
  `result-*`, `.zvec-grep/`, and any `*.hm-backup` left by home-manager.

## Layout

- `flake.nix` — inputs, devShell, formatter, `checks` (per-host toplevel +
  `lint`), and the three `nixosConfigurations`. Hosts share `./modules`.
- `modules/{hardware,programs,security,services,stylix,system,users}` — system
  modules shared by every host. `modules/system/nixpkgs.nix` holds the host
  overlays and imports `pkgs/default.nix` (the single definition of every
  local derivation).
- `<host>/configuration/` — per-host system config; `disko.nix` and
  `hardware-configuration.nix` next to it. `desktop-laptop/` is shared between
  desktop and laptop only, and is imported by both.
- `home/` — one shared home-manager tree for `codebam` (imported in `flake.nix`).
  `home.nix` owns packages and user files; `agents.nix` owns the coding agents
  (opencode/opencode2, pi, dsh), their MCP servers, and their instruction files.
- `pkgs/` — local derivations, defined once in `pkgs/default.nix` and exposed
  two ways: the parent flake's `packages` / `overlays.default` outputs, and a
  standalone `pkgs/flake.nix` (`github:codebam/nixos?dir=pkgs`) whose only
  input is nixpkgs. `pkgs/unfree.nix` is the allowlist shared with the hosts.
- `secrets/` + `.sops.yaml` — SOPS secrets.

A package or service belongs in the narrowest place that fits: host-specific in
`<host>/configuration/`, desktop+laptop shared in `desktop-laptop/`, otherwise
`modules/<group>/`; user-level in `home/`.

## Host quirks that change decisions

- **Root is wiped at boot** on bare metal via `cleanup-root` (btrfs/bcachefs):
  anything written outside declared/preserved state is gone after reboot. The
  `preservation` module lists what survives — check
  `modules/system/preservation.nix` before adding persistent state under `$HOME`.
- **Desktop** is the primary host and the tailnet binary cache (`nix-serve-ng`);
  Viewport (Smithay) is the primary compositor, Sway the UWSM fallback. Services
  live in `desktop/configuration/` (nginx/ACME, SearXNG on `127.0.0.1:8081`,
  FlareSolverr, Ollama, media stack).
- **Laptop** is bcachefs, no discrete GPU, power-management oriented.
- **Steam Deck** runs the vendored Jovian module; keep gaming-specific modules
  (lsfg-vk, extest, Gamescope) out of other hosts. Builds are distributed to the
  desktop.
- **No `sudo`** on this system: root access is via the declarative user model and
  polkit, not shell escalation.

## Conventions

- Comments explain **why**, not what. The existing tree carries the reasoning
  behind pins, workarounds, and upstream caveats — preserve that style and add
  to it rather than replacing it.
- Prefer existing helpers and patterns over new machinery; grep for a similar
  module or derivation first. Do not refactor unrelated code in the same change.
- Verify NixOS option names before using them; do not guess. `nix develop`
  provides `nil`, `nixd`, `nixfmt`, `statix`, and `deadnix`.
- Pin flake inputs deliberately, not to branch names; bumping a pinned input is
  its own change with a rebuild to verify it.
- Keep changes reviewable: one concern per change, and say what was built to
  check it.

## Agent-local overlays

This file is loaded from the project root down to the working directory, so
per-subsystem guidance belongs in a nested `AGENTS.md` (for example
`home/AGENTS.md`) rather than appended here. Harnesses that support a local
overlay — dsh reads `AGENTS.local.md` after this file — can use one for
machine-local notes (paths, temporary state, hostnames) it is fine to leave
uncommitted; add it to `.gitignore` if you start one.
