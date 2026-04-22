{ lib
, inputs
, config
, pkgs
, ...
}:
{
  nixpkgs = {
    config = {
      # checkMeta = true;
      # showDerivationWarnings = [ "maintainerless" ];
      allowUnfreePredicate =
        pkg:
        builtins.elem (lib.getName pkg) [
          "android-studio"
          "android-sdk-platform-tools"
          "steam"
          "steam-original"
          "steam-run"
          "steam-unwrapped"
          "open-webui"
          "discord"
          "discord-ptb"
          "discord-canary"
          "steamdeck-hw-theme"
          "steam-jupiter-unwrapped"
          "libretro-genesis-plus-gx"
          "libretro-snes9x"
          "libretro-fbneo"
          "libretro-mame2000"
          "libretro-mame2003"
          "libretro-mame2015"
          "vscode"
          "via"
          "claude-code"
          "google-cloud-sdk"
          "google-chrome"
          "google-chrome-unstable"
          "antigravity"
          "cuda_nvcc"
          "mongodb"
        ];
    };
    overlays = [
      (final: prev: {
        # pipewire = (inputs.staging.legacyPackages.${prev.stdenv.hostPlatform.system}).pipewire;
        # vllm = (import inputs.vllm-update {
        #   system = prev.stdenv.hostPlatform.system;
        #   config.allowUnfree = true;
        #   config.rocmSupport = true;
        #   overlays = [
        #     (pythonFinal: pythonPrev: {
        #       python313 = pythonPrev.python313.override {
        #         packageOverrides = self: super: {
        #           mistral-common = super.mistral-common.overridePythonAttrs (old: rec {
        #             version = "1.10.0";
        #             src = prev.fetchFromGitHub {
        #               owner = "mistralai";
        #               repo = "mistral-common";
        #               rev = "v${version}";
        #               hash = "sha256-If0nukwe/9W4i42S+lE52lT/AU77VK0S9LKG1AyWzjA=";
        #             };
        #             doCheck = false;
        #           });
        #           compressed-tensors = super.compressed-tensors.overridePythonAttrs (old: {
        #             version = "0.14.0.1";
        #             doCheck = false;
        #           });
        #           outlines = super.outlines.overridePythonAttrs (old: {
        #             version = "1.2.12";
        #             doCheck = false;
        #           });
        #           accelerate = super.accelerate.overridePythonAttrs (old: {
        #             doCheck = false;
        #           });
        #           transformers = super.transformers.overrideAttrs (old: {
        #             version = "5.5.0-dev";
        #             doCheck = false;
        #             src = prev.fetchFromGitHub {
        #               owner = "huggingface";
        #               repo = "transformers";
        #               rev = "main";
        #               hash = "sha256-M5FMLe6CnC5cIFoSSP4t9F8ZJtSlPagzHyYtOO71vbs=";
        #             };
        #           });
        #         };
        #       };
        #     })
        #   ];
        # }).python3Packages.vllm;
        wlroots_0_19 = prev.wlroots_0_19.overrideAttrs (old: {
          pname = "wlroots";
          version = "0.21.0-dev";
          src = prev.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = "wlroots";
            repo = "wlroots";
            rev = "700ee83ab805b01bec3ccb072844e67d21d0986d";
            hash = "sha256-IOtlKzsHIUi4ZjAvmN8tPbB4AVv+XKFMDFAgCKrWhWE=";
          };
          mesonFlags = builtins.filter (opt: !prev.lib.hasInfix "xwayland" opt) old.mesonFlags;
        });
        sway-unwrapped = prev.sway-unwrapped.overrideAttrs (old: {
          src = prev.fetchFromGitHub {
            owner = "swaywm";
            repo = "sway";
            rev = "9a5f09c867894dacf25f54929cfd808b301712b1";
            hash = "sha256-pRSV2Z40FPoo1MDWWGgM+rQXs9Q47Iz7rspyV9d1JjE=";
          };
        });
        xdg-desktop-portal-wlr = prev.xdg-desktop-portal-wlr.overrideAttrs (oldAttrs: {
          src = prev.fetchFromGitHub {
            owner = "emersion";
            repo = "xdg-desktop-portal-wlr";
            rev = "01171a150b705cf07066ebc0fb7e1ff537027bec";
            hash = "sha256-HITf/hgiASWvn/z49mzS8IS1vuyXwdk1JiAOOHRSQMo=";
          };
          nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [ prev.makeWrapper ];
          buildInputs = oldAttrs.buildInputs ++ [ prev.wmenu ];
          postInstall = ''
            ${oldAttrs.postInstall or ""}
            wrapProgram $out/libexec/xdg-desktop-portal-wlr \
              --prefix PATH : ${lib.makeBinPath [ prev.wmenu ]}
          '';
        });
        android-tools = prev.androidenv.androidPkgs.platform-tools.overrideAttrs (oldAttrs: rec {
          version = "36.0.0";
          src = prev.fetchurl {
            url = "https://dl.google.com/android/repository/platform-tools_r${version}-linux.zip";
            sha256 = "sha256-Dq1kLJQ//nlwH8zKj18cacTOT0PfLu/uVT9syyfL++g=";
          };
        });
      })
    ];
  };
}
