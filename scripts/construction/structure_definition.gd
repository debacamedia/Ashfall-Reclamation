class_name StructureDefinition
extends Resource
## Something you can build: a barricade, wall, gate, trap, storage crate,
## bench, platform, stairs or ladder. You craft its kit (an item whose
## `structure` points here) with a normal recipe, then place it in build
## mode (B). Also used for the level's own props that you can move or scrap
## (`is_level_prop`, no kit).
##
## Saved as .tres in resources/structures/ (props in resources/structures/props/).

## How the ghost snaps to what's already built:
##   NONE   free placement
##   EDGE   wall-like: its ends (±X) hinge onto other EDGE ends at any
##          angle, and it lines up along platform edges
##   TILE   platforms: edge to edge with other platforms, or on top of one
##   ATTACH stairs and ladders: against a platform edge, facing out
enum Snap { NONE, EDGE, TILE, ATTACH }

@export var id: StringName = &"structure"
@export var display_name := "Structure"
## The scene placed in the world. Its root has structure.gd (or a subclass).
@export_file("*.tscn") var scene_path := ""
@export var max_health := 300.0
## Placement box (m): width (X), height (Y), depth (Z), standing on the
## ground at the origin. Nothing may overlap it.
@export var footprint := Vector3(2.4, 1.0, 0.6)
## Most structures are obstacles raiders walk around (the navmesh is rebaked
## when one is placed or destroyed); traps aren't.
@export var blocks_navigation := true
## Can raiders hit it when it's in their way?
@export var breakable := true
## Items needed to repair it to full health.
@export var repair_cost: Dictionary[ItemDefinition, int] = {}
## Items you get back when you dismantle it.
@export var dismantle_return: Dictionary[ItemDefinition, int] = {}

@export_group("Building")
@export var snap: Snap = Snap.NONE
## Its top is a floor you can build on (platforms). Walls, platforms and the
## rest can stand on it; it can't be removed while something does.
@export var supports_building := false
## Other choices when placing this kit (V): e.g. the wall with a window, the
## doorway. Set on the kit's main definition; it comes first itself.
@export var variants: Array[StructureDefinition] = []
## Short name shown for this variant ("Window").
@export var variant_name := ""

@export_group("Level props")
## One of the level's own props (barrels, fences, trucks), not built by you.
@export var is_level_prop := false
## Can it be picked up and moved (F)? Trucks can only be scrapped.
@export var movable := true


## The variant list for a kit: this one, then `variants`.
func get_variants() -> Array[StructureDefinition]:
	var out: Array[StructureDefinition] = [self]
	out.append_array(variants)
	return out


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item: ItemDefinition in cost:
		parts.append("%s ×%d" % [item.display_name, cost[item]])
	return ", ".join(parts)
