{
  config,
  pkgs,
  lib,
  ...
}:

let
  # aiohttp only. A tokeniser would be the one other dependency worth having,
  # but pulling transformers in for a single number is not worth the closure --
  # see estimate_tokens in the script for what is done instead.
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.aiohttp ]);

  port = 8080;

  # llama-server, not ollama, for the public model. ollama refuses to batch
  # this architecture outright -- measured on 0.32.14, with the reason in its
  # own journal:
  #
  #   "model architecture does not currently support parallel requests"
  #     architecture=qwen35
  #
  # It is a policy gate on the architecture string, not a capability limit and
  # not a memory clamp: the same server granted n_seq_max=4 to qwen2.5-coder
  # and gemma4 in the same breath, and qwen3.8 still came back 1 at 8k context
  # with 4.4 GiB free and the vision projector stripped out. llama.cpp
  # underneath has no such objection -- it reports n_slots = 4 for the same
  # GGUF -- so the fix is to run llama-server directly rather than to change
  # models or to build vLLM.
  #
  # ollama keeps the private path (litellm, the other models) and is untouched
  # by any of this.
  # 8081 is searxng and 8191 is flaresolverr; 8099 is free. Checked against
  # `ss -lnt` rather than assumed -- llama-server binding a taken port fails in
  # the direction of "the endpoint answers, with somebody else's 404".
  serverPort = 8099;

  # Cached in the binary cache -- ~76 MiB, no local build, because the ROCm
  # runtime is already on this host for ollama.
  llamaCpp = pkgs.llama-cpp.override { rocmSupport = true; };

  # 03:00-11:00 America/Toronto, which is 07:00-15:00 UTC: the European working
  # day. The window is when the desktop is otherwise idle, so the card is not
  # being fought over by a compositor under load.
  windowStart = 3;
  windowEnd = 11;

  # The profile ladder, measured on this card rather than estimated. It spans
  # two engines, because they are good at opposite things.
  #
  # ollama decodes at 61 tok/s where llama-server manages 25, and the gap is
  # entirely speculative decoding: qwen3.8 ships an MTP draft head (the blk.64
  # "nextn" tensors) and ollama drives it via draft_num_predict. llama.cpp has
  # no MTP support for this architecture and logs those tensors as "unused
  # tensor ... ignoring". Measured on the same blob minutes apart:
  #
  #        ollama, draft_num_predict=4    61.2 tok/s
  #        ollama, draft_num_predict=0    25.0 tok/s
  #        llama-server                   24.9 tok/s
  #
  # Raw decode is identical; the draft head is the whole difference. But ollama
  # refuses to batch this architecture at all ("model architecture does not
  # currently support parallel requests", architecture=qwen35), so it is one
  # fast slot or several slow ones and there is no third option.
  #
  # Hence the ladder: ollama first, and llama-server only once demand proves
  # somebody is actually waiting. One caller alone is far better served by
  # 61 tok/s than by two idle slots.
  #
  #        engine   slots  per-slot  aggregate
  #        ollama     1      160k     61 tok/s
  #        llama      2      160k     50 tok/s
  #        llama      3      101k     75 tok/s
  #
  # The llama rows below are the clean fits from the VRAM sweep. llama-server
  # DIVIDES --ctx-size among slots, so `ctx` is per-slot and the flag it gets
  # is slots * ctx. Card total is 24560 MiB:
  #
  #        slots  per-slot   total    card use   free
  #          1      190k      190k     20006     4554   <- clean
  #          2      160k      328k     22996     1564   <- clean
  #          3      101k      311k     22777     1783   <- clean
  #          3      112k      344k     23474     1086   fit warning
  #          4       80k      328k     23256     1304   fit warning
  #          2      190k      389k     24284      276   fit warning
  #          3      128k      393k        --       --   refused outright
  #
  # Two things the table shows that arithmetic does not. Total context is the
  # wall and it sits just past 328k, so 3 slots at 128k is not a tuning problem
  # -- it is 393k against a card that stops at ~330k. And at equal total, more
  # slots costs more: 4x80k and 2x160k are both 328k, yet only the 2-slot row
  # is clean, because each slot carries overhead beyond its KV.
  #
  # llama.cpp fit-checks itself and declines rather than thrashing, which is
  # what made probing these survivable -- unlike ollama, whose own fit check
  # missed by ~2.9 GiB and left a thread wedged in amdgpu holding 22 GiB until
  # reboot. Rows marked "fit warning" logged common_fit_params failing and are
  # excluded on that basis, not on the free figure alone.
  profiles = [
    {
      engine = "ollama";
      slots = 1;
      ctx = 163840;
    }
    {
      engine = "llama";
      slots = 2;
      ctx = 163840;
    }
    {
      engine = "llama";
      slots = 3;
      ctx = 103936;
    }
  ];

  # The tag ollama serves on the fast rung. Same one litellm.nix uses for the
  # private path, deliberately: one resident model rather than two, and no
  # eviction when the desktop's own session overlaps the window.
  ollamaModel = "qwen3.8:160k";
  ollamaUrl = "http://127.0.0.1:11434";

  # Card total is 24560 MiB.
  #
  # vramIdleCeiling is the line between "compositor down" (~40 MiB measured)
  # and "compositor up" (~1067 MiB with sway, swaybg, Xwayland and the viewport
  # shell running). It is the guard that makes a manual "I closed my window
  # manager before bed" safe to automate around: forget to close it, and the
  # window opens on the single-slot profile instead of trying to fit 328k
  # beside a compositor.
  #
  # vramLoadedCeiling is set above the worst clean row (22996) and below the
  # best warning row (23256), so a profile that lands where the fit warnings
  # start is rejected by measurement even if the ladder is edited badly later.
  vramIdleCeilingMiB = 200;
  vramLoadedCeilingMiB = 23100;

  # Halved from llama.cpp's default. Prompt-eval buffers scale with batch size
  # and not with context, so this is the one place to recover VRAM that costs
  # prompt-eval throughput only and leaves decode speed untouched.
  numBatch = 256;

  # Read in place from ollama's blob store. A hardlink would have been tidier
  # -- it would keep the 16.8 GiB alive by refcount if ollama ever collected
  # its own manifest -- but /var/lib/ollama is a separate btrfs bind-mount from
  # the preservation setup (different st_dev), so link() returns EXDEV. Copying
  # would mean a second 16.8 GiB and a second thing to keep in sync.
  #
  # The blob is found through ollama's manifest by mediaType rather than by a
  # digest hardcoded here, so re-pulling the model picks up the new weights on
  # the next restart instead of silently serving stale ones. The projector
  # layer is deliberately not used -- it costs ~1.1 GiB and a text endpoint
  # never touches it.
  ollamaManifest = "/var/lib/ollama/models/manifests/registry.ollama.ai/library/qwen3.8/latest";

  # A wrapper rather than flags in ExecStart: systemd's $VAR expansion does not
  # word-split inside ${...} and does split bare $VAR, which is a subtle way to
  # pass "--parallel" and "2" as one argument. Reading the values in a shell
  # keeps that unambiguous, and gives somewhere to put the defaults that apply
  # when no window is open.
  llamaServerExec = pkgs.writeShellScript "llm-server-run" ''
    set -eu
    digest=$(${lib.getExe pkgs.jq} -r \
      '.layers[] | select(.mediaType=="application/vnd.ollama.image.model") | .digest' \
      ${ollamaManifest} | ${pkgs.gnused}/bin/sed 's/:/-/')
    if [ -z "$digest" ]; then
      echo "no model layer in ${ollamaManifest}" >&2
      exit 1
    fi
    # The single-slot profile is the fallback, matching llm-proxy.py's own
    # defaults, so a start outside the window serves rather than failing.
    parallel="''${LLM_PARALLEL:-1}"
    total="''${LLM_CTX_TOTAL:-194560}"
    exec ${llamaCpp}/bin/llama-server \
      --model "/var/lib/ollama/models/blobs/$digest" \
      --ctx-size "$total" \
      --parallel "$parallel" \
      --n-gpu-layers 99 \
      --flash-attn on \
      --cache-type-k q4_0 \
      --cache-type-v q4_0 \
      --batch-size ${toString numBatch} \
      --ubatch-size ${toString numBatch} \
      --host 127.0.0.1 \
      --port ${toString serverPort} \
      --alias qwen3.8
  '';

  scalerEnv = {
    LLM_PROFILES = builtins.toJSON profiles;
    LLM_SERVER_URL = "http://127.0.0.1:${toString serverPort}";
    LLM_OLLAMA_URL = ollamaUrl;
    LLM_OLLAMA_MODEL = ollamaModel;
    LLM_VRAM_CEILING_MIB = toString vramLoadedCeilingMiB;
    LLM_VRAM_IDLE_CEILING_MIB = toString vramIdleCeilingMiB;
    LLM_WINDOW_ENV = "/run/llm-window.env";
    LLM_SCALER_STATE = "/var/lib/llm-scaler/state.json";
    PROXY_DEMAND_PATH = "/run/llm-proxy/demand.json";
  };

  scalerPath = lib.makeBinPath [
    pkgs.curl
    pkgs.systemd
  ];

  # Exits non-zero outside the window, which systemd's ExecCondition treats as
  # "skip this unit" rather than "this unit failed". That is what makes both
  # Persistent=true on the timer and a boot trigger safe: an 03:00 trigger
  # replayed at 13:00 finds the condition false and does nothing.
  #
  # A script rather than an inline bash -c because the unit file would need
  # both nix indented-string escaping and systemd %-escaping to survive, and
  # getting either wrong fails silently in the direction of "never opened".
  # 10# is there because date +%H zero-pads and bash reads 08 and 09 as
  # invalid octal.
  inWindow = pkgs.writeShellScript "llm-in-window" ''
    h=$((10#$(${pkgs.coreutils}/bin/date +%H)))
    [ "$h" -ge ${toString windowStart} ] && [ "$h" -lt ${toString windowEnd} ]
  '';
in
{
  # Puts ollama in front of strangers without letting them reach ollama.
  #
  # ollama has no authentication and will pull and delete models for whoever
  # reaches the port, which is why it is bound to 127.0.0.1 in ./services.nix.
  # This proxy is what may be exposed instead: it authenticates, allowlists two
  # endpoints, and -- the part that matters most -- rewrites the request body
  # so a caller cannot set num_ctx.
  #
  # That last one is not theoretical. The measured table in ./services.nix has
  # 224k running at a tenth speed while ollama still reports 100% GPU, and the
  # 256k probe OOM-killed llama-server and left a thread wedged in amdgpu's
  # kfd_process_notifier_release_internal holding 22 GiB of VRAM through a
  # service restart -- the card only came back on reboot. A client-supplied
  # context size is a reboot someone else gets to schedule.
  systemd = {
    services = {
      llm-proxy = {
        description = "Sanitising reverse proxy for ollama";
        after = [
          "network.target"
          "llm-server.service"
        ];
        # After= but deliberately NOT Wants=. llm-proxy runs all day so that its
        # window gate can answer "outside service hours" to anyone who calls; if it
        # pulled the server in, 20 GiB of weights would be resident all day too,
        # and -- worse -- llm-window-down restarts llm-proxy, which would drag the
        # server back up at 11:00 immediately after stopping it. llm-window-up owns
        # starting it; llm-window-down owns stopping it.
        wantedBy = [ "multi-user.target" ];

        environment = {
          PROXY_HOST = "127.0.0.1";
          PROXY_PORT = toString port;
          # OLLAMA_URL is absent here for the same reason as PROXY_MODEL below: the
          # upstream changes with the engine, so llm-scaler.py writes it into
          # /run/llm-window.env alongside the rest of the profile. The script's own
          # default is ollama, which is both the fast rung and the right thing to
          # fall back to when no window is open.

          # PROXY_MODEL, PROXY_SLOTS and PROXY_MAX_PROMPT_TOKENS are deliberately
          # absent. They belong to whichever profile is loaded, so llm-scaler.py
          # writes all three into /run/llm-window.env -- the same file ollama reads
          # OLLAMA_NUM_PARALLEL from, which is what keeps the two from disagreeing.
          # A proxy with more slots than ollama just moves the queue; one with
          # fewer wastes KV the card already paid for.
          #
          # Setting them here as well would be a coin flip: systemd applies
          # Environment= and EnvironmentFile= in unit-file order, and the NixOS
          # module does not promise which it emits first. The script's own defaults
          # (one slot, qwen3.8:140k) are the fallback instead, which is also the
          # right state for a boot with no window open.

          # Matches what litellm.nix allows the same model. 8192 was too tight for
          # a coding harness -- a single large file write runs past it, and the
          # clamp is silent from the caller's side: the reply just stops with
          # finish_reason "length". The cost of raising it is time on the one slot,
          # not memory, and PROXY_QUEUE_TIMEOUT already bounds how long a single
          # request can hold the card against everyone else.
          PROXY_MAX_OUTPUT_TOKENS = "32000";

          PROXY_QUEUE_TIMEOUT = "300";
          PROXY_RATE_LIMIT = "60";

          # Read by llm-scaler.service. RuntimeDirectory below creates the
          # directory owned by the DynamicUser and removes it when the unit stops,
          # so a stale snapshot cannot outlive the process that wrote it -- which
          # matters, because the scaler treats a stale file as "do nothing".
          PROXY_DEMAND_PATH = "/run/llm-proxy/demand.json";

          PROXY_RESERVATION_PATH = "/var/lib/llm-proxy/reservations.json";

          # 30 minutes. Long enough that a working session is not punctuated by
          # re-reserving, short enough that a slot abandoned by someone who closed
          # their laptop comes back the same night. Re-reserving before it lapses
          # extends it, so the ceiling is politeness rather than a hard cap.
          PROXY_RESERVATION_TTL = "1800";

          PROXY_TZ = "America/Toronto";
          PROXY_WINDOW_START = toString windowStart;
          PROXY_WINDOW_END = toString windowEnd;
          PROXY_WINDOW = "1";
        };

        serviceConfig = {
          ExecStart = "${pythonEnv}/bin/python ${./scripts/llm-proxy.py}";
          Restart = "on-failure";
          RestartSec = 5;

          # systemd reads the credential as root and hands it to the DynamicUser,
          # so the sops secret stays root-owned 0400 and there is no static account
          # to chown to -- same arrangement as litellm.nix and nix-serve.nix.
          LoadCredential = [ "keys:${config.sops.secrets.llm-proxy-keys.path}" ];

          RuntimeDirectory = "llm-proxy";
          RuntimeDirectoryMode = "0755";

          # Reservations live here rather than in RuntimeDirectory: llm-scaler
          # restarts this unit when it changes profile, and a hold that evaporated
          # on restart would break exactly when someone was relying on it.
          StateDirectory = "llm-proxy";
          StateDirectoryMode = "0700";

          # Written by llm-scaler.py. Optional (-) so a boot with no window open
          # falls back to the script's single-slot defaults rather than failing.
          EnvironmentFile = "-/run/llm-window.env";

          DynamicUser = true;
          # It talks to loopback and reads one credential. Nothing else.
          CapabilityBoundingSet = [ "" ];
          AmbientCapabilities = [ "" ];
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          ProtectSystem = "strict";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged"
            "~@resources"
          ];
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
        };
      };

      # The public inference server. Started on demand by llm-scaler rather than at
      # boot: outside the window there is nobody to serve, and 20 GiB of resident
      # weights is 20 GiB the compositor cannot have.
      llm-server = {
        description = "llama-server for the public qwen3.8 endpoint";
        after = [ "network.target" ];

        # The same override ollama needs on this card (see services.nix). Without
        # it ROCm does not recognise the GPU and llama.cpp logs "no usable GPU" and
        # runs the whole 27B on the CPU -- which starts, answers /health, and looks
        # entirely healthy while serving at a few tokens a second.
        environment.HSA_OVERRIDE_GFX_VERSION = "11.0.0";

        serviceConfig = {
          # The same window gate as the timers. Without it, anything that starts
          # this unit outside service hours -- a nixos-rebuild switch restarting a
          # changed unit, most easily -- parks 20 GiB on the card until 11:00, with
          # nobody to serve and a compositor that may want it back. Exit non-zero
          # is "skip", not "fail", so a switch does not report an error either.
          ExecCondition = [ "${inWindow}" ];

          ExecStart = "${llamaServerExec}";
          Restart = "on-failure";
          RestartSec = 5;

          # Written by llm-scaler.py; carries LLM_PARALLEL and LLM_CTX_TOTAL.
          # Optional (-) so a start with no window open falls back to the wrapper's
          # single-slot defaults rather than failing.
          EnvironmentFile = "-/run/llm-window.env";

          # Loading 16.8 GiB and allocating up to 328k of KV is not fast, and a
          # timeout here would read as "the model does not fit" when it merely did
          # not finish.
          TimeoutStartSec = "10min";

          # Mirrors ollama's own hardening from the NixOS module, minus the nvidia
          # device classes. That set is proven to reach this exact card, which is
          # worth more here than a set reasoned out from first principles: three of
          # these were found the hard way.
          #
          # char-kfd and char-drm as device CLASSES, not "/dev/kfd rw" -- a path
          # that is not a device node matches nothing, and since any DeviceAllow
          # turns the unit into an allowlist, the mistake denies the GPU instead of
          # erroring. llama.cpp then logs "no usable GPU" and runs the 27B on the
          # CPU, which starts, answers /health, and looks entirely healthy.
          DevicePolicy = "closed";
          DeviceAllow = [
            "char-drm"
            "char-kfd"
          ];

          # AF_UNIX belongs here. Without it the ROCm stack segfaults during model
          # load rather than reporting a failed socket.
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];

          # Required, not incidental: ProtectSystem=strict makes /tmp read-only,
          # and rocBLAS and comgr write kernel caches there during load.
          PrivateTmp = true;

          SupplementaryGroups = [ "render" ];

          # Not an empty set. It runs as root but reads two files it does not own
          # out of ollama's store, and the manifest is 0600 ollama:ollama --
          # bypassing that needs CAP_DAC_READ_SEARCH. An empty bounding set here
          # failed as EACCES from jq, which reads as "the model is missing" rather
          # than "the sandbox is too tight".
          CapabilityBoundingSet = [ "CAP_DAC_READ_SEARCH" ];
          NoNewPrivileges = true;
          # NOT PrivateUsers, which ollama's own unit does set. This one runs as
          # real root specifically to read ollama's blob store -- the manifest is
          # 0600 ollama:ollama -- and a user namespace maps root to nobody, which
          # turns that read into EACCES.
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          # ProtectSystem=strict already makes the whole hierarchy read-only, which
          # is all this needs: it opens one GGUF out of ollama's blob store and
          # writes nothing to disk at all.
          ProtectSystem = "strict";
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "@resources"
            "~@privileged"
          ];
          LockPersonality = true;
        };
      };

      # Opens the window on the top of the ladder and lets llm-scaler take it from
      # there. The down side is a separate unit with its own timer, rather than a
      # stop on this one, because it must run even if the up side never did -- an
      # 03:00 that skipped on the VRAM guard still needs 11:00 to release the card
      # if anything else started a server in between.
      llm-window-up = {
        description = "Load the initial serving profile for the window";
        path = [ scalerPath ];
        environment = scalerEnv // {
          LLM_SCALER_INITIAL = "1";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Skip-not-fail, so Persistent=true on the timer cannot replay an 03:00
          # trigger into a 13:00 load with the compositor up.
          ExecCondition = [ "${inWindow}" ];
          ExecStart = "${pythonEnv}/bin/python ${./scripts/llm-scaler.py}";
          StateDirectory = "llm-scaler";
          TimeoutStartSec = "15min";
        };
      };

      llm-window-down = {
        description = "Stop the public server and release the card";
        serviceConfig = {
          Type = "oneshot";
          # The card has to be empty before the tty1 login asks for its ~1 GiB
          # back. Restarting llm-proxy drops it to its own single-slot defaults so
          # nothing advertises slots that no longer exist.
          ExecStart = pkgs.writeShellScript "llm-window-down" ''
            set -eu
            ${pkgs.systemd}/bin/systemctl stop llm-server.service || true
            # Either engine may be the one holding the card, so release both. The
            # keep_alive 0 evicts ollama's copy without stopping ollama itself,
            # which litellm still wants on the private path.
            ${lib.getExe pkgs.curl} -sf -m 120 ${ollamaUrl}/api/generate \
              -d '{"model":"${ollamaModel}","keep_alive":0}' >/dev/null || true
            rm -f /run/llm-window.env
            ${pkgs.systemd}/bin/systemctl restart llm-proxy.service || true
          '';
        };
      };

      # The scaler proper. Every ten minutes during the window it reads the proxy's
      # demand snapshot and decides whether a different profile is worth a restart.
      # It usually decides no: there is a 30-minute cooldown, an hour of required
      # quiet before it will trade slots back for context, and a hard refusal to
      # restart while any request is in flight.
      llm-scaler = {
        description = "Trade context length against slots based on demand";
        after = [ "llm-window-up.service" ];
        path = [ scalerPath ];
        environment = scalerEnv;
        serviceConfig = {
          Type = "oneshot";
          ExecCondition = [ "${inWindow}" ];
          ExecStart = "${pythonEnv}/bin/python ${./scripts/llm-scaler.py}";
          StateDirectory = "llm-scaler";
          TimeoutStartSec = "15min";
        };
      };

    };

    timers = {
      llm-window-up = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* ${lib.fixedWidthNumber 2 windowStart}:00:00";
          Persistent = true;
        };
      };

      llm-window-down = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* ${lib.fixedWidthNumber 2 windowEnd}:00:00";
          Persistent = false;
        };
      };

      llm-scaler = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* *:00/10:00";
          Persistent = false;
        };
      };
    };
  };

  # One bearer key per line, blank lines and # comments ignored. Rotation is
  # editing the secret and restarting the unit; revocation is deleting a line.
  #
  #   sops set secrets/secrets.yaml '["llm-proxy-keys"]' \
  #     "$(printf 'sk-%s\nsk-%s\n' "$(openssl rand -hex 24)" "$(openssl rand -hex 24)" | jq -Rs .)"
  sops.secrets.llm-proxy-keys = { };
}
