# Increment 4 — Raider enemy: navigation, senses, melee

**Status:** complete. 83 automated tests pass (17 new; all earlier tests still pass), run headless in Godot 4.7. Also run in a real window with raiders active: no script errors.
**Playable result:** three **raiders** roam the wasteland outside Outpost 17. They notice you by sight (30 m, 120° view cone, blocked by walls) or by hearing your gunshots (60 m), and an orange **"!"** pops over a raider's head when it does. They run over a baked navigation mesh, through the gate and around cover and buildings, to reach you. Each swing has a visible wind-up, so step back to dodge; a hit deals 20. Raiders have 80 HP: two headshots or three body shots. Dead raiders fall and despawn after 30 s, and replacements arrive 20 s after each kill. Raiders can't fit through the culvert.

> **After pulling:** open the project with **Edit** in the Project Manager (not Run), then press F5. This update adds new scripts (`Raider`, `EnemySpawner`).

---

## 1. Files

| File | Purpose |
|---|---|
| `scripts/npcs/raider.gd` | **New.** `Raider`: state machine, perception, navigation movement, melee, death |
| `scripts/npcs/enemy_spawner.gd` | **New.** `EnemySpawner`: keeps N enemies alive at child Marker3D spawn points |
| `scenes/enemies/raider.tscn` | **New.** Raider body, hit zones, model, NavAgent, health, "!" label |
| `assets/materials/raider_*.tres` | **New.** 6 raider materials |
| `levels/outpost_17/outpost_17_navmesh.tres` | **New.** Baked navigation mesh (721 polygons) |
| `levels/outpost_17/outpost_17.tscn` | **Patched.** + `Navigation` region, + `RaiderSpawner` with 4 spawn points; geometry nodes tagged `navigation_geometry` |
| `scripts/combat/weapon_definition.gd` | **Changed.** + `noise_radius` (60 m) |
| `scripts/combat/hitscan_weapon.gd` | **Changed.** Each shot calls `hear_noise()` on the `noise_listeners` group |
| `scripts/core/game_mode.gd` | **Changed.** Kill cause uses a source's `display_name` ("Killed by Raider") |
| `tests/test_raider.gd` | **New suite** (12 tests). `test_outpost_17.gd` +5 level tests; `test_case.gd` + navigation helpers |

`scripts/npcs/` is a new folder: NPC behaviour (raiders now, settlers and soldiers later) sits next to `scripts/player/`.

## 2. Scene hierarchy

### `scenes/enemies/raider.tscn`
```
Raider              CharacterBody3D   layer 4 npcs; mask 1,2,3,4      script: raider.gd
├── BodyShape       Capsule r0.35 h1.45     meta damage_multiplier = 1.0
├── HeadShape       Sphere r0.16 at y 1.6   meta damage_multiplier = 2.0
├── %Visual         Node3D (pivot at feet; flinch + death fall)
│   ├── legs, boots, belt, torso, straps, tyre pad, head, bandana, goggles, mohawk
│   ├── %LeftArm    Node3D (shoulder pivot)
│   └── %RightArm   Node3D (shoulder pivot) + machete — swings on attack
├── %Eyes           Marker3D y 1.62 (sight ray origin)
├── %NavAgent       NavigationAgent3D  path_height_offset 0.5, desired distances 0.8
├── %HealthComponent max 80
└── %AlertLabel     Label3D "!" (billboard, no depth test)
```

### Level additions
```
Outpost17
├── Navigation        NavigationRegion3D  navmesh: outpost_17_navmesh.tres
│                     (source: nodes in group "navigation_geometry", static colliders on layers 1+2)
└── RaiderSpawner     Node3D + enemy_spawner.gd  (enemy_scene raider.tscn, max 3, respawn 20 s)
    ├── SpawnSouthWest  (-32, 0, 58)
    ├── SpawnSouthEast  (34, 0, 62)
    ├── SpawnSouth      (-6, 0, 66)
    └── SpawnNorthWest  (-48, 0, -48)
```
Tagged `navigation_geometry`: Terrain, Perimeter, MainGate, GuardTowers, Buildings, Props, Vehicles, DrainageCulvert, FiringRange.

## 3. How the raider works

| State | Behaviour | Leaves when |
|---|---|---|
| IDLE | stands 2–5 s | timer → WANDER |
| WANDER | walks (1.8 m/s) to a random navmesh point ≤ 12 m from home (skips roofs) | arrives → IDLE |
| CHASE | runs (5 m/s) at the target; repaths every 0.25 s | in range → ATTACK; unseen 4 s → SEARCH; target dead → IDLE |
| ATTACK | stops, faces target, **0.45 s wind-up** (arm raised), strike, 0.8 s recovery | → CHASE |
| SEARCH | runs/walks to last known or heard position, looks around 6 s | → WANDER |
| DEAD | falls, collision off (bullets and players pass), despawns after 30 s | — |

- **Sight** (checked 10× per second): within 30 m, inside a 120° cone (or within 2.5 m in any direction), and a clear ray from the eyes to your head against terrain and structures.
- **Hearing:** each rifle shot calls `hear_noise(origin, 60, shooter)` on the `noise_listeners` group. A calm raider within range runs to investigate.
- **Being shot** alerts the raider to the shooter immediately.
- **The strike lands only if** you're still within 2.0 m and within 70° in front when the wind-up ends. Backing off dodges it.

## 4. Input Map

No changes.

## 5. Inspector settings

**Raider** (all in Inspector groups): walk 1.8 / run 5.0 m/s, wander radius 12, sight 30 m / FOV 120° / proximity 2.5 m, hearing multiplier 1, lose target 4 s, search 6 s, attack range 1.7 / damage 20 / wind-up 0.45 / recovery 0.8 / hit angle 70°, despawn 30 s, `display_name` "Raider". HealthComponent 80.
**EnemySpawner:** `enemy_scene`, `max_alive` 3, `respawn_delay` 20, `min_player_distance` 25, `enabled`.
**Service rifle:** `noise_radius` 60.
**NavigationMesh:** cell 0.25 / 0.25, agent radius 0.25, height 1.75, max climb 0.25, max slope 45°, bake AABB ±78 m.

## 6. Signals

| Signal | When | Used by |
|---|---|---|
| `Raider.state_changed(state)` | any state change | tests → later: barks, music intensity |
| `Raider.attacked(target, hit)` | each strike | → later: swing/impact audio |
| `Raider.killed(raider)` | death | EnemySpawner (schedules replacement) → later: loot, XP, faction reputation |
| `EnemySpawner.enemy_spawned(enemy)` | each spawn | → later: raid waves, MilitaryManager |
| `HealthComponent.damaged` (raider) | hit | Raider flinch + alert to shooter |

## 7. Editing in the editor

- **Re-bake navigation after changing the level:** select `Navigation`, then click **Bake NavigationMesh** in the toolbar. New solid props need to sit under a node in the `navigation_geometry` group (Node → Groups) so the bake sees them.
- **Add a spawn point:** add a Marker3D as a child of `RaiderSpawner`.
- **Peaceful testing:** untick `enabled` on `RaiderSpawner`.
- **See the navmesh while playing:** Debug menu → **Visible Navigation**.

## 8. Testing

```
godot --headless --path . -s res://tests/test_runner.gd
```
Result: **83 passed, 0 failed.**

**test_raider** (isolated arena with a runtime-baked navmesh): wanders near home; sees a player 15 m in front; doesn't see one behind; a wall blocks sight; 40 m is out of range; hears a gunshot and moves toward it; ignores a noise out of range; paths around a wall, reaches the player and hits twice for 20 each (source is the raider, hits spaced by the attack cycle); stepping away during the wind-up avoids damage; rifle headshot deals 68, then a body shot kills (killed signal, collision off, despawns); stops chasing a dead player; kill message "Killed by Raider".
**test_outpost_17** (real level): navmesh routes from the south spawn through the gate into the barracks; culvert too low for raiders; spawner places 3 raiders outside the walls away from the player; a raider comes 60 m through the gate and hits a player in the yard; a killed raider is replaced after the delay.

**Bugs the tests caught and fixed:**
1. **The barracks interior was sealed off** because a 0.5 m navigation margin closed the 1.2 m doors. The margin is now 0.25 m.
2. **Raiders stalled mid-route.** The baked mesh sits about 0.5 m above the floor, so the agent never "reached" its first waypoint after re-pathing. Fixed with `path_height_offset`.
3. **Raiders slowed to a walk after losing sight of you.** They now keep running to your last known position.

### Manual checklist (Edit → F5)
- [ ] Fire a few shots at the range: raiders to the south come running, with "!" over their heads.
- [ ] Hide behind a building: raiders that lose sight go to where they last saw you and search.
- [ ] Let one reach you, then back off as it raises its machete: no damage.
- [ ] Two headshots or three body shots kill. The body falls and a replacement appears ~20 s later.
- [ ] Die to a raider: "Killed by Raider".

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| Game frozen on start, red screen | Stale script cache. Open with **Edit**, not Run (see README). |
| Raiders walk straight into walls | The navmesh is missing or stale. Re-bake `Navigation`. Check that new geometry is in the `navigation_geometry` group. |
| Raiders stand still for a second after loading | Normal. Godot builds the navigation map asynchronously during the first frames. |
| Raiders can't enter a new building | Doors narrower than ~0.8 m are sealed off by the 0.25 m navigation margin. |
| Raiders never notice you | Check `RaiderSpawner.enabled`, the raider's `sight_range`, and that the player is in the `players` group (automatic). |
| Too hard or too easy | Tune `attack_damage`, `run_speed`, `attack_windup` and `sight_range` on the raider scene, and `max_alive` / `respawn_delay` on the spawner. |

## 10. How this connects to future systems

- **Stealth:** `can_see()` gains modifiers for crouching, darkness (day/night cycle) and suppressed weapons (`noise_radius`).
- **Ranged soldiers:** same state machine with a `HitscanWeapon` ticked from the Eyes marker instead of melee.
- **MilitaryManager and raids:** EnemySpawner becomes the building block for raid waves against your settlement; guards use the same perception and navigation.
- **FactionManager:** raiders get a faction and reputation, so killing them changes standing.
- **Loot (Inc 7):** `Raider.killed` drops a lootable container with the raider's inventory.
- **Save (Inc 8):** spawner and raider states are saved (position, health, state).
- **Co-op:** AI runs on the host only; `MultiplayerSynchronizer` replicates transform, `state` and health to guests.
