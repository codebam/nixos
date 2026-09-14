# nono profiles for the languages this tree is used to write. home/nono.nix
# installs the JSON under $XDG_CONFIG_HOME/nono/profiles, so
# `nono run --profile <name>` carries the same rules across rebuilds.
#
# The shared base deliberately differs from nono's built-in *-dev profiles:
#   - it extends linux-host-compat but excludes linux_runtime_state, which
#     keeps /run/secrets and the per-user agent/keyring sockets denied; only
#     the narrow /run paths language tooling needs are added back;
#   - workdir.access stays readwrite, so the project tree is the only
#     writable user tree. Package caches write under ~/.cache through
#     user_caches_linux, never into toolchain directories;
#   - the built-in developer network profile filters egress, environment
#     deny_vars strips common credential variables, and package-manager
#     credential files stay unreadable. As a result npm publish, cargo
#     publish, wrangler deploy, and git push fail inside the sandbox rather
#     than letting project code reach the tokens.
#
# A language profile should only add the runtime paths and registry domains
# its toolchain needs; everything else belongs in dev-base.
let
  mkLang =
    base: name: description: extra:
    {
      extends = base;
      meta = { inherit name description; };
    }
    // extra;

  # Exact names and trailing-* prefixes only (nono's pattern syntax). The
  # point is to drop credentials that happen to be exported into the shell
  # before untrusted project code runs; nono-injected credentials and
  # environment.set_vars ignore this list.
  credentialEnv = [
    "AWS_*"
    "AZURE_*"
    "GCP_*"
    "GOOGLE_*"
    "GITHUB_*"
    "GH_*"
    "GITLAB_*"
    "OPENAI_*"
    "ANTHROPIC_*"
    "GEMINI_*"
    "GROQ_*"
    "COHERE_*"
    "HUGGINGFACE_*"
    "HF_*"
    "CLOUDFLARE_*"
    "CF_*"
    "DISCORD_*"
    "TELEGRAM_*"
    "SLACK_*"
    "NPM_TOKEN"
    "NODE_AUTH_TOKEN"
    "CARGO_REGISTRY_TOKEN"
    "SOPS_*"
    "VAULT_*"
    "STRIPE_*"
    "TWILIO_*"
    "SENDGRID_*"
    "SSH_AUTH_SOCK"
    "GPG_AGENT_INFO"
    "TOKEN"
    "PASSWORD"
    "SECRET"
  ];

  base = {
    extends = "linux-host-compat";
    meta = {
      name = "dev-base";
      description = "Shared language sandbox: project-scoped writes, developer-registry network, credentials and agent state out of reach";
    };
    groups = {
      include = [
        "nix_runtime"
        "git_config"
        "user_caches_linux"
      ];
      exclude = [ "linux_runtime_state" ];
    };
    workdir.access = "readwrite";
    environment.deny_vars = credentialEnv;
    filesystem = {
      read = [
        "/etc/nix"
        "/nix/var/nix/daemon-socket"
        "/run/current-system"
      ];
      unix_socket = [ "/nix/var/nix/daemon-socket/socket" ];
      deny = [
        "/run/secrets"
        "$XDG_CONFIG_HOME/nono"
        "$XDG_STATE_HOME/nono"
        "$HOME/.dsh"
        "$HOME/.claude"
        "$HOME/.pi"
        "$XDG_CONFIG_HOME/opencode"
        "$HOME/.kimi-code"
        "$HOME/.sigmashake"
      ];
    };
    network = {
      network_profile = "developer";
      # GitHub release assets moved to this host; uv, bun, Electron, and
      # CMake FetchContent all pull through it.
      allow_domain = [ "release-assets.githubusercontent.com" ];
    };
  };
in
{
  "dev-base" = base;

  nix =
    mkLang "dev-base" "nix" "Nix/flake development: daemon and Nix caches, project-scoped writes"
      {
        filesystem.read = [ "/etc/nixos" ];
        network.allow_domain = [
          "nixos.org"
          "*.nixos.org"
          "cachix.org"
          "*.cachix.org"
          "*.determinate.systems"
          "codeberg.org"
          "*.codeberg.org"
          "tangled.org"
          "*.tangled.org"
        ];
      };

  python =
    mkLang "dev-base" "python"
      "Python/uv sandbox: project venvs, PyPI network, package-manager credentials denied"
      {
        groups.include = [ "python_runtime" ];
        filesystem = {
          # CPython multiprocessing and PyTorch DataLoader's file_system strategy
          # need /dev/shm; it is reboot-local and carries no persistent state.
          allow = [ "/dev/shm" ];
          deny = [
            "$XDG_CONFIG_HOME/pip"
            "$HOME/.pip"
            "$HOME/.pypirc"
            "$XDG_CONFIG_HOME/uv"
          ];
        };
        network.allow_domain = [
          "pypi.org"
          "*.pypi.org"
          "pythonhosted.org"
          "files.pythonhosted.org"
          "*.pythonhosted.org"
          "pypa.io"
          "*.pypa.io"
          "python.org"
          "*.python.org"
          "astral.sh"
          "*.astral.sh"
        ];
      };

  web =
    mkLang "dev-base" "web"
      "Node.js/TypeScript/Bun sandbox: writable package caches, registry/CDN network, publish credentials denied"
      {
        groups.include = [
          "node_runtime"
          "bun_runtime"
        ];
        filesystem = {
          allow = [
            "$HOME/.npm"
            "$HOME/.local/share/pnpm"
            "$HOME/.bun"
          ];
          # Wrangler's OAuth token and Yarn's registry credentials live here;
          # keeping them out of reach is what makes deploy and publish fail.
          deny = [
            "$HOME/.wrangler"
            "$XDG_CONFIG_HOME/.wrangler"
            "$HOME/.yarnrc"
            "$HOME/.yarnrc.yml"
            "$XDG_CONFIG_HOME/yarn"
          ];
        };
        network.allow_domain = [
          "npmjs.org"
          "*.npmjs.org"
          "npmjs.com"
          "*.npmjs.com"
          "yarnpkg.com"
          "*.yarnpkg.com"
          "nodejs.org"
          "*.nodejs.org"
          "bun.sh"
          "*.bun.sh"
          "esm.sh"
          "playwright.dev"
          "*.playwright.dev"
          "playwright.azureedge.net"
          "playwright.download.prss.microsoft.com"
          "download.cypress.io"
          "cdn.cypress.io"
          "edgedl.me.gvt1.com"
          "googlechromelabs.github.io"
          {
            # Puppeteer/Chrome for Testing downloads; the path restriction keeps
            # the rest of Google Cloud Storage off the allowlist.
            domain = "storage.googleapis.com";
            endpoints = [
              {
                method = "GET";
                path = "/chrome-for-testing-public/**";
              }
            ];
          }
        ];
      };

  rust =
    mkLang "dev-base" "rust"
      "Rust/Cargo sandbox: project target dirs, private CARGO_HOME cache, cargo credentials unreadable"
      {
        filesystem = {
          # ~/.cargo/bin is on PATH and ~/.rustup holds the toolchain; neither
          # needs write access for builds. Only the bin directory is granted so
          # ~/.cargo/credentials.toml cannot be read.
          read = [
            "$HOME/.cargo/bin"
            "$HOME/.rustup"
          ];
          deny = [
            "$HOME/.cargo/credentials"
            "$HOME/.cargo/credentials.toml"
            "$HOME/.cargo/config"
            "$HOME/.cargo/config.toml"
          ];
        };
        environment.set_vars = {
          # Cargo's registry/cache and credential lookup both follow CARGO_HOME;
          # pointing it at ~/.cache/cargo keeps the real ~/.cargo token file out
          # of reach and puts the cache where user_caches_linux already grants.
          CARGO_HOME = "$HOME/.cache/cargo";
          RUSTUP_HOME = "$HOME/.rustup";
        };
        network.allow_domain = [
          "rust-lang.org"
          "*.rust-lang.org"
          "crates.io"
          "*.crates.io"
          "docs.rs"
          "*.docs.rs"
          "sh.rustup.rs"
        ];
      };

  c-cpp =
    mkLang "dev-base" "c-cpp"
      "C/C++ sandbox: compiler toolchain and project tree only, Git-fetched dependencies only"
      {
        network.allow_domain = [
          "gnu.org"
          "*.gnu.org"
          "llvm.org"
          "*.llvm.org"
          "cmake.org"
          "*.cmake.org"
          "mesonbuild.com"
          "*.mesonbuild.com"
          "ninja-build.org"
        ];
      };

  dotnet =
    mkLang "dev-base" "dotnet"
      "C#/.NET sandbox: project output and NuGet cache, feed credentials denied"
      {
        filesystem = {
          allow = [
            "$HOME/.dotnet"
            "$HOME/.nuget/packages"
            "$XDG_DATA_HOME/NuGet"
            "$HOME/.templateengine"
          ];
          # NuGet stores feed credentials in its config tree; the packages cache
          # above is the only NuGet path the sandbox needs.
          deny = [
            "$HOME/.nuget/NuGet"
            "$XDG_CONFIG_HOME/NuGet"
          ];
        };
        environment.set_vars = {
          DOTNET_CLI_TELEMETRY_OPTOUT = "1";
          DOTNET_NOLOGO = "1";
          DOTNET_SKIP_FIRST_TIME_EXPERIENCE = "1";
        };
        network.allow_domain = [
          "nuget.org"
          "*.nuget.org"
          "dotnet.microsoft.com"
          "dotnetcli.azureedge.net"
          "dotnetbuilds.azureedge.net"
          "builds.dotnet.microsoft.com"
        ];
      };

  lua =
    mkLang "dev-base" "lua"
      "Lua/LuaRocks and Neovim plugin sandbox: plugin state writable, config read-only"
      {
        filesystem = {
          allow = [
            "$XDG_DATA_HOME/nvim"
            "$XDG_STATE_HOME/nvim"
          ];
          read = [
            "$XDG_CONFIG_HOME/nvim"
            "$HOME/.luarocks/share"
            "$HOME/.luarocks/lib"
            "$HOME/.luarocks/bin"
          ];
        };
        network.allow_domain = [
          "lua.org"
          "*.lua.org"
          "luarocks.org"
          "*.luarocks.org"
          "neovim.io"
          "*.neovim.io"
        ];
      };

  steel =
    mkLang "rust" "steel"
      "Steel/Scheme sandbox: cargo toolchain, Steel package cache, GitHub-fetched packages"
      {
        filesystem = {
          allow = [ "$XDG_DATA_HOME/steel" ];
          read = [ "$HOME/.steel" ];
        };
        environment.set_vars.STEEL_HOME = "$XDG_DATA_HOME/steel";
        network.allow_domain = [ ];
      };

  shell =
    mkLang "dev-base" "shell"
      "POSIX/bash script sandbox: project-only writes, developer-registry network, shell configs/history denied"
      { };
}
