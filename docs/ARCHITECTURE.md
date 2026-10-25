# ASHFALL: RECLAMATION — Milestone 1 Technical Architecture

Engine: **Godot 4.7**, GDScript (typed), **Forward+** renderer.
Scope: the Milestone 1 vertical slice at **Outpost 17**, built in small increments that each leave the project runnable.

---

## 1. Guiding rules

1. **Scenes are the source of truth for objects.** Every reusable thing (player, props, structures, vehicles, UI) is a `.tscn`. Scripts add behaviour, and levels instance scenes.
2. **Data lives in Resources.** Items, buildings, recipes, factions and NPC types become custom `Resource` classes saved as `.tres`. Code never hard-codes item stats.
3. **Intent and simulation are separate.** Input, UI and AI produce *requests*. A single authoritative function applies each request and changes state. In single-player the local game is the authority. In co-op the host is. Same code path.
4. **Signals for notifications, method calls for requests.** A system changes another system by calling its authoritative method. It reacts to changes by connecting to signals. No global "event bus" for everything; only a few autoloads where shared access is genuinely needed.
5. **Build incrementally.** Every increment ships with automated tests that are actually run headless, and a short guide.

---

## 2. Authority model (designed in now, networked later)

```
 Local input / UI / AI           Authority (host or single-player)        Everyone
 ───────────────────────         ─────────────────────────────────        ──────────
 PlayerInput.gather()  ──frame──▶ PlayerController.simulate(frame)  ──▶  position / state
 "Pick up item" button ─request─▶ InventoryManager.request_add(...)  ──▶  inventory_changed signal
 "Place wall"          ─request─▶ BuildingManager.request_place(...) ──▶  structure_spawned signal
```

- **Movement:** `PlayerInput` turns keyboard and mouse into an `InputFrame` each physics tick. `PlayerController.simulate(frame, delta)` is the *only* code that moves a player. Later, guests send frames to the host, which runs the same `simulate()` (with client-side prediction for the local player).
- **Validation:** every `request_*` function validates its arguments (range, ownership, permissions, costs) before changing anything. `InputFrame.from_dict()` already clamps untrusted values.
- **Single-player never opens a network session.** `NetworkManager` (Milestone 2+) reports `is_authority() == true` when offline, so request functions run directly.
- **Synchronizers are for replication, not authority.** `MultiplayerSynchronizer` will mirror state such as transforms and health for display. Combat outcomes, resources, construction, trading, recruiting and diplomacy are decided only in host-side request functions.

---

## 3. Systems for Milestone 1

| System | Milestone 1 scope | Type | Increment |
|---|---|---|---|
| **PlayerController** | Look, walk, sprint, crouch, jump, head-clearance check, head bob, signals | `CharacterBody3D` scene + script | 1 ✅ |
| PlayerInput | Keyboard and mouse to `InputFrame`, mouse capture, crouch toggle option | Node in player scene | 1 ✅ |
| Combat (weapon) | One hitscan rifle via physics ray queries, ammo, reload | Node + `WeaponDefinition` Resource | 2 ✅ |
| Health | `HealthComponent` node, damage and death signals (player and NPCs) | Node component | 2 ✅ |
| Death and respawn | Player death, respawn at Outpost 17 spawn point | PlayerController + `GameMode` node in the level | 3 ✅ |
| Enemy NPC | `NavigationAgent3D` pathing on a baked `NavigationRegion3D`, sight + hearing, chase and melee, `EnemySpawner` | `CharacterBody3D` scene | 4 ✅ |
| Interaction | Ray from the camera, `Interactable` (Area3D), prompt UI, hold-to-interact | Area3D + RayCast3D | 5 ✅ |
| Items and resources | `ItemDefinition` Resource, world pickups (scrap, cloth, fuel...) | Resource + scene | 5 ✅ |
| **InventoryManager** | `InventoryComponent` (slots, stacks, weight cap), transfers, signals | Node component + Resources | 6 ✅ |
| Inventory UI | Grid UI bound to an `InventoryComponent` | `Control` scene | 6 ✅ |
| Aiming and ladders | ADS (zoom, spread, recoil, speed) simulated from `InputFrame.aim`; `Ladder` scene found by group, `CLIMBING` state | PlayerController + Resource fields + scene | 6.5 ✅ |
| Salvage containers | Interactable containers with their own inventory and loot tables; two-sided transfer screen; validated take/store | Scene + `LootTable` Resource | 7 ✅ |
| **SaveManager** | Save/load player, inventories, container state and ground loot to `user://saves/`, versioned JSON; `persist` group contract | Autoload | 8 ✅ |

**Planned for later milestones, with hooks left in place now:** WorldManager (day and night, weather, ticks), BuildingManager, SettlementManager, ResourceManager, EconomyManager (Marks), MilitaryManager, FactionManager, QuestManager, NetworkManager.

### Autoloads (planned)
Only systems that genuinely need global access:
- `SaveManager` (Increment 8 ✅). Collects state from nodes in the `persist` group, which implement `save_state()` and `load_state()` (and `is_save_removable()` for things that can disappear).
- `WorldManager` (Increment 12 ✅). Regions and travel: carries the player between level scenes, remembers each region's `persist` state, and adds it to saves. The day and night clock and the world tick signal will live here too.
- `NetworkManager` (Milestone 3). Owns `ENetMultiplayerPeer`, peers, permissions and `is_authority()`.

Managers that belong to a place, such as a settlement's resources or buildings, are **nodes in the level**, not autoloads. That allows several settlements and regions later.

**GameMode** (Increment 3) follows the same rule. It is a node in each level that owns player death and respawn rules. Players *request* a respawn; GameMode (host-side in co-op) decides.

---

## 4. Collision layers

Named in Project Settings → Layer Names → 3D Physics, and mirrored as constants in `scripts/core/physics_layers.gd`.

| # | Name | Value | Who is on it | Typically masks |
|---|---|---|---|---|
| 1 | terrain | 1 | ground, berms | — |
| 2 | structures | 2 | walls, buildings, props, vehicles | — |
| 3 | player | 4 | player bodies | terrain, structures, npcs |
| 4 | npcs | 8 | enemies, settlers, soldiers | terrain, structures, player, npcs |
| 5 | interactables | 16 | containers, pickups, doors (interaction shapes) | — |
| 6 | projectiles | 32 | physical projectiles (grenades etc.) | terrain, structures, player, npcs |
| 7 | triggers | 64 | Area3D zones (region entry, quest triggers) | player, npcs |

Hitscan weapons query terrain, structures, player and npcs with `PhysicsRayQueryParameters3D`. The interaction ray masks **interactables** only.

---

## 5. Project structure

```
res://
├── project.godot
├── docs/                      ARCHITECTURE.md, increment guides
├── scenes/
│   ├── player/                player.tscn
│   ├── weapons/               (Inc 2)
│   ├── enemies/               (Inc 4)
│   ├── npcs/                  (later)
│   ├── buildings/             player-constructed buildings (BuildingManager, later)
│   ├── vehicles/              military_truck.tscn
│   ├── world/
│   │   ├── structures/        prefab buildings, towers, gate, walls, culvert
│   │   └── props/             containers, sandbags, barriers, crates, drums, fence
│   └── ui/                    hud.tscn
├── scripts/
│   ├── core/                  input_frame.gd, physics_layers.gd, game_mode.gd
│   ├── player/                player_controller.gd, player_input.gd
│   ├── npcs/                  raider.gd, enemy_spawner.gd (NPC behaviour)
│   ├── world/                 scripts for world props (shipping_container.gd)
│   ├── interaction/           interactable.gd, pickup.gd, player_interactor.gd
│   ├── ui/                    hud.gd
│   ├── combat/ inventory/ construction/ settlement/ economy/
│   ├── military/ factions/ networking/ persistence/   (filled in later increments)
├── resources/                 items/ buildings/ crafting/ factions/ npc_types/  (.tres data)
├── assets/
│   ├── materials/             PBR materials (.tres) with normal maps
│   ├── models/ textures/ animations/ audio/                (imported art, later)
├── levels/
│   ├── outpost_17/            outpost_17.tscn, outpost_17_environment.tres
│   ├── haldens_crossing/      haldens_crossing.tscn (+ environment, navmesh)
│   └── regions/               (later)
└── tests/                     headless test runner + test suites
```

**Changes from the proposed structure, and why:**
- **`scripts/interaction/` added** (Increment 5). Anything the player presses E on.
- **`tools/` added** (Increment 5). Offline tools, such as the sound synthesizer. Godot ignores it.
- **`scripts/npcs/` added** (Increment 4). NPC behaviour (raiders, later settlers and soldiers) mirrors `scripts/player/`.
- **`scripts/player/` added.** The player controller and input don't fit under `core/` or `combat/`, and they'll grow (stamina, interaction, equipment).
- **`scenes/world/` split into `structures/` and `props/`.** Outposts reuse dozens of pieces, and the split keeps both lists scannable. `scenes/buildings/` is reserved for *player-built* structures, which carry BuildingManager data such as cost, health and upgrades. World set dressing does not.
- **`scripts/ui/` and `scripts/world/` added.** Scripts sit next to the scene category they serve.
- **`docs/` added.** Architecture and per-increment guides live with the code, so they stay in version control.

---

## 6. Scene conventions

- Root node type matches the object's role: `CharacterBody3D` (actors), `StaticBody3D` (solid world pieces), `Node3D` (groups and levels), `CanvasLayer` (HUD).
- Nodes other scripts need are marked **Access as Unique Name** and fetched with `%Name`, so they survive hierarchy edits.
- Collision shapes in scenes that will be instanced many times with per-instance changes (the player capsule) are **Local to Scene**.
- Each level has a `PlayerSpawn` `Marker3D`. Respawn and co-op join points will use it.
- Materials are shared `.tres` files in `assets/materials/` and are never embedded per mesh. One edit restyles the whole outpost.
- Placeholder meshes use real-world scale: 1 unit = 1 m, doors 1.2 × 2.2 m, player 1.8 m tall (1.1 m crouched), wall height 3.2 m.

---

## 7. Performance plan

- Static world pieces are instanced scenes that share meshes and materials. When dense repetition appears (fences, sandbags across many outposts), switch to `MultiMeshInstance3D`.
- Use visibility ranges (`visibility_range_end`) for small props, so they drop out at distance. Proper LOD meshes come with imported art.
- Occlusion culling (`OccluderInstance3D`) once there are real buildings; enable in Project Settings → Rendering → Occlusion Culling.
- Region-based simulation: WorldManager ticks distant regions at a low rate and only fully simulates the player's current region.
- Forward+ with SSAO, glow and fog in the environment. SDFGI is off by default for performance and can be evaluated later.

---

## 8. Increment roadmap (Milestone 1)

| # | Increment | Playable result |
|---|---|---|
| 1 ✅ | Project structure, player controller, Outpost 17 | Walk, sprint, crouch and jump around a 3D military outpost |
| 2 ✅ | Rifle + HealthComponent + target dummies | Shoot targets that take damage |
| 3 ✅ | Player health, death and respawn | Take damage, die and respawn at the outpost |
| 4 ✅ | Enemy NPC with navigation and melee attack | A raider paths around the outpost and attacks |
| 5 ✅ | Interaction system + collectible resources (+ sound pass) | Look at a pickup, press E, collect scrap |
| 6 ✅ | Inventory (data + UI) + stored medkits / quick-heal | Open the inventory, see stacks and weight; heal with H |
| 6.5 ✅ | Aim down sights + ladders | Aim through a red-dot sight; climb the guard towers |
| 7 ✅ | Salvage containers | Search crates and transfer loot |
| 8 ✅ | SaveManager | Save and load the player, inventory and opened containers |

Each increment adds a guide in `docs/increments/` and tests in `tests/`.

### Milestone 2 (early, planned)
| Increment | Playable result |
|---|---|
| Weapon slots + new guns ✅ (Inc 9) | Carry a pistol, shotgun and scoped rifle in numbered slots (1–3, mouse wheel); each draws its own ammo item from the inventory |
| Crafting ✅ (Inc 10: materials, recipes, benches) | Use a workbench at Outpost 17 to turn scrap, cloth, electronics and fuel into ammo, medkits and weapon parts via `RecipeDefinition` Resources |
| Gun crafting + attachments ✅ (Inc 11) | Start with a machete and craft a pipe pistol; build gun parts and assemble guns at the weapons bench; fit attachments (red dot, 4× scope, suppressor, extended magazine, foregrip) |
| First new region ✅ (Inc 12: Halden's Crossing) | Travel by road to a ruined town with a raider camp, close-quarters buildings and long sightlines; region state saved per level |

Then co-op networking (`NetworkManager`, Milestone 3), settlements, building and the economy, with more regions added along the way.
