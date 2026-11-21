# Qwen Code (`qwen`) at the v0.28.3 release tag. The nixpkgs pin carries
# 0.26.7; this rebuilds the same derivation at the newer tag rather than
# waiting for the pin to catch up. The build recipe is unchanged across the
# 0.27/0.28 line (pnpm workspaces, patch-package, `--cli-only` bundle, the
# cli-entry.js bin wrapper), so only version, src and the pnpm deps hash move.
# Drop this override once nixpkgs ships >= 0.28.3.
{
  base,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_11,
}:
base.overrideAttrs (
  finalAttrs: _old: {
    version = "0.28.3";

    src = fetchFromGitHub {
      owner = "QwenLM";
      repo = "qwen-code";
      tag = "v${finalAttrs.version}";
      hash = "sha256-jrvSoYbjl4476sBgzDFwkA8zl7yzd4nZB3d75GYhPJw=";
    };

    pnpmDeps = fetchPnpmDeps {
      inherit (finalAttrs)
        pname
        version
        src
        ;
      pnpm = pnpm_11;
      fetcherVersion = 4;
      hash = "sha256-P+mKEcMmcKzUS7aOxBx468U2zk+Do/y6pgWnXCZtFw4=";
    };
  }
)
