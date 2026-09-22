# Qwen-Image-2.1 image generation: a prompting front end over
# stable-diffusion.cpp (`pkgs/default.nix` pins the version that knows this
# model) plus the one-time weight download.
#
#   qwen-image "a lovely cat holding a sign that says 'nixos'"
#
# writes a PNG into the current directory and prints its absolute path;
# `qwen-image-models` fetches and verifies the weights on their own.
#
# Desktop only: config.rocmSupport is set there (desktop/configuration/
# nixpkgs.nix), so sd.cpp builds its HIP backend for the card. Anywhere else
# this would be the CPU backend behind the same ~10 GiB of weights, at minutes
# per image, and the home tree is shared, so the gate keeps that off the
# laptop and Deck closures.
{
  pkgs,
  lib,
  osConfig,
  ...
}:

let
  # An explicit override rather than an XDG lookup baked in at build time: the
  # scripts can run outside the home-manager session, and the weights are data,
  # not store paths, so they belong in the preserved home directory
  # (modules/system/preservation.nix carries the root-wipe entry).
  modelsDir = ''"''${QWEN_IMAGE_MODELS_DIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/qwen-image}"'';

  downloader = pkgs.writeShellApplication {
    name = "qwen-image-models";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
    ];
    text = ''
      set -eu

      # Weights for Qwen-Image-2.1 under stable-diffusion.cpp. Re-running is
      # cheap: a file whose sha256 matches is skipped, a partial download is
      # resumed, and a file that still fails verification is removed rather
      # than left to poison the next run.
      #
      # Q4_K_M is the diffusion release's recommended quantization; --quant
      # selects another one. The text encoder and VAE do not depend on that
      # choice.
      #
      # The encoder is sd.cpp's documented Qwen3-VL-8B GGUF (~5 GiB). The
      # diffusion release also carries BF16 (17.5 GiB) and INT8 convrot
      # (9.35 GiB) safetensors of the same model, and sd.cpp loads either, so
      # QWEN_IMAGE_LLM=/path/to/file remains a way to buy quality with RAM.

      hf=https://huggingface.co
      models_dir=${modelsDir}

      quant=Q4_K_M
      while [ $# -gt 0 ]; do
        case "$1" in
          --quant)
            quant="''${2:?--quant needs a value}"
            shift 2
            ;;
          --quant=*)
            quant="''${1#--quant=}"
            shift
            ;;
          -h | --help)
            echo "usage: qwen-image-models [--quant Q4_0|Q4_K_M|Q5_K_M|Q6_K|Q8_0]"
            exit 0
            ;;
          *)
            echo "qwen-image-models: unexpected argument: $1" >&2
            exit 2
            ;;
        esac
      done

      case "$quant" in
        Q4_0) sha_diffusion=8efd261419f4d60bf0eda8ae86a656e229ed440a248a22e20bf1f1f9606f6124 ;;
        Q4_K_M) sha_diffusion=833439e91bc1152d28f37aa198c7f6f4218b7de95754c2f7a318a2422ab4b2f8 ;;
        Q5_K_M) sha_diffusion=88ce8e90e5b959cce5e248f697d7f6c9c7ca5696c1eac64a10dadb041dd7fd07 ;;
        Q6_K) sha_diffusion=a3a0d39bb03cda26302fc048b49d019baaea1c381cbda3994f6f2a7826344fb9 ;;
        Q8_0) sha_diffusion=9a7ec02f4c9d5cf5b78e8efa6ccd81ec0c35a898defbf8e77ac7c02a32fe0d7e ;;
        *)
          echo "qwen-image-models: unknown quantization: $quant" >&2
          echo "supported: Q4_0 Q4_K_M Q5_K_M Q6_K Q8_0" >&2
          exit 2
          ;;
      esac

      hash_ok() {
        # file, sha256
        [ -f "$1" ] && printf '%s  %s\n' "$2" "$1" | sha256sum --check --status -
      }

      fetch() {
        # url, destination, sha256 of the finished file
        if hash_ok "$2" "$3"; then
          printf 'have  %s\n' "$2"
          return 0
        fi

        printf 'fetch %s\n' "$2" >&2
        # Resume a partial file first. If the server refuses to range into it,
        # or the file has gone stale (HTTP 416) or was appended to, the first
        # pass fails and the second starts over from scratch; without that
        # fallback the download would be left deleted for the caller to notice
        # and re-run by hand.
        curl_args=(--fail --location --retry 5 --retry-delay 5 --continue-at -)
        if ! curl "''${curl_args[@]}" --output "$2" "$1" || ! hash_ok "$2" "$3"; then
          printf 'qwen-image-models: %s did not resume; downloading from scratch\n' "$2" >&2
          rm -f "$2"
          curl_args=(--fail --location --retry 5 --retry-delay 5)
          if ! curl "''${curl_args[@]}" --output "$2" "$1" || ! hash_ok "$2" "$3"; then
            rm -f "$2"
            printf 'qwen-image-models: download failed or failed verification: %s\n' "$1" >&2
            return 1
          fi
        fi
      }

      mkdir -p "$models_dir/diffusion" "$models_dir/text_encoders" "$models_dir/vae"

      fetch "$hf/abenzerps/Qwen-Image-2.1-GGUF/resolve/main/qwen-image-2.1-$quant.gguf" \
        "$models_dir/diffusion/qwen-image-2.1-$quant.gguf" "$sha_diffusion"
      fetch "$hf/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/Qwen3VL-8B-Instruct-Q4_K_M.gguf" \
        "$models_dir/text_encoders/Qwen3VL-8B-Instruct-Q4_K_M.gguf" \
        67d1659bfe71b89d50b45a4ad1a9e5b997e5bb16ce5da66a6a6167abd569e9e2
      fetch "$hf/abenzerps/Qwen-Image-2.1-GGUF/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors" \
        "$models_dir/vae/qwen_image_2.1_vae_bf16.safetensors" \
        bb21f7473051e1ac368515dd3f2e15cd44d7a11748ee8823e1ddca3e4876b7c9

      printf 'qwen-image-models: weights ready in %s\n' "$models_dir"
    '';
  };

  qwenImage = pkgs.writeShellApplication {
    name = "qwen-image";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -eu

      # Prompting front end for Qwen-Image-2.1 on stable-diffusion.cpp. The
      # absolute path of the PNG is the only thing on stdout, so
      # `img=$(qwen-image "prompt")` works; sd.cpp's progress output and the
      # chosen seed go to stderr.
      #
      # Defaults follow upstream's Qwen-Image-2.1 example (euler, cfg 6.0) at
      # 1024x1024 -- sd.cpp's own default is 512x512, too small for this model.
      # Anything after `--`, and any option this front end does not know, is
      # passed to sd.cpp unchanged (--offload-to-cpu, --diffusion-fa, -b, ...).

      sd_bin="${lib.getExe' pkgs.stable-diffusion-cpp "sd-cli"}"
      models_bin="${lib.getExe downloader}"
      models_dir=${modelsDir}

      prompt=
      negative=
      output=
      seed=
      steps=
      cfg=
      method=
      quant=Q4_K_M
      model="''${QWEN_IMAGE_MODEL:-}"
      llm="''${QWEN_IMAGE_LLM:-}"
      vae="''${QWEN_IMAGE_VAE:-}"
      extra=()
      width=1024
      height=1024

      usage() {
        cat <<'USAGE'
      usage: qwen-image [options] "prompt"

      Renders one Qwen-Image-2.1 image into the current directory and prints its
      path. Progress and the chosen seed go to stderr.

      Options:
        -p, --prompt TEXT        prompt (or pass it as the one positional argument)
        -n, --negative-prompt T  negative prompt
        -o, --output PATH        output file (default ./<slug>.png, -2 etc. on collision)
        -W, --width N            width in pixels, divisible by 32 (default 1024)
        -H, --height N           height in pixels, divisible by 32 (default 1024)
            --seed N             RNG seed (default: random, and it is printed)
            --steps N            sampling steps (sd.cpp default: 20)
            --cfg-scale F        guidance scale (default 6.0)
            --sampling-method M  sampling method (default euler)
            --quant Q            Q4_0|Q4_K_M|Q5_K_M|Q6_K|Q8_0 diffusion quant (default Q4_K_M)
            --model PATH         diffusion GGUF (also $QWEN_IMAGE_MODEL)
            --llm PATH           text encoder (also $QWEN_IMAGE_LLM)
            --vae PATH           VAE (also $QWEN_IMAGE_VAE)
            --                   pass the rest of the arguments to sd.cpp
        -h, --help               this text

      Weights live in $QWEN_IMAGE_MODELS_DIR (default $XDG_DATA_HOME/qwen-image)
      and are downloaded on first use by qwen-image-models.
      USAGE
      }

      while [ $# -gt 0 ]; do
        case "$1" in
          -p | --prompt)
            prompt="''${2:?$1 needs a value}"
            shift 2
            ;;
          -n | --negative-prompt)
            negative="''${2:?$1 needs a value}"
            shift 2
            ;;
          -o | --output)
            output="''${2:?$1 needs a value}"
            shift 2
            ;;
          -W | --width)
            width="''${2:?$1 needs a value}"
            shift 2
            ;;
          -H | --height)
            height="''${2:?$1 needs a value}"
            shift 2
            ;;
          --seed)
            seed="''${2:?$1 needs a value}"
            shift 2
            ;;
          --steps)
            steps="''${2:?$1 needs a value}"
            shift 2
            ;;
          --cfg-scale)
            cfg="''${2:?$1 needs a value}"
            shift 2
            ;;
          --sampling-method)
            method="''${2:?$1 needs a value}"
            shift 2
            ;;
          --quant)
            quant="''${2:?$1 needs a value}"
            shift 2
            ;;
          --model)
            model="''${2:?$1 needs a value}"
            shift 2
            ;;
          --llm)
            llm="''${2:?$1 needs a value}"
            shift 2
            ;;
          --vae)
            vae="''${2:?$1 needs a value}"
            shift 2
            ;;
          -h | --help)
            usage
            exit 0
            ;;
          --)
            shift
            extra+=("$@")
            break
            ;;
          -*)
            extra+=("$1")
            shift
            ;;
          *)
            if [ -n "$prompt" ]; then
              echo "qwen-image: unexpected argument: $1" >&2
              echo "qwen-image: value-taking sd.cpp options go after --" >&2
              exit 2
            fi
            prompt="$1"
            shift
            ;;
        esac
      done

      if [ -z "$prompt" ]; then
        usage >&2
        exit 2
      fi

      if [ -z "$seed" ]; then
        seed=$(od -An -N4 -tu4 /dev/urandom | tr -d '[:space:]')
      fi

      if [ -z "$output" ]; then
        slug=$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed -e 's/^-//' -e 's/-$//' | cut -c1-60)
        [ -n "$slug" ] || slug=image
        output="$PWD/$slug.png"
        n=1
        while [ -e "$output" ]; do
          n=$((n + 1))
          output="$PWD/$slug-$n.png"
        done
      fi

      model="''${model:-$models_dir/diffusion/qwen-image-2.1-$quant.gguf}"
      llm="''${llm:-$models_dir/text_encoders/Qwen3VL-8B-Instruct-Q4_K_M.gguf}"
      vae="''${vae:-$models_dir/vae/qwen_image_2.1_vae_bf16.safetensors}"

      if [ ! -f "$model" ] || [ ! -f "$llm" ] || [ ! -f "$vae" ]; then
        printf 'qwen-image: weights missing; fetching them first (about 10 GiB)\n' >&2
        "$models_bin" --quant "$quant"
        for f in "$model" "$llm" "$vae"; do
          if [ ! -f "$f" ]; then
            printf 'qwen-image: missing weight file: %s\n' "$f" >&2
            printf 'qwen-image: when --model/--llm/--vae point outside %s,\n' "$models_dir" >&2
            printf 'qwen-image: fetch them yourself; qwen-image-models only knows the defaults\n' >&2
            exit 1
          fi
        done
      fi

      args=(
        --diffusion-model "$model"
        --vae "$vae"
        --llm "$llm"
        --prompt "$prompt"
        --width "$width"
        --height "$height"
        --seed "$seed"
        --cfg-scale "''${cfg:-6.0}"
        --sampling-method "''${method:-euler}"
        --output "$output"
      )
      if [ -n "$negative" ]; then
        args+=(--negative-prompt "$negative")
      fi
      if [ -n "$steps" ]; then
        args+=(--steps "$steps")
      fi

      printf 'qwen-image: seed %s (--seed %s repeats this render)\n' "$seed" "$seed" >&2
      "$sd_bin" "''${args[@]}" "''${extra[@]}" >&2

      if [ ! -f "$output" ]; then
        printf 'qwen-image: sd.cpp did not write %s\n' "$output" >&2
        exit 1
      fi
      printf '%s\n' "$output"
    '';
  };
in
{
  home.packages = lib.optionals (osConfig.networking.hostName == "nixos-desktop") [
    # The binary pair is installed too, not just named by the wrapper, so
    # `sd-cli` and `sd-server` are on PATH for other models and for checking
    # the backend the package was built with.
    pkgs.stable-diffusion-cpp
    downloader
    qwenImage
  ];
}
