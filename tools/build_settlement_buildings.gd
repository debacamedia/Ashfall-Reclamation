extends SceneTree
## Builds what settlers can build (Increment 19.6): the scenes in
## scenes/settlement/ and their StructureDefinitions in
## resources/structures/settlement/. See SettlementPlans for costs and hours.
##
##   farm_fence    a 4 m length of split-rail fence
##   guard_post    a sandbagged spot for a guard, with a tin roof
##   guard_tower   a lookout 2.6 m up, with a stair, a rail and a roof
##   bunkhouse     8 × 6 m, two bunk beds (four beds)
##   storehouse    12 × 6 m tin shed with a run of shelves (60 slots)
##   farm_plot     a 12 × 10 m field with crops, for two farmers
##
##   godot --headless --path . -s res://tools/build_settlement_buildings.gd

const Kit := preload("res://tools/site_kit.gd")
const SCENES := "res://scenes/settlement/"
const DEFS := "res://resources/structures/settlement/"

var top: Node3D
var M := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	M["wood"] = load("res://assets/ashfall_pack_v1/materials/wood_weathered.tres")
	M["wood_plain"] = load("res://assets/materials/wood.tres")
	M["sandbag"] = load("res://assets/materials/sandbag.tres")
	M["tin"] = load("res://assets/materials/corrugated_metal.tres")
	M["rust"] = load("res://assets/materials/rust.tres")
	M["soil"] = load("res://levels/early_zone/materials/field_soil.tres")
	M["crop"] = load("res://levels/early_zone/materials/crop_green.tres")
	M["cloth"] = load("res://assets/materials/raider_cloth.tres")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENES))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEFS))
	_fence()
	_guard_post()
	_guard_tower()
	_bunkhouse()
	_storehouse()
	_farm_plot()
	quit()


# ---------------------------------------------------------------- the things

func _fence() -> void:
	var b := _begin("FarmFence", "farm_fence", "Farm Fence", Vector3(4.0, 1.35, 0.3), 250.0,
		{&"wood_plank": 1}, {&"wood_plank": 1})
	var body := _body(b)
	for x in [-1.93, 1.93]:
		_box(body, "Post" + ("L" if x < 0 else "R"), Vector3(0.14, 1.35, 0.14), Vector3(x, 0.675, 0), M["wood"], true)
	_box(body, "RailLow", Vector3(4.0, 0.1, 0.06), Vector3(0, 0.55, 0.05), M["wood"], false)
	_box(body, "RailHigh", Vector3(4.0, 0.1, 0.06), Vector3(0, 1.05, 0.05), M["wood"], false)
	_shape(body, "Panel", Vector3(4.0, 1.2, 0.16), Vector3(0, 0.6, 0.03))
	_finish(b, "farm_fence")


func _guard_post() -> void:
	var b := _begin("GuardPost", "guard_post", "Guard Post", Vector3(3.2, 2.7, 3.2), 600.0,
		{&"cloth": 2, &"wood_plank": 1}, {&"wood_plank": 3, &"cloth": 2})
	var body := _body(b)
	# Sandbags in front and down both sides; open at the back
	_box(body, "BagsFront", Vector3(3.0, 1.0, 0.5), Vector3(0, 0.5, -1.25), M["sandbag"], true)
	_box(body, "BagsLeft", Vector3(0.5, 1.0, 1.6), Vector3(-1.25, 0.5, -0.2), M["sandbag"], true)
	_box(body, "BagsRight", Vector3(0.5, 1.0, 1.6), Vector3(1.25, 0.5, -0.2), M["sandbag"], true)
	for c in [Vector2(-1.4, -1.4), Vector2(1.4, -1.4), Vector2(-1.4, 1.4), Vector2(1.4, 1.4)]:
		_box(body, "Pole", Vector3(0.1, 2.5, 0.1), Vector3(c.x, 1.25, c.y), M["wood"], true)
	_box(body, "Roof", Vector3(3.3, 0.06, 3.3), Vector3(0, 2.53, 0), M["tin"], true)
	_markers(b, "GuardSpots", [Vector3(0, 0, -0.3)])
	_finish(b, "guard_post")


func _guard_tower() -> void:
	# Deck at the back half of the footprint, the stair coming down at the front
	var h := 2.6
	var deck_z := -1.7
	var b := _begin("GuardTower", "guard_tower", "Guard Tower", Vector3(3.2, 5.0, 6.6), 900.0,
		{&"wood_plank": 3, &"scrap_metal": 1}, {&"wood_plank": 6, &"scrap_metal": 2})
	var body := _body(b)
	for c in [Vector2(-1.4, deck_z - 1.4), Vector2(1.4, deck_z - 1.4), Vector2(-1.4, deck_z + 1.4), Vector2(1.4, deck_z + 1.4)]:
		_box(body, "Leg", Vector3(0.22, h, 0.22), Vector3(c.x, h / 2.0, c.y), M["wood"], true)
		_box(body, "Post", Vector3(0.12, 2.2, 0.12), Vector3(c.x, h + 1.1, c.y), M["wood"], true)
	_box(body, "Deck", Vector3(3.0, 0.15, 3.0), Vector3(0, h - 0.075, deck_z), M["wood_plain"], true)
	# Rails round the deck, open where the stair arrives (front right)
	_box(body, "RailBack", Vector3(3.0, 1.0, 0.08), Vector3(0, h + 0.5, deck_z - 1.46), M["wood"], true)
	_box(body, "RailLeft", Vector3(0.08, 1.0, 3.0), Vector3(-1.46, h + 0.5, deck_z), M["wood"], true)
	_box(body, "RailRight", Vector3(0.08, 1.0, 3.0), Vector3(1.46, h + 0.5, deck_z), M["wood"], true)
	_box(body, "RailFront", Vector3(1.6, 1.0, 0.08), Vector3(-0.7, h + 0.5, deck_z + 1.46), M["wood"], true)
	_box(body, "Roof", Vector3(3.4, 0.08, 3.4), Vector3(0, h + 2.24, deck_z), M["tin"], true)
	# The stair: like the wooden stairs you build (2.6 m up over 3.4 m)
	var run := 3.4
	var length := sqrt(h * h + run * run)
	var angle := atan2(h, run)
	var stair := Transform3D(Basis(Vector3.RIGHT, angle), Vector3(0.8, h / 2.0, deck_z + 1.5 + run / 2.0))
	var ramp := CollisionShape3D.new()
	ramp.name = "Ramp"
	var rb := BoxShape3D.new()
	rb.size = Vector3(1.2, 0.12, length)
	ramp.shape = rb
	ramp.transform = stair
	_add(body, ramp)
	for i in 12:
		var t := (i + 0.5) / 12.0
		_box(body, "Step%d" % i, Vector3(1.2, 0.06, 0.3), Vector3(0.8, h * (1.0 - t) + 0.03, deck_z + 1.5 + run * t), M["wood_plain"], false)
	for x in [0.2, 1.4]:
		var side := MeshInstance3D.new()
		side.name = "Stringer"
		var sm := BoxMesh.new()
		sm.size = Vector3(0.08, 0.25, length)
		side.mesh = sm
		side.material_override = M["wood"]
		side.transform = Transform3D(Basis(Vector3.RIGHT, angle), Vector3(x, h / 2.0, deck_z + 1.5 + run / 2.0))
		_add(body, side)
	_markers(b, "GuardSpots", [Vector3(-0.3, h, deck_z - 0.3)])
	_finish(b, "guard_tower")


func _bunkhouse() -> void:
	var b := _begin("Bunkhouse", "bunkhouse", "Bunkhouse", Vector3(8.2, 4.6, 6.2), 1500.0,
		{&"wood_plank": 4, &"scrap_metal": 1}, {&"wood_plank": 10, &"scrap_metal": 3})
	b.set("beds", 4)
	var house := _kit_building(b, Vector2(8, 6), {
		"wall": "wood", "floor": "wood", "roof": "pitched",
		"openings": [["S", 0, "door"], ["E", 0, "window"], ["W", 0, "window"], ["N", -2, "window"], ["N", 2, "window"]],
	})
	# Two bunk beds against the back wall, a table and a chest of drawers
	for x in [-2.4, 2.4]:
		for y in [0.0, 1.1]:
			_box(house, "Bunk", Vector3(1.0, 0.25, 2.0), Vector3(x, 0.35 + y, -1.6), M["wood_plain"], true)
			_box(house, "Mattress", Vector3(0.9, 0.12, 1.9), Vector3(x, 0.53 + y, -1.6), M["cloth"], false)
		for c in [Vector2(-0.45, -2.55), Vector2(0.45, -2.55), Vector2(-0.45, -0.65), Vector2(0.45, -0.65)]:
			_box(house, "BunkPost", Vector3(0.08, 1.9, 0.08), Vector3(x + c.x, 0.95, c.y), M["wood"], true)
	_box(house, "Table", Vector3(1.4, 0.75, 0.8), Vector3(0, 0.375, -0.6), M["wood_plain"], true)
	_finish(b, "bunkhouse")


func _storehouse() -> void:
	var b := _begin("Storehouse", "storehouse", "Storehouse", Vector3(12.2, 4.2, 6.2), 1500.0,
		{&"wood_plank": 3, &"scrap_metal": 2}, {&"wood_plank": 8, &"scrap_metal": 5})
	var shed := _kit_building(b, Vector2(12, 6), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "pitched", "height": 3.6,
		"openings": [["S", 0, "wide"], ["E", 0, "window"], ["W", 0, "window"]],
	})
	var shelves := (load("res://scenes/world/containers/food_shelves.tscn") as PackedScene).instantiate() as SalvageContainer
	shelves.name = "Storage"
	shelves.container_name = "Storehouse Shelves"
	shelves.object_name = "Storehouse Shelves"
	shelves.position = Vector3(0, 0, -3.0 + 0.3 + 0.32)
	_add(b, shelves)
	shelves.unique_name_in_owner = true
	var _unused := shed
	_finish(b, "storehouse")


func _farm_plot() -> void:
	var size := Vector2(12, 10)
	var b := _begin("FarmPlot", "farm_plot", "Farm Plot", Vector3(12.2, 0.6, 10.2), 300.0,
		{&"wood_plank": 1}, {&"wood_plank": 2})
	(b.get("definition") as StructureDefinition).blocks_navigation = false
	var body := _body(b)
	var soil := MeshInstance3D.new()
	soil.name = "Soil"
	var pm := PlaneMesh.new()
	pm.size = size
	soil.mesh = pm
	soil.material_override = M["soil"]
	soil.position.y = 0.015
	_add(body, soil)
	# Edging planks, and a thin floor to find it by (you walk over it)
	for side in [-1.0, 1.0]:
		_box(body, "EdgeX", Vector3(size.x + 0.2, 0.12, 0.1), Vector3(0, 0.06, side * size.y / 2.0), M["wood"], false)
		_box(body, "EdgeZ", Vector3(0.1, 0.12, size.y), Vector3(side * size.x / 2.0, 0.06, 0), M["wood"], false)
	_shape(body, "Ground", Vector3(size.x, 0.04, size.y), Vector3(0, 0.02, 0))
	# Rows of crops, one mesh
	var plant := CylinderMesh.new()
	plant.top_radius = 0.04
	plant.bottom_radius = 0.28
	plant.height = 0.9
	plant.radial_segments = 5
	plant.rings = 0
	plant.cap_top = false
	plant.cap_bottom = false
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 619
	var row := -size.x * 0.5 + 1.0
	while row < size.x * 0.5 - 0.5:
		var along := -size.y * 0.5 + 1.0
		while along < size.y * 0.5 - 0.5:
			if rng.randf() < 0.85:
				var hh := rng.randf_range(0.5, 1.1)
				st.append_from(plant, 0, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, hh, 1)), Vector3(row, 0.45 * hh, along)))
			along += 0.7
		row += 1.3
	var crops := MeshInstance3D.new()
	crops.name = "Crops"
	crops.mesh = st.commit()
	crops.material_override = M["crop"]
	crops.visibility_range_end = 220.0
	_add(body, crops)
	_markers(b, "FarmSpots", [Vector3(-3, 0, 0), Vector3(3, 0, 0)])
	_finish(b, "farm_plot")


# ---------------------------------------------------------------- helpers

## A SettlementBuilding root with a fresh StructureDefinition.
func _begin(node_name: String, id: String, display: String, footprint: Vector3, health: float, repair: Dictionary, back: Dictionary) -> SettlementBuilding:
	var def := StructureDefinition.new()
	def.id = StringName(id)
	def.display_name = display
	def.scene_path = SCENES + id + ".tscn"
	def.footprint = footprint
	def.max_health = health
	def.movable = false
	def.repair_cost = _items(repair)
	def.dismantle_return = _items(back)
	top = SettlementBuilding.new()
	top.name = node_name
	top.set("definition", def)
	var hit := AudioStreamPlayer3D.new()
	hit.name = "HitSound"
	hit.stream = load("res://assets/audio/sets/structure_hit.tres")
	hit.volume_db = -2.0
	hit.unit_size = 4.0
	hit.bus = &"SFX"
	hit.position.y = 0.9
	_add(top, hit)
	hit.unique_name_in_owner = true
	return top as SettlementBuilding


func _items(d: Dictionary) -> Dictionary[ItemDefinition, int]:
	var out: Dictionary[ItemDefinition, int] = {}
	for id: StringName in d:
		out[load("res://resources/items/%s.tres" % id) as ItemDefinition] = d[id]
	return out


func _body(b: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = PhysicsLayers.STRUCTURES
	body.collision_mask = 0
	_add(b, body)
	return body


## A building from the site kit (walls round the openings, floor, roof, lamp),
## moved under `b` as its body.
func _kit_building(b: Node3D, size: Vector2, opts: Dictionary) -> StaticBody3D:
	var k := Kit.new("Tmp", "Tmp", 1)
	var house := k.building("Body", Vector2.ZERO, 0, size, opts)
	house.get_parent().remove_child(house)
	k.root.free()
	house.transform = Transform3D.IDENTITY
	house.remove_from_group("navigation_geometry")
	b.add_child(house)
	_own(house)
	return house


func _own(n: Node) -> void:
	n.owner = top
	for c in n.get_children():
		_own(c)


func _box(body: Node3D, name: String, size: Vector3, pos: Vector3, mat: Material, solid: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	_add(body, mi)
	if solid:
		_shape(body, name + "Col", size, pos)


func _shape(body: Node3D, name: String, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = name
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	_add(body, cs)


func _markers(b: Node3D, group: String, points: Array) -> void:
	var g := Node3D.new()
	g.name = group
	_add(b, g)
	var i := 0
	for p: Vector3 in points:
		var m := Marker3D.new()
		m.name = "Spot%d" % i
		m.position = p
		_add(g, m)
		i += 1


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child, true)
	child.owner = top


func _finish(b: Node3D, id: String) -> void:
	var def := b.get("definition") as StructureDefinition
	var err := ResourceSaver.save(def, DEFS + id + ".tres")
	def.take_over_path(DEFS + id + ".tres")
	b.set("definition", load(DEFS + id + ".tres"))
	var packed := PackedScene.new()
	err = packed.pack(b)
	if err == OK:
		err = ResourceSaver.save(packed, SCENES + id + ".tscn")
	print("wrote %s (%s)" % [id, error_string(err)])
	b.free()
