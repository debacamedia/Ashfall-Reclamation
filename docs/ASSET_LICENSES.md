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
| Ultimate Gun Pack | Quaternius | CC0 1.0 | 23 Nov 2026, `License.txt` in the zip and quaternius.com | `assets/models/quaternius/guns/` with `LICENSE_Ultimate_Gun_Pack.txt` | The Service Rifle, Sidearm Pistol, Pump Shotgun and Marksman Rifle, the 4× scope, suppressor and foregrip; settlers' rifles (30) |
| Farm Buildings | Quaternius | CC0 1.0 | 23 Nov 2026: no licence file in the zip; quaternius.itch.io/lowpoly-farm-buildings says CC0 | `assets/models/quaternius/farm/` with `LICENSE_Farm_Buildings.txt` (a note recording the page and the date) | Ash Creek's silo and wind pump, the chicken pen's hen house (30). Its barns' look (red board and batten, white trim, X-braced doors) copied onto Ash Creek's barn, farmhouse and coop and the settlers' bunkhouse, kitchen and storehouse (31); that's our own geometry, no pack files |
| Downtown City MegaKit (Standard) | Quaternius | CC0 1.0 | 23 Nov 2026, `License_Standard.txt` in the zip and quaternius.com | `assets/models/quaternius/city/` with `LICENSE_Downtown_City_MegaKit.txt`; made-ready pieces in `city/built/` | Halden's Crossing's twelve buildings: walls, windows, shopfronts, doorways, corner columns, cornices; manhole covers, drains, air conditioners and planters (31) |
| Everything else: models, levels, materials, synthesized sounds, icons, code | Made for this project | Project-owned | | | |

## Downloaded, not in the game yet

| Asset | Author / source | Licence | Checked | What's in it | Could be used for |
|---|---|---|---|---|---|
| (none right now) | | | | | |

When one of these comes into the game, move its row up, add the licence file next to its files (or, where a zip has none, a note recording the page that gives the licence and the date checked), and say which increment.

## Things to watch

- **Real-looking guns:** the Ultimate Gun Pack's guns look like real designs (an AK, an M4, an AWP…) but carry no brand names. Keep it that way: no real model or maker names on items, in the code or in the store listing.
- **Logos and signs:** Downtown City's previews show shop signs, but the Standard version's file list has no sign pieces. Halden's signs are the project's own (Resource Pack 3). Whatever signs the game gets, don't put a real company's name or logo on them.
- **More of the city kit:** Halden's uses about 40 of its 150 pieces. The rest (slate roofs, stairs, streets and sidewalks with curbs, road markings, the 3 ready buildings) are there for Dusthaven and Red Mesa.
- **Paid versions:** Quaternius's Source versions are also CC0, so buying one later changes nothing here. Record the purchase anyway.
- **Before release:** a Credits screen listing Godot's notice and thanking Quaternius and anyone else listed here.
