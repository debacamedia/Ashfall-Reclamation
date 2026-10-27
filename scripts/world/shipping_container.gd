@tool
extends StaticBody3D
## Shipping container prop. Pick a paint colour per instance in the Inspector;
## it shows in the editor as well as in game.
##
## The paint uses whichever of Resource Pack 3's weathered container
## textures (red, blue, olive) is closest in colour, tinted so the container
## keeps exactly the colour picked here. Untick `weathered_paint` for the old
## flat paint.
##
## Scene: res://scenes/world/props/shipping_container.tscn

## Pack 3 texture and its average colour.
const PAINTS := [
	["res://assets/ashfall_pack_v3/materials/container_paint_red.tres", Color(0.583, 0.249, 0.211)],
	["res://assets/ashfall_pack_v3/materials/container_paint_blue.tres", Color(0.296, 0.437, 0.551)],
	["res://assets/ashfall_pack_v3/materials/container_paint_olive.tres", Color(0.396, 0.445, 0.319)],
]

@export var paint := Color(0.33, 0.36, 0.25):
	set(value):
		paint = value
		_apply_paint()
@export var weathered_paint := true:
	set(value):
		weathered_paint = value
		_apply_paint()


func _ready() -> void:
	_apply_paint()


func _apply_paint() -> void:
	var body := get_node_or_null("Body") as MeshInstance3D
	if body == null:
		return
	if weathered_paint:
		var best: Array = PAINTS[0]
		for p: Array in PAINTS:
			if _chroma_distance(paint, p[1]) < _chroma_distance(paint, best[1]):
				best = p
		var base := load(best[0]) as StandardMaterial3D
		if base != null:
			var weathered := base.duplicate() as StandardMaterial3D
			var avg: Color = best[1]
			weathered.albedo_color = Color(paint.r / avg.r, paint.g / avg.g, paint.b / avg.b)
			body.material_override = weathered
			return
	var plain := (load("res://assets/materials/metal_painted.tres") as StandardMaterial3D).duplicate() as StandardMaterial3D
	plain.albedo_color = paint
	body.material_override = plain


## How different two colours' hues are (brightness ignored).
static func _chroma_distance(a: Color, b: Color) -> float:
	var sa := a.r + a.g + a.b
	var sb := b.r + b.g + b.b
	return Vector3(a.r / sa - b.r / sb, a.g / sa - b.g / sb, a.b / sa - b.b / sb).length()
