# Asset licences

A register of everything in the game that wasn't written for it from scratch: where it came from, its licence, and whether it can go in a game that's sold. **Add a row whenever a new pack or plugin comes in**, and keep the pack's own licence file next to its files in `assets/`.

The downloads themselves are kept in **Ashfall Assets** on the Desktop of the Mac the game is made on, with a README listing what's there.

## Can it go in a game that's sold?

| Licence | Selling the game | Credit needed | Notes |
|---|---|---|---|
| **CC0 1.0** (public domain) | Yes | No | Credit anyway, as thanks. Nothing to include |
| **MIT** | Yes | Yes | Its copyright notice and licence text go in the game (an About or Credits screen, or a file shipped with it) |
| **CC-BY** | Yes | Yes | Credit the author as they ask |
| CC-BY-NC, "personal use only", unknown | **No** | | Don't bring these in |

Only **CC0** and **MIT** (or another licence on the "yes" rows) come into the repo.

## The engine

| What | Licence | In the game | What's needed |
|---|---|---|---|
| **Godot Engine 4.7** (godotengine.org) | MIT, plus the MIT/BSD-style licences of the libraries built into it | Everything | **Before release:** put Godot's licence notice in the game's credits or a shipped file. The text is in the editor (Help → About → Licenses) and in Godot's `COPYRIGHT.txt` |

## In the game now

| Asset | Author / source | Licence | Checked | Where in the repo | Used for |
|---|---|---|---|---|---|
| Universal Animation Library (Standard) | Quaternius, quaternius.com | CC0 1.0 | 22 Nov 2026, licence file in the zip | `assets/characters/quaternius/animations/` with `LICENSE_animation_library.txt` | Every settler's and raider's animations (29) |
| Universal Base Characters (Standard) | Quaternius | CC0 1.0 | 22 Nov 2026, licence file in the zip | `assets/characters/quaternius/bodies/`, `hair/` with `LICENSE_base_characters.txt` | Settlers' and raiders' heads, bodies, hair (29) |
| Modular Character Outfits – Fantasy (Standard) | Quaternius | CC0 1.0 | 23 Nov 2026, licence file in the zip and the pack's itch.io page | `assets/characters/quaternius/outfits/` with `LICENSE_Modular_Character_Outfits_Fantasy.txt` | Everyone's clothes, and armour as clothes (29.1) |
| ASHFALL Resource Packs 1.0, 2.0, 3.0 | Made for this project (procedural materials, decals, signs, sounds), from the user | Project-owned | 25 Oct 2026, the packs' READMEs | `assets/ashfall_pack_v1/`, `v2/`, `v3/` | Outpost 17's and Halden's materials, signs, graffiti, decals, surface and town sounds |
| Everything else: models, levels, materials, synthesized sounds, icons, code | Made for this project | Project-owned | | | |

## Downloaded, not in the game yet

| Asset | Author / source | Licence | Checked | What's in it | Could be used for |
|---|---|---|---|---|---|
| Ultimate Gun Pack | Quaternius | CC0 1.0 | 23 Nov 2026, `License.txt` in the zip and quaternius.com | 41 low-poly guns (pistols, revolvers, shotguns, assault rifles, bullpups, SMGs, sniper rifles) and 15 attachments (scopes, silencers, grip, stock, bipod, tripod, flashlight, bayonets). FBX, OBJ, .blend; flat colours | The player's guns and attachments, guards' and raiders' guns in hand |
| Farm Buildings | Quaternius | CC0 1.0 | 23 Nov 2026: **no licence file in the zip**; quaternius.itch.io/lowpoly-farm-buildings says CC0 | 13 pieces: barns (small, big, open), silo, silo house, chicken coop, windmill, wind pump, water tower, well, two fences. FBX, OBJ, .blend; flat colours | Ash Creek Farms, pens, the coop |
| Downtown City MegaKit (Standard) | Quaternius | CC0 1.0 | 23 Nov 2026, `License_Standard.txt` in the zip and quaternius.com | About 150 modular city pieces: brick, metal and trim walls, windows, columns, cornices, doors, slate roofs, floors, stairs, streets, sidewalks, road decals, small props, 3 ready buildings. glTF for Godot, textured | Halden's Crossing, Dusthaven, Red Mesa: towns built from real pieces |

When one of these comes into the game, move its row up, add the licence file next to its files (for Farm Buildings, write one recording the itch.io page and the date checked), and say which increment.

## Things to watch

- **Real-looking guns:** the Ultimate Gun Pack's guns look like real designs (an AK, an M4, an AWP…) but carry no brand names. Keep it that way: no real model or maker names on items, in the code or in the store listing.
- **Logos and signs:** Downtown City's previews show shop signs, but the Standard version's file list has no sign pieces. Whatever signs the game gets, don't put a real company's name or logo on them.
- **Paid versions:** Quaternius's Source versions are also CC0, so buying one later changes nothing here. Record the purchase anyway.
- **Before release:** a Credits screen listing Godot's notice and thanking Quaternius and anyone else listed here.
