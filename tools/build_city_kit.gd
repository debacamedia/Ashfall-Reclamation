extends SceneTree
## Increment 31: Quaternius's Downtown City MegaKit (CC0) made ready for
## Halden's Crossing. Each piece the town uses is saved as one mesh,
## assets/models/quaternius/city/built/<snake_name>.res, with:
##
## - the glass and the painted-on "rooms" behind the windows taken out, so
##   every window is an open, broken window you can see (and shoot) through;
## - the kit's materials shared between pieces (one per kit material, saved
##   in built/materials/) and weathered: dustier and a little darker, for a
##   town that's stood empty since the ash.
##
##   godot --headless --path . -s res://tools/build_city_kit.gd

const SRC := "res://assets/models/quaternius/city/"
const OUT := "res://assets/models/quaternius/city/built/"
const MATS := OUT + "materials/"
## The pieces Halden's is built from
const USED := [
	# Brick
	"Brick_Plain_3", "Brick_Plain_1", "Brick_BottomTrim", "Brick_TopTrim", "Brick_Window_Trim", "Brick_Window_Trim_Single",
	"Brick_Window_Square_Single", "Brick_Inset", "Brick_Inset_Window", "Brick_Inset_Window_Curved", "Brick_Window_CurvedDouble",
	"Brick_RedWhite_DoubleWindow",
	# Painted stone trim
	"Trim_Plain_3", "Trim_Window", "Trim_FirstFloor_Wall", "Trim_FirstFloor_Window_001", "Trim_Column_Center", "Trim_Wall_Guard",
	# Metal and concrete
	"Metal_Plain_3", "Metal_Plain_1", "Metal_Window_Half", "Metal_FullWindow", "Metal_FirstFloor_Window", "Metal_FirstFloor_Wall",
	"Metal_FirstFloor_Wall_1", "Metal_Column_Center",
	# Doors
	"DoorFrame_Trim", "DoorFrame_Metal_Single", "DoorFrame_Wooden", "Door_1", "Door_2",
	# Cornices
	"Cornice_Brick_Center", "Cornice_Metal_Center", "Cornice_Trim_Center",
	# Street
	"Sidewalk_Straight_3m", "Prop_ACUnit", "Prop_Bollard", "Prop_ManholeCover", "Prop_Drain", "Prop_Planter_Single",
]
## Taken out of every piece
const DROPPED := ["MI_Glass", "MI_FakeInterior"]
## Weathering: how much each kit colour fades toward a dusty grey-brown,
## and how much darker it gets
const DUST := Color(0.55, 0.5, 0.44)
const FADE := 0.18
const DARKEN := 0.93

var _mats := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(MATS)
	for n: String in USED:
		var out := _piece(n)
		var err := ResourceSaver.save(out, OUT + n.to_snake_case() + ".res")
		print("%s: %s %s, %d surfaces" % [n, error_string(err), out.get_aabb().size, out.get_surface_count()])
	quit()


## One piece: its meshes (with their node transforms) as one mesh, without
## the glass.
func _piece(n: String) -> ArrayMesh:
	var scene := (load(SRC + n + ".gltf") as PackedScene).instantiate() as Node3D
	var out := ArrayMesh.new()
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D()
		var p: Node = mi
		while p != scene and p != null:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var mname := src.resource_name if src != null else ""
			if mname in DROPPED:
				continue
			var arrays := mi.mesh.surface_get_arrays(s)
			# (One piece carries a custom data channel the game doesn't use)
			for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
				arrays[c] = null
			if xf != Transform3D.IDENTITY:
				arrays = _moved(arrays, xf)
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(out.get_surface_count() - 1, _material(src))
	scene.free()
	return out


func _moved(arrays: Array, xf: Transform3D) -> Array:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i] = xf * v[i]
	arrays[Mesh.ARRAY_VERTEX] = v
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var nb := xf.basis.inverse().transposed()
		var nn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in nn.size():
			nn[i] = (nb * nn[i]).normalized()
		arrays[Mesh.ARRAY_NORMAL] = nn
	return arrays


## The kit's material, weathered, one per kit material name (so the town's
## pieces share them and the batcher can merge them).
func _material(src: Material) -> Material:
	var name := src.resource_name if src != null else "MI_Default"
	if _mats.has(name):
		return _mats[name]
	var m: StandardMaterial3D
	if src is StandardMaterial3D:
		m = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		m = StandardMaterial3D.new()
	m.resource_name = name
	var c := m.albedo_color
	c = Color(lerpf(c.r, DUST.r, FADE), lerpf(c.g, DUST.g, FADE), lerpf(c.b, DUST.b, FADE)) * DARKEN
	m.albedo_color = Color(c.r, c.g, c.b, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	m.roughness = maxf(m.roughness, 0.85)
	var path := MATS + name.to_snake_case() + ".tres"
	var err := ResourceSaver.save(m, path)
	assert(err == OK, "save " + path)
	m = load(path) as StandardMaterial3D
	_mats[name] = m
	return m
