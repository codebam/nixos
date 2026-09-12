# NixOS Flake — codebam

Personal NixOS configuration managing three machines: a desktop, a laptop, and a
Steam Deck. The same flake defines every host via a shared module tree, with
per-host overrides for hardware, networking, and services.

## Hosts

| Host | Arch | Root FS | Disk |
|------|------|---------|------|
| `nixos-desktop` | x86_64 | btrfs on LUKS | Patriot P400L 1 TB |
| `nixos-laptop` | x86_64 | bcachefs | Samsung MZVLB1T0HALR 1 TB |
| `nixos-steamdeck` | x86_64 | btrfs | Micron 2500 1 TB |

### Desktop (`nixos-desktop`)
- AMD Ryzen 7 5700X3D + Radeon RX 7900 XTX
- Dual 2560x1440@240 Hz monitors (DP-1, DP-3)
- `linuxPackages_latest`, AMD pstate + prefcore, full preempt
- aarch64 binfmt emulation
- GPU overclocking via `applyGpuSettings` systemd service (3050 MHz core, 334 W power cap)
- AMDGPU overdrive enabled
- BTRFS `@root` wiped every boot via `cleanupRoot`
- ROCm support enabled (Ollama)

### Laptop (`nixos-laptop`)
- Samsung SSD, bcachefs root filesystem
- `linuxPackages_latest`
- Power management: `power-profiles-daemon`, `thermald`, `upower`, `powertop`
- No Steam or discrete GPU

### Steam Deck (`nixos-steamdeck`)
- Jovian NixOS module (vendored prebuilt through `chaotic`): Steam Deck device
  support, Decky Loader, Steam auto-start
- Sway session (Plasma6 forced off)
- Extest layer, Gamescope, Proton CachyOS
- RetroArch with libretro cores, Prism Launcher, Moonlight
- VRAM-based swapfile (2 GB)
- Distributed builds off the desktop

## Flake Structure

```
/persistent/etc/nixos/
├── flake.nix                    # Entry point: hosts, inputs, packages, devShell
├── flake.lock
├── modules/                     # Shared NixOS modules (every host)
│   ├── default.nix
│   ├── chaotic.nix              # Chaotic NG (vendors prebuilt Jovian; Mesa Git off)
│   ├── lix.nix                  # Lix Nix implementation overlay
│   ├── hardware/                # Bluetooth, uinput, graphics, QMK, redistributable firmware
│   ├── programs/                # nix-index, UWSM/sway, fish, wireshark, gnupg,
│   │                              gaming (Steam/Gamescope), sops-pass
│   ├── security/                # ACME, polkit, apparmor, rtkit, no sudo
│   ├── services/                # scx_lavd, tailscale, pipewire, openssh, ...
│   ├── stylix/                  # kanagawa scheme, Papirus icons, capitaine cursor,
│   │                              JetBrainsMono Nerd Font, NixOS-artwork wallpaper
│   ├── system/                  # boot, cleanup-root, env, fonts, journald,
│   │                              networking, nix, nixpkgs (overlays), preservation,
│   │                              streaming-mode, sysctl, systemd, time, xdg, zram
│   └── users/                   # Root + codebam (immutable, fish, Yubikey SSH keys)
├── desktop/
│   ├── disko.nix                # GPT → LUKS → btrfs subvolumes
│   └── configuration/           # cleanupRoot, Viewport, AMDGPU, nftables
│                                  VPN-bypass, services (Lidarr/Prowlarr/Transmission/
│                                  Navidrome/Ollama/OpenRGB/nginx/SearXNG/FlareSolverr),
│                                  audio routing (media ducker, DeepFilterNet), SOPS
│                                  secrets, GPU OC, makano user, nix-serve (tailnet cache)
├── desktop-laptop/              # Shared: Podman, IVPN, OBS Studio
├── laptop/
│   └── configuration/           # cleanupRoot (bcachefs), power-profiles-daemon, thermald
├── steamdeck/
│   └── configuration/           # cleanupRoot (btrfs), Jovian, Decky, Steam, RetroArch,
│                                  gaming/extest, lsfg-vk, Moonlight, distributed builds
├── home/                        # Shared home-manager for codebam
│   ├── home.nix                 # Packages, env vars, custom scripts
│   ├── programs.nix             # fish, git, gh, tmux, starship, fastfetch, gpg, wlogout,
│   │                              helix, firefox, mpv (Anime4K), mangohud, browsers,
│   │                              terminals (ghostty, rio)
│   ├── agents.nix               # opencode/opencode2/pi providers, MCP servers, AGENTS.md
│   ├── services.nix             # swayidle, wl-clip-persist, gpg-agent, tmux user unit
│   ├── shell-common.nix         # bash, carapace, zoxide, direnv, nushell, tmux, fzf
│   ├── stylix.nix               # Per-user theming targets
│   ├── sway.nix                 # Sway config (keybindings, outputs, inputs, gaps, bars)
│   ├── terminal.nix             # defaultTerminal option
│   ├── viewport.nix             # Viewport bootstrap config
│   ├── voxtype.nix              # Offline dictation daemon and transcript processing
│   ├── waybar.nix               # Base Waybar bar config
│   └── xdg.nix                  # MIME apps
├── pkgs/                        # Local derivations (also a standalone flake)
│   ├── default.nix              # The one definition of every local derivation
│   ├── flake.nix                # `nix run github:codebam/nixos?dir=pkgs#<name>`
│   ├── unfree.nix               # Unfree names the hosts and package flake allow
│   ├── agent-overview.nix       # tmux agent dashboard
│   ├── dsh.nix                  # DeepSeek Harness CLI
│   ├── opencode-cli.nix         # @opencode/cli beta (opencode2)
│   ├── opencode-desktop-beta.nix
│   ├── pinentry-auto.nix        # terminal-aware pinentry
│   ├── polariumcode/            # Polarium Code desktop app (AppImage wrapper)
│   ├── ripwire.nix              # C++ codebase-map CLI + MCP server
│   ├── sigmashake-desktop.nix
│   ├── ssg.nix                  # sigmashake CLI
│   ├── voxtype-plainify.nix     # transcript filter (a sed program, not a package)
│   └── zvec-grep.nix            # hybrid workspace search + MCP server
├── secrets/                     # SOPS-encrypted secrets (Yubikey + age)
└── .sops.yaml                   # SOPS key configuration
```

## Installing a single package

Every derivation in `pkgs/` is defined once, in `pkgs/default.nix`, and exposed
two ways, so one can be installed without adopting a host. Prefer the
`?dir=pkgs` flake: its only input is nixpkgs, so it does **not** pull this
repo's disko/lanzaboote/chaotic/... inputs for a single tool.

```bash
nix run   github:codebam/nixos?dir=pkgs#ripwire
nix build github:codebam/nixos?dir=pkgs#dsh
nix profile install github:codebam/nixos?dir=pkgs#zvec-grep
```

For a NixOS config or another flake, consume the overlay instead:

```nix
{
  inputs.packages.url = "github:codebam/nixos?dir=pkgs";
  # ...
  nixpkgs.overlays = [ inputs.packages.overlays.default ];  # then pkgs.ripwire, ...
}
```

The parent flake exposes the same set (`packages.<system>.<name>` and
`overlays.default`), so `nix run github:codebam/nixos#ripwire` works too — it
just evaluates the whole input graph. Unfree names are allowed through
`pkgs/unfree.nix`, shared with the hosts, so `ssg`, `sigmashake-desktop` and
`polariumcode` resolve without extra config. `voxtype-plainify` is not here: it
is a sed program, not a derivation.

## Flake Inputs

| Input | Source |
|-------|--------|
| `nixpkgs` | nixos-unstable |
| `chaotic` | chaotic-cx/nyx (nyxpkgs-unstable; vendors prebuilt Jovian) |
| `home-manager` | nix-community/home-manager |
| `disko` | nix-community/disko |
| `lanzaboote` | nix-community/lanzaboote (Secure Boot) |
| `rust-overlay` | oxalica/rust-overlay |
| `sops-nix` | Mic92/sops-nix |
| `stylix` | danth/stylix |
| `preservation` | nix-community/preservation |
| `nix-index-database` | nix-community/nix-index-database |
| `lsfg-vk-flake` | pabloaul/lsfg-vk-flake (Steam Deck) |
| `voxtype` | peteonrails/voxtype v0.7.5 |
| `sops-pass` | codebam/sops-pass |
| `viewport` | codebam/viewport (compositor; default `servoshell` backend) |

## Key Features

### Root-on-TMPFS with Cleanup
Every bare-metal host wipes `/` to a fresh subvolume on every boot using
`cleanup-root`, a custom stage-1 systemd service supporting both btrfs and
bcachefs. Old roots archived under `old_roots/` for 30 days. A `noCleanup` boot
specialisation preserves the current root for troubleshooting.

### Immutable Users
`mutableUsers = false`. `codebam` (uid 1000, all hosts) and `makano` (uid 1001,
desktop) with declarative passwords, groups, SSH keys, and shell.

### Lix
Nix implementation replaced by Lix, bringing `nixpkgs-review`, `nix-eval-jobs`,
`nix-fast-build`, and `colmena`.

### Audio Pipeline (Desktop)
- **Media ducker**: LSP sidechain compressor ducks media when game audio detected
- **Game listen**: Direct-to-DAC loopback for low-latency game audio
- **DeepFilterNet**: AI noise cancellation for microphone input
- Low-latency quantum (256/512), configurable sample rates (44.1k–96k)

### Services
- **Media**: Lidarr, Prowlarr, Transmission, Navidrome behind nginx + ACME
- **Search**: SearXNG on 127.0.0.1:8081 (JSON API for agents)
- **Cloudflare**: FlareSolverr container (loopback) for interstitial solving
- **Local AI**: Ollama (loopback, AMD ROCm override)
- **Networking**: Tailscale, IVPN, NetworkManager/iwd, systemd-resolved (DoT)
- **Gaming**: Steam (extest, Gamescope, Proton CachyOS); Steam firewall holes closed
- **GPU**: OpenRGB
- **Monitoring**: SMART disk monitoring
- **Cache**: `nix-serve-ng` on the desktop serves the tailnet (laptop/Deck pull
  locally-built paths instead of compiling them)

### Desktop
- **Viewport** (Smithay rewrite): primary Wayland compositor, `servoshell`
  (Servo) backend
- **Sway** (`sway_git`): fallback under UWSM
- **Waybar**: transparent status bar with system stats, MPRIS controls, GPU telemetry
- **Swaylock**, **Wlogout**: screen lock and session management
- **ArRPC** + **Mprisence**: Discord Rich Presence

### Home Manager
- **Shells**: fish, bash, nushell, tmux, starship, zoxide, direnv, fzf
- **Editors**: Helix (git, nixd LSP), vim → hx alias
- **Browsers**: Firefox, Google Chrome, Ungoogled Chromium
- **Terminals**: Ghostty, Rio
- **Agents**: OpenCode (stable + beta `opencode2`), OpenCode Desktop, Pi, with
  zvec-grep and ripwire MCP servers
- **Dev**: gh, git (signed commits), claude-code
- **Media**: mpv (Anime4K upscaling), OBS Studio (VAAPI)
- **Gaming**: MangoHud, Prism Launcher (Deck), Moonlight (Deck)

### Security
- AppArmor enabled, polkit (local/active wheel passwordless), no sudo
- OpenSSH: key-only, no root, kbd-interactive off, tailnet-only (`openFirewall = false`)
- GPG agent with Yubikeys (graphical pinentry)
- SOPS secrets via age + Yubikeys
- Secure Boot via lanzaboote

## Convenience

```bash
# Development shell with Nix tooling
nix develop

# Format all Nix files
nix fmt

# Check all configurations (builds every host)
nix flake check

# Build a single local package
nix build .#ripwire

# Rebuild
nh os switch
```
