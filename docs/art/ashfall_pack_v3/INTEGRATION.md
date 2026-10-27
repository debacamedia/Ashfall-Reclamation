# ASHFALL Resource Pack 3.0: integration

Merged into `main` in PR #15 (26 Oct 2026), after a playtest. The pack's footsteps were reverted at that review.

The pack is in `assets/ashfall_pack_v3/` exactly as shipped: 253 files, byte-identical to the ZIP, with its own README and manifest. Files I made from it live beside it, in clearly named folders:

| Folder | Contents |
|---|---|
| `derived/` | Fixed copies: seamless fire and insect loops, and the dusty sky with its seam removed |
| `sets/` | 22 sound sets. Each one picks a random take and varies its pitch a little |
| `materials/` | 37 materials for textures, signs, graffiti and decals |
| `environments/` | Sky environments, built but not used |

No existing material, script, scene, sound or texture was overwritten. Existing scenes only had resource *paths* repointed (listed below). Collision geometry, navmeshes and the save format are untouched.

## Integrated vs only imported

**131 of the pack's 251 asset files are used in the game. The other 120 are imported only.** Imported-only files are in the project and load, but nothing uses them. `tests/test_art_pack3.gd` checks what's placed in each level.

### Textures (13 sets)

| Set | Status | Where / why not |
|---|---|---|
| `brick_weathered` | **Integrated** | Halden's Crossing brick buildings, in place of the old brick. Darkened to 55%, because untinted it glowed next to everything else |
| `asphalt_cracked` | **Integrated** | Halden's main street. Darkened to 72% |
| `canvas_tent` | **Integrated** | The raider camp tents |
| `roofing_tarpaper` | **Integrated** | The 7 flat roofs in Halden's (nodes named `Roof` only; concrete elsewhere is unchanged) |
| `container_paint_red` / `_blue` / `_olive` | **Integrated** | Every shipping container. Each container keeps its colour: it picks the nearest paint and tints it to match |
| `wood_charred` | Imported only | Tried on the fence posts and poles. At that size the grain made them look like twisted rope |
| `desert_sand` | Imported only | Tried as the ground. It was far too bright, and the whole level looked bleached |
| `plaster_peeling` | Imported only | It has a visible tiling seam |
| `corrugated_rusty` | Imported only | It looks blobby and cartoonish next to the other metal |
| `floor_linoleum` | Imported only | Same problem: blobby. There are also few interior floors where it would show |
| `dirt_road` | Imported only | The terrain shader already handles dirt tracks. Swapping it in would change the terrain, which this pack doesn't touch |

### Signs and graffiti (13)

| File | Status | Where / why not |
|---|---|---|
| `sign_general_store`, `_hotel`, `_clinic`, `_bank`, `_gas` | **Integrated** | Above each building's door in Halden's Crossing. Each is cropped to the board, about 2 m wide, and placed to clear the windows and doors |
| `sign_diner`, `sign_feed_supply` | **Integrated** | The same, on the two ruined buildings. They're smaller (×0.7) and lower, to fit what's left of the walls |
| `sign_keep_out` ×2, `sign_turn_back` | **Integrated** | Raider camp: on the gate and the approach |
| `graffiti_raider_1` (skull), `_2` (cross) | **Integrated** | On two of the camp's shipping containers |
| `graffiti_raider_3` ("RAID →") | **Integrated** | The bank's south wall, high up, pointing toward the camp |
| `sign_welcome_haldens` | Imported only | **The pack image is defective: the town name is cut off at the edge.** It's ready to place if a fixed version arrives |

### Decals (11)

All of them are **integrated**: 15 placements in Halden's and 9 in Outpost 17.

| Decal | Placements |
|---|---|
| Oil stains | Halden's: garage, gas station and street. Outpost: beside each truck |
| Tyre tracks | Halden's: main street and gas forecourt. Outpost: through the gate and across the yard |
| Scorch marks | Around fire barrels, 3 m across so they show past the barrel |
| Blood | Two spots in the raider camp |
| Cracks | Halden's main street ×2 and the Outpost yard |
| Posters | Halden's ×2, the Outpost command post, and the barracks. The barracks poster ended up on an inside wall, visible through the doorway, and I kept it there |
| Water stain | The hotel |

These are flat textured quads rather than Godot `Decal` nodes. `Decal` nodes don't draw in the Compatibility renderer. Quads draw everywhere and cost nothing.

### Sound (145 files)

**Integrated (86 files):**

- **Bullet impacts** picked by the surface hit: dirt, concrete or metal.
  - Built structures and props go by their type.
  - Ground is dirt.
  - Buildings are concrete.
  - A node can override this with the `surface` metadata.
  - Wood keeps the existing structure-hit sound, since the pack has no wood impact.
- **Bodies and the machete:** flesh impacts, plus the machete's swing and its own hit sound.
- **Movement:** jumping and landing, ladder steps.
- **Weapons:**
  - Weapon draw, aim in, dry fire.
  - Pistol, rifle and pipe-pistol reloads.
  - Shotgun pump and shell insert.
  - Marksman bolt cycle.
- **Items:** all four pickup sounds (soft, metal, ammo, weapon) on every item, and the medkit and bandage heals.
- **Crafting and salvage:**
  - Rummage sounds.
  - Containers: locker and crate open and close. The lockers used to borrow the ladder sound for their lid.
  - Salvage: metal and wood tearing sounds while you hold E, then a break.
  - Crafting: saw, hammer or file while it runs, depending on the recipe, then a completion sound.
- **HUD:** hit marker, kill confirm, denied.
- **Ambience:**
  - Halden's: town ruins, distant gunfire, and insects at the farmhouse.
  - The burning barrels' fire loop.

**Imported only (60 files):**

| Files | Why not |
|---|---|
| Footsteps: gravel, concrete, metal, wood (24) | **Reverted after your playtest: they sounded bad.** The player and raiders use the original footsteps again |
| Every gunshot: pistol, rifle, shotgun, marksman, pipe pistol, both suppressed (21) | The pistol, rifle and shotgun shots are thinner than the current ones. The marksman, pipe-pistol and suppressed shots measure as mostly hiss. **Listen for yourself; I can swap any of them in.** |
| Raider alert, pain and death (9) | The takes in each group sound nearly identical. The current voices vary more |
| Player hurt (3) | The current ones read better against gunfire |
| `heartbeat_loop`, `amb_desert_wind` | Both are almost all sub-bass, so they disappear on laptop speakers |
| `ui_click` | The menus don't make click sounds yet |

Also left as they were: the death sting, the marksman reload and the target pings. The pack has no versions of these.

### Sky (2)

| File | Status | Why not |
|---|---|---|
| `sky_dusty_afternoon` | Imported only | It has a hard seam, which is fixed in `derived/`. On screen it washed out the whole scene: a flat white sky, low contrast and the sun's direction lost |
| `sky_overcast` | Imported only | The levels are lit for a clear afternoon. An overcast sky would need the lighting redone to match, so it's left for later |

Environments using both are built in `environments/`. Pointing a level's `WorldEnvironment` at one is a one-line change if you want to try it.

### HUD (6) and icons (33)

All are **imported only.**

| Files | Why not |
|---|---|
| `crosshair`, `hitmarker`, `damage_arc` | The HUD already draws these itself, and they scale with spread and resolution. Images would be a step back |
| `scope_reticle_4x` | Its centre is nearly opaque, so you couldn't see the target |
| `bar_frame` | The health and stamina bars are drawn by the HUD; a frame would need the bar layout rebuilt around it |
| `map_background` | There's no map screen yet |
| All 33 item icons | The current icons are rendered from the actual 3D models and are clearly better (see `icons_current_vs_pack.jpg`). Also, the `machete` icon has no inventory item to go on |

## What changed in the game

**Levels (text edits only; Godot never re-saved them):**
- `levels/haldens_crossing/haldens_crossing.tscn`:
  - 3 material paths repointed: brick, asphalt, tent canvas.
  - 7 roof materials changed.
  - A `Pack3Dressing` instance added.
- `levels/outpost_17/outpost_17.tscn`: a `Pack3Dressing` instance added.
- New: `levels/*/pack3_dressing.tscn`, holding the signs, graffiti, decals and ambience. Generated; don't edit it by hand.

**Scenes and items (sound paths repointed, nothing else):**
- The player, raider and raider veteran.
- All six weapons, plus the bullet impact.
- The footlocker, weapons locker and supply crate.
- The burning barrel and the spike trap.
- 43 item resources (their pickup and use sounds).

**Scripts:**

| Script | Change |
|---|---|
| `scripts/world/surface_sounds.gd` | New: decides what a surface is made of |
| `player_audio.gd` | Crafting tool sounds |
| `bullet_impact.gd`, `hitscan_weapon.gd` | Impact sound follows the surface hit |
| `salvage_pile.gd` | Tearing sounds while held, break sound |
| `shipping_container.gd` | Pack paint, keeping each container's colour |
| `hud.gd` | Three sound paths |

**Import settings:**
- Textures: VRAM-compressed, mipmapped, capped at 1024 px (the pack ships 2048), with normal maps flagged as normal maps.
- Sky: 2048 px, no mipmaps.
- Ambience loops: loop mode on.

**Saves:** a save from before this branch loads, and the test checks this. Nothing new is saved.

## Re-running

From the project root:

```
python3 tools/audio/make_pack3_loops.py                     # derived/ fire and insect loops
godot --headless --path . -s res://tools/integrate_resource_pack_v3.gd   # sets, materials, environments, dressing scenes
python3 tools/apply_resource_pack_v3.py                     # level edits
python3 tools/apply_resource_pack_v3_audio.py               # sound paths
```

All four are safe to re-run.

## Checks

- **Tests:** the full suite passes, 293 tests and 0 failures. The new `tests/test_art_pack3.gd` adds 10 of them:

  | Test | What it checks |
  |---|---|
  | Pack installed as shipped | Byte-identical to the ZIP |
  | Sets and materials | They load and point at pack files |
  | Halden's dressing | 13 signs and graffiti, 15 decals, looping ambience, nothing saved |
  | Outpost dressing | 9 decals, and an old save still loads |
  | Surfaces | Each surface is classified correctly |
  | Footsteps | The player and both raider types keep the original sound |
  | Bullet impacts | They match what was hit |
  | Crafting and salvage | The right sounds play |
  | Containers | They keep their paint colour |
  | Loops and sky | Both are seamless |

- `tests/test_salvage.gd` now expects the pack's locker and crate lid sounds.
- **Visual review:** before/after shots are in this folder (`compare_*.jpg` and the close-ups).
