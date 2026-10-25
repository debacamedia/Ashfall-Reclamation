class_name BenchStructure
extends Structure
## A workbench you build: works exactly like Outpost 17's (E to use), so you
## can craft components, ammo and medkits wherever you set up.
##
## Scene: res://scenes/structures/field_workbench.tscn. Root → %Bench (an
## instance of scenes/world/stations/workbench.tscn).

@onready var bench: CraftingStation = %Bench


func move_block_reason() -> String:
	return dismantle_block_reason()


func dismantle_block_reason() -> String:
	for p in get_tree().get_nodes_in_group("players"):
		if (p as PlayerController).current_station == bench:
			return "Someone's using it"
	return ""
