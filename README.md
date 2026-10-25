# ASHFALL: RECLAMATION

Post-apocalyptic first-person survival shooter with base building, settlement management, trading, military and diplomacy. Built in **Godot 4.7** (GDScript, Forward+).

## Current state: Milestone 2 complete (Increment 12)
- **Increment 1:** first-person character (walk, sprint, crouch, jump) at **Outpost 17**: walled military outpost with a fortified gate, guard towers, enterable buildings, a warehouse, a motor pool and a crouch-only culvert.
- **Increment 2:** service rifle (full-auto, reload, recoil, spread, muzzle flash, bullet holes), reusable `HealthComponent`, and a **firing range** east of the gate.
- **Increment 3:** player health, fall damage, burning barrels, a 6 m range tower, damage feedback, death screen, and respawn via `GameMode`.
- **Increment 4:** raider enemies that see and hear you, path through the gate and around cover on a baked navmesh, and attack with a dodgeable machete swing.
- **Increment 5:** interaction (**E**, tap or hold), 6 item types and 22 pickups (scrap, cloth, fuel, electronics, ammo, medkits), raider loot drops, and **sound** for nearly everything (synthesized placeholders).
- **Increment 6:** **inventory** (Tab / I): 24 slots, stacking, 30 kg carry weight, item icons, drag to move or drop. Medkits are stored and used with **H** (2 s quick-heal). Rifle ammo is an inventory item.
- **Increment 6.5:** **aim down sights** (right-click or Q to toggle: red-dot sight, 1.4× zoom, tighter spread, less recoil) and **ladders**: all four guard towers can be climbed.
- **Increment 7:** **salvage containers**: 11 crates, footlockers, weapons lockers, a tool chest and wasteland stashes. Hold E to search (loot is rolled once), then move items with a two-sided transfer screen (double-click, drag, Take All with R).
- **Increment 8:** **save and load**: F5 quick save, F9 quick load (fn+F5 / fn+F9 on Mac). Saves the player, inventory, every container and the loot on the ground as versioned JSON. Also quieter footsteps and clanging lockers.
- **Increment 9 (Milestone 2):** **weapon slots** (1–4, mouse wheel): service rifle, sidearm pistol, pump shotgun (pellets, shell-by-shell reload; command post) and a marksman rifle with a 4× scope (up the north-west tower). Each gun has its own ammo.
- **Increment 10:** **crafting**: K to craft by hand anywhere; a workbench (warehouse) and weapons bench (command post); 13 recipes for components, ammo, bandages and medkits; break down pallets and furniture for wood.
- **Increment 11:** **gun crafting and attachments**: you now start with only a **machete** (slot 5) and craft a **pipe pistol** by hand. Gun parts (barrel, receiver, stock, trigger group, magazine) are made at the weapons bench and assembled into the pistol, shotgun, service rifle and marksman rifle. **Attachments** (red dot, 4× scope, suppressor, extended magazine, foregrip) are fitted on the bench's **Modify Weapons** tab and show on the gun. Every gun has iron sights.
- **Increment 12:** **a second region, Halden's Crossing**: follow the road south out of Outpost 17 and hold E at the road sign. A ruined town with enterable shops, a two-storey hotel and a burned church, rooftop and water-tower sightlines, and a walled raider camp held by tougher **Raider Veterans**. 21 containers, scrap heaps and appliance piles for crafting materials in bulk. You carry your gear between regions, each region remembers what you looted, and saves include every region.

## Run it
1. Install Godot 4.7 (standard, not .NET).
2. Godot Project Manager → **Import** → choose this folder's `project.godot`.
3. Press **F5**.

Controls: WASD move · Mouse look · Left click fire · Right click / Q aim (toggle) · 1–5 / mouse wheel switch weapons (5 = machete) · R reload · E interact · Tab/I inventory · H use medkit · K craft · F5 quick save · F9 quick load · Hold E on a road sign to travel · Shift sprint · Space jump · C/Ctrl crouch · Esc free mouse · F3 debug.

## After pulling an update — important
Open the project with **Edit** (not **Run**) in Godot's Project Manager, then press F5 or the ▶ button in the editor.

**Why:** Godot keeps a cache of script class names in the hidden `.godot/` folder, and only the editor rebuilds it. If an update adds new scripts and you press **Run** in the Project Manager, the cache is stale: the new scripts fail to load, and the game sits frozen on its first frame with a red-tinted screen and placeholder HUD values. Opening the editor once fixes it.

## Tests
```
godot --headless --path . -s res://tests/test_runner.gd
```
(macOS: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s res://tests/test_runner.gd`)

## Docs
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): Milestone 1 technical architecture, authority model, collision layers, structure, roadmap.
- [`docs/increments/`](docs/increments/): one guide per increment: files, hierarchy, inputs, inspector settings, signals, testing, troubleshooting.
