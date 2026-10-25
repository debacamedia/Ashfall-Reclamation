# ASHFALL Resource Pack 1.0 — Outpost 17

For Godot 4.7 / Forward+. This is an **additive visual/audio upgrade**. No game files are overwritten.

## Contents
- 9 procedural 1024×1024 PBR-style materials, each with albedo, normal and roughness maps.
- 4 transparent PNG military decals, 1024×512.
- 4 synthesized WAV sound effects (generator idle, radio static, metal clank and wind). These are placeholders pending professionally produced sounds.
- 9 ready-to-load StandardMaterial3D `.tres` files.

## Installation
Copy `assets/ashfall_pack_v1/` from this ZIP into the repository's `assets/` folder, preserving directories. Open the project through Godot's editor to import files. Do not copy over any of the existing `assets/materials/*.tres` or WAVs.

## Integration order (Claude)
1. Commit the standalone imported folder to a dedicated branch `art/ashfall-resource-pack-v1`.
2. Choose one existing Outpost 17 wall instance (not the reusable original scene) and override its `material_override` with `res://assets/ashfall_pack_v1/materials/concrete_weathered.tres`.
3. Verify triplanar mapping and scale in-game; adjust `uv1_scale` to avoid repetition. Test in Forward+.
4. Apply the asphalt and dirt to small test patches; keep the game's current layout, scripts, physics and material originals unchanged.
5. Integrate decals as Alpha-enabled mesh planes placed a few millimeters in front of geometry (avoid z-fighting).
6. Add audio to new AudioStreamPlayer3D nodes for generator props / radio props; do not replace existing weapons sounds until reviewed.
7. Run Godot headless scene import/check and repository test suite; manually play Outpost 17 and Halden's Crossing.
8. Open a PR with before/after screenshots. Do not merge automatically.

## Caveats
This is a useful prototype graphics pack, NOT a photogrammetry-quality AAA scan library. The nine tileable-looking textures use periodic noise and material detail, rather than real photos. They should be reviewed in engine at typical gameplay scale. WAVs are synthetic and should be replaced or augmented when higher-fidelity sound sources are available.

## Rights
All procedural materials, graphic signs and sound waves in this pack were generated specifically for this project. Review any externally sourced additions separately.
