# Increment 3 — Player health, fall damage, death and respawn

**Status:** complete. 66 automated tests pass (15 new; all earlier tests still pass), run headless in Godot 4.7.
**Playable result:** you have 100 health shown bottom-left. Falls over ~3.3 m hurt, and ~16.5 m kills. The two burning barrels (yard and motor pool) burn you if you touch them. A 6 m **range tower** behind the firing line lets you test fall damage by jumping off its open back edge. When you die you see "YOU DIED", the cause, and a 5 s countdown, then press **Space** to respawn at the outpost spawn point. Falling out of the world now kills you instead of teleporting you.

---

## 1. Files

| File | Purpose |
|---|---|
| `scripts/core/game_mode.gd` | **New.** `GameMode`: death bookkeeping, respawn rules (delay, spawn point), cause-of-death text |
| `scripts/combat/damage_zone.gd` | **New.** `DamageZone` (Area3D): damage over time to anything with health inside it |
| `scripts/ui/damage_indicator.gd` | **New.** Red arcs pointing toward damage sources |
| `scripts/world/flicker_light.gd` | **New.** Fire-light flicker (visual) |
| `scenes/world/props/burning_barrel.tscn` | **New.** Barrel, fire particles, flickering light, `FireZone` (15 dps) |
| `scenes/world/structures/range_tower.tscn` | **New.** 6 m platform with stair ramp; open back edge |
| `scripts/player/player_controller.gd` | **Changed.** Health, fall damage, DEAD state, `respawn_requested` and `respawn_at()`, lethal kill plane |
| `scripts/combat/hitscan_weapon.gd` | **Changed.** + `cancel_reload()`, `restock()` |
| `scripts/ui/hud.gd` | **Changed.** Health bar with damage trail, red vignette (hit flash + low-health pulse), damage arcs, death screen |
| `scenes/player/player.tscn` | **Patched.** + `%HealthComponent` (100) |
| `scenes/ui/hud.tscn` | **Patched.** + DamageVignette, DamageIndicator, HealthPanel, DeathScreen |
| `levels/outpost_17/outpost_17.tscn` | **Patched.** + `GameMode`, `FiringRange/RangeTower`, `Props/BurningBarrelYard`, `Props/BurningBarrelMotorPool` |
| `tests/test_player_health.gd` | **New suite.** Plus 3 new level tests in `test_outpost_17.gd` |

## 2. Scene hierarchy (additions)

```
Player (player.tscn)
└── %HealthComponent        max_health 100

Outpost17
├── GameMode                 Node   script: game_mode.gd
│                            spawn_point → ../PlayerSpawn, players → [../Player], respawn_delay 5
├── HUD                      game_mode → ../GameMode   (new export)
├── FiringRange/RangeTower   range_tower.tscn at (11, 0, 47)
└── Props/BurningBarrelYard, Props/BurningBarrelMotorPool

BurningBarrel (StaticBody3D, layer 2)
├── Drum, DrumShape
├── Fire                     GPUParticles3D
├── FireLight                OmniLight3D + flicker_light.gd
└── FireZone                 Area3D + damage_zone.gd  (layer 7 triggers; mask 3 player + 4 npcs)
    └── ZoneShape            Cylinder r 0.75, h 1.4

HUD/Root
├── %DamageVignette          TextureRect, radial red gradient (first child = behind all)
├── %Crosshair ...
├── %DamageIndicator         Control + damage_indicator.gd
├── HealthPanel              bottom-left: HealthTitle, %HealthLabel, HealthBarBg, %HealthTrail, %HealthFill
└── %DeathScreen             Dim, DeathTitle, %DeathCause, %RespawnPrompt  (hidden while alive)
```

## 3. Scripts — key points

- **Death is a state, not a scene change.** When health hits 0, `PlayerController` enters `DEAD`: it ignores movement, look and weapon input, hides the weapon, cancels reloads, and plays a death-camera tween. The body still falls under gravity.
- **Respawn is requested, not performed, by the player.** Jump while dead → `respawn_requested` → `GameMode.try_respawn()` checks the delay → `player.respawn_at(spawn)` revives, resets stance, camera and weapon. In co-op the host's GameMode makes this call, so a client can't skip the timer.
- **Fall damage** is `max_health × (impact_speed − safe) / (lethal − safe)`, from the `landed` signal. Safe 8 m/s (≈ 3.3 m), lethal 18 m/s (≈ 16.5 m). A 6 m drop deals ≈ 28; jumping off adds a little more.
- **`DamageZone`** applies `damage_per_second × tick_interval` every interval to each body inside that has a `HealthComponent`, starting the tick after entry. It works on players and NPCs, and the zone is the damage `source`, so HUD arcs point at it.
- **Cause of death:** a source's `death_message` property, if it has one ("You burned to death"), otherwise the damage type ("You fell to your death"), otherwise "Killed by <source name>".
- **Ammo on respawn** is restocked to starting values for now. When ammo becomes inventory items (Increment 6), the death rules here decide what you keep.

## 4. Input Map

No new actions. **Jump (Space)** respawns while dead.

## 5. Inspector settings

| Node | Property | Default |
|---|---|---|
| Player → Fall damage | `safe_fall_speed` / `lethal_fall_speed` | 8 / 18 m/s |
| Player → Control | `kill_plane_y` | −30 (now lethal) |
| Player/%HealthComponent | `max_health` | 100 |
| GameMode | `respawn_delay` / `spawn_point` / `players` | 5 s / PlayerSpawn / [Player] |
| HUD | `game_mode` / `low_health_threshold` | ../GameMode / 0.3 |
| BurningBarrel/FireZone (DamageZone) | `damage_per_second` / `tick_interval` / `death_message` | 15 / 0.5 s / "You burned to death" |
| DamageIndicator | `radius` / `arc_degrees` / `duration` | 110 px / 40° / 1.2 s |

## 6. Signals

| Signal | Emitted | Connected to |
|---|---|---|
| `PlayerController.died(info)` | health reaches 0 | GameMode (records time and cause) → later: drop loot, notify squad |
| `PlayerController.respawn_requested` | jump pressed while dead | GameMode.try_respawn |
| `PlayerController.respawned` | after `respawn_at` | → later: spawn protection, UI toast |
| `PlayerController.landed(speed)` | touchdown | PlayerController fall damage (internal) |
| `GameMode.player_died / player_respawned` | | → later: kill feed, settlement morale, co-op messages |
| `HealthComponent.health_changed / damaged` | | HUD bar, trail, vignette, damage arcs |
| `DamageZone.damaged_body(body, amount)` | each damage step | → later: burn audio and effects |

## 7. Building in the editor yourself (optional)

- **Hazard:** add an **Area3D** to any prop, attach `damage_zone.gd`, and give it a CollisionShape3D. Set Collision **Layer 7** only and **Mask 3 + 4**. Set `damage_per_second` and `death_message`.
- **GameMode in a new level:** add a **Node**, attach `game_mode.gd`, set `spawn_point` to a Marker3D, add the player to `players`, and set the HUD's `game_mode` to it.
- **Player health:** already in `player.tscn` (`%HealthComponent`, Access as Unique Name on).

## 8. Testing

```
godot --headless --path . -s res://tests/test_runner.gd
```
Result: **66 passed, 0 failed.**

New tests:
- **test_player_health:** starts at 100; 3 m drop safe; 8 m fall matches the curve and is survivable; 25 m fall kills with FALL; damage curve values; kill plane kills; dead player can't move or shoot and the weapon hides; death camera drops; jump while dead requests respawn; GameMode refuses respawn before the delay, then restores health, position, camera, weapon and movement; cause-of-death texts; DamageZone ≈ dps over time and stops on exit; DamageZone hurts NPCs.
- **test_outpost_17:** climb the range tower stairs to 6 m without damage, walk off the back and take 15–45 damage; the burning barrel hurts on contact and not 4 m away; full loop in the real level (HUD 65 → death screen with cause and countdown → "Press SPACE" → respawn at PlayerSpawn, HUD back to 100).
- **test_player_controller:** the old "kill plane teleports" test was removed; it's replaced by "kill plane kills".

### Manual checklist (F5)
- [ ] Touch a burning barrel: health drops, the screen flashes red, and an arc points at the barrel.
- [ ] Below 30 health the bar turns red and the screen edges pulse.
- [ ] Climb the range tower and jump off the back (marked "NO RAILING"): about 30 damage.
- [ ] Die by standing in the fire: "YOU DIED / You burned to death / Respawn in 5…", then press Space.
- [ ] After respawn: full health, full ammo, at the spawn by the gate.

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| Pressing Space while dead does nothing | Wait for the countdown. Also check the HUD's `game_mode` and GameMode's `players` include the player. |
| Respawn puts you at the world origin | GameMode `spawn_point` isn't set. |
| A hazard doesn't hurt | The Area3D mask must include layer 3 (player). The target needs a HealthComponent. Check `enabled`. |
| No damage when falling from height | You landed on something sloped, which cuts impact speed. Or `safe_fall_speed` was raised. |
| The death screen never hides | Something is damaging the player right after respawn, such as respawning inside a DamageZone. Move the spawn. |
| Can't climb the tower stairs | Player `floor_max_angle` must stay ≥ 25° (it's 46°). The ramp is 24.8°. |

## 10. How this connects to future systems

- **Increment 4 (enemies):** raiders deal MELEE damage with `source = self`, so the HUD arcs point at them and the death screen says "Killed by Raider". Their HealthComponent is the same class.
- **Increment 5 (items):** medkits call `health.heal()`.
- **Increment 6 (inventory):** GameMode decides what's lost on death (drop a backpack at the death position, recover it later). `respawn_at` stops restocking ammo.
- **Increment 8 (save):** save `current_health`. Dead players save as respawned.
- **Settlement milestones:** GameMode chooses among spawn points (owned settlements, beds). DamageZone covers radiation, toxic water and electrified fences.
- **Co-op:** only the host's GameMode and DamageZones apply damage and respawns. Clients replicate health via `MultiplayerSynchronizer` and show the same HUD.
