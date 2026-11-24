extends "res://tests/test_case.gd"
## Increment 31: farm buildings in the style of the Farm Buildings pack: red
## board-and-batten barns with white trim, sliding X-braced doors and
## hayloft doors; white lap-sided farmhouses with shutters and a porch;
## shingled roofs. Only what you see changes: walls, doorways, windows and
## roofs are as solid (and as open) as before.

const FARM := "res://levels/ash_creek_farms/ash_creek_farms.tscn"
const PAINT := "res://assets/materials/farm/"


func _trim_triangles(b: Node3D) -> PackedVector3Array:
	var mi := b.get_node("FarmTrim") as MeshInstance3D
	var out := PackedVector3Array()
	for s in mi.mesh.get_surface_count():
		var a := mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for i in idx:
			out.append(mi.transform * v[i])
	return out


## Building space rays in through a doorway, at a few heights: does any of
## the trim cover it?
func _door_clear(b: Node3D, tris: PackedVector3Array) -> bool:
	for d: Array in b.get_meta("doors", []):
		# (Doors are listed in the site's space)
		var centre := b.transform.affine_inverse() * (d[0] as Vector3)
		var out := (b.basis.inverse() * (d[1] as Vector3)).normalized()
		var across := out.cross(Vector3.UP).normalized()
		for y: float in [0.4, 1.2, 2.0]:
			for x: float in [-0.5, 0.0, 0.5]:
				var from := centre + out * 1.0 + across * x + Vector3.UP * y
				for t in range(0, tris.size(), 3):
					if Geometry3D.ray_intersects_triangle(from, -out, tris[t], tris[t + 1], tris[t + 2]) != null:
						var hit: Vector3 = Geometry3D.ray_intersects_triangle(from, -out, tris[t], tris[t + 1], tris[t + 2])
						if hit.distance_to(from) < 1.4:
							return false
	return true


func _check_styled(b: Node3D, label: String, wall_paint: String, pitched: bool) -> void:
	var trim := b.get_node_or_null("FarmTrim") as MeshInstance3D
	check(trim != null and trim.mesh != null and trim.mesh.get_surface_count() >= 2, "%s: painted and trimmed" % label)
	if trim == null:
		return
	check(trim.find_children("*", "CollisionObject3D").is_empty() and not trim.get_children().any(func(c: Node) -> bool: return c is CollisionShape3D),
		"%s: the trim adds nothing solid" % label)
	var walls := b.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D and c.name.begins_with("Wall"))
	check(not walls.is_empty() and walls.all(func(w: MeshInstance3D) -> bool: return w.material_override.resource_path == PAINT + wall_paint + ".tres"),
		"%s: walls in %s" % [label, wall_paint])
	if pitched:
		check((b.get_node("Roof") as MeshInstance3D).material_override.resource_path == PAINT + "farm_shingle.tres", "%s: a shingled roof" % label)
	check(_door_clear(b, _trim_triangles(b)), "%s: nothing over its doorways" % label)


func test_ash_creek() -> void:
	var farm := (load(FARM) as PackedScene).instantiate() as Node3D
	var buildings := farm.get_node("Buildings")
	_check_styled(buildings.get_node("Barn"), "the barn", "farm_red", true)
	_check_styled(buildings.get_node("Farmhouse"), "the farmhouse", "farm_siding", true)
	_check_styled(buildings.get_node("ChickenCoop"), "the chicken coop", "farm_red", false)
	# The barn's sliding doors stand either side of its big doorway, and a
	# hayloft door's up in the gable
	var barn := buildings.get_node("Barn") as Node3D
	var trim_box := (barn.get_node("FarmTrim") as MeshInstance3D).get_aabb()
	var roof := barn.get_node("Roof") as MeshInstance3D
	check(trim_box.end.y > roof.position.y, "the barn's trim reaches up the gables")
	# The farmhouse's porch: a roof on posts, clear of the door
	var house := buildings.get_node("Farmhouse") as Node3D
	check(house.has_node("PorchRoof") and house.find_children("PorchPost*", "MeshInstance3D", false, false).size() == 3, "the farmhouse's porch roof and posts")
	for post: MeshInstance3D in house.find_children("PorchPost*", "MeshInstance3D", false, false):
		check(absf(post.position.x - (-2.0)) > 1.5, "a porch post clear of the door (x %.1f)" % post.position.x)
	farm.free()


func test_settlement_buildings() -> void:
	for spec in [["bunkhouse", "farm_red"], ["storehouse", "farm_red"], ["kitchen", "farm_siding"]]:
		var s := (load("res://scenes/settlement/%s.tscn" % spec[0]) as PackedScene).instantiate() as Node3D
		var body := s.find_child("Body", true, false) as Node3D
		_check_styled(body, spec[0], spec[1], true)
		check((body.get_node("FarmTrim") as MeshInstance3D).mesh.resource_path.begins_with("res://scenes/settlement/trim/"), "%s: its trim saved with the settlement's scenes" % spec[0])
		s.free()
