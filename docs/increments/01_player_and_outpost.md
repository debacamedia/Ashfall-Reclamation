# Increment 1 — Project structure, first-person player, Outpost 17

**Status:** complete. 23 automated tests pass, run headless in Godot 4.7 (see §8).
**Playable result:** walk, sprint, crouch and jump around a 3D military outpost: perimeter walls, fortified gate, guard towers, buildings you can enter, a warehouse, a motor pool, and a culvert you have to crouch through.

---

## 1. Files

Dependencies first. Each file only uses files above it in this list.

| File | Purpose |
|---|---|
| `project.godot` | Input Map, collision layer names, main scene, MSAA |
| `scripts/core/physics_layers.gd` | `PhysicsLayers` collision bit constants |
| `scripts/core/input_frame.gd` | `InputFrame`: one tick of player intent, plus network-safe `from_dict()` |
| `scripts/player/player_input.gd` | `PlayerInput`: keyboard and mouse → `InputFrame`, mouse capture |
| `scripts/player/player_controller.gd` | `PlayerController`: look, walk, sprint, crouch, jump, signals |
| `scenes/player/player.tscn` | Player scene |
| `scripts/ui/hud.gd` + `scenes/ui/hud.tscn` | Crosshair and debug readout (F3) |
| `scripts/world/shipping_container.gd` | `@tool` per-instance paint colour |
| `assets/materials/*.tres` | 18 PBR materials (noise albedo, noise normal maps, world triplanar UVs) |
| `scenes/world/props/*.tscn` | Concrete wall segment, Jersey barrier, sandbag wall, crate, fuel drums, shipping container, chain-link fence, flag pole |
| `scenes/world/structures/*.tscn` | Small prefab building, warehouse, guard tower, fortified gate, drainage culvert |
| `scenes/vehicles/military_truck.tscn` | Placeholder truck |
| `levels/outpost_17/outpost_17_environment.tres` | Sky, fog, SSAO, glow, tonemapping |
| `levels/outpost_17/outpost_17.tscn` | The level (main scene) |
| `tests/*.gd` | Test runner + 3 suites |

## 2. Scene hierarchy

### `scenes/player/player.tscn`
```
Player                CharacterBody3D   script: player_controller.gd
├── %CollisionShape   CollisionShape3D  CapsuleShape3D r=0.35 h=1.8 (Local to Scene)
├── %Head             Node3D            y = 1.68 (moved by stance)
│   └── %Camera       Camera3D          fov 75, near 0.05, far 1500
├── %HeadClearance    ShapeCast3D       sphere r=0.3 at y 0.8, target (0, 0.7, 0)
└── %PlayerInput      Node              script: player_input.gd
```
`%` = **Access as Unique Name** is enabled, so the script finds nodes with `%Name`.

### `scenes/ui/hud.tscn`
```
HUD                   CanvasLayer       script: hud.gd   (export: player)
└── Root              Control           Full Rect, Mouse Filter = Ignore
    ├── Crosshair     ColorRect         4×4 px, centre anchors
    └── %DebugLabel   Label             hidden; F3 toggles
```

### `levels/outpost_17/outpost_17.tscn`
```
Outpost17             Node3D
├── Lighting
│   ├── WorldEnvironment            outpost_17_environment.tres
│   └── Sun                         DirectionalLight3D, shadows on
├── Terrain           StaticBody3D  layer 1 terrain: 400×400 m ground + world-edge berms
├── Surfaces                        road, gravel yard, motor pool (visual only)
├── Perimeter                       96 concrete wall segments (gap on the south side)
├── MainGate                        fortified_gate.tscn
├── GuardTowers                     4 × guard_tower.tscn
├── Buildings                       CommandPost, Barracks (prefab_building_small), Warehouse
├── Props                           containers (one stacked), sandbags, chicane barriers, crates, drums, flag pole, motor-pool fence
├── Vehicles                        2 × military_truck.tscn
├── DrainageCulvert                 1.35 m clearance: crouch only
├── PlayerSpawn       Marker3D      (0, 0.05, 14)
├── Player                          player.tscn
└── HUD                             hud.tscn   (player → ../Player)
```

## 3. Scripts

Complete scripts are in the files listed in §1. They are typed GDScript with doc comments. Key points:
- `PlayerController.simulate(frame, delta)` is the only function that moves the player.
- `controlled_locally = false` disables local input so tests, and later the network host, can drive the player.
- Stance changes use a `ShapeCast3D` overhead check, so you can't stand up under a low ceiling.
- Acceleration uses `1 - exp(-rate * delta)` smoothing, so behaviour doesn't change with frame rate.

## 4. Input Map

Defined in `project.godot` (Project Settings → Input Map):

| Action | Keys |
|---|---|
| `move_forward` | W, ↑ |
| `move_back` | S, ↓ |
| `move_left` | A, ← |
| `move_right` | D, → |
| `jump` | Space |
| `sprint` | Shift |
| `crouch` | C, Ctrl |
| `pause` | Esc (frees the mouse; click to recapture) |
| `toggle_debug` | F3 |

## 5. Inspector settings

**Player (PlayerController)**
| Property | Default | Notes |
|---|---|---|
| Walk / Sprint / Crouch speed | 4.5 / 7.5 / 2.2 m/s | Sprint only applies when moving mostly forward |
| Jump velocity | 4.8 m/s | ≈ 1.18 m jump height |
| Ground accel / decel / air accel | 12 / 14 / 2 | Higher = snappier |
| Stand / crouch height | 1.8 / 1.1 m | Must match the HeadClearance ShapeCast (see §9) |
| Max pitch | 89° | |
| Head bob | on, 0.035 m, 1.5 m stride | |
| Controlled locally | on | Off for remote players and tests |
| Kill plane Y | −30 | Temporary respawn safety net |
| Collision layer / mask | 3 player / 1, 2, 4 | terrain, structures, npcs |

**PlayerInput:** mouse sensitivity 0.0022, invert Y off, crouch toggle off.
**HUD:** `player` → `../Player`.
**Shipping containers:** `paint` colour per instance.

## 6. Signals and connections

| Signal | Emitted when | Planned listeners |
|---|---|---|
| `PlayerController.jumped` | jump starts | footstep/jump audio (sound pass) |
| `PlayerController.landed(impact_speed)` | touches down after being airborne | fall damage (Inc 3), landing audio |
| `PlayerController.stance_changed(is_crouching)` | stand ↔ crouch | stealth/noise, HUD stance icon |
| `PlayerController.movement_state_changed(state)` | IDLE/WALKING/SPRINTING/CROUCHING/AIRBORNE changes | stamina, footsteps, weapon sway |
| `PlayerInput.mouse_capture_changed(captured)` | Esc / click | pause menu (UI increment) |

No editor connections are needed in this increment. HUD reads the player each frame via its `player` export.

## 7. Building it in the editor yourself (optional)

The scenes are already assembled. To recreate the player by hand:
1. Scene → New Scene → root **CharacterBody3D** named `Player`. Attach `player_controller.gd`.
2. Add **CollisionShape3D** `CollisionShape`, set Shape to a new CapsuleShape3D (radius 0.35, height 1.8), position y 0.9. On the shape, expand Resource and tick **Local to Scene**.
3. Add **Node3D** `Head` at y 1.68, and a **Camera3D** `Camera` under it.
4. Add **ShapeCast3D** `HeadClearance`: new SphereShape3D r 0.3, position y 0.8, Target Position (0, 0.7, 0), Collision Mask 1 + 2, **Enabled off**.
5. Add **Node** `PlayerInput`, then attach `player_input.gd`.
6. Right-click each of CollisionShape, Head, Camera, HeadClearance and PlayerInput → **Access as Unique Name**.
7. Inspector → Collision: Layer 3 only; Mask 1, 2, 4. Save as `scenes/player/player.tscn`.

## 8. Testing

### Automated (run these after any change)
```
godot --headless --path . -s res://tests/test_runner.gd
```
On a Mac, `godot` is `/Applications/Godot.app/Contents/MacOS/Godot`. A test fails on a failed check **or** on any script error logged while it runs.

Result of the run for this increment: **23 passed, 0 failed.**

| Suite | Tests |
|---|---|
| `test_input_map` | all actions exist; each key triggers its action; Ctrl also crouches |
| `test_player_controller` | settles on floor; walk speed; sprint speed; no backwards sprint; stops when released; jump apex ≈ v²/2g with one jumped and one landed signal; no double jump; crouch height/camera/speed; no crouch-jump; stays crouched under a ceiling then stands when clear; wall blocks; pitch clamp; yaw turns movement; kill plane respawn; untrusted InputFrame data is clamped |
| `test_outpost_17` | level loads, player at spawn and on ground, HUD wired; can walk out of the gate; perimeter wall blocks; can walk into the barracks; culvert blocks a standing player but a crouching one gets through |

### Manual checklist (press F5)
- [ ] Mouse look is smooth and stops at straight up and down.
- [ ] W/A/S/D move relative to where you look. Shift sprints forward only.
- [ ] Space jumps about 1.2 m. You can't jump again mid-air.
- [ ] C or Ctrl crouches and the view drops. Crouch into the culvert by the west wall, release C inside, and you stay crouched until you exit.
- [ ] Walk into the barracks, command post and warehouse. They're lit inside.
- [ ] Esc frees the mouse; clicking the window recaptures it.
- [ ] F3 shows state, speed and position.

## 9. Common errors and troubleshooting

| Symptom | Cause / fix |
|---|---|
| Can't look around; mouse moves freely | The window doesn't have focus, or Esc was pressed. Click inside the game window. |
| Keys do nothing after editing the Input Map | Action names must match exactly (`move_forward`, not `forward`). The `test_input_map` suite checks this. |
| `Invalid get index ... on base 'null instance'` at `%Head` etc. | A node was renamed or lost **Access as Unique Name**. Re-enable it (right-click the node). |
| Player stands up through a low ceiling | The HeadClearance ShapeCast must span from crouch height to stand height. If you change `crouch_height` or `stand_height`, set its position y to `crouch_height − 0.3` and target y to `stand_height − crouch_height`. |
| Crouch height affects every player in co-op | The capsule shape lost **Local to Scene**. Re-tick it on the CapsuleShape3D. |
| Player walks through a new prop | The prop's StaticBody3D must be on layer 2 (structures) or 1 (terrain), with a CollisionShape3D as a **direct child**. |
| Player falls through the world | The terrain lost its collision. You respawn at the kill plane (y −30) anyway. |
| Very dark buildings | Interior OmniLights are in the building scenes. Check they weren't deleted. |
| Godot warns "UID not found" after moving files | Move files inside the Godot FileSystem dock (not Finder), so references update. |

## 10. How this connects to future systems

- **Combat (Inc 2).** The weapon attaches under `%Camera` and fires a physics ray from it. `movement_state` drives weapon sway and spread.
- **Health, death and respawn (Inc 3).** A `HealthComponent` node goes on the player. `landed(impact_speed)` feeds fall damage. `respawn()` already exists and returns to `PlayerSpawn`.
- **Interaction (Inc 5).** A `RayCast3D` under `%Camera` masking layer 5 (interactables). The interact action joins the Input Map then.
- **Inventory (Inc 6).** An `InventoryComponent` node joins the player scene. The HUD gains an inventory screen.
- **Save/Load (Inc 8).** The player joins the `persist` group and saves its transform, stance and (later) inventory.
- **Co-op (Milestone 2).** Guests send `InputFrame.to_dict()` to the host. The host runs `InputFrame.from_dict()` (already validated) then `simulate()` on that guest's player, with `controlled_locally = false`. A `MultiplayerSynchronizer` mirrors transforms back.
- **Settlement and construction.** World structures here are set dressing. Player-built buildings will live in `scenes/buildings/`, carrying BuildingManager data such as cost, health and upgrades.
