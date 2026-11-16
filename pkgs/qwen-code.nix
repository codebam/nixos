# Qwen Code (`qwen`) at the v0.27.4 release tag. The nixpkgs pin carries
# 0.26.7; this rebuilds the same derivation at the newer tag rather than
# waiting for the pin to catch up. The build recipe is unchanged between the
# two releases (pnpm workspaces, patch-package, `--cli-only` bundle, the
# cli-entry.js bin wrapper), so only version, src and the pnpm deps hash move.
# Drop this override once nixpkgs ships >= 0.27.4.
{
  base,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_11,
}:
base.overrideAttrs (
  finalAttrs: _old: {
    version = "0.27.4";

    src = fetchFromGitHub {
      owner = "QwenLM";
      repo = "qwen-code";
      tag = "v${finalAttrs.version}";
      hash = "sha256-lmwmzLEu7SS3eHBxSdVefo9KYLZRrL8uFn2VfbktnTA=";
    };

    pnpmDeps = fetchPnpmDeps {
      inherit (finalAttrs)
        pname
        version
        src
        ;
      pnpm = pnpm_11;
      fetcherVersion = 4;
      hash = "sha256-Hd+HddouueF007Iez+gexpfJVPGL2PxM+2s/rVbnRx0=";
    };
  }
)
