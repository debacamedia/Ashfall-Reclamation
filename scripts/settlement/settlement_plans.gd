class_name SettlementPlans
extends RefCounted
## What settlers can build at a settlement (Increment 19.6), and what each
## costs. A plan becomes a ConstructionSite: you (or the settlement's
## stores) supply the materials, Builders put in the hours, and it turns into
## SettlementBuildings.
##
## Some plans you place yourself in build mode (B) inside a settlement you
## hold: the bunkhouse, storehouse, guard tower, guard post and farm plot.
## Fences come with the settlement's own plan (laid out when you claim it),
## as runs of 4 m lengths.
##
## A settlement hour is a minute of play: one Builder puts in an hour's work
## a minute.

const DIR := "res://resources/structures/settlement/"

## id -> name, structure, cost (per piece for fences), hours (per piece for
## fences), placeable, about
const PLANS := {
	&"bunkhouse": {"name": "Bunkhouse", "structure": "bunkhouse", "placeable": true, "hours": 6.0,
		"cost": {&"wood_plank": 30, &"scrap_metal": 10, &"cloth": 6}, "about": "Four more beds"},
	&"storehouse": {"name": "Storehouse", "structure": "storehouse", "placeable": true, "hours": 5.0,
		"cost": {&"wood_plank": 20, &"scrap_metal": 12, &"metal_pipe": 2}, "about": "Shelves for 60 more stacks: food or anything else"},
	&"guard_tower": {"name": "Guard Tower", "structure": "guard_tower", "placeable": true, "hours": 4.0,
		"cost": {&"wood_plank": 16, &"scrap_metal": 6, &"metal_pipe": 2}, "about": "A raised lookout for a guard, up a stair"},
	&"guard_post": {"name": "Guard Post", "structure": "guard_post", "placeable": true, "hours": 2.0,
		"cost": {&"wood_plank": 6, &"cloth": 4, &"scrap_metal": 2}, "about": "A sandbagged spot for a guard"},
	&"farm_plot": {"name": "Farm Plot", "structure": "farm_plot", "placeable": true, "hours": 2.0,
		"cost": {&"wood_plank": 4, &"scrap_metal": 2, &"vegetables": 10}, "about": "A new field: work for two more farmers"},
	&"fence": {"name": "Fence", "structure": "farm_fence", "placeable": false, "hours": 0.25,
		"cost": {&"wood_plank": 1}, "about": "Split-rail fence, in 4 m lengths"},
}
## Fences also need a Scrap Metal (nails and wire) for every four lengths.
const FENCE_SCRAP_EVERY := 4


static func has(id: StringName) -> bool:
	return PLANS.has(id)


static func display_name(id: StringName) -> String:
	return str(PLANS[id]["name"]) if PLANS.has(id) else "Building"


static func about(id: StringName) -> String:
	return str(PLANS[id]["about"]) if PLANS.has(id) else ""


static func structure(id: StringName) -> StructureDefinition:
	if not PLANS.has(id):
		return null
	return load(DIR + str(PLANS[id]["structure"]) + ".tres") as StructureDefinition


## The plans you can place yourself, in menu order.
static func placeable() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in PLANS:
		if PLANS[id]["placeable"]:
			out.append(id)
	return out


## Materials for `pieces` of plan `id`: {item id: count}.
static func cost(id: StringName, pieces := 1) -> Dictionary:
	var out := {}
	if not PLANS.has(id):
		return out
	var per: Dictionary = PLANS[id]["cost"]
	var n := pieces if id == &"fence" else 1
	for item: StringName in per:
		out[item] = int(per[item]) * n
	if id == &"fence":
		out[&"scrap_metal"] = ceili(float(pieces) / FENCE_SCRAP_EVERY)
	return out


## Hours of a Builder's work for `pieces` of plan `id`.
static func hours(id: StringName, pieces := 1) -> float:
	if not PLANS.has(id):
		return 1.0
	return float(PLANS[id]["hours"]) * (pieces if id == &"fence" else 1)


## "Wood Plank ×30, Scrap Metal ×10" for a cost dictionary of item ids.
static func cost_text(c: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id: StringName in c:
		var item := ItemDatabase.get_item(id)
		parts.append("%s ×%d" % [item.display_name if item != null else str(id), c[id]])
	return ", ".join(parts)
