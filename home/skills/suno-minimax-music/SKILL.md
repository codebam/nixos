---
name: suno-minimax-music
description: Write songs for Suno v6 and MiniMax Music 3 (MiniMax Audio) — one structure-tagged lyric sheet, one shared style prompt, and the per-platform settings that render it on both.
whenToUse: Use when writing original lyrics, a style prompt, or generation settings for Suno or MiniMax Music, or when one song draft must render on either platform.
metadata:
  adapted-from: "a5c-ai/babysitter lyric-writing (SK-MAC-001), rewritten for Suno v6 + MiniMax Music 3"
  facts-checked: "2026-09-12"
---

# Suno + MiniMax Music

Deliver a **song package that renders on both platforms from one paste**:

1. **Lyric sheet** — structure-tagged, no inline production notes, ≤3,000 characters.
2. **Style core** — one ≤1,000-character prompt that pastes into Suno's Styles field
   and MiniMax's music description unchanged (MiniMax may then expand it to ≤2,000).
3. **Settings blocks** — Suno Custom mode + Advanced Options; MiniMax Music 3
   model/lyrics/audio settings.

Ship one shared lyric sheet. Only add the optional *Suno pass* below when the user
asks for per-section directions, and label it as not for MiniMax.

## 1. Pin the brief

Decide, and state in one line: subject/narrator, genre + at most two influences,
mood and its arc, tempo/BPM and groove, key/scale, vocal (gender, range, timbre,
delivery by section), language, target duration, explicit vs clean, instrumental
or not, and any must-use phrase. If the user gave only a vibe, choose specific
defaults rather than asking more than one question.

## 2. Write the lyric sheet

- Structure: `[Intro]` (0–4 lines) → two or three `[Verse]` (4–8 lines each) →
  `[Pre-Chorus]` (2–4) → `[Chorus]` (4–8) → optional `[Post-Chorus]`/`[Hook]` →
  `[Bridge]` (2–6) → final `[Chorus]` → `[Outro]` (1–4).
- Hook: ≤8 words, repeatable, first or last line of the chorus, **identical text
  every time the chorus appears** (repetition is how both models lock the melody).
- One image or one idea per line; concrete nouns over abstractions.
- Keep matching lines within about ±2 syllables (roughly 6–12 syllables a line);
  sing the hook silently in your head before committing it.
- Rhyme intentionally (AABB/ABAB; near rhymes are fine) — never force a rhyme
  against meaning.
- Arc: verse 1 sets the world → pre-chorus tightens → chorus releases → verse 2
  complicates → bridge turns → final chorus lands changed in arrangement only.
- Parentheses mark **backing vocals / ad-libs only** — both platforms sing them as
  such (MiniMax's own generated examples use `(So wonderful)`); never put
  instructions inside them.
- **No production notes in the shared sheet.** Dynamics, delivery and arrangement
  directions belong in the style core, or in the Suno-only pass.

### Tag vocabulary

**Core tags — documented by both Suno and MiniMax Music 3:**
`[Intro]`, `[Verse]` / `[Verse 1]` / `[Verse 2]`, `[Pre-Chorus]`, `[Chorus]`,
`[Post-Chorus]`, `[Bridge]`, `[Instrumental]`, `[Solo]`, `[Outro]`

**Extended tags — both accept, use when the song needs them:**
`[Hook]`, `[Interlude]`, `[Break]`, `[Build-Up]`, `[Drop]`, `[Breakdown]`,
`[Transition]`

**Rules:** one tag per line; tags stay in English even when the lyrics are not;
number repeated sections (`[Verse 1]`, `[Verse 2]`); blank line between sections;
if a platform ignores a tag, switch to the spelling in that platform's current
docs (MiniMax's Music API also lists `[Pre Chorus]`, `[Post Chorus]`,
`[Build Up]`, `[Inst]`).

**Suno-only tags — only in the optional Suno pass, never in the shared sheet:**
parameterized tags `[Verse 1: whispered vocals, sparse piano only]`, plus
`[Whisper]`, `[Spoken Word]`, `[Ad-lib]`, `[Backing Vocals]`, `[Male Vocal]`,
`[Female Vocal]`, `[Choir]`, `[Duet]`, `[Harmony]`, `[Rap]`, `[Scream]`,
`[Humming]`, `[Fade In]`, `[Fade Out]`, `[Silence]`, `[Crescendo]`,
`[Decrescendo]`, `[Key Change]`, `[Tempo: slow]`, `[End]`.
MiniMax documents only structure tags; everything else belongs in its music
description.

**Length budget:** MiniMax hard-caps lyrics at 3,500 characters; Suno accepts
5,000 but starts rushing past roughly 3,000. Target **≤3,000 characters including
tags** (about 40–60 lines), which leaves headroom on both.

## 3. Write the style core (≤1,000 characters)

Pastes into **Suno's Styles field** and **MiniMax's music description**. Order
matters — front-load what matters most.

Formula, as one prose block with no labels or brackets:

> genre + one or two influences → mood and emotional progression → tempo/BPM and
> groove → key/scale (optional) → three to six instruments with their roles →
> vocal type and how it changes by section → arrangement arc (verse sparse →
> chorus wide → bridge stripped → final chorus lift) → production profile
> (clean/warm/punchy, analog/digital, stereo width)

Rules:

- Front-load genre + vocal + mood; Suno weights the opening of the style prompt,
  and MiniMax still keys on the first descriptors.
- One primary genre, at most two influences. Stacking many genres produces mush,
  especially on MiniMax.
- No artist or band names and no "sounds like": describe traits instead (both
  platforms may filter or ignore references) — "powerful female pop vocal over
  piano and live drums", not "sounds like Adele".
- No negatives ("no drums", "avoid"): those go in Suno's **Exclude Styles**; in
  the MiniMax description, restate what **is** wanted.
- No mixer jargon (sidechain, saturation settings), no slider numbers in the text,
  and treat BPM as guidance, not a lock.
- Give the vocal somewhere to go: "breathy, close verses; belted, layered chorus;
  stacked harmonies on the final chorus".

Example (≈600 characters):

> Modern dark R&B with subtle melodic trap influences, late-night and
> introspective. About 84 BPM, laid-back head-nod groove in F minor. Deep 808
> sub-bass, sparse minor piano, soft ambient pads, restrained trap hats. Warm
> male baritone, intimate sing-rap verses that open into a wider, layered chorus;
> stacked harmonies on the final chorus. Verses stay minimal, the pre-chorus
> raises tension, the chorus widens with full drums and vocal stacks, the bridge
> strips back to piano and voice. Clean modern mix, controlled low end, wide but
> natural stereo image.

**MiniMax expansion (optional, ≤2,000 characters):** MiniMax Music 3's model card
recommends a *Structured Caption* with three parts — **Global metadata** (genre,
subgenre, BPM, key/scale, emotional progression, listening scenario, production
profile), **Vocal details** (gender, timbre, performance style, harmony, backing
vocals, effects), **Arrangement** (lead and supporting instruments and how they
evolve per section, groove, bass, percussion, textures, space). Same content as
the style core, more section-level detail.

## 4. Suno settings (v6 family)

All pre-v6 models are retired. Custom mode exposes: Lyrics, Styles, Title, and
Advanced Options.

| Setting | Value |
|---|---|
| Model | `v6` for precision; `v6-wild` to explore; `v6-mini` for fast free drafts |
| Mode | Custom (Simple only for throwaway ideas) |
| Title | ≤100 characters, descriptive |
| Styles | paste the style core |
| Exclude Styles | everything rejected, comma-separated, ≤1,000 chars |
| Vocal Gender | Male / Female (Advanced Options) — must match the style core |
| Instrumental | off for vocal songs; on for instrumentals |
| Variety | **0** keeps your style tags exactly as typed; raise (~20–40) only to explore, it rewrites the prompt |
| Style Influence | start **75–85** for adherence; lower toward Loose only to let the model reinterpret |
| Weirdness | 50 is neutral; ~20 for a conventional, release-safe take; 60–70 to get strange |
| Max Mode | on for songs >2:00, close covers, style transfer, consistent vocals; off for quick drafts |
| Audio Influence | appears only with an audio upload; use when covering/continuing |

Slider numbers are calibration, not law — change one control per generation.

**Optional Suno pass** (only if asked): a second copy of the lyrics that adds
parameterized section tags (`[Verse 1: whispered, sparse piano]`) and `(backing
vocal)` lines. Do not paste this pass and the shared sheet together.

## 5. MiniMax settings (Music 3 / MiniMax Audio)

Music 3.0 generates up to about five minutes and takes a **music description**
plus **lyrics**. The paid Music and Lyrics APIs stopped accepting new users on
2026-08-20; use the MiniMax Audio app, or the open-source MiniMax-Music3 model
via SGLang/ComfyUI/diffusers. `music-2.6` is the fallback API model.

| Setting | Value |
|---|---|
| Model | `music-3.0` (app: Music 3.0) |
| Music description | the style core (expand to the Structured Caption up to 2,000 chars) |
| Lyrics | paste the shared sheet, ≤3,500 chars |
| Instrumental | on → omit lyrics; the description becomes required (1–2,000 chars) |
| Lyrics optimizer | off when pasting lyrics (it only writes lyrics when the box is empty) |
| API output_format | `url` (24 h expiry) or `hex` |
| API audio_setting | `sample_rate: 44100`, `bitrate: 256000`, `format: mp3` (`wav`/`pcm` also) |

Minimal API shape:

```json
POST https://api.minimax.io/v1/music_generation
{
  "model": "music-3.0",
  "prompt": "<style core>",
  "lyrics": "<shared sheet>",
  "output_format": "url",
  "audio_setting": { "sample_rate": 44100, "bitrate": 256000, "format": "mp3" }
}
```

For a local/diffusers run set `audio_duration` in seconds; on SGLang-Omni,
`max_new_tokens` is audio frames at 25 fps. The cover model uses different limits
(prompt 10–300 chars, lyrics 10–1,000, reference audio 6 s–6 min).

## 6. Instrumentals

Suno: toggle **Instrumental** on and put `[Instrumental]` in the lyrics field;
fill Exclude Styles with `vocals`. MiniMax: set the instrumental flag, omit
lyrics and make the description carry the whole arrangement (state the lead
instrument and how it evolves). There is no reliable "no vocals" metatag on
either platform.

## 7. Output template

```markdown
# <Title>

**Brief** — <genre>, <vocal>, <mood>, ~<BPM> BPM, <key>, <language>, target ~<duration>.
**Concept** — <one sentence>.

## Lyrics (paste into Suno Lyrics and MiniMax lyrics)
[Intro]
...
[Verse 1]
...
[Chorus]
...
[Outro]
...

## Style core (≤1,000 chars — paste into Suno Styles and MiniMax description)
<style core paragraph>

## Suno — Custom mode
Model: v6 · Mode: Custom · Variety: 0 · Style Influence: 80 · Weirdness: 50 · Max Mode: <on/off>
Vocal Gender: <Male/Female> · Instrumental: off
Exclude Styles: <comma-separated>
Styles: <style core>

## MiniMax — Music 3.0
Model: music-3.0 · Instrumental: off · Lyrics optimizer: off
Description: <style core / Structured Caption>
Lyrics: <shared sheet>
API: output_format url; audio_setting sample_rate 44100, bitrate 256000, format mp3

## Render notes
- First pass: ...
- If Suno rushes: ...
- If MiniMax sounds generic: ...
```

## 8. Checklist

- [ ] Lyric sheet ≤3,000 chars; tags on their own lines, in English; sections numbered.
- [ ] Only core/extended tags in the shared sheet; no Suno-only tags, no inline directions.
- [ ] Parentheses used only for backing vocals/ad-libs.
- [ ] Every chorus has identical text; the hook is repeated verbatim.
- [ ] Style core ≤1,000 chars, front-loaded, no artist names, no negatives, no slider numbers.
- [ ] Suno Exclude Styles carries every rejected element.
- [ ] MiniMax description expanded to the Structured Caption when the render sounds generic.
- [ ] Both settings blocks and render notes present.

## 9. Guardrails

- Write original lyrics; never reproduce existing copyrighted lyrics.
- If asked to imitate a named artist, translate the request into descriptive
  traits (genre, era, instrumentation, vocal quality) and say that is what you
  did. Never promise a cloned voice.
- Deliver the package as text; you cannot render audio from this skill.
- Keep explicit content only to the level requested; default to clean.
