# ASHFALL Resource Pack 2.0 — Outpost Detail & Atmosphere

## Contents
- Six 1024x512 PNG military/settlement signs.
- Four transparent 1024x1024 PNG weathering decal overlays.
- Six transparent 256x256 PNG HUD/settlement icons.
- Four standalone Godot 4.7 primitive-mesh prop scenes with simple collision (radio, toolbox, water tank, generator). These are functional placeholder 3D props, not photorealistic GLB models.
- Six 44.1kHz mono WAV procedural prototype sound effects and ambiences.

## Install
Copy `assets/ashfall_pack_v2/` into the existing project `assets/` directory. Do **not** overwrite `assets/ashfall_pack_v1/` or existing `assets/materials/`, `assets/audio/`, `scenes/` files.

## Integration guidance
1. Create branch `art/ashfall-pack-v2` from latest main after Pack 1 integration.
2. Stage new prop scenes in a separate test level first. Scenes are basic meshes and collision; they provide no interactions or resource logic.
3. Place PNG signs using a QuadMesh / Sprite3D in Godot with transparency enabled, and consider a double-sided material if needed.
4. For overlay decals, use transparent quads or a Godot decal system; adjust alpha/blend appropriately.
5. Use audio effects as replaceable ambience, not final sound design. Set looping on persistent ambience streams in the Godot editor if appropriate, and crossfade loops to hide seams.
6. Keep existing inventory icons and gameplay scenes unchanged until visual review.
7. Run headless tests and inspect in the editor. Submit as a PR.

## Quality statement
This is a procedurally created utility/detail pack. PNG signs are stylized, not photographic. No realistic rigged characters, high-poly vehicles, or high-fidelity recorded audio are included.

## Rights
Generated specifically for the ASHFALL project using original procedural designs. Review third-party rights when combining with external assets.
