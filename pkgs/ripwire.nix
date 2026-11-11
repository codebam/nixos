{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ripwire";
  version = "0.6.10";

  src = fetchFromGitHub {
    owner = "redhat-et";
    repo = "ripwire";
    rev = "v${finalAttrs.version}";
    hash = "sha256-vvOEqwRIgXM/HeoDsCnvdxH+h2zvAokjuHxl7z2ET/w=";
  };

  nativeBuildInputs = [ cmake ];

  # The project's own install.sh configures Release: an installed binary is
  # one you USE, so it gets the fast flavour. RIPWIRE_NATIVE stays off: it
  # bakes `-march=native` into the binary, which is wrong for a store path
  # shared across machines (and this repo's hosts differ).
  #
  # All dependencies are vendored in-tree (third_party/deps), so the build is
  # offline-clean: no FetchContent downloads, no network in the sandbox.
  cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];

  # The project builds with -Werror; GCC 15 promotes -Wformat-security to an
  # error, which fires on its runtime-format snprintf helpers. Downgrade just
  # that warning rather than patching upstream sources.
  env.NIX_CFLAGS_COMPILE = "-Wno-error=format-security";

  # `--component ripwire` keeps the vendored tree-sitter subproject's own
  # install rules (headers/pkgconfig/static lib) out of this output. Since
  # upstream added its own install rules for the agent assets, that same
  # component now also stages skills/ and hooks/ under share/ripwire exactly
  # the way install.sh describes them, so `ripwire wrap claude` probes the
  # staged copy and prints a working installer path straight from the store.
  installPhase = ''
    runHook preInstall
    cmake --install . --prefix "$out" --component ripwire
    runHook postInstall
  '';

  meta = {
    description = "Deterministic codebase maps for coding agents (CLI + MCP server)";
    homepage = "https://github.com/redhat-et/ripwire";
    license = lib.licenses.asl20;
    maintainers = [
      {
        name = "codebam";
        github = "codebam";
      }
    ];
    mainProgram = "ripwire";
    platforms = lib.platforms.unix;
  };
})
