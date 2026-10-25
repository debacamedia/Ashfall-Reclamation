class_name StructureDefinition
extends Resource
## Something you can build: a barricade, wall, gate, trap, storage crate or
## bench. You craft its kit (an item whose `structure` points here) with a
## normal recipe, then place it in build mode (B).
##
## Saved as .tres in resources/structures/.

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


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item: ItemDefinition in cost:
		parts.append("%s ×%d" % [item.display_name, cost[item]])
	return ", ".join(parts)
