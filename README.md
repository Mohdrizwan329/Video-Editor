# Video Editor

A professional mobile video editor built with Flutter. Multi-clip timeline with a
centred playhead, live-graded preview, overlay lanes for text, stickers, PIP
and audio, and a single-pass FFmpeg renderer that matches what the preview
shows.

## What it does

**Library**
- Projects saved as individual JSON files, autosaved while you edit
- Cover frames pulled from the first clip, rename / duplicate / delete
- Ratio shortcuts to start a Reels, square, YouTube or cinemascope project
- Back up a project to a single `.svproj` bundle (manifest + embedded media)
  and restore it on another device

**Templates**
- 15 prefab templates across 6 categories (Reels, Vlog, Travel, Promo, Story,
  Cinematic)
- Pick a template, pick your media, and the slots are filled: cuts timed,
  transitions set, grades applied, Ken Burns moves written as real keyframes
- Media is cycled when you supply fewer clips than there are slots, so the
  result is always a complete edit
- Everything a template produces is an ordinary editable clip or layer — there
  is no locked "template mode" to escape from

**Import**
- Gallery grid with albums, video/photo tabs and ordered multi-select
- Drag to reorder the selection before it lands on the timeline
- File browse fallback for desktop and for when photo permission is denied

**Timeline**
- Fixed centre playhead; the track scrolls under it, drag to scrub
- Pinch to zoom between 12 and 320 px/s
- Filmstrip thumbnails, trim grips on the selected clip, long-press to reorder
- Transition handle at every clip boundary
- Separate lanes for PIP overlays, text, stickers and audio, with overlapping
  items auto-packed onto sub-rows
- Keyframe diamonds under the selection; tap one to seek to it
- Beat ticks on music lanes, with snap-to-nearest-beat

**Keyframes**
- 9 animatable properties: position X/Y, scale, rotation, opacity, volume,
  filter intensity, corner radius, blur
- 5 easings per key: linear, ease in, ease out, ease in-out, hold
- Works on main-track clips, text, stickers, PIP layers and audio
- Step between keys, drop or delete one at the playhead
- Exported as real FFmpeg expressions — `overlay` x/y, `scale` with
  `eval=frame`, `rotate`, `geq` alpha and `volume` with `eval=frame`

**Clip tools**
- Split at playhead, duplicate, delete, replace
- Flat speed 0.1x-8x, or 8 ramping curves (Montage, Hero, Bullet, Jumper,
  Flash in/out, Ramp up/down) rendered as a variable-rate `setpts` map
- Volume with fade in/out
- 59 colour grades in 6 categories with an intensity slider
- 19 manual adjustments: brightness, contrast, saturation, temperature, tint,
  hue, highlights, shadows, a three-point tone curve, sharpen, vignette, fade,
  grain, blur and denoise
- Crop insets, zoom, pan, fit/fill/stretch, rotate, mirror
- 7 mask shapes with feather, size, position, rotation and invert
- Chroma key with similarity and edge blend
- One-pass stabilization
- Reverse and freeze-frame (rendered to real files by FFmpeg)
- Extract audio onto its own lane
- Optional `.cube` LUT per clip

**Transitions**
- 52 transitions in 6 groups (Basic, Slide, Wipe, Shape, Bars, Motion), each
  mapped to a real `xfade` mode so the picker never offers what the renderer
  cannot produce

**Layers**
- Text: 25 style presets in 6 categories, 5 bundled fonts, gradient fill,
  outline, shadow, backdrop, spacing, line height, alignment
- 33 animations in 6 families, including continuous ones (shake, pulse, blink,
  wobble, neon, wave) that run for the layer's whole life
- Stickers: 6 emoji packs plus 8 vector shapes with colour and size
- PIP overlays: 14 blend modes, masks, chroma key, own grade, own speed,
  volume, corner radius, opacity
- Audio: 28-sound built-in library, music import with a remembered "My music"
  list, voice-over recording synced to the playhead, waveform display, beat
  detection, per-item volume, fades, speed, ±12 semitone pitch and 10
  voice-changer presets
- Drag, pinch and twist any layer directly on the preview canvas

**Sound library**
- 6 musical loops (Lo-fi, Ambient, Upbeat, Cinematic, Chill, Minimal) and 22
  effects across Riser, Whoosh, Impact, UI and Tone
- Nothing here is a recording: every sound is synthesised on device with
  FFmpeg's `aevalsrc`, which is how the app ships a usable library without
  licensing anyone's audio
- Loops are real arpeggios built note by note from chord voicings, not drones
- Imported tracks are remembered in "My music" so the next project starts with
  something in it

**Speech**
- Text-to-speech through the platform engine (Android TextToSpeech, iOS
  AVSpeechSynthesizer): pick a device voice, set rate and pitch, preview, then
  drop the narration on the timeline as a real audio clip
- Auto-captions with whisper.cpp running fully on device — nothing is uploaded
- Three model sizes (Tiny / Base / Small); the weights are downloaded once on
  first use and the panel says so before starting
- Captions are wrapped to fit the canvas and land as flagged text layers, so
  they can be restyled or cleared as a group without touching hand-placed text
- SRT import and export

**Canvas**
- 9 aspect ratios including Original
- Background: solid colour, blurred copy of the frame, or gradient

**Export**
- MP4 (H.264/AAC) or animated GIF with a generated palette
- 480p / 720p / 1080p / 2K / 4K, 24-60 fps, 4 quality tiers
- Live progress with ETA and encode speed, cancellable
- Saves to the system gallery

## How it is put together

```
lib/
  core/          theme, timeline constants, duration formatting
  data/
    models/      Project, VideoClip, the layer types, filters, adjustments
    repositories/ project persistence
    services/    FFprobe metadata, thumbnails, overlay rasterizer, renderer
  state/         EditorController (mutations + undo), PreviewEngine (playback)
  ui/            home, picker, editor (preview / timeline / toolbar / panels), export
```

Three ideas hold it together:

**One source of truth for the look.** A grade is a `FilterPreset` — a handful
of numbers. The same object produces a 4×5 colour matrix for the live preview
and an FFmpeg `eq`/`colorchannelmixer`/`curves` chain for the render, so the
two cannot drift apart.

**One virtual canvas.** Every overlay stores its size against a reference
canvas 1000 units tall. The preview scales by `previewHeight / 1000`, the
renderer by `outputHeight / 1000`. Text placed at 1080p lands identically at
4K.

**One shader for the key.** Chroma keying in the preview runs as a real
fragment shader (`shaders/chroma_key.frag`) over a `SnapshotWidget` raster of
the video texture, keying on chroma in YUV so a green shirt in shadow still
keys out. It degrades to unkeyed rendering if the shader will not load — a
missing shader must never make the footage vanish from the canvas.

**One clock.** Playback does not follow any single player. A wall clock drives
the playhead and every video and audio player is re-synced whenever it drifts
past 130 ms, which is what keeps a multi-clip timeline with music in step.

Undo is snapshot-based: each mutation pushes the previous project as JSON.
Cheap at this scale and impossible to get subtly wrong the way hand-written
command inverses are.

The renderer describes the whole timeline as a single `filter_complex` — clips
concatenated in runs and joined with `xfade` where transitions exist, overlays
composited as pre-rasterized PNGs, and all audio delayed to its slot and mixed
in one `amix`. One pass, no intermediate files, no generation loss.

## Running it

```bash
flutter pub get
flutter run              # Android or iOS device
flutter test             # timeline maths, export sizing, serialisation
```

Android needs API 24+ (FFmpeg Kit and the media3 player both require it).

FFmpeg ships native libraries for every ABI, so a fat debug APK lands around
320 MB. Build per-ABI for anything you actually distribute:

```bash
flutter build apk --release --split-per-abi
```

## Known limits

These are real gaps, not polish items:

- **The caption model is downloaded, not bundled.** First use needs a network
  connection to fetch 75-466 MB of whisper weights; after that it is offline.
  The panel warns before starting the download.
- **TTS depends on the device.** Voices come from the platform engine, so the
  list differs per phone and a device with no installed voice gets none. Some
  Android engines report success while writing nothing — that case is detected
  and reported rather than adding a silent clip.
- **The music loops are synthesised, not recorded.** They are real arpeggios
  and pads, but they are not a substitute for a licensed production-music
  library.
- **Sticker packs are emoji and vector shapes.** There is no online sticker or
  GIF catalogue.
- **Heart and star masks export as a circle.** Their preview is exact, but
  neither has a cheap closed form for FFmpeg's `geq`, so the renderer
  substitutes a circle rather than dropping the mask silently.
- **Word-by-word and line-by-line text reveals preview correctly but export as
  a fade**, because per-glyph timing is not expressible in one filter graph.
- **Reverse renders the trimmed region to a new file up front**, so it is slow
  on long clips — FFmpeg's `reverse` filter buffers the segment in memory.
- **Stabilization is one-pass `deshake`**, not the stronger two-pass `vidstab`,
  which would need an intermediate analysis file.
- **A blend mode on a PIP layer pads it to full canvas** before blending, so a
  small blended overlay costs the same as a full-frame one.
