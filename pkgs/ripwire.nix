{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ripwire";
  version = "0.3.8";

  src = fetchFromGitHub {
    owner = "redhat-et";
    repo = "ripwire";
    rev = "v${finalAttrs.version}";
    hash = "sha256-ZBuF5GupyyiLe0SVvbtma0EnGMfm0z80eSUure1rIwo=";
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

  # v0.3.8's CMake installs only the binary: `--component ripwire` keeps the
  # vendored tree-sitter subproject's own install rules (headers/pkgconfig/
  # static lib) out of this output.
  installPhase = ''
    runHook preInstall
    cmake --install . --prefix "$out" --component ripwire
    runHook postInstall
  '';

  # v0.3.8 predates upstream's own skills/hooks install rules, so stage the
  # agent assets beside the binary the way install.sh describes them
  # ($prefix/share/ripwire/{skills,hooks}). `ripwire wrap` probes exactly
  # that staged copy, so e.g. `ripwire wrap claude` prints a working
  # installer path straight from the store.
  postInstall = ''
    mkdir -p "$out/share/ripwire"
    cp -r "$src/skills" "$out/share/ripwire/skills"
    cp -r "$src/hooks" "$out/share/ripwire/hooks"
  '';

  meta = {
    description = "Deterministic codebase maps for coding agents (CLI + MCP server)";
    homepage = "https://github.com/redhat-et/ripwire";
    license = lib.licenses.asl20;
    mainProgram = "ripwire";
    platforms = lib.platforms.unix;
  };
})
