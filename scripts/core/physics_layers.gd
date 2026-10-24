class_name PhysicsLayers
extends RefCounted
## Collision layer bit values. These match the names set in
## Project Settings > Layer Names > 3D Physics. Use these constants instead
## of magic numbers, e.g. `collision_mask = PhysicsLayers.TERRAIN | PhysicsLayers.STRUCTURES`.

const TERRAIN := 1        ## Layer 1: ground, berms
const STRUCTURES := 2     ## Layer 2: walls, buildings, props, vehicles
const PLAYER := 4         ## Layer 3: player bodies
const NPCS := 8           ## Layer 4: enemies, settlers, soldiers
const INTERACTABLES := 16 ## Layer 5: containers, pickups, doors
const PROJECTILES := 32   ## Layer 6: physical projectiles
const TRIGGERS := 64      ## Layer 7: Area3D zones

## What a player body collides with.
const PLAYER_MASK := TERRAIN | STRUCTURES | NPCS
## Solid world geometry: used for head-clearance and line-of-sight checks.
const WORLD_SOLID := TERRAIN | STRUCTURES
