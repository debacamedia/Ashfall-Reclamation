extends SceneTree
## Builds the Food Shelves (Increment 19.5): scenes/world/containers/
## food_shelves.tscn. A 10 m run of wooden shelving, four bays of four
## shelves, that holds a settlement's food: 60 slots (1,200 vegetables).
## Crates of produce appear on the shelves as it fills (ShelfFill).
##
##   godot --headless --path . -s res://tools/build_food_shelves.gd

const OUT := "res://scenes/world/containers/food_shelves.tscn"
const SLOTS := 60
const BAYS := 4
const BAY_W := 2.5
const DEPTH := 0.6
const HEIGHT := 2.1
const LEVELS := [0.1, 0.62, 1.14, 1.66]  # top of each shelf board
const CRATE := Vector3(0.66, 0.3, 0.44)

var shelves: SalvageContainer


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var wood := load("res://assets/materials/wood.tres") as Material
	var dark := load("res://assets/materials/metal_dark.tres") as Material
	var length := BAYS * BAY_W
	shelves = SalvageContainer.new()
	shelves.name = "FoodShelves"
	shelves.collision_layer = 16
	shelves.collision_mask = 0
	shelves.monitoring = false
	shelves.container_name = "Food Shelves"
	shelves.search_time = 0.0
	shelves.set("focus_offset", Vector3(0, 1.0, 0.3))
	var area := CollisionShape3D.new()
	area.name = "Shape"
	var ash := BoxShape3D.new()
	ash.size = Vector3(length + 0.1, HEIGHT, DEPTH + 0.3)
	area.shape = ash
	area.position = Vector3(0, HEIGHT / 2.0, 0.1)
	_add(shelves, area)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 2
	body.collision_mask = 0
	_add(shelves, body)
	var bs := CollisionShape3D.new()
	bs.name = "BodyShape"
	var bsh := BoxShape3D.new()
	bsh.size = Vector3(length, HEIGHT, DEPTH)
	bs.shape = bsh
	bs.position = Vector3(0, HEIGHT / 2.0, 0)
	_add(body, bs)
	# Uprights at each bay edge, front and back
	for i in BAYS + 1:
		var x := -length / 2.0 + i * BAY_W
		x = clampf(x, -length / 2.0 + 0.03, length / 2.0 - 0.03)
		for z in [-DEPTH / 2.0 + 0.03, DEPTH / 2.0 - 0.03]:
			_box(body, "Upright%d%s" % [i, "B" if z < 0 else "F"], Vector3(0.06, HEIGHT, 0.06), Vector3(x, HEIGHT / 2.0, z), dark)
	# Boards, and a top
	for j in LEVELS.size():
		_box(body, "Shelf%d" % j, Vector3(length, 0.04, DEPTH), Vector3(0, LEVELS[j] - 0.02, 0), wood)
	_box(body, "Top", Vector3(length, 0.04, DEPTH), Vector3(0, HEIGHT - 0.02, 0), wood)
	_box(body, "Back", Vector3(length, HEIGHT - 0.1, 0.02), Vector3(0, HEIGHT / 2.0, -DEPTH / 2.0 + 0.01), wood)
	# A painted sign on the top
	var sign := Label3D.new()
	sign.name = "Sign"
	sign.text = "FOOD STORE"
	sign.font_size = 64
	sign.pixel_size = 0.004
	sign.outline_size = 0
	sign.modulate = Color(0.95, 0.9, 0.78)
	sign.position = Vector3(0, HEIGHT - 0.2, DEPTH / 2.0 + 0.01)
	_add(body, sign)
	# Crates of produce, in fill order: bottom shelf first, left to right
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _crate_mesh(wood)
	var xf: Array[Transform3D] = []
	for lv in LEVELS:
		for bay in BAYS:
			for c in 3:
				var x := -length / 2.0 + (bay + 0.5) * BAY_W + (c - 1) * 0.78
				xf.append(Transform3D(Basis(Vector3.UP, deg_to_rad(float((xf.size() * 37) % 13 - 6))), Vector3(x, lv, 0.02)))
	var colors := [Color(0.38, 0.6, 0.22), Color(0.85, 0.48, 0.16), Color(0.7, 0.2, 0.15), Color(0.55, 0.65, 0.25), Color(0.62, 0.42, 0.3)]
	var cols := PackedColorArray()
	for i in xf.size():
		cols.append(colors[(i * 7) % colors.size()])
	var fill := ShelfFill.new()
	fill.name = "Fill"
	fill.multimesh = mm  # filled from spots/colors when it loads
	fill.spots = xf
	fill.colors = cols
	fill.container_path = NodePath("..")
	_add(shelves, fill)
	var inv := InventoryComponent.new()
	inv.name = "Inventory"
	inv.slot_count = SLOTS
	inv.max_weight = 0.0
	_add(shelves, inv)
	inv.unique_name_in_owner = true
	for spec in [["OpenSound", "res://assets/ashfall_pack_v3/audio/crate_open.wav"], ["CloseSound", "res://assets/ashfall_pack_v3/audio/crate_close.wav"]]:
		var a := AudioStreamPlayer3D.new()
		a.name = spec[0]
		a.stream = load(spec[1])
		a.unit_size = 5.0
		a.bus = &"SFX"
		a.position.y = 1.0
		_add(shelves, a)
		a.unique_name_in_owner = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var packed := PackedScene.new()
	var err := packed.pack(shelves)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("wrote ", OUT, " (", error_string(err), ")")
	shelves.free()
	quit()


## A wooden crate with produce heaped in it: two surfaces (the produce takes
## the instance colour).
func _crate_mesh(wood: Material) -> ArrayMesh:
	var am := ArrayMesh.new()
	_add_box(am, Vector3(CRATE.x, CRATE.y, CRATE.z), Vector3(0, CRATE.y / 2.0, 0), wood)
	var produce := StandardMaterial3D.new()
	produce.vertex_color_use_as_albedo = true
	produce.roughness = 0.8
	_add_box(am, Vector3(CRATE.x - 0.08, 0.1, CRATE.z - 0.08), Vector3(0, CRATE.y + 0.02, 0), produce)
	return am


func _add_box(am: ArrayMesh, size: Vector3, offset: Vector3, mat: Material) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var arrays := bm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] += offset
	arrays[Mesh.ARRAY_VERTEX] = verts
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(am.get_surface_count() - 1, mat)


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = shelves


func _box(parent: Node, name: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	_add(parent, mi)
