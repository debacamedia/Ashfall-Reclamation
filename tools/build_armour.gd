extends SceneTree
## Builds Increment 22's clothing and armour: Leather (tanned from Raw Hide
## on a Tanning Rack), and six pieces for the head, body and legs, made at a
## workbench. Their models, items and recipes, and Leather in some loot.
##
##   godot --headless --path . -s res://tools/build_armour.gd
## Then render the icons (needs a window):
##   godot --path . -s res://tools/render_item_icons.gd -- leather,leather_cap,leather_jacket,leather_trousers,scrap_helmet,plated_vest,plated_trousers

const MODELS := "res://scenes/items/models/"
const ITEMS := "res://resources/items/"
const RECIPES := "res://resources/recipes/"

## id: [name, slot (1 head, 2 body, 3 legs), protection, durability, speed,
##      weight, value, repair {id: n}, recipe inputs {id: n}, craft s, description]
const PIECES := {
	&"leather_cap": ["Leather Cap", 1, 0.06, 120.0, 1.0, 0.4, 10, {&"leather": 1}, {&"leather": 2, &"cloth": 1}, 4.0,
		"A stitched leather cap. Takes a little off a blow to the head."],
	&"leather_jacket": ["Leather Jacket", 2, 0.14, 200.0, 1.0, 2.0, 25, {&"leather": 1}, {&"leather": 5, &"cloth": 2}, 8.0,
		"A heavy leather jacket from Ash Creek hides. Light, quiet, and turns a machete."],
	&"leather_trousers": ["Leather Trousers", 3, 0.08, 160.0, 1.0, 1.2, 15, {&"leather": 1}, {&"leather": 3, &"cloth": 2}, 6.0,
		"Leather trousers with patched knees."],
	&"scrap_helmet": ["Scrap Helmet", 1, 0.12, 300.0, 1.0, 1.5, 20, {&"scrap_metal": 2}, {&"leather": 1, &"scrap_metal": 4, &"metal_plate": 1}, 8.0,
		"A beaten steel helmet on a leather liner."],
	&"plated_vest": ["Plated Vest", 2, 0.26, 400.0, 0.94, 6.0, 45, {&"scrap_metal": 2}, {&"leather": 3, &"metal_plate": 2, &"scrap_metal": 4}, 12.0,
		"Steel plates riveted to a leather vest. Stops a lot, and slows you a little."],
	&"plated_trousers": ["Plated Trousers", 3, 0.14, 300.0, 0.97, 3.5, 30, {&"scrap_metal": 2}, {&"leather": 2, &"metal_plate": 1, &"scrap_metal": 3}, 10.0,
		"Leather trousers with steel plates over the shins and thighs. A little slower."],
}

## Leather found about the place: [table, weight, min, max].
const LOOT := [["town_household", 1.0, 1, 2], ["scavenger_stash", 1.5, 1, 3], ["footlocker", 1.0, 1, 2], ["raider_camp_cache", 1.0, 1, 2]]


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	var leather := _item(&"leather", "Leather", "Tanned hide, ready to cut and stitch. Make clothing and armour from it at a workbench, or mend leather pieces.",
		ItemDefinition.Category.RESOURCE, 0.5, 20, 6, "leather")
	ResourceSaver.save(leather, ITEMS + "leather.tres")
	print("item leather")
	for id: StringName in PIECES:
		var s: Array = PIECES[id]
		var it := _item(id, s[0], s[10], ItemDefinition.Category.EQUIPMENT, s[5], 1, s[6], String(id))
		it.armour_slot = s[1]
		it.armour_protection = s[2]
		it.armour_durability = s[3]
		it.armour_speed = s[4]
		it.armour_repair = s[7]
		ResourceSaver.save(it, ITEMS + String(id) + ".tres")
		var r := RecipeDefinition.new()
		r.id = id
		r.category = RecipeDefinition.Category.GEAR
		r.station = RecipeDefinition.Station.WORKBENCH
		var inputs: Dictionary[ItemDefinition, int] = {}
		for iid: StringName in s[8]:
			inputs[load(ITEMS + String(iid) + ".tres") as ItemDefinition] = s[8][iid]
		r.inputs = inputs
		r.output = load(ITEMS + String(id) + ".tres")
		r.output_quantity = 1
		r.craft_time = s[9]
		ResourceSaver.save(r, RECIPES + String(id) + ".tres")
		print("piece ", id)
	for e in LOOT:
		var path := "res://resources/loot/%s.tres" % e[0]
		var lt: LootTable = load(path)
		var item: ItemDefinition = load(ITEMS + "leather.tres")
		if not lt.entries.any(func(x: LootEntry) -> bool: return x.item == item):
			var le := LootEntry.new()
			le.item = item
			le.weight = e[1]
			le.min_quantity = e[2]
			le.max_quantity = e[3]
			lt.entries.append(le)
			ResourceSaver.save(lt, path)
		print("loot ", e[0])
	quit()


func _item(id: StringName, display: String, about: String, cat: ItemDefinition.Category, weight: float, stack: int, value: int, model_kind: String) -> ItemDefinition:
	var model := _model(model_kind)
	var packed := PackedScene.new()
	packed.pack(model)
	var model_path := MODELS + String(id) + ".tscn"
	ResourceSaver.save(packed, model_path)
	model.free()
	var path := ITEMS + String(id) + ".tres"
	var item: ItemDefinition = load(path) if ResourceLoader.exists(path) else ItemDefinition.new()
	item.id = id
	item.display_name = display
	item.description = about
	item.category = cat
	item.weight = weight
	item.max_stack = stack
	item.base_value = value
	item.pickup_sound = load("res://assets/ashfall_pack_v3/sets/pickup_soft.tres")
	item.world_model = load(model_path)
	var icon := "res://assets/icons/%s.png" % String(id)
	if ResourceLoader.exists(icon):
		item.icon = load(icon)
	return item


# ---------------------------------------------------------------- models

func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(parent: Node3D, n: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	mi.owner = parent if parent.owner == null else parent.owner
	return mi


func _dome(parent: Node3D, n: String, r: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var m := SphereMesh.new()
	m.radius = r
	m.height = r
	m.is_hemisphere = true
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	mi.owner = parent if parent.owner == null else parent.owner
	return mi


## Laid flat (as they'd lie on the ground), about 0.4 m across.
func _model(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind.capitalize().replace(" ", "")
	var hide := _mat(Color(0.48, 0.3, 0.17), 0.85)
	var dark := _mat(Color(0.3, 0.19, 0.11), 0.85)
	var steel := _mat(Color(0.42, 0.43, 0.45), 0.6, 0.5)
	var rust := _mat(Color(0.45, 0.3, 0.22), 0.7, 0.4)
	match kind:
		"leather":
			for i in 3:
				var b := _box(root, "Sheet%d" % i, Vector3(0.3 - i * 0.02, 0.012, 0.22 - i * 0.015), Vector3(i * 0.01, 0.006 + i * 0.012, -i * 0.008), hide if i % 2 == 0 else dark)
				b.rotation_degrees.y = i * 7.0
			_box(root, "Cord", Vector3(0.02, 0.04, 0.24), Vector3(0, 0.02, 0), dark)
		"leather_cap", "scrap_helmet":
			var mat := hide if kind == "leather_cap" else steel
			_dome(root, "Crown", 0.12, Vector3(0, 0.0, 0), mat)
			_box(root, "Brim", Vector3(0.26, 0.012, 0.09) if kind == "leather_cap" else Vector3(0.26, 0.012, 0.26), Vector3(0, 0.006, -0.1 if kind == "leather_cap" else 0.0), mat if kind == "leather_cap" else rust)
			if kind == "scrap_helmet":
				for i in 4:
					_box(root, "Rivet%d" % i, Vector3(0.015, 0.015, 0.015), Vector3(cos(i * 1.57) * 0.1, 0.05, sin(i * 1.57) * 0.1), rust)
		"leather_jacket", "plated_vest":
			var body := hide if kind == "leather_jacket" else dark
			_box(root, "Torso", Vector3(0.32, 0.05, 0.36), Vector3(0, 0.025, 0), body)
			if kind == "leather_jacket":
				for x in [-0.22, 0.22]:
					var sl := _box(root, "Sleeve%s" % ("L" if x < 0 else "R"), Vector3(0.11, 0.04, 0.32), Vector3(x, 0.02, 0.06), dark)
					sl.rotation_degrees.y = -20.0 if x < 0 else 20.0
				_box(root, "Zip", Vector3(0.015, 0.055, 0.34), Vector3(0, 0.03, 0.0), _mat(Color(0.7, 0.6, 0.35), 0.4, 0.8))
				_box(root, "Collar", Vector3(0.18, 0.06, 0.05), Vector3(0, 0.04, -0.17), dark)
			else:
				for i in 4:
					_box(root, "Plate%d" % i, Vector3(0.13, 0.02, 0.15), Vector3(-0.075 + (i % 2) * 0.15, 0.06, -0.08 + (i / 2) * 0.17), steel)
				for x in [-0.12, 0.12]:
					_box(root, "Strap%s" % ("L" if x < 0 else "R"), Vector3(0.04, 0.03, 0.4), Vector3(x, 0.03, 0), hide)
		"leather_trousers", "plated_trousers":
			for x in [-0.07, 0.07]:
				_box(root, "Leg%s" % ("L" if x < 0 else "R"), Vector3(0.12, 0.04, 0.42), Vector3(x, 0.02, 0.05), hide)
				if kind == "plated_trousers":
					_box(root, "Plate%s" % ("L" if x < 0 else "R"), Vector3(0.1, 0.02, 0.16), Vector3(x, 0.05, 0.12), steel)
			_box(root, "Waist", Vector3(0.28, 0.045, 0.08), Vector3(0, 0.022, -0.18), dark)
	return root
