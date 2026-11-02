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
##   kitchen       8 × 6 m, a cooking stove and a fridge: a Cook works here (21.5)
##   chicken_coop  a hen house and a wire run, 8 × 6 m: room for 8 chickens
##   pig_pen       a 10 × 8 m pen with a trough, mud and a shelter: 6 pigs
##   cow_pasture   a 16 × 12 m paddock with a trough and hay: 4 cows
##   tanning_rack  a frame with a hide stretched on it and a tub: put Raw Hides
##                 in the tub and they come out Leather (22)
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
	M["mud"] = _plain(Color(0.28, 0.2, 0.13), 0.95)
	M["straw"] = _plain(Color(0.78, 0.66, 0.36), 0.95)
	M["water"] = _plain(Color(0.25, 0.35, 0.4), 0.2)
	M["wire"] = _plain(Color(0.55, 0.55, 0.55), 0.5)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENES))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEFS))
	_fence()
	_guard_post()
	_guard_tower()
	_bunkhouse()
	_storehouse()
	_farm_plot()
	_kitchen()
	_pen("ChickenCoop", "chicken_coop", "Chicken Coop", &"chicken", 8, Vector2(8, 6), 0.9)
	_pen("PigPen", "pig_pen", "Pig Pen", &"pig", 6, Vector2(10, 8), 1.0)
	_pen("CowPasture", "cow_pasture", "Cow Pasture", &"cow", 4, Vector2(16, 12), 1.35)
	_tanning_rack()
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
	# Boarded in below the deck (22.1): nobody stands under it thinking
	# they're at the post above
	_box(body, "SkirtBack", Vector3(2.9, 1.2, 0.05), Vector3(0, 0.6, deck_z - 1.38), M["wood"], true)
	_box(body, "SkirtFront", Vector3(2.9, 1.2, 0.05), Vector3(0, 0.6, deck_z + 1.38), M["wood"], true)
	_box(body, "SkirtLeft", Vector3(0.05, 1.2, 2.9), Vector3(-1.38, 0.6, deck_z), M["wood"], true)
	_box(body, "SkirtRight", Vector3(0.05, 1.2, 2.9), Vector3(1.38, 0.6, deck_z), M["wood"], true)
	_shape(body, "UnderDeck", Vector3(2.8, 1.2, 2.8), Vector3(0, 0.6, deck_z))
	# Rails round the deck, open where the stair arrives (front right)
	_box(body, "RailBack", Vector3(3.0, 1.0, 0.08), Vector3(0, h + 0.5, deck_z - 1.46), M["wood"], true)
	_box(body, "RailLeft", Vector3(0.08, 1.0, 3.0), Vector3(-1.46, h + 0.5, deck_z), M["wood"], true)
	_box(body, "RailRight", Vector3(0.08, 1.0, 3.0), Vector3(1.46, h + 0.5, deck_z), M["wood"], true)
	# The stair is 1.5 m wide between its rails (22.1: narrower, the navmesh
	# lost the way up), from x0 to x1, clear of the front right leg
	var x0 := -0.25
	var x1 := 1.27
	var xm := (x0 + x1) / 2.0
	_box(body, "RailFront", Vector3(x0 + 1.5, 1.0, 0.08), Vector3((x0 - 1.5) / 2.0, h + 0.5, deck_z + 1.46), M["wood"], true)
	_box(body, "Roof", Vector3(3.4, 0.08, 3.4), Vector3(0, h + 2.24, deck_z), M["tin"], true)
	# The stair: 2.6 m up over 3.4 m. Solid underneath (22.1): with only a
	# sloping board, the navmesh joined it from the side where it was already
	# knee-high, and settlers walked into its edge
	var run := 3.4
	var length := sqrt(h * h + run * run)
	var angle := atan2(h, run)
	var z_top := deck_z + 1.5
	var z_foot := z_top + run
	var wedge := CollisionShape3D.new()
	wedge.name = "Ramp"
	var ws := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for x in [x0, x1]:
		pts.append(Vector3(x, 0.0, z_foot))
		pts.append(Vector3(x, h, z_top))
		pts.append(Vector3(x, 0.0, z_top))
	ws.points = pts
	wedge.shape = ws
	_add(body, wedge)
	# Boarded sides under the stair
	for x in [x0 + 0.02, x1 - 0.02]:
		var panel := MeshInstance3D.new()
		panel.name = "StairSide"
		var pm := PrismMesh.new()
		pm.left_to_right = 1.0  # the high end at the deck (local +x turns to -z)
		pm.size = Vector3(run, h, 0.04)
		panel.mesh = pm
		panel.material_override = M["wood"]
		panel.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(x, h / 2.0, z_top + run / 2.0))
		_add(body, panel)
	# Handrails down both sides, carried on past the foot by a post (22.1):
	# the only way on is from the front
	for x in [x0, x1]:
		var rail := Transform3D(Basis(Vector3.RIGHT, angle), Vector3(x, h / 2.0, z_top + run / 2.0)) \
			* Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))
		var rm := MeshInstance3D.new()
		rm.name = "Handrail"
		var rbm := BoxMesh.new()
		rbm.size = Vector3(0.06, 0.9, length)
		rm.mesh = rbm
		rm.material_override = M["wood"]
		rm.transform = rail
		_add(body, rm)
		var rc := CollisionShape3D.new()
		rc.name = "HandrailCol"
		var rcs := BoxShape3D.new()
		rcs.size = Vector3(0.06, 0.9, length)
		rc.shape = rcs
		rc.transform = rail
		_add(body, rc)
		_box(body, "Newel", Vector3(0.1, 1.0, 0.5), Vector3(x, 0.5, z_foot + 0.15), M["wood"], true)
	for i in 12:
		var t := (i + 0.5) / 12.0
		_box(body, "Step%d" % i, Vector3(x1 - x0, 0.06, 0.3), Vector3(xm, h * (1.0 - t) + 0.03, z_top + run * t), M["wood_plain"], false)
	for x in [x0, x1]:
		var side := MeshInstance3D.new()
		side.name = "Stringer"
		var sm := BoxMesh.new()
		sm.size = Vector3(0.08, 0.25, length)
		side.mesh = sm
		side.material_override = M["wood"]
		side.transform = Transform3D(Basis(Vector3.RIGHT, angle), Vector3(x, h / 2.0, z_top + run / 2.0))
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


## The Kitchen (21.5): a stove you (and a Cook) cook at, a fridge for what's
## cooked, a counter and a table. Markers: CookSpots (where a Cook stands).
func _kitchen() -> void:
	var b := _begin("Kitchen", "kitchen", "Kitchen", Vector3(8.2, 4.6, 6.2), 1500.0,
		{&"wood_plank": 4, &"scrap_metal": 1}, {&"wood_plank": 8, &"scrap_metal": 3})
	var house := _kit_building(b, Vector2(8, 6), {
		"wall": "wood", "floor": "wood", "roof": "pitched",
		"openings": [["S", 0, "door"], ["E", 0, "window"], ["W", 0, "window"], ["N", 2, "window"]],
	})
	var stove := (load("res://scenes/world/stations/cooking_stove.tscn") as PackedScene).instantiate() as Node3D
	stove.name = "Stove"
	stove.position = Vector3(-2.2, 0, -2.55)
	_add(b, stove)
	var fridge := (load("res://scenes/world/containers/fridge.tscn") as PackedScene).instantiate() as Node3D
	fridge.name = "Fridge"
	fridge.position = Vector3(3.15, 0, -2.6)
	_add(b, fridge)
	fridge.unique_name_in_owner = true
	_box(house, "Counter", Vector3(2.2, 0.9, 0.6), Vector3(0.6, 0.45, -2.65), M["wood_plain"], true)
	_box(house, "Table", Vector3(1.6, 0.75, 0.9), Vector3(0.2, 0.375, 0.6), M["wood_plain"], true)
	_box(house, "Pots", Vector3(0.5, 0.25, 0.35), Vector3(0.1, 1.02, -2.65), M["rust"], false)
	_markers(b, "CookSpots", [Vector3(-2.2, 0, -1.3)])
	_finish(b, "kitchen")


## A pen for `kind` (21.5): a fence round `size` with a gap on the south side
## to walk in by, a trough, and something to shelter in. The animals (made
## at run time by the pen, `animal_capacity` at most) wander inside
## AnimalArea (a Marker3D whose "size" meta is the space they keep to).
## TendSpots: where a Rancher stands to feed them.
func _pen(node_name: String, id: String, display: String, kind: StringName, capacity: int, size: Vector2, height: float) -> void:
	var b := _begin(node_name, id, display, Vector3(size.x + 0.3, height + 1.5, size.y + 0.3), 600.0,
		{&"wood_plank": 2, &"scrap_metal": 1}, {&"wood_plank": 5, &"scrap_metal": 2})
	b.set("animal_kind", kind)
	b.set("animal_capacity", capacity)
	var body := _body(b)
	var hx := size.x / 2.0
	var hz := size.y / 2.0
	var gap := 1.4
	var fence_mat: Material = M["wire"] if kind == &"chicken" else M["wood"]
	# Posts every 2 m round the edge
	var posts: Array[Vector3] = []
	var x := -hx
	while x <= hx + 0.01:
		posts.append(Vector3(x, 0, -hz))
		if absf(x) > gap / 2.0 + 0.1:
			posts.append(Vector3(x, 0, hz))
		x += 2.0
	var z := -hz + 2.0
	while z < hz - 0.01:
		posts.append(Vector3(-hx, 0, z))
		posts.append(Vector3(hx, 0, z))
		z += 2.0
	posts.append(Vector3(-gap / 2.0, 0, hz))
	posts.append(Vector3(gap / 2.0, 0, hz))
	var i := 0
	for pp in posts:
		_box(body, "Post%d" % i, Vector3(0.1, height + 0.1, 0.1), Vector3(pp.x, (height + 0.1) / 2.0, pp.z), M["wood"], false)
		i += 1
	# The sides (solid), the front in two halves either side of the way in
	var rails := [0.35, height - 0.1] if kind != &"chicken" else [0.1, 0.45, height - 0.05]
	var sides := [[Vector3(0, 0, -hz), size.x, true], [Vector3(-hx, 0, 0), size.y, false], [Vector3(hx, 0, 0), size.y, false]]
	var half := (size.x - gap) / 2.0
	sides.append([Vector3(-hx + half / 2.0, 0, hz), half, true])
	sides.append([Vector3(hx - half / 2.0, 0, hz), half, true])
	var n := 0
	for sd in sides:
		var at: Vector3 = sd[0]
		var length: float = sd[1]
		var along_x: bool = sd[2]
		for r: float in rails:
			_box(body, "Rail%d" % n, Vector3(length, 0.07, 0.05) if along_x else Vector3(0.05, 0.07, length), at + Vector3(0, r, 0), fence_mat, false)
			n += 1
		if kind == &"chicken":
			# Wire mesh: a thin see-through panel
			var wire := StandardMaterial3D.new()
			wire.albedo_color = Color(0.6, 0.6, 0.6, 0.35)
			wire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_box(body, "Wire%d" % n, Vector3(length, height, 0.01) if along_x else Vector3(0.01, height, length), at + Vector3(0, height / 2.0, 0), wire, false)
			n += 1
		_shape(body, "Side%d" % n, Vector3(length, height, 0.12) if along_x else Vector3(0.12, height, length), at + Vector3(0, height / 2.0, 0))
	# Ground
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = size - Vector2(0.1, 0.1)
	ground.mesh = pm
	ground.material_override = M["straw"] if kind == &"chicken" else M["mud"]
	ground.position.y = 0.012
	_add(body, ground)
	# A trough by the back fence
	var trough_at := Vector3(hx - 1.4, 0, -hz + 0.6)
	_box(body, "Trough", Vector3(1.6, 0.35, 0.5), trough_at + Vector3(0, 0.175, 0), M["wood"], true)
	_box(body, "TroughFill", Vector3(1.45, 0.03, 0.38), trough_at + Vector3(0, 0.34, 0), M["straw"] if kind != &"cow" else M["water"], false)
	# Shelter
	match kind:
		&"chicken":
			var hut := Vector3(-hx + 1.4, 0, -hz + 1.1)
			_box(body, "HenHouse", Vector3(2.2, 1.3, 1.6), hut + Vector3(0, 0.85, 0), M["wood"], true)
			_box(body, "HenRoof", Vector3(2.5, 0.08, 1.9), hut + Vector3(0, 1.55, 0), M["tin"], false)
			_box(body, "HenLegs", Vector3(2.0, 0.2, 1.4), hut + Vector3(0, 0.1, 0), M["wood"], false)
			_box(body, "Ramp", Vector3(0.3, 0.05, 0.9), hut + Vector3(0.6, 0.18, 1.1), M["wood"], false)
		&"pig":
			var lean := Vector3(-hx + 1.6, 0, -hz + 1.2)
			_box(body, "ShelterRoof", Vector3(3.0, 0.08, 2.2), lean + Vector3(0, 1.3, 0), M["tin"], false)
			for c in [Vector2(-1.4, -1.0), Vector2(1.4, -1.0), Vector2(-1.4, 1.0), Vector2(1.4, 1.0)]:
				_box(body, "ShelterPost%d%d" % [int(c.x > 0), int(c.y > 0)], Vector3(0.1, 1.3, 0.1), lean + Vector3(c.x, 0.65, c.y), M["wood"], false)
			_box(body, "Mud", Vector3(3.5, 0.02, 2.6), Vector3(1.5, 0.02, 1.0), M["mud"], false)
		&"cow":
			var lean := Vector3(-hx + 2.2, 0, -hz + 1.6)
			_box(body, "ShelterRoof", Vector3(4.2, 0.1, 3.0), lean + Vector3(0, 2.3, 0), M["tin"], false)
			_box(body, "ShelterBack", Vector3(4.2, 2.3, 0.1), lean + Vector3(0, 1.15, -1.45), M["wood"], true)
			for c in [-2.0, 2.0]:
				_box(body, "ShelterPost%d" % int(c > 0), Vector3(0.14, 2.3, 0.14), lean + Vector3(c, 1.15, 1.4), M["wood"], false)
			for k in 3:
				_box(body, "HayBale%d" % k, Vector3(1.0, 0.5, 0.6), Vector3(hx - 1.2 - k * 1.1, 0.25, hz - 1.0), M["straw"], true)
	# Where the animals keep to, and where a Rancher stands
	var area := Marker3D.new()
	area.name = "AnimalArea"
	area.set_meta("size", size - Vector2(1.2, 1.2))
	_add(b, area)
	_markers(b, "TendSpots", [trough_at + Vector3(0, 0, 1.0)])
	_finish(b, id)


## The Tanning Rack (22): a wooden frame with a hide stretched on it, and a
## tub (%Rack, 6 slots) you put Raw Hides in; the settlement turns them into
## Leather in the tub, a few hours each.
func _tanning_rack() -> void:
	var b := _begin("TanningRack", "tanning_rack", "Tanning Rack", Vector3(3.2, 2.4, 1.6), 400.0,
		{&"wood_plank": 1}, {&"wood_plank": 3, &"cloth": 1})
	var body := _body(b)
	var hide := _plain(Color(0.6, 0.42, 0.26), 0.9)
	for x in [-1.3, 1.3]:
		_box(body, "Upright%s" % ("L" if x < 0 else "R"), Vector3(0.12, 2.1, 0.12), Vector3(x, 1.05, -0.3), M["wood"], true)
	_box(body, "TopBar", Vector3(2.8, 0.1, 0.1), Vector3(0, 2.05, -0.3), M["wood"], false)
	_box(body, "LowBar", Vector3(2.8, 0.1, 0.1), Vector3(0, 0.45, -0.3), M["wood"], false)
	_box(body, "Hide", Vector3(2.2, 1.4, 0.03), Vector3(0, 1.25, -0.28), hide, false)
	for i in 6:
		_box(body, "Lace%d" % i, Vector3(0.02, 0.02, 0.06), Vector3(-1.1 + i * 0.44, 1.95, -0.28), M["wood"], false)
	var tub := SalvageContainer.new()
	tub.name = "Rack"
	tub.collision_layer = 16
	tub.collision_mask = 0
	tub.monitoring = false
	tub.container_name = "Tanning Tub"
	tub.search_time = 0.0
	tub.set("focus_offset", Vector3(0, 0.5, 0))
	tub.position = Vector3(0.9, 0, 0.45)
	_add(b, tub)
	tub.unique_name_in_owner = true
	var area := CollisionShape3D.new()
	area.name = "Shape"
	var ash := BoxShape3D.new()
	ash.size = Vector3(1.0, 0.9, 1.0)
	area.shape = ash
	area.position = Vector3(0, 0.45, 0)
	_add(tub, area)
	var tb := StaticBody3D.new()
	tb.name = "Body"
	tb.collision_layer = 2
	tb.collision_mask = 0
	_add(tub, tb)
	var tbs := CollisionShape3D.new()
	tbs.name = "BodyShape"
	var tbb := BoxShape3D.new()
	tbb.size = Vector3(0.8, 0.6, 0.8)
	tbs.shape = tbb
	tbs.position = Vector3(0, 0.3, 0)
	_add(tb, tbs)
	var cyl := MeshInstance3D.new()
	cyl.name = "Tub"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.36
	cm.height = 0.6
	cyl.mesh = cm
	cyl.material_override = M["wood"]
	cyl.position.y = 0.3
	_add(tb, cyl)
	var liquor := MeshInstance3D.new()
	liquor.name = "Liquor"
	var lm := CylinderMesh.new()
	lm.top_radius = 0.38
	lm.bottom_radius = 0.38
	lm.height = 0.02
	liquor.mesh = lm
	liquor.material_override = _plain(Color(0.35, 0.25, 0.15), 0.2)
	liquor.position.y = 0.55
	_add(tb, liquor)
	var inv := InventoryComponent.new()
	inv.name = "Inventory"
	inv.slot_count = 6
	inv.max_weight = 0.0
	_add(tub, inv)
	inv.unique_name_in_owner = true
	_finish(b, "tanning_rack")


func _plain(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


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
