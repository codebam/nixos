# NixOS Flake — codebam

Personal NixOS configuration managing four machines: a desktop, a laptop, a Steam Deck, and an AArch64 AVF VM. The same flake defines every host via a shared module tree, with per-host overrides for hardware, networking, and services.

## Hosts

| Host | Arch | Root FS | Disk |
|------|------|---------|------|
| `nixos-desktop` | x86_64 | btrfs on LUKS | Patriot P400L 1 TB |
| `nixos-laptop` | x86_64 | bcachefs | Samsung MZVLB1T0HALR 1 TB |
| `nixos-steamdeck` | x86_64 | btrfs | Micron 2500 1 TB |
| `nixos-avf` | aarch64 | ephemeral | GCE VM (nixos-avf) |

### Desktop (`nixos-desktop`)
- AMD Ryzen + Radeon RX 7900 XTX
- Dual 2560x1440@240 Hz monitors (DP-1, DP-3)
- CachyOS kernel (`linuxPackages_cachyos`), AMD pstate + prefcore, full preempt
- aarch64 binfmt emulation
- GPU overclocking via `applyGpuSettings` systemd service (3050 MHz core, 334 W power cap)
- AMDGPU overdrive enabled
- BTRFS `@root` wiped every boot via `cleanupRoot`
- ROCm support enabled

### Laptop (`nixos-laptop`)
- Samsung SSD, bcachefs root filesystem
- CachyOS kernel, bcachefs support
- Power management: `power-profiles-daemon`, `thermald`, `upower`, `powertop`
- No Steam or discrete GPU (CPU-only whisper.cpp backend)

### Steam Deck (`nixos-steamdeck`)
- Jovian NixOS module: Steam Deck device support, Decky Loader, Steam auto-start
- Sway session (Plasma6 forced off)
- Extest layer, Gamescope, Proton GE + CachyOS
- RetroArch with 12 libretro cores, Prism Launcher, Moonlight
- VRAM-based swapfile (2 GB)
- Distributed builds off the desktop

### AVF (`nixos-avf`)
- AArch64 Android VM via `nixos-avf`
- Lightweight: tailscale, SSH on port 8022 (tailnet-only), no display server
- Fish shell, Helix, basic CLI tools

## Flake Structure

```
/etc/nixos/
├── flake.nix                    # Entry point: hosts, inputs, devShell
├── flake.lock
├── modules/                     # Shared NixOS modules (every host)
│   ├── default.nix
│   ├── chaotic.nix              # Chaotic NG (Mesa Git)
│   ├── lix.nix                  # Lix Nix implementation overlay
│   ├── hardware/                # Bluetooth, uinput, graphics, QMK, redistributable firmware
│   ├── programs/                # nix-index, ccache, UWSM/sway, fish, wireshark, gnupg,
│   │                              gaming (Steam/Gamescope), sops-pass, voice-to-text
│   ├── security/                # ACME, polkit, apparmor, rtkit, no sudo
│   ├── services/                # scx_lavd, tailscale, pipewire, openssh, ...
│   ├── stylix/                  # irblack scheme, Papirus icons, capitaine cursor, FiraCode Nerd Font
│   ├── system/                  # boot, cleanup-root, env, fonts, gcp-builder, journald,
│   │                              networking, nix, nixpkgs (overlays), preservation,
│   │                              sysctl, systemd, time, xdg, zram
│   └── users/                   # Root + codebam (immutable, fish, Yubikey SSH keys)
├── desktop/
│   ├── disko.nix                # GPT → LUKS → btrfs subvolumes
│   └── configuration/           # cleanupRoot, CachyOS, Viewport, AMDGPU, nftables
│                                  VPN-bypass, services (Lidarr/Prowlarr/Transmission/
│                                  Navidrome/Ollama/OpenRGB/nginx/SearXNG), audio routing
│                                  (media ducker, DeepFilterNet), SOPS secrets, GPU OC,
│                                  makano user, nix-serve (binary cache, tailnet-only)
├── desktop-laptop/              # Shared: Podman, IVPN, OBS Studio
├── laptop/
│   └── configuration/           # cleanupRoot (bcachefs), power-profiles-daemon, thermald
├── steamdeck/
│   └── configuration/           # cleanupRoot (btrfs), Jovian, Decky, Steam, RetroArch,
│                                  gaming/extest, lsfg-vk, Moonlight, distributed builds
├── avf/
│   └── configuration.nix        # Minimal: tailscale, SSH, fish, helix
├── home/                        # Shared home-manager for codebam
│   ├── home.nix                 # Packages, env vars, custom scripts
│   ├── programs.nix             # fish, git, gh, tmux, starship, fastfetch, gpg, wlogout,
│   │                              helix, firefox nightly, mpv (Anime4K), mangohud, browsers,
│   │                              terminals (ghostty, rio), iamb
│   ├── services.nix             # swayidle, wl-clip-persist, gpg-agent
│   ├── shell-common.nix         # bash, carapace, zoxide, direnv, nushell, tmux, fzf
│   ├── sops.nix                 # iamb Matrix auto-login
│   ├── stylix.nix               # Per-user theming targets
│   ├── sway.nix                 # Sway config (keybindings, outputs, inputs, gaps, bars)
│   ├── systemd.nix              # Tmux systemd user service
│   ├── viewport.nix             # Viewport bootstrap config
│   ├── waybar.nix               # Base Waybar bar config
│   └── xdg.nix                  # MIME apps
├── pkgs/
│   ├── voice-to-text.nix        # Custom whisper.cpp offline dictation package
│   ├── voice-to-text-stream.nix # Streaming variant: types each utterance
│   └── voice-to-text-plainify.nix # Shared transcript filter: lowercase, no punctuation, no "um"
├── secrets/                     # SOPS-encrypted secrets (Yubikey + age)
└── .sops.yaml                   # SOPS key configuration
```

## Flake Inputs

| Input | Source |
|-------|--------|
| `nixpkgs` | nixos-unstable |
| `chaotic` | chaotic-cx/nyx (nyxpkgs-unstable) |
| `home-manager` | nix-community/home-manager |
| `disko` | nix-community/disko |
| `lanzaboote` | nix-community/lanzaboote (Secure Boot) |
| `rust-overlay` | oxalica/rust-overlay |
| `sops-nix` | Mic92/sops-nix |
| `stylix` | danth/stylix |
| `preservation` | nix-community/preservation |
| `nix-index-database` | nix-community/nix-index-database |
| `lsfg-vk-flake` | pabloaul/lsfg-vk-flake |
| `nixos-avf` | nix-community/nixos-avf |
| `sops-pass` | codebam/sops-pass (codeberg) |
| `viewport-smithay` | codebam/viewport-smithay (active compositor) |
| `hermes-agent` | NousResearch/hermes-agent |

## Key Features

### Root-on-TMPFS with Cleanup
Every bare-metal host wipes `/` to a fresh subvolume on every boot using `cleanup-root`, a custom stage-1 systemd service supporting both btrfs and bcachefs. Old roots archived under `old_roots/` for 30 days. A `noCleanup` boot specialisation preserves the current root for troubleshooting.

### Immutable Users
`mutableUsers = false`. `codebam` (uid 1000, all hosts) and `makano` (uid 1001, desktop) with declarative passwords, groups, SSH keys, and shell.

### Lix
Nix implementation replaced by Lix, bringing `nixpkgs-review`, `nix-eval-jobs`, `nix-fast-build`, and `colmena`.

### GCP Builder
Off by default (`services.gcp-builder.enable = false`). When enabled, `rebuild-switch` is local unless you pass `--gcp`, which spins up an ephemeral Spot VM (n2-standard-32).

### Audio Pipeline (Desktop)
- **Media ducker**: LSP sidechain compressor ducks media when game audio detected
- **Game listen**: Direct-to-DAC loopback for low-latency game audio
- **DeepFilterNet**: AI noise cancellation for microphone input
- Low-latency quantum (256/512), configurable sample rates (44.1k–96k)

### Services
- **Media**: Lidarr, Prowlarr, Transmission, Navidrome behind nginx + ACME
- **Search**: SearXNG on 127.0.0.1:8081 (JSON API for Hermes/Claude)
- **Local AI**: Ollama (loopback, AMD ROCm override)
- **Networking**: Tailscale, IVPN, NetworkManager/iwd, systemd-resolved (DoT)
- **Gaming**: Steam (extest, Gamescope, Proton GE/CachyOS); Steam firewall holes closed
- **GPU**: OpenRGB
- **Monitoring**: SMART disk monitoring

### Desktop
- **Viewport** (Smithay rewrite): Primary Wayland compositor
- **Sway** (sway_git): Fallback under UWSM
- **Waybar**: Transparent status bar with system stats, MPRIS controls, GPU telemetry
- **Swaylock**, **Wlogout**: Screen lock and session management
- **ArRPC** + **Mprisence**: Discord Rich Presence

### Home Manager
- **Shells**: fish, bash, nushell, tmux, starship, zoxide, direnv, fzf
- **Editors**: Helix (git, nixd LSP), vim → hx alias
- **Browsers**: Firefox Nightly (Chaotic), Google Chrome, Ungoogled Chromium
- **Terminals**: Ghostty (git), Rio
- **Messaging**: iamb (Matrix, auto-login from SOPS secret)
- **Dev**: gh, git (signed commits), claude-code, gcloud SDK
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

# Rebuild
nh os switch

# Rebuild on a GCP Spot VM (requires services.gcp-builder.enable = true)
rebuild-switch --gcp
```