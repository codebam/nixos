{
  lib,
  inputs,
  config,
  pkgs,
  ...
}:
{
  nixpkgs = {
    config = {
      # checkMeta = true;
      # showDerivationWarnings = [ "maintainerless" ];
      allowUnfreePredicate =
        pkg:
        builtins.elem (lib.getName pkg) [
          "android-sdk-platform-tools"
          "android-studio"
          "antigravity"
          "claude-code"
          "cuda_nvcc"
          "discord"
          "discord-canary"
          "discord-ptb"
          "google-chrome"
          "google-chrome-unstable"
          "google-cloud-sdk"
          "libretro-fbneo"
          "libretro-genesis-plus-gx"
          "libretro-mame2000"
          "libretro-mame2003"
          "libretro-mame2015"
          "libretro-snes9x"
          "mongodb"
          "open-webui"
          "rpcs3"
          "steam"
          "steam-jupiter-unwrapped"
          "steam-original"
          "steam-run"
          "steam-unwrapped"
          "steamdeck-hw-theme"
          "via"
          "vscode"
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
            rev = "57441ded02b8895ed1bb2f66c5cff6a6478307f0";
            hash = "sha256-FNOWsNspf/d1cUdwPB6s8iKxt2mZYUymcjOKVJK+7Lk=";
          };
          mesonFlags = builtins.filter (opt: !prev.lib.hasInfix "xwayland" opt) old.mesonFlags;
        });
        sway-unwrapped = prev.sway-unwrapped.overrideAttrs (old: {
          src = prev.fetchFromGitHub {
            owner = "swaywm";
            repo = "sway";
            rev = "c857ca3a978896f4f9bdd481ec5cf395662a2dc5";
            hash = "sha256-6x4pLV25W6kmCxRMIVh9ZNdQJ2m52IkzHzPzRapuSSs=";
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
