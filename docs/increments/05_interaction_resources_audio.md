# Increment 5 — Interaction, collectible resources, and sound

**Status:** complete. 106 automated tests pass (23 new; all earlier tests still pass), run headless in Godot 4.7. Also run in a real window: no script errors.
**Playable result:** look at loot and a prompt appears: **"[E] Pick up Scrap Metal ×6"**. Heavier items (fuel cans, medkits) need **E held** and show a progress bar. 22 pickups are placed around Outpost 17: warehouse shelves, barracks, command post, motor pool, range bench, and some riskier ones out in raider territory. Raiders drop loot 60% of the time. Ammo refills your reserve (up to 240). Medkits heal 40 and are refused at full health ("Already at full health"). Resources (scrap, cloth, fuel, electronics) are counted top-right, with "+6 Scrap Metal" pop-ups.

The game also has **sound** now: gunshots, reload, dry-fire click, bullet impacts (dirt vs. hard surfaces with ricochets), metal pings on range targets, footsteps, landings, hurt sounds, a low-health heartbeat, a death sting, raider shouts, pain, death, machete swings and footsteps, crackling fire on the burning barrels, wasteland wind, pickup sounds, and hit-marker ticks.

> **After pulling:** open with **Edit** in the Project Manager (not Run). This update adds 8 new scripts.

---

## 1. Files

| File | Purpose |
|---|---|
| `scripts/inventory/item_definition.gd` | **New.** `ItemDefinition` Resource: id, name, category, stack, weight, value (Marks), world model, hold time, pickup sound, heal, ammo type |
| `resources/items/*.tres` | **New.** scrap_metal, cloth, fuel, electronics, rifle_ammo, medkit |
| `scripts/interaction/interactable.gd` | **New.** `Interactable` (Area3D, layer 5): prompt, block reason, hold time, validated `try_interact()` |
| `scripts/interaction/pickup.gd` + `scenes/items/pickup.tscn` | **New.** `Pickup`: an item lying in the world; shows the item's model, highlights when focused |
| `scenes/items/models/*.tscn` | **New.** Placeholder models for the six items |
| `scripts/interaction/player_interactor.gd` | **New.** `PlayerInteractor` (RayCast3D under the head): focus, press and hold handling |
| `scripts/inventory/player_resources.gd` | **New.** `PlayerResources`: what picking up means (store, refill ammo, heal); stand-in for the Inc 6 inventory |
| `scripts/player/player_audio.gd` | **New.** `PlayerAudio`: footsteps, landing, hurt, heartbeat, death, pickup sounds |
| `tools/audio/synth_sounds.py` | **New.** Generates all 40 sound effects (Python + numpy/scipy) |
| `assets/audio/*.wav`, `assets/audio/sets/*.tres` | **New.** Sounds, plus `AudioStreamRandomizer` sets for variation |
| `default_bus_layout.tres` | **New.** Audio buses: Master → SFX, UI, Ambience |
| Changed scripts | `input_frame.gd` (+interact), `player_input.gd`, `player_controller.gd` (ticks interactor), `weapon_definition.gd` (+ammo_type, max_reserve), `hitscan_weapon.gd` (sounds, `add_reserve_ammo`, surface-aware impacts, dry-fire fix), `bullet_impact.gd`, `raider.gd` (sounds, loot drops), `target_dummy.gd` (ping), `hud.gd` |
| Patched scenes | player, HUD, raider, service rifle, bullet impact, target dummy, burning barrel, warehouse (per-shelf collision), Outpost 17 (+Ambience, +Loot) |

`scripts/interaction/` is a new folder: anything you press E on (pickups now; containers, doors and workbenches later).

## 2. Scene hierarchy (additions)

```
Player
├── Head/%Interactor     RayCast3D + player_interactor.gd  (3 m, hits areas; layers 1,2,5)
├── %Resources           Node + player_resources.gd
└── Audio                Node3D + player_audio.gd
    ├── %Footsteps       AudioStreamPlayer3D (footstep_gravel set)
    ├── %Land            AudioStreamPlayer3D
    └── %Hurt, %Heartbeat, %Death, %Pickup   AudioStreamPlayer

Pickup (scenes/items/pickup.tscn)
└── Area3D + pickup.gd   layer 5 interactables · Shape (0.6×0.45×0.6) · item's world_model added at runtime

HUD/Root  + %PromptLabel, %PromptReason, %HoldBar, %Notices (VBox), %ResourcesLabel ; HUD/%UISound (bus UI)
ServiceRifle + %ShotSound (polyphony 6), %ReloadSound, %DryFireSound
BulletImpact + %DirtSound, %HardSound
Raider + %AlertSound, %PainSound, %DeathSound, %SwingSound, %HitSound, %FootstepSound
TargetDummy + %PingSound ; BurningBarrel + FireSound (looping, autoplay)
Outpost17 + Ambience (wind loop, bus Ambience) + Loot (22 pickups)
```

## 3. Key points

- **Interact flow:** each tick `PlayerInteractor` casts 3 m from the eyes. Walls block it; it focuses the first `Interactable` hit. On press (or after the hold completes), it calls `Interactable.try_interact(player, eye_position)`. That **re-validates** reach, line of sight and `get_block_reason()` before acting, so a co-op host can safely run guest requests.
- **Holding E grabs one item, not everything in a row.** Instant pickups trigger on the press, not the hold.
- **`PlayerResources.receive()`** is the only place picking up changes state. Increment 6 swaps its storage for a real `InventoryComponent` with the same `receive()` / `get_refusal_reason()` API, so pickups don't change.
- **Sound variation:** sets use `AudioStreamRandomizer` (no immediate repeats, ±7% pitch, ±1.5 dB), so 650 rpm fire doesn't sound like one sample on repeat.
- **Footsteps** fire per distance walked (0.75 m; sprint strides 25% longer; crouching is quieter), not on a timer.
- **Bullet impacts** play dirt or hard sounds based on the hit layer. Characters and targets play their own (flesh, metal ping), and get no decal.

## 4. Input Map

| Action | Key |
|---|---|
| `interact` | **E** (tap, or hold for hold-items) |

## 5. Inspector settings

| Where | Property | Value |
|---|---|---|
| `ItemDefinition` (.tres) | category / max_stack / weight / base_value | per item (see `resources/items/`) |
| | pickup_hold_time | fuel 0.8 s, medkit 0.5 s, others 0 |
| | heal_amount / ammo_type | medkit 40 / rifle ammo `rifle_556` |
| `Pickup` | item, quantity, animate | set per placement; raider drops animate (spin and bob) |
| `Interactable` | action_name, hold_time, max_distance (3), enabled | |
| `service_rifle.tres` | ammo_type / max_reserve | `rifle_556` / 240 |
| `Raider` → Death | drop_items / drop_chance / drop_min–max | 7-entry weighted list / 0.6 / 1–3 (ammo 10–20) |
| `PlayerAudio` | step_length / heartbeat_threshold | 0.75 m / 30% |
| Buses | SFX / UI / Ambience | 0 / −4 / −6 dB |

**Adding a new item:** create a `.tres` with `ItemDefinition`, give it a model scene and a sound, then drag `scenes/items/pickup.tscn` into the level and set `item` and `quantity`.

## 6. Signals

| Signal | Used by |
|---|---|
| `PlayerInteractor.focus_changed / hold_progress_changed` | HUD prompt and hold bar |
| `PlayerInteractor.interaction_succeeded / interaction_refused(target, reason)` | HUD (denied sound) → later: tutorials |
| `Interactable.interacted(interactor)` | → later: quests ("collect 10 scrap"), door and container logic |
| `Pickup.picked_up(item, qty, by)` | → later: SaveManager marks it collected |
| `PlayerResources.item_received(item, qty)` | HUD notices, PlayerAudio pickup sound |
| `PlayerResources.counts_changed` | HUD resource list |

## 7. About the sounds

All 40 sounds are **synthesized** by `tools/audio/synth_sounds.py` from noise, oscillators and filters, so they have no licensing issues. Re-run it with `python3 tools/audio/synth_sounds.py`. They are **placeholders**: punchy enough to give feedback, but more retro than recorded audio. **The raider voices are the weakest**, so replace those first.

To replace a sound, drop a recorded file in `assets/audio/` with the **same file name** (`.wav`), or point the player node or `.tres` set at a new file. Good free sources: **Kenney** (CC0), **Sonniss GDC bundles** (royalty-free), **freesound.org** (check each license).

How each sound was checked: waveforms and spectrograms were inspected for clipping and clicks, loops were checked for a seamless join, and tests confirm each one imports and plays on the right event. Nobody has listened to them yet. That needs a human, so please tell me what sounds off.

## 8. Testing

```
godot --headless --path . -s res://tests/test_runner.gd
```
Result: **106 passed, 0 failed.**

- **test_interaction** (11): items valid; focus and prompt text; nothing focused beyond 3 m or through a wall; tap pickup adds resources and removes the pickup; holding E takes only one; hold-to-pick fuel (progress, early release cancels, completes at 0.8 s); medkit refused at full health then heals 40; ammo refills to max and leaves the remainder; `try_interact` rejects a 10 m request; dead players can't interact; raiders drop loot at their feet.
- **test_audio** (8): all 40 WAVs import; loops loop; buses exist; shot, reload and dry-fire play; footsteps scale with distance and stop when idle; hurt, heartbeat (stops when healed) and death; raider shout, flesh hit and target ping; level ambience and barrel fire play.
- **test_outpost_17** (+3): all 22 loot items rest on a surface; the HUD prompt reads "[E]  Pick up Rifle Ammo ×30" and the notice shows "+30 Rifle Ammo"; loot on warehouse shelves can be targeted.

**Bugs caught and fixed:**
1. **Warehouse rack loot was unreachable.** Each rack's collision was one solid block, so the interaction ray hit it instead. Each shelf and post now has its own collision, and the navmesh was rebaked.
2. **The empty-gun click was swallowed** if you pulled the trigger during the fire-rate cooldown.
3. **A HUD script typo** was caught by a new pre-build check. Every script is now parse-checked before scenes are generated, so a broken script can't silently strip scene settings.

### Manual checklist (Edit → F5)
- [ ] Shoot: a gunshot with an echo tail; the range targets **ping**; the walls crack, sometimes with a ricochet whine.
- [ ] Walk, sprint and crouch: footsteps change pace and volume.
- [ ] Warehouse: pick scrap and electronics off the shelves (E), and **hold E** on the fuel can.
- [ ] Gate medkit: "Already at full health". Take damage at a fire barrel, then pick it up.
- [ ] Below 30 health: a heartbeat. Raiders shout when they spot you and groan when they die; some drop spinning loot.

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| No sound at all | Check the OS output device. In Godot, check the Audio tab at the bottom (bus volumes, mute). |
| Sounds don't loop | Loops rely on the WAV loop marker. Keep the import setting **Loop Mode = Detect From WAV** (default). Re-run the synth script if files were edited. |
| Prompt never appears | The object must be an `Interactable` on **layer 5** with a CollisionShape3D, within 3 m, with nothing solid in between. |
| Can't pick up ammo | "Ammo full" means the reserve is at `max_reserve` (240). |
| Too loud or quiet | Adjust bus volumes (Audio tab), or a player node's `volume_db` / `unit_size`. |

## 10. How this connects to future systems

- **Increment 6 (inventory):** `PlayerResources` becomes a real `InventoryComponent` (slots, stacks, weight from `ItemDefinition.weight`), and the HUD list becomes the inventory screen. Ammo and medkits become inventory items you use from there.
- **Increment 7 (salvage containers):** containers are `Interactable`s with "Search" as the action and a hold time, opening a transfer UI.
- **Increment 8 (save):** collected pickups and carried resources are saved.
- **Economy:** `base_value` is the Marks price before supply and demand. Resource counts feed crafting and building costs.
- **Audio later:** surface-specific footsteps, reverb zones indoors, music intensity driven by raider states, voice lines.
