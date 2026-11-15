/* An OLED-safe animated gradient wallpaper for Viewport's wallpaper-extension
 * hook (registerWallpaper). It renders entirely in the shell — a z-index:-1
 * layer under the desktop's own children, the same place the shell puts a film
 * wallpaper — so it works under every compositor renderer, Vulkan included,
 * with no GLSL.
 *
 * Built to the burn-in rules in this directory's README:
 *
 *   * True black is the ground. Unlit OLED pixels do not age, so the frame is
 *     black wherever no glow reaches, not a dark grey wash.
 *   * The light MOVES and never settles. Each glow drifts on its own period and
 *     the periods are pairwise incommensurate (primes), so the composite is
 *     quasi-periodic — it never loops back to the same frame the way a short
 *     animation does. A loop puts its light back in the same pixels every cycle
 *     and ages them like a still; this does not.
 *   * Nothing is bright. The glows are the dark end of the Kanagawa Dragon
 *     palette, capped so the brightest pixel stays well under half drive and
 *     the mean drive is a few percent — the same budget the baked pool keeps.
 *   * A fixed screen-space dither (interleaved gradient noise, one LSB) sits on
 *     top so the near-black falloffs do not band. It is static, so it cannot
 *     shimmer.
 *   * It is cheap: the motion is GPU-composited CSS transforms, not a per-frame
 *     canvas redraw, so an idle desktop costs a compositor thread and nothing
 *     else — which matters when the machine is also running a game.
 *
 * `root` is the output's own `.desktop`, so the layer is built inside it and
 * paints that monitor alone; the container, stylesheet and keyframes are named
 * per output so two monitors can run different palettes at different speeds.
 *
 * Options (wallpaper_options), all optional:
 *   palette   "dragon" (default), "orchid", "ice", "ember", "mono"
 *   intensity 0..1, scales the glow strength (default 1). Lower = darker.
 *   speed     multiplier on the drift periods (default 1). Higher = faster.
 *   dither    0..2, dither strength in LSB (default 1). 0 disables.
 */
registerWallpaper('oled-gradient', {
  apply({ root, options }) {
    const opts = options || {};
    const suffix = (root.dataset && root.dataset.output) || 'page';
    const wrapId = `oled-gradient-${suffix}`;
    const styleId = `oled-gradient-style-${suffix}`;

    /* The dark end of each palette, lifted from live.html so a gradient stays
     * coherent with the baked pool and the pinned base16 scheme. Only the first
     * few stops are used: the bright end of the ramp is exactly what an OLED
     * should not hold. */
    const PALETTES = {
      dragon: ['#0b1514', '#16302c', '#2c5347', '#4f7c60', '#84a487', '#b7b490'],
      orchid: ['#140d22', '#2a1745', '#4b2a72', '#7a4f9e', '#a292a3', '#c9a6c4'],
      ice:    ['#0a141c', '#14273a', '#22475f', '#3f7290', '#6ea0bb', '#a8c7d8'],
      ember:  ['#1c0d09', '#3a1610', '#6b2a1a', '#a04a26', '#c4746e', '#d9a066'],
      mono:   ['#101010', '#1f1f1f', '#383838', '#5c5c5c', '#848484', '#adadad'],
    };
    const pal = PALETTES[opts.palette] || PALETTES.dragon;
    const intensity = Number.isFinite(opts.intensity)
      ? Math.max(0, Math.min(1, opts.intensity)) : 1.0;
    const speed = Number.isFinite(opts.speed) && opts.speed > 0 ? opts.speed : 1;
    const dither = Number.isFinite(opts.dither)
      ? Math.max(0, Math.min(2, opts.dither)) : 1;

    /* Pairwise-incommensurate drift periods (seconds), scaled by `speed`. The
     * glow never returns to the same place at the same time as another, so the
     * light keeps moving across the panel instead of etching a loop. */
    const periods = [47, 71, 113, 157].map((p) => p / speed);

    /* One small, brighter accent gives the frame a readable peak (~0.5-0.6 sRGB)
     * while the broad glows behind it stay dark, so the mean drive stays a few
     * percent: a clump on black, not a haze — the same shape the pool keeps. */
    const glows = [
      { c: pal[4], a: 0.85, size: 46, x: 30, y: 36, dx: 16, dy: 12, rot: 9 },
      { c: pal[3], a: 0.50, size: 68, x: 72, y: 60, dx: -16, dy: -12, rot: -6 },
      { c: pal[2], a: 0.55, size: 92, x: 46, y: 82, dx: 12, dy: -14, rot: 5 },
      { c: pal[1], a: 0.60, size: 115, x: 82, y: 16, dx: -10, dy: 12, rot: -4 },
    ];

    const hexToRgb = (h) => [
      parseInt(h.slice(1, 3), 16),
      parseInt(h.slice(3, 5), 16),
      parseInt(h.slice(5, 7), 16),
    ];

    let keyframes = '';
    let layers = '';
    glows.forEach((g, i) => {
      const [r, gg, b] = hexToRgb(g.c);
      const alpha = (g.a * intensity).toFixed(3);
      const dur = periods[i % periods.length].toFixed(2);
      const anim = `oled-grad-drift-${suffix}-${i}`;
      /* A gentle closed drift: out and back on an ease, plus a slow turn, so
       * the blob wanders rather than sliding on a straight line. */
      keyframes += `
        @keyframes ${anim} {
          0%   { transform: translate(-50%, -50%) translate(0, 0) rotate(0deg) scale(1); }
          50%  { transform: translate(-50%, -50%) translate(${g.dx}vw, ${g.dy}vh) rotate(${g.rot}deg) scale(1.12); }
          100% { transform: translate(-50%, -50%) translate(0, 0) rotate(0deg) scale(1); }
        }`;
      layers += `
        #${wrapId} .glow-${i} {
          left: ${g.x}%; top: ${g.y}%;
          width: ${g.size}vmax; height: ${g.size}vmax;
          background: radial-gradient(closest-side,
            rgba(${r}, ${gg}, ${b}, ${alpha}), transparent 72%);
          animation: ${anim} ${dur}s ease-in-out infinite;
        }`;
    });

    /* Fixed screen-space dither: interleaved gradient noise, the same pattern
     * live.html uses, baked once into a tile and laid over the glows at ~1 LSB.
     * Static, so it cannot shimmer; it only breaks the near-black banding. */
    let ditherUrl = '';
    if (dither > 0) {
      const n = 256;
      const cv = document.createElement('canvas');
      cv.width = n; cv.height = n;
      const ctx = cv.getContext('2d');
      const img = ctx.createImageData(n, n);
      const ign = (x, y) => {
        const v = 52.9829189 * ((0.06711056 * x + 0.00583715 * y) % 1);
        return v - Math.floor(v);
      };
      for (let y = 0; y < n; y++) {
        for (let x = 0; x < n; x++) {
          const on = ign(x, y) > 0.5 ? 255 : 0;
          const o = (y * n + x) * 4;
          img.data[o] = img.data[o + 1] = img.data[o + 2] = on;
          img.data[o + 3] = 255;
        }
      }
      ctx.putImageData(img, 0, 0);
      ditherUrl = cv.toDataURL('image/png');
    }
    /* ~1 LSB over near-black: white at this alpha lifts a dark pixel by about
     * dither/255 of full scale. */
    const ditherOpacity = (dither * 0.004).toFixed(4);

    let style = document.getElementById(styleId);
    if (!style) {
      style = document.createElement('style');
      style.id = styleId;
      document.head.appendChild(style);
    }
    style.textContent = `
      .oled-gradient {
        background-image: none !important;
        background-color: transparent !important;
      }
      #${wrapId} {
        position: absolute; inset: 0;
        z-index: -1;
        pointer-events: none;
        overflow: hidden;
        background: #000;
      }
      #${wrapId} .glow {
        position: absolute;
        transform: translate(-50%, -50%);
        will-change: transform;
      }
      ${keyframes}
      ${layers}
      #${wrapId} .dither {
        position: absolute; inset: 0;
        background-image: url(${ditherUrl});
        background-repeat: repeat;
        opacity: ${ditherOpacity};
        mix-blend-mode: screen;
      }
      @media (prefers-reduced-motion: reduce) {
        #${wrapId} .glow { animation: none; }
      }
    `;

    let wrap = document.getElementById(wrapId);
    if (!wrap) {
      wrap = document.createElement('div');
      wrap.id = wrapId;
      glows.forEach((g, i) => {
        const el = document.createElement('div');
        el.className = `glow glow-${i}`;
        wrap.appendChild(el);
      });
      if (dither > 0) {
        const d = document.createElement('div');
        d.className = 'dither';
        wrap.appendChild(d);
      }
      /* Inside the output's own desktop, under its children — not on the page
         body — so each monitor carries its own scene. */
      root.appendChild(wrap);
    }
    root.classList.add('oled-gradient');
  },

  clear({ root }) {
    const suffix = (root.dataset && root.dataset.output) || 'page';
    root.classList.remove('oled-gradient');
    document.getElementById(`oled-gradient-style-${suffix}`)?.remove();
    document.getElementById(`oled-gradient-${suffix}`)?.remove();
  },
});
