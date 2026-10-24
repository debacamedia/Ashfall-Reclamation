@tool
extends StaticBody3D
## Shipping container prop. Pick a paint colour per instance in the Inspector;
## it shows in the editor as well as in game.
##
## Scene: res://scenes/world/props/shipping_container.tscn

@export var paint := Color(0.33, 0.36, 0.25):
	set(value):
		paint = value
		_apply_paint()


func _ready() -> void:
	_apply_paint()


func _apply_paint() -> void:
	var body := get_node_or_null("Body") as MeshInstance3D
	if body == null:
		return
	var base := load("res://assets/materials/metal_painted.tres") as StandardMaterial3D
	var tinted := base.duplicate() as StandardMaterial3D
	tinted.albedo_color = paint
	body.material_override = tinted
