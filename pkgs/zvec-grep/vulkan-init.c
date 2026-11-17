/* Registers the ggml Vulkan backend inside zg processes.
 *
 * zg 0.3.0's prebuilt Linux binary never loads GPU backends beyond its own
 * CUDA plugin logic: llama_cpp::llama_backend::load_backends_from_path (the
 * only caller of ggml_backend_load_all_from_path) is dead code, so a
 * libggml-vulkan.so sitting in lib/ is never discovered and `--device
 * vulkan` reports "GPU backend is unavailable, falling back to CPU".
 *
 * This shim is LD_PRELOADed by the zg wrapper. Its constructor runs after
 * the executable's libraries are initialized; the RTLD_NOLOAD probe keeps
 * it inert in every other process the wrapper's environment reaches (rg,
 * node, ...), where the bundled ggml is not loaded. ZG_VULKAN_PLUGIN is
 * defined at compile time to the installed plugin's store path.
 */
#include <dlfcn.h>

__attribute__((constructor)) static void zg_vulkan_init(void) {
  void *ggml = dlopen("libggml.so.0", RTLD_NOLOAD | RTLD_NOW);
  if (!ggml) {
    return;
  }
  void (*load)(const char *) =
      (void (*)(const char *))dlsym(ggml, "ggml_backend_load");
  if (load) {
    load(ZG_VULKAN_PLUGIN);
  }
}