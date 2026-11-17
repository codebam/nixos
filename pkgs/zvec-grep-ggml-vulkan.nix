# Vulkan backend plugin for the ggml that zvec-grep bundles.
#
# zvec-grep's prebuilt platform package ships only ggml CPU backends, and
# upstream's only GPU components are CUDA (platforms.json) -- dead weight on
# AMD. The plugin is built from the *same* ggml release as the bundled
# libggml-base.so.0 (they share the backend ABI) and registered at process
# start by the constructor shim in pkgs/zvec-grep/vulkan-init.c: the zg
# binary's own backend discovery never loads it (its
# load_backends_from_path is dead code), so dropping it in lib/ alone does
# nothing.
#
# The version MUST track the ggml inside zvec-grep. Re-derive it after a
# zvec-grep bump by dlopening the bundled libggml-base.so.0 and calling
# ggml_version() (0.18.0 for zvec-grep 0.3.0; the build embeds no git
# commit, so the release tag is the pin).
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  vulkan-headers,
  vulkan-loader,
  spirv-headers,
  shaderc,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "zvec-grep-ggml-vulkan";
  version = "0.18.0";

  src = fetchFromGitHub {
    owner = "ggml-org";
    repo = "ggml";
    tag = "v${finalAttrs.version}";
    hash = "sha256-vXh5Kf0sXTcKa7IefyWzIC5EQC8c8ehzn+Dqhue+/nk=";
  };

  # The cmake setup hook passes absolute install dirs, which ggml.pc.in
  # joins onto ${prefix} and the fixup hook rejects; same fix as nixpkgs'
  # ggml (NixOS/nixpkgs#144170).
  postPatch = ''
    substituteInPlace ggml.pc.in \
      --replace-fail \
        "\''${prefix}/@CMAKE_INSTALL_INCLUDEDIR@" \
        "@CMAKE_INSTALL_FULL_INCLUDEDIR@" \
      --replace-fail \
        "\''${prefix}/@CMAKE_INSTALL_LIBDIR@" \
        "@CMAKE_INSTALL_FULL_LIBDIR@"
  '';

  nativeBuildInputs = [
    cmake
    # glslc, which ggml's Vulkan build invokes to compile its shaders.
    shaderc
  ];
  buildInputs = [
    vulkan-headers
    vulkan-loader
    spirv-headers
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DBUILD_SHARED_LIBS=ON"
    # Build the backend as a dlopen-able plugin instead of linking it into
    # libggml, matching how the bundled CPU backends are packaged.
    "-DGGML_BACKEND_DL=ON"
    # A PATH cache entry: a relative value would resolve against the build
    # tree and the plugin would never reach $out.
    "-DGGML_BACKEND_DIR=${placeholder "out"}/lib"
    "-DGGML_VULKAN=ON"
    # Only the Vulkan plugin is wanted; the CPU backends already ship with
    # zvec-grep, and tests/examples would pull in the whole framework.
    "-DGGML_CPU=OFF"
    "-DGGML_BLAS=OFF"
    "-DGGML_BUILD_TESTS=OFF"
    "-DGGML_BUILD_EXAMPLES=OFF"
    # Resolve libggml-base.so.0 from the directory the plugin is installed
    # into (zvec-grep's lib/), not from this derivation's own store path.
    "-DCMAKE_INSTALL_RPATH=$ORIGIN"
  ];

  meta = {
    description = "Vulkan backend plugin for the ggml bundled by zvec-grep";
    homepage = "https://github.com/ggml-org/ggml";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
