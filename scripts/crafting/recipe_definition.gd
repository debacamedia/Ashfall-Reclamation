class_name RecipeDefinition
extends Resource
## One thing you can make: what goes in, what comes out, how long it takes
## and where it has to be made. Saved as .tres in resources/recipes/.
##
## The same recipes will drive gun crafting (Increment 11) and construction
## (later): the output becomes a weapon, an attachment or a placeable
## structure, but the inputs, station and time work the same way.

enum Station { HAND, WORKBENCH, WEAPONS_BENCH }
enum Category { MATERIALS, COMPONENTS, AMMO, MEDICAL, WEAPONS, ATTACHMENTS, STRUCTURES }

@export var id: StringName = &"recipe"
## Shown in the recipe list; empty = the output's name.
@export var display_name := ""
@export var category: Category = Category.MATERIALS
## Where it can be made. HAND recipes can also be made at any bench.
@export var station: Station = Station.HAND
## Items consumed: {ItemDefinition: quantity}.
@export var inputs: Dictionary[ItemDefinition, int] = {}
@export var output: ItemDefinition
@export_range(1, 999) var output_quantity := 1
## Seconds per craft.
@export var craft_time := 2.0


func get_display_name() -> String:
	if display_name != "":
		return display_name
	return output.display_name if output != null else String(id)


## True if this recipe can be made with `at` (HAND = no bench nearby).
func can_make_at(at: Station) -> bool:
	return station == Station.HAND or station == at


static func station_name(s: Station) -> String:
	match s:
		Station.WORKBENCH:
			return "Workbench"
		Station.WEAPONS_BENCH:
			return "Weapons Bench"
	return "Hand"


static func category_name(c: Category) -> String:
	return Category.keys()[c].capitalize()
