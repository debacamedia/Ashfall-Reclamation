class_name CraftingStation
extends Interactable
## A bench you use to craft (E to open). Opens the crafting screen with this
## station's recipes plus everything you can make by hand. You have to stay
## near it while it works.
##
## Scenes: res://scenes/world/stations/workbench.tscn, weapons_bench.tscn
## Root (this Area3D, layer 5) → Shape, Body (StaticBody3D, layer 2, meshes).

@export var station: RecipeDefinition.Station = RecipeDefinition.Station.WORKBENCH

@onready var _body: CollisionObject3D = get_node_or_null("Body")


func _ready() -> void:
	add_to_group("crafting_stations")
	action_name = "Use"
	object_name = RecipeDefinition.station_name(station)


func get_block_reason(interactor: Node3D) -> String:
	return "" if interactor is PlayerController else "Can't use that"


func _perform(interactor: Node3D) -> void:
	var player := interactor as PlayerController
	if player != null:
		player.open_station(self)


func _get_line_of_sight_exclusions() -> Array[RID]:
	var out: Array[RID] = []
	if _body != null:
		out.append(_body.get_rid())
	return out
