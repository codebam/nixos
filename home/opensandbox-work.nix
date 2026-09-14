# The per-work-type sandbox catalog for OpenSandbox. This is the OpenSandbox
# replacement for the old nono language profiles: each entry is a pinned OCI
# image that covers one kind of work this tree is written in, and `osb-work`
# creates a sandbox with the current project bind-mounted at /workspace.
#
# Images are pinned by manifest digest (the `image` field), with the upstream
# tag kept beside it for humans. Bump a tag and digest together; never point
# `image` at a mutable tag.
{ pkgs, lib }:
let
  # `nixos/nix` is upstream's own image, not the host's Lix; it carries its
  # own store, so `nix develop`/`nix build` inside it fetch their own closure.
  # That is the cost of keeping the sandbox independent of the host store.
  sandboxTypes = {
    nix = {
      tag = "docker.io/nixos/nix:2.35.2";
      image = "docker.io/nixos/nix@sha256:7a007c766426c1877758ddc5cb87a965ac131fc78c582ce0083d922d51ae945c";
      description = "Nix/flake development with its own store (container-local builds)";
    };

    python = {
      tag = "docker.io/library/python:3.13-slim";
      image = "docker.io/library/python@sha256:9d2e5553305c7c7b0097999bb17187c69b921ccd6bc9d40e4bb5ebe652c00285";
      description = "Python 3.13, pip/venv and the CPython build deps in the slim base";
    };

    web = {
      tag = "docker.io/library/node:24-bookworm-slim";
      image = "docker.io/library/node@sha256:2fe369e969550cde8e867afc3fe370b260140cab4a23d467074295b42163d553";
      description = "Node.js 24 LTS, npm/npx and corepack for TypeScript/web work";
    };

    bun = {
      tag = "docker.io/oven/bun:1-debian";
      image = "docker.io/oven/bun@sha256:4f6e31d1a54d6a3dd312daef655fc998101b5043d52e12592ac293ef04b9bc73";
      description = "Bun runtime plus its npm-compatible package manager";
    };

    rust = {
      tag = "docker.io/library/rust:1-bookworm";
      image = "docker.io/library/rust@sha256:9a73a5088750b4c95158ab26629c854c3d6fc4b173cb7bc8079ad252d8ed7bfa";
      description = "Rust stable with cargo/rustup in the bookworm base";
    };

    c-cpp = {
      tag = "docker.io/library/gcc:15-bookworm";
      image = "docker.io/library/gcc@sha256:9ca91b05c7b07d2979f16413e8b2cd6ec8a7c80ffca4121ccab0aeba33f90460";
      description = "GCC 15 C/C++ toolchain with make and the usual binutils";
    };

    dotnet = {
      tag = "mcr.microsoft.com/dotnet/sdk:10.0";
      image = "mcr.microsoft.com/dotnet/sdk@sha256:2fa828c68761b1b8c23d7662dc134421b9d3b59fe1425fdbc80804e390cdb24d";
      description = ".NET 10 SDK for C#/F# builds and tests";
    };

    lua = {
      # The Docker Hub `library/lua` repository disappears periodically and is
      # inaccessible as of this pin; nickblah/lua is a minimal, reproducible
      # Lua/LuaRocks image, pinned by digest so the tag owner cannot move it.
      tag = "docker.io/nickblah/lua:5.4.8";
      image = "docker.io/nickblah/lua@sha256:31fb45a25b526ab62d3f9fcf53c8f677778382cc728a83db6aa8b7fe4b9556ea";
      description = "Lua 5.4 and LuaRocks (Neovim plugin work; no Neovim binary)";
    };

    steel = {
      # Steel is a Rust package; there is no maintained upstream image.
      tag = "docker.io/library/rust:1-bookworm";
      image = "docker.io/library/rust@sha256:9a73a5088750b4c95158ab26629c854c3d6fc4b173cb7bc8079ad252d8ed7bfa";
      description = "Steel/Scheme via cargo (same Rust image; cargo install or git)";
    };

    shell = {
      tag = "docker.io/library/debian:trixie-slim";
      image = "docker.io/library/debian@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132";
      description = "Debian trixie minimal shell for scripts and packaging chores";
    };

    browser = {
      tag = "mcr.microsoft.com/playwright:v1.56.0-noble";
      image = "mcr.microsoft.com/playwright@sha256:35246d87a7c88ea9b771c65d33171b2611b02a8253b4b12ce6f94376c55f99f2";
      description = "Playwright 1.56 with Chromium/Firefox/WebKit and browsers preinstalled";
    };

    code = {
      # Large (multi-GB) and pulled only when this type is used; it is the
      # multi-language evaluator (Python/Java/Go/TypeScript) with execd.
      tag = "docker.io/opensandbox/code-interpreter:v1.1.0";
      image = "docker.io/opensandbox/code-interpreter@sha256:133a3c1720dd52291a019740c2987e7164ea6de79e23d8198798e58950ae2e6e";
      description = "OpenSandbox multi-language code interpreter (Python/Java/Go/TypeScript)";
    };
  };

  typesJson = builtins.toJSON (
    lib.mapAttrs (name: value: {
      inherit name;
      inherit (value) tag image description;
    }) sandboxTypes
  );
in
{
  inherit sandboxTypes;

  osbWork = pkgs.writeShellApplication {
    name = "osb-work";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      types_json='${typesJson}'
      state_root="''${XDG_STATE_HOME:-$HOME/.local/state}/opensandbox/work"

      die() {
        printf 'osb-work: %s\n' "$*" >&2
        exit 1
      }

      usage() {
        printf '%s\n' 'osb-work — OpenSandbox work-type sandboxes'
        printf '\n'
        printf '%s\n' 'Commands:'
        printf '%s\n' '  list                                  list the work types and images'
        printf '%s\n' '  image <type>                          print the pinned image reference'
        printf '%s\n' '  start <type> [--dir DIR] [--timeout T]'
        printf '%s\n' '                                        create a sandbox with DIR at /workspace'
        printf '%s\n' '                                        (default DIR: current directory, timeout: 8h)'
        printf '%s\n' '  exec <type> [--timeout T] -- CMD...   run CMD in the last sandbox of <type>'
        printf '%s\n' '  run <type> [--dir DIR] [--timeout T] [--keep] -- CMD...'
        printf '%s\n' '                                        start, run, and stop a sandbox'
        printf '%s\n' '  id <type>                             print the last sandbox id'
        printf '%s\n' '  stop <type>                           delete the last sandbox of <type>'
        printf '\n'
        printf '%s\n' 'Inside the sandbox the bind-mounted project is /workspace; exec and'
        printf '%s\n' 'run start commands there. The server and client wrappers are managed'
        printf '%s\n' 'by home/opensandbox.nix.'
      }

      require_type() {
        printf '%s' "$types_json" | jq -e --arg t "$1" 'has($t)' >/dev/null 2>&1 \
          || die "unknown work type '$1' (run: osb-work list)"
      }

      state_file() {
        printf '%s/%s.id' "$state_root" "$1"
      }

      image_for() {
        printf '%s' "$types_json" | jq -r --arg t "$1" '.[$t].image'
      }

      create_sandbox() {
        local type="$1" dir="$2" timeout="$3" image volumes output id
        image="$(image_for "$type")"
        volumes="$(mktemp)"
        jq -n --arg dir "$dir" \
          '[{name:"workspace",host:{path:$dir},mountPath:"/workspace"}]' > "$volumes"
        if ! output="$(osb sandbox create \
            --image "$image" \
            --volumes-file "$volumes" \
            --timeout "$timeout" \
            --ready-timeout 15m \
            -o json)"; then
          rm -f "$volumes"
          return 1
        fi
        rm -f "$volumes"
        id="$(printf '%s' "$output" | jq -r '.id // empty')"
        [ -n "$id" ] || die "could not parse a sandbox id from: $output"
        printf '%s\n' "$id"
      }

      parse_dir_timeout() {
        # Fills OPT_DIR / OPT_TIMEOUT / OPT_KEEP for the current subcommand.
        OPT_DIR="$PWD"
        OPT_TIMEOUT="8h"
        OPT_TIMEOUT_SET="no"
        OPT_KEEP="no"
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --dir)
              [ "$#" -ge 2 ] || die "--dir needs a value"
              OPT_DIR="$2"
              shift 2
              ;;
            --timeout)
              [ "$#" -ge 2 ] || die "--timeout needs a value"
              OPT_TIMEOUT="$2"
              OPT_TIMEOUT_SET="yes"
              shift 2
              ;;
            --keep)
              OPT_KEEP="yes"
              shift
              ;;
            --)
              shift
              break
              ;;
            *)
              break
              ;;
          esac
        done
        REMAINING=("$@")
      }

      default_timeout_for_run() {
        if [ "$OPT_TIMEOUT_SET" = "no" ]; then
          if [ "$OPT_KEEP" = "yes" ]; then
            # A kept sandbox is meant to outlive the command that created it.
            OPT_TIMEOUT="8h"
          else
            OPT_TIMEOUT="30m"
          fi
        fi
      }

      command="''${1:-help}"
      [ "$#" -gt 0 ] && shift

      case "$command" in
        list)
          if [ "''${1:-}" = "-o" ] && [ "''${2:-}" = "json" ]; then
            printf '%s\n' "$types_json"
            exit 0
          fi
          printf '%s' "$types_json" | jq -r 'to_entries[] | "\(.key)\t\(.value.description)\n         \(.value.tag)"'
          ;;
        image)
          type="''${1:-}"
          [ -n "$type" ] || die "usage: osb-work image <type>"
          require_type "$type"
          image_for "$type"
          echo
          ;;
        start)
          type="''${1:-}"
          [ -n "$type" ] || die "usage: osb-work start <type> [--dir DIR] [--timeout T]"
          shift
          require_type "$type"
          parse_dir_timeout "$@"
          [ "$OPT_KEEP" = "no" ] || die "--keep is only valid with run"
          [ -d "$OPT_DIR" ] || die "workspace directory does not exist: $OPT_DIR"
          OPT_DIR="$(realpath "$OPT_DIR")"
          mkdir -p "$state_root"
          id="$(create_sandbox "$type" "$OPT_DIR" "$OPT_TIMEOUT")" \
            || die "sandbox create failed (is opensandbox-server running? try: systemctl --user status opensandbox-server)"
          printf '%s\n' "$id" > "$(state_file "$type")"
          printf 'sandbox:   %s\n' "$id"
          printf 'work type: %s\n' "$type"
          printf 'image:     %s\n' "$(image_for "$type")"
          printf 'workspace: %s -> /workspace\n' "$OPT_DIR"
          printf 'exec:      osb-work exec %s -- <command...>\n' "$type"
          printf 'stop:      osb-work stop %s\n' "$type"
          ;;
        exec)
          type="''${1:-}"
          [ -n "$type" ] || die "usage: osb-work exec <type> [--timeout T] -- CMD..."
          shift
          require_type "$type"
          parse_dir_timeout "$@"
          file="$(state_file "$type")"
          [ -f "$file" ] || die "no saved sandbox for '$type'; run: osb-work start $type"
          id="$(cat "$file")"
          [ "''${#REMAINING[@]}" -gt 0 ] || die "usage: osb-work exec $type -- CMD..."
          timeout_args=()
          if [ "$OPT_TIMEOUT_SET" = "yes" ]; then
            timeout_args=(-t "$OPT_TIMEOUT")
          fi
          exec osb command run "$id" -w /workspace -o raw "''${timeout_args[@]}" -- "''${REMAINING[@]}"
          ;;
        run)
          type="''${1:-}"
          [ -n "$type" ] || die "usage: osb-work run <type> [--dir DIR] [--timeout T] [--keep] -- CMD..."
          shift
          require_type "$type"
          parse_dir_timeout "$@"
          default_timeout_for_run
          [ -d "$OPT_DIR" ] || die "workspace directory does not exist: $OPT_DIR"
          OPT_DIR="$(realpath "$OPT_DIR")"
          [ "''${#REMAINING[@]}" -gt 0 ] || die "usage: osb-work run $type -- CMD..."
          mkdir -p "$state_root"
          id="$(create_sandbox "$type" "$OPT_DIR" "$OPT_TIMEOUT")" \
            || die "sandbox create failed (is opensandbox-server running?)"
          printf 'sandbox: %s\n' "$id" >&2
          if [ "$OPT_KEEP" = "yes" ]; then
            printf '%s\n' "$id" > "$(state_file "$type")"
          fi
          rc=0
          osb command run "$id" -w /workspace -o raw -- "''${REMAINING[@]}" || rc=$?
          if [ "$OPT_KEEP" != "yes" ]; then
            osb sandbox kill "$id" >/dev/null 2>&1 || true
          fi
          exit "$rc"
          ;;
        id)
          type="''${1:-}"
          [ -n "$type" ] || die "usage: osb-work id <type>"
          require_type "$type"
          cat "$(state_file "$type")" 2>/dev/null \
            || die "no saved sandbox for '$type'; run: osb-work start $type"
          ;;
        stop)
          type="''${1:-}"
          [ -n "$type" ] || die "usage: osb-work stop <type>"
          require_type "$type"
          file="$(state_file "$type")"
          [ -f "$file" ] || die "no saved sandbox for '$type'"
          id="$(cat "$file")"
          if osb sandbox kill "$id" -o json >/dev/null 2>&1; then
            rm -f "$file"
            printf 'stopped %s (%s)\n' "$type" "$id"
          else
            die "could not stop sandbox $id for '$type' (is opensandbox-server running?)"
          fi
          ;;
        help | -h | --help | *)
          usage
          [ "$command" = "help" ] || [ "$command" = "-h" ] || [ "$command" = "--help" ] \
            || die "unknown command '$command'"
          ;;
      esac
    '';
  };
}
