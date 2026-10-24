# Increment 2 — Rifle, HealthComponent, target dummies

**Status:** complete. 51 automated tests pass (28 new, plus all 23 from Increment 1), run headless in Godot 4.7.
**Playable result:** you carry a service rifle (full-auto, 30-round magazine, reload, recoil, muzzle flash, bullet holes and dust). Walk out of the gate and follow the sign east to the **firing range**: five targets at 10, 20, 35 and 50 m that show damage numbers, take double damage to the head, fall when killed and reset after 3 seconds.

---

## 1. Files

Dependencies first.

| File | Purpose |
|---|---|
| `scripts/combat/damage_info.gd` | `DamageInfo`: amount, type, source, hit point/normal/direction, zone multiplier |
| `scripts/combat/health_component.gd` | `HealthComponent`: reusable health with damage/heal/revive and signals; `find_on()` |
| `scripts/combat/weapon_definition.gd` | `WeaponDefinition` Resource: all weapon stats |
| `resources/items/weapons/service_rifle.tres` | The service rifle's stats |
| `scripts/combat/bullet_impact.gd` + `scenes/weapons/effects/bullet_impact.tscn` | Bullet-hole decal + dust puff |
| `scripts/combat/hitscan_weapon.gd` | `HitscanWeapon`: fire rate, modes, ammo, reload, spread/bloom, recoil, hit zones, falloff |
| `scenes/weapons/service_rifle.tscn` | Rifle scene: viewmodel, muzzle, muzzle flash |
| `scripts/ui/crosshair.gd` | `Crosshair`: dynamic gap = real spread, hit markers |
| `scripts/world/target_dummy.gd` + `scenes/world/range/target_dummy.tscn` | Range target |
| `assets/materials/target_plate.tres`, `target_marking.tres` | Target materials |
| **Changed:** `scripts/core/input_frame.gd` | + `fire`, `reload` (and in `to_dict`/`from_dict`) |
| **Changed:** `scripts/player/player_input.gd` | Reads fire/reload; ignores the click that recaptures the mouse |
| **Changed:** `scripts/player/player_controller.gd` | Ticks the weapon, applies recoil, movement spread, sprint blocks fire |
| **Changed:** `scripts/ui/hud.gd`, `scenes/ui/hud.tscn` | Ammo + weapon name, new crosshair, hit markers |
| **Changed:** `scenes/player/player.tscn` | + `WeaponMount/Weapon` under the camera |
| **Changed:** `levels/outpost_17/outpost_17.tscn` | + `FiringRange` (added; nothing else changed) |
| `tests/test_health_component.gd`, `test_hitscan_weapon.gd`, `test_target_dummy.gd` | New test suites |

## 2. Scene hierarchy

### `scenes/weapons/service_rifle.tscn`
```
ServiceRifle            Node3D   script: hitscan_weapon.gd   definition: service_rifle.tres
└── %Model              Node3D   (visual only; kicks and tilts in _process)
    ├── Receiver, Handguard, Barrel, MuzzleDevice, Magazine, Grip, Stock, TopRail, Optic...
    └── %Muzzle         Marker3D   (barrel tip)
        └── %MuzzleFlash Node3D    (hidden; shown ~0.05 s per shot)
            ├── FlashLight  OmniLight3D
            └── FlashCard ×2, FlashStar   MeshInstance3D (additive quads)
```

### Player additions (`scenes/player/player.tscn`)
```
Player
└── Head
    └── Camera
        └── WeaponMount   Node3D   pos (0.13, −0.135, −0.4), scale 0.72
            └── %Weapon   service_rifle.tscn instance
```

### `scenes/world/range/target_dummy.tscn`
```
TargetDummy            Node3D         script: target_dummy.gd
├── Stand              StaticBody3D   layer 2 — StandShape meta damage_multiplier = 0
├── %Hinge             Node3D         y 0.9 (rotates to flinch / fall)
│   └── TargetBody     StaticBody3D   layer 2
│       ├── TorsoShape CollisionShape3D   meta damage_multiplier = 1.0
│       ├── HeadShape  CollisionShape3D   meta damage_multiplier = 2.0
│       └── Torso, Shoulders, Neck, Head, ScoringZone, HeadMark (meshes)
├── %HealthComponent   max 100
└── %DamageLabel       Label3D (billboard)
```

### `levels/outpost_17/outpost_17.tscn` → `FiringRange`
Lane gravel, two sandbag walls at the firing line (x = 15), shooting bench, ammo crate, targets `Target10mA/B`, `Target20m`, `Target35m`, `Target50m`, distance markers, earth backstop, and a sign at the gate.

### HUD additions
`Root/%Crosshair` (full-rect Control, replaces the old dot), `Root/%WeaponLabel`, `Root/%AmmoLabel` (bottom-right).

## 3. Scripts — key points

- **`HitscanWeapon.tick()` is simulation.** Fire rate (with remainder carry-over, so 650 rpm really is 650), trigger edge detection for semi-auto, reload timing, bloom, and the physics ray. `_process()` is visuals only. The owner passes the aim transform, the shooter to exclude, a movement spread multiplier, and whether it may fire.
- **Hit zones need no code on the target.** Any `CollisionShape3D` can carry metadata `damage_multiplier` (2.0 head, 0.0 armour or stands). The weapon reads it from the exact shape the ray hit.
- **`HealthComponent.find_on(collider)`** checks the collider and three parents, so colliders can be nested inside the object that owns the health.
- **Spread** is a uniform random cone: (base + bloom) × movement multiplier (idle 1.0, walking or sprinting 1.8, crouching 0.6, airborne 3.0). Bloom grows per shot and recovers after a 0.2 s pause.
- **Sprint-to-fire.** You can't shoot while sprinting. Pressing fire cancels sprint, and the first shot leaves once you've slowed, a few hundredths of a second later.

## 4. Input Map (new actions)

| Action | Binding |
|---|---|
| `fire` | Left mouse button |
| `reload` | R |

## 5. Inspector settings

**`service_rifle.tres` (WeaponDefinition)**
| Group | Property | Value |
|---|---|---|
| Damage | damage / falloff start / end / min | 34 / 50 m / 200 m / 0.6 |
| | max range | 300 m |
| Handling | fire mode / rpm | Full Auto / 650 |
| | magazine / starting reserve / reload | 30 / 120 / 2.3 s |
| Accuracy | base / per shot / max bloom | 0.35° / 0.25° / 3.0° |
| | bloom recovery / delay | 6°/s after 0.2 s |
| Recoil | pitch / yaw per shot | 0.55° / ±0.2° |

**HitscanWeapon:** `definition`, `spawn_impact_effects` (on).
**PlayerController → Weapon handling:** spread idle 1.0, walking 1.8, crouching 0.6, airborne 3.0.
**TargetDummy:** reset delay 3 s, show damage numbers on. **HealthComponent:** max 100.

To make a new gun: duplicate `service_rifle.tres`, change the numbers, duplicate `service_rifle.tscn`, and point its `definition` at the new resource.

## 6. Signals

| Signal | Emitted | Connected to (now → later) |
|---|---|---|
| `HitscanWeapon.fired(origin, direction)` | each shot | → audio, AI hearing, tracers |
| `HitscanWeapon.hit_confirmed(target, damage, killed, zone)` | a shot damaged something | HUD hit marker → kill feed, XP |
| `HitscanWeapon.surface_hit(pos, normal, collider)` | any hit | → impact audio per surface |
| `HitscanWeapon.ammo_changed(mag, reserve)` | fire, reload | HUD ammo → inventory ammo (Inc 6) |
| `HitscanWeapon.reload_started / reload_finished / dry_fired` | reload flow | → audio, animation |
| `HealthComponent.damaged(amount, info)` | damage applied | TargetDummy flinch + number → player hurt effect (Inc 3) |
| `HealthComponent.died(info)` | health hits 0 | TargetDummy falls → player death (Inc 3), NPC death (Inc 4) |
| `HealthComponent.health_changed / healed / revived` | | → HUD health bar (Inc 3) |

The HUD connects to the player's weapon automatically, including if the weapon is swapped later.

## 7. Building in the editor yourself (optional)

1. **Weapon data:** FileSystem → right-click `resources/items/weapons` → New Resource → `WeaponDefinition`. Fill in the stats and save.
2. **Weapon scene:** New Scene → root Node3D, attach `hitscan_weapon.gd`, and drag the `.tres` into `definition`. Add a Node3D `Model` (unique name) holding your meshes, a Marker3D `Muzzle` at the barrel tip, and under it a Node3D `MuzzleFlash` (unique name) with an OmniLight3D and flash quads.
3. **Equip:** open `player.tscn` and add a Node3D `WeaponMount` under `Head/Camera`. Instance the weapon scene under it, name it `Weapon`, and enable **Access as Unique Name**.
4. **A damageable object:** add a `HealthComponent` child next to (or above) its collider. Optionally add metadata `damage_multiplier` (float) on individual CollisionShape3Ds: Inspector → bottom → **Add Metadata**.

## 8. Testing

```
godot --headless --path . -s res://tests/test_runner.gd
```
Result: **51 passed, 0 failed.**

| Suite | New tests |
|---|---|
| `test_health_component` | starts full; damage and signal; overkill clamps, dies once; zero/negative/null/invulnerable ignored; heal clamps, not when dead; revive; `find_on` through nested nodes |
| `test_hitscan_weapon` | 650 rpm → 10–11 shots/s; semi-auto needs release; dry fire + auto reload; reload timing and ammo transfer; no firing while reloading; reload rules; torso 34 / head 68 damage; falloff at range; shooter not hit; bloom grows and recovers; every shot inside the spread cone; recoil per shot |
| `test_target_dummy` | damage numbers (headshots marked); falls, then resets with full health; zone metadata |
| `test_player_controller` | rifle equipped; firing uses ammo and recoil raises aim; can't fire mid-sprint but can after slowing; crouching tightens spread |
| `test_outpost_17` | shooting from the firing line damages the 10 m target, and the HUD ammo counter updates |
| `test_input_map` | left mouse fires; R reloads |

**Two real problems the tests caught and fixed:** (1) bloom recovered faster than full-auto fire added it, so sustained fire never lost accuracy; it now recovers only after a 0.2 s pause. (2) Increment 1's runner bug, already fixed: crashed tests now count as failures.

### Manual checklist (F5)
- [ ] Hold left click: full-auto at ~11 rounds/s, view climbs, crosshair widens, muzzle flashes.
- [ ] Release: crosshair tightens after a moment. Crouching tightens it; walking widens it.
- [ ] Empty the magazine: the counter goes red, click once to auto-reload, or press R anytime. RELOADING % shows.
- [ ] Sprint, then click: a brief delay before the first shot.
- [ ] Range: body hits show white numbers; headshots show yellow "68!". Three body shots or two headshots drop a target, and it stands back up after 3 s.
- [ ] Bullet holes and dust appear on walls and ground (holes need Forward+, the default on your Mac).

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| Clicking to recapture the mouse fires a shot | Shouldn't happen: that click is ignored until released. If it does, check `PlayerInput._fire_blocked_until_release`. |
| Shots pass through an object | Its collision layer must be 1, 2, 3 or 4 (the weapon's `HIT_MASK`). Layer 5 (interactables) is deliberately not shot. |
| Object takes no damage | It needs a `HealthComponent` on the collider or within 3 parents. Check the hit shape doesn't have `damage_multiplier = 0`. |
| Rifle clips into walls when you stand close | Known limitation of a world-space viewmodel. A dedicated viewmodel render layer is planned with real art. |
| No bullet holes | Decals need Forward+ (Project Settings → Rendering → Renderer). The Compatibility renderer doesn't draw them. |
| Changing stats in code does nothing | Stats come from `service_rifle.tres`. Edit the resource, not the script defaults. |
| Weapon edits in `player.tscn` vanish | Edit the rifle in `scenes/weapons/service_rifle.tscn`; the player only instances it. |

## 10. How this connects to future systems

- **Increment 3 (player health).** The player gets a `HealthComponent`. Enemies and fall damage call `apply_damage`. The HUD gets a health bar from `health_changed`.
- **Increment 4 (enemies).** NPCs get a `HealthComponent` plus head and body zone metadata, and the rifle already works on them. NPC soldiers can use `HitscanWeapon.tick()` with their own aim.
- **Increment 6 (inventory).** `reserve_ammo` becomes ammo items in the inventory. `WeaponDefinition` becomes the weapon part of an `ItemDefinition`, so swapping weapons is equipping a different item.
- **Increment 8 (save).** The weapon saves `ammo_in_magazine` and `reserve_ammo`; health saves `current_health`.
- **Co-op.** Clients send `InputFrame.fire/reload`, the host runs `tick()` and applies damage (authoritative), and clients play `fired`/`surface_hit` effects. `set_rng_seed()` lets client effects match the host's spread.
