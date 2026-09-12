# oled — wallpapers a panel should not remember

Procedural wallpapers for an OLED desk, built so that nothing they draw stays
in one place, and nothing they draw is bright enough to matter.

## Why a picture cannot fix burn-in

Burn-in is not a property of an image, it is a property of *exposure*: how much
light a subpixel emits, and how long it emits it in the same place. That makes
two independent failure modes, and they need different answers.

- **A bright static shape** — a logo, a bar, a sun in the corner — etches its
  own outline. Every scene here is procedural and has no shape that recurs, and
  nothing is drawn at a fixed position.
- **A whole panel held above black** — even a soft, dim, even wash ages every
  pixel of the panel, just slowly. This is the one people forget, because a
  grey wallpaper looks harmless. A frame with a large area over 25% grey is
  rejected by the generator for this reason.

And there is a third thing that no single image can do anything about: *a
single image is still*. So the pool rotates, through the compositor's own
config socket. That is the actual burn-in fix; everything else is what makes
each frame cheap to hold while it is up.

## What the numbers mean

The unit that ages a subpixel is emitted light, which is **linear**. Pixel
values in a PNG are **sRGB**, which is not: sRGB 0.5 is linear 0.214. So half
grey is a fifth of the drive, and a wallpaper that looks like a moody dark
picture is cheaper than it looks. Every frame is measured both ways:

| measure | what it is | budget |
| --- | --- | --- |
| `apl` | mean linear drive over the frame — the light emitted | < 8% |
| `drive50` | fraction of pixels over **half drive** | < 0.8% |
| `max` | brightest pixel in sRGB — whether the frame reads at all | 0.40 .. 0.95 |
| `over25` | fraction over 25% grey — a wash lights the whole panel | < 62% |

`bake.mjs selftest` prints that table for every scene, and `verify` prints it
for the files actually on disk. The shipped pool measures **0.35–4.7% mean
drive, nothing over half drive, peaks 0.48–0.72** — a moody dark picture that
costs a few percent of the panel's drive and has no pixel running hard.

The sampler scores each candidate frame and *retries* an outlier, moving both
the moment and the noise realisation, because a sparse seed of the nebula field
stays sparse at every moment. It rejects two opposite failures: too much light
(the budget above), and — the one an average cannot see — a frame that is
blank because almost nothing in it is lit. A frame with a 0.71 peak and 0.4% of
its pixels above a quarter grey is a black screen with a speck on it, and 0.08%
mean drive sounds ideal to a budget that only looks at drive.

The knob is `peak` (`--peak`, default 0.55, or `[` / `]` live): the largest
fraction of full drive any pixel may reach, applied as a soft chroma-preserving
knee so luminance asymptotes to it instead of clipping and shifting hue.

## The pieces

| | |
| --- | --- |
| `live.html` | the art, and the only copy of it. Animates forever in a browser: drifts, rotates its hue, and swaps scene every `?rotate=` seconds. |
| `bake.mjs` | drives one headless Chromium over DevTools to render `live.html` to files, verify them, and preview them. |
| `oled-cycle` | rotates the pool through Viewport's control socket on an interval. |
| `pool/` | the frames, plus `manifest.json` and a `preview.html` |

Because the baker runs the same page and the same draw call as the live
wallpaper, a baked still and a live frame cannot drift apart. Nothing here
reimplements the shader in a second language.

## Using it

```console
$ node bake.mjs selftest                       # every scene, with its drive budget
$ node bake.mjs pool --count 14 --jobs 6 --w 5120 --h 1440
$ node bake.mjs verify --dir pool              # decode every file, measure it
$ node bake.mjs verify --dir pool --diff       # ... and diff it against a re-render
$ node bake.mjs sheet                          # contact sheet -> preview.png
$ ./oled-cycle --list                          # the rotation order
$ ./oled-cycle --interval 30m                  # rotate for real
```

`verify` is the check worth having. It decodes each file the way the shell will
and reports the same budget on the artifact, and with `--diff` it re-renders
the parameters that made each frame and compares them pixel by pixel. That is
what catches an encode that crushed the dither and left the dark end banded,
which no summary average can see, because banding is a shape. The whole shipped
pool currently diffs at **0/255** — the files are exactly what the shader drew.

To choose by eye, open `pool/preview.html`, or look at `preview.png`; both show
the frames in rotation order with their drive.

### Size

14 frames at 5120×1440 are **29 MB**, because they are stored lossless. That is
worth knowing before it is committed: `pool/` is a build product of
`live.html` plus a fixed seed, so it can be `.gitignore`d and regenerated, or
made smaller with `--count 7`. The lossless choice is not caution —
WebP at quality ≤ 0.98 measured **17–18/255 of error** on the aurora frame,
which is a quantiser step several times larger than the 1-LSB dither it then
throws away, and a dither that does not survive the encode is not protecting
the gradient it was added for. At quality 1.0 WebP is lossless, and measures
2–3× smaller than PNG for this art (`--format png` is there if you want a
format that is lossless by construction rather than by measurement).

## Wiring it into this desk

The desktop is Viewport (Smithay) drawing DP-1 + DP-3 joined as one
5120×1440 surface, so the frames are baked at exactly that: nothing is scaled
or cropped, which is also why the art is written to be continuous in x rather
than centred on a single screen.

The wallpaper is settable at runtime, which upstream documents as the thing a
wallpaper cycler uses — no config reload, nothing written to disk:

```console
$ viewport msg -t config.wallpaper --path /persistent/etc/nixos/wallpapers/oled/pool/00-silk-mono.webp
$ viewport msg -t config.wallpaper --mode fill     # mode and picture are independent
```

`oled-cycle` runs that on a timer. The rotation order is interleaved by scene,
so no two neighbours are the same one; it holds no state on disk and starts at
a fresh point each launch. To run it as a user service, in the style of
`home/services.nix`:

```nix
systemd.user.services.oled-cycle = {
  Unit = {
    Description = "Rotate the OLED wallpaper pool";
    After = [ "graphical-session.target" ];
    PartOf = [ "graphical-session.target" ];
  };
  Service = {
    ExecStart = "/persistent/etc/nixos/wallpapers/oled/oled-cycle --interval 30m";
    Restart = "always";
    RestartSec = 30;
  };
  Install.WantedBy = [ "default.target" ];
};
```

`pool` is the script's own directory, so there is nothing to point at. No
`WAYLAND_DISPLAY` is needed: `viewport msg` falls back to the newest
`viewport-*.sock` in `$XDG_RUNTIME_DIR` when it is unset, which is the case for
a unit that never imported the session environment (name one with `--socket`
to override). A 30 minute interval is a default, not a rule — what matters is
that no frame is up for hours.

For a *static* setting that survives restarts, `pool/00-*.webp` is an ordinary
picture path, so `stylix.image` can point at one (or `programs.viewport.extraArgs`
at `--wallpaper`). The rotation is the part that wants the socket.

## Choices worth knowing

- **Scene.** `silk` (domain-warped fbm), `aurora`, `nebula`, `orbit`, `ripple`,
  `bands`, `whisper`. `whisper` is silk at a fraction of the drive, for a dark
  room or a panel that already has hours on it. `?mode=N` live, or `--list`.
- **Palette.** `dragon` is the default and is Kanagawa Dragon's own accents on
  a near-black ground, so a frame stays coherent with the pinned base16 scheme;
  `orchid`, `ice`, `ember`, `synthwave`, `mono` are the others. Low saturation
  is deliberate — it is the friendliest thing to ask of a subpixel every day.
  `synthwave` measures ~30% more drive than `dragon` for the same scene, which
  is the honest cost of the punchier colour.
- **Why not an animated GIF or video.** Both are supported as a `wallpaper`,
  and both loop. A loop puts its light back in the same pixels every cycle, so
  over a day the exposure per pixel is exactly the same as a still — only
  smearier. Rotation is the thing that moves the light.
- **`background_terminal`** would allow a genuinely animated backdrop, but the
  running compositor here is the **CEF** shell, which paints opaque and refuses
  it (the docs say to start with `--shell-backend=webkitgtk`). Hence stills.
- **`live.html`** is the real animated answer, at 60 fps, with a Lissajous
  pixel offset whose two periods never line up and no overscan needed — the
  content is procedural and unbounded, so translating it cannot uncover an
  edge. It needs a browser window, which is why the pool exists.
- **Silent choices.** Five octaves of fbm (`--oct`); a fixed screen-space
  interleaved-gradient dither at one LSB, which is what keeps near-black
  gradients from banding on OLED and cannot shimmer, because it is not random
  per frame (`--dither-mode bayer` swaps in the ordered matrix, ~10% smaller
  lossless, more visible as texture — off by default so a baked frame and a
  live frame stay the same picture); a black point that takes everything under
  ~0.35% drive to true zero, so those pixels are genuinely off; and no text
  anywhere, because a label is a fixed shape.
- **Not included.** Screen-off/idle handling (the compositor and swayidle
  already do that), and anything that writes to the compositor's config: the
  rotation is runtime only, so a restart lands back on `stylix.image`.
