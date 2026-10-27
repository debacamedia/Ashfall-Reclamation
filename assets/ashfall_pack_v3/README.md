# ASHFALL Resource Pack v3.0

This pack is structured to install under `assets/ashfall_pack_v3/` in a Godot 4.7 project.

## Contents
- 13 PBR texture sets (`albedo.png`, `normal.png`, `roughness.png`) at **2048x2048** PNG.
- 2 sky panoramas at **4096x2048** PNG.
- 10 signs and 3 graffiti tags at **1024x512** PNG.
- 11 decals at **1024x1024** PNG.
- 33 inventory icons at **256x256** PNG.
- 6 HUD PNGs.
- 145 mono WAV files at **44.1 kHz / 16-bit**.

## How assets were made
- **Textures:** procedurally generated tileable textures using layered mathematical noise, simple pattern synthesis, and derived normal / roughness maps. Several texture sets were synthesized at an intermediate resolution and exported at the required final 2048x2048 size.
- **Sky images:** procedurally generated equirectangular panoramas using layered cloud and haze synthesis.
- **Signs / decals / icons / HUD:** programmatically drawn 2D assets with generated distressing and weathering.
- **Audio:** procedurally synthesized and layered audio using filtered / smoothed noise, tonal components, and amplitude envelopes.

## Real sizes
- Textures: **2048x2048** each
- Skies: **4096x2048** each
- Signs: **1024x512** each
- Decals: **1024x1024** each
- Icons: **256x256** each
- `crosshair.png`: **64x64**
- `hitmarker.png`: **64x64**
- `damage_arc.png`: **512x512**
- `scope_reticle_4x.png`: **2048x2048**
- `bar_frame.png`: **512x64**
- `map_background.png`: **2048x1024**

## Texture scale notes
- `brick_weathered` — covers 2 m x 2 m per tile
- `plaster_peeling` — covers 2 m x 2 m per tile
- `wood_charred` — covers 2 m x 2 m per tile
- `roofing_tarpaper` — covers 2 m x 2 m per tile
- `floor_linoleum` — covers 2 m x 2 m per tile
- `asphalt_cracked` — covers 3 m x 3 m per tile
- `dirt_road` — covers 3 m x 3 m per tile
- `corrugated_rusty` — covers 2 m x 2 m per tile
- `container_paint_red` — covers 2 m x 2 m per tile
- `container_paint_blue` — covers 2 m x 2 m per tile
- `container_paint_olive` — covers 2 m x 2 m per tile
- `canvas_tent` — covers 2 m x 2 m per tile
- `desert_sand` — covers 3 m x 3 m per tile

## Limitations / honesty notes
- These are generated and procedural assets, not photogrammetry or studio-recorded audio.
- They are intended to be Godot-ready and useful for prototyping / integration, but some items may benefit from later hand polish or replacement.
- Audio loops were synthesized to avoid obvious starts/ends, but should still be tested in-engine in case you want additional trimming or mix adjustments.
- The pack does **not** include 3D models; it contains 2D images, textures, HUD art, and WAV audio only.
