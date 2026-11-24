# Increment 30.1: no more getting stuck in a building as it goes up

**Status:** complete. The suites that build sites or drop your gear all pass (gear and guns, kitchens and animals, settlement building, fortifying), and so do 3 new tests in `tests/test_build_clearance.gd`. The full run comes with Increment 31.

## The bug you found

If you stood inside a chicken coop as it finished being built, you were caught in its solid parts (the hen house, the fence). You couldn't move, and you could sink through the ground and die. When you died there, your **Your Gear** chest went where you died: under the world, out of reach.

It wasn't just coops. Any building settlers put up (a bunkhouse, a guard tower, a palisade length…) could catch you, a settler or a raider standing where it went up. Your own builds were already safe: build mode won't place a kit on top of anyone.

## Now

- **Out of the way as it goes up.** When a piece of a settlement building is finished, anyone caught in its solid parts (you, settlers, raiders, animals) is moved just outside its footprint, to the nearest side, 0.8 m clear, standing on the ground. If you're in the middle of a pen and not touching any of it, you're left where you are: you can walk out by the gate.
- **Your gear never falls out of the world.** The game remembers the last place you stood on solid ground. If you die below the world, or where there's no ground under you, your gear chest goes there instead, on the ground and reachable.

## How it's built

- `ConstructionSite.clear_space(structure)`: checks each of the new piece's collision shapes against players and NPCs, then moves anyone caught to the nearest side of its footprint and down onto the ground. It's called as each piece is built.
- `PlayerController.last_safe_position`: updated whenever you're on the floor (not on a ladder).
- `DeathCache.drop_for()` uses that place when you died out of the world, or with no ground beneath you.

## Tests (`tests/test_build_clearance.gd`)

1. **Standing in a coop as it goes up:** you stand where the hen house is built and finish it. You're no longer inside any of its solid parts, and you walk off, alive and above ground. (Without the fix, this test fails with you inside the hen house.)
2. **A settler in the way:** a guard post going up on a settler moves them out of its way.
3. **Gear never falls out of the world:** where you last stood is remembered; you fall out of the world and die, and your gear is where you last stood, not under it.
