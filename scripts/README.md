# scripts — manual host tools

These files are deliberately not imported, packaged, or started by the flake.
Nothing under modules/, home/ or pkgs/ references them; run them by hand from a
checkout on the host they target (the desktop).

## stream-display.sh

Streams the whole display output (VT console and Wayland session) to YouTube
HLS, or records it to a local Matroska file. Capture uses ffmpeg's kmsgrab, so
it follows whatever the GPU is scanning out; the encode is VAAPI.

    ./scripts/stream-display.sh [--output DP-1] [--file out.mkv] \
        [--codec h264|hevc|av1] [--pass-entry NAME | --key-file PATH] \
        [--fps N] [--bitrate 6M] [--size WxH]

Defaults and requirements:

- Desktop only: needs a DRM/KMS device and a VAAPI render node (default
  /dev/dri/renderD128).
- Re-execs itself with run0 because kmsgrab needs CAP_SYS_ADMIN. The stream key
  from `pass show youtube-hls` (or --key-file) is written to a 0600 temp file
  and unlinked by the privileged half; it never enters argv or the environment.
- Nix with flakes is required: the script runs ffmpeg-full, drm_info, jq and gcc
  from nixpkgs on demand.
- h264 is the only codec observed to play back on YouTube; AV1 ingests but never
  appears in Studio, hevc is untested.
- --file switches to local recording and reads no stream key.

## kms-dropmaster.c

An LD_PRELOAD shim for ffmpeg's kmsgrab. ffmpeg opens the DRM primary node with
open(O_RDWR), which hands it DRM master when no compositor holds it; kmsgrab
does not need master, and holding it makes the compositor fail to start with
EBUSY. The shim drops master immediately after such an open, and is harmless
when another process already holds it.

It is not built standalone: stream-display.sh compiles it into its private
workdir with gcc -O2 -shared -fPIC. Set KMS_DROPMASTER_DEBUG=1 to log each drop
to stderr.
