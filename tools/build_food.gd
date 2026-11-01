extends SceneTree
## Builds the food (Increments 21 and 21.5): the models and items for
## Canned Beans, Canned Peaches, Vegetable Stew, Meat Stew, Cooked Meat and
## Fried Eggs, and the raw things from the farm's animals (Raw Meat, Eggs,
## Raw Hide); the cooking recipes; the Cooking Stove station and the Fridge.
## (Fresh Vegetables already exist; this gives them a food value.)
##
## Cooking burns a Wood Plank (21.5: the same for you and for a Cook).
##
##   godot --headless --path . -s res://tools/build_food.gd
## Then render the icons (needs a window):
##   godot --path . -s res://tools/render_item_icons.gd -- canned_beans,canned_peaches,vegetable_stew,meat_stew,cooked_meat,fried_eggs,raw_meat,egg,raw_hide

const MODELS := "res://scenes/items/models/"
const ITEMS := "res://resources/items/"

## id: [name, description, food, use time, weight, stack, value, sound, model, settler meals]
const FOODS := {
	&"canned_beans": ["Canned Beans", "Baked beans in a dented tin. Filling, and it keeps forever. Eat with J.", 30.0, 2.0, 0.45, 10, 6, "eat_can", "can_beans"],
	&"canned_peaches": ["Canned Peaches", "Sliced peaches in syrup. Sweet, a little filling. Eat with J.", 20.0, 2.0, 0.4, 10, 5, "eat_can", "can_peaches"],
	&"vegetable_stew": ["Vegetable Stew", "Ash Creek vegetables stewed in a tin bowl. Cook it on a stove or a workbench: 3 vegetables and a plank for the fire. In a settlement's fridge it feeds four.", 60.0, 2.5, 0.6, 5, 12, "eat", "stew", 4.0],
	&"meat_stew": ["Meat Stew", "Meat and vegetables, stewed for hours. The most filling thing there is. In a settlement's fridge it feeds five.", 75.0, 2.5, 0.7, 5, 18, "eat", "meat_stew", 5.0],
	&"cooked_meat": ["Cooked Meat", "A slab of meat off the stove. In a settlement's fridge it feeds two.", 40.0, 2.0, 0.4, 10, 10, "eat", "cooked_meat", 2.0],
	&"fried_eggs": ["Fried Eggs", "Two eggs, fried. In a settlement's fridge they feed two.", 25.0, 1.5, 0.25, 10, 6, "eat", "fried_eggs", 2.0],
}

## Raw things from the farm's animals (21.5): [name, description, category, weight, stack, value, model]
const RAW := {
	&"raw_meat": ["Raw Meat", "Fresh from the farm's animals. Cook it first: on a stove or a workbench, or leave it in the stores for a Cook.", ItemDefinition.Category.FOOD, 0.5, 20, 4, "raw_meat"],
	&"egg": ["Egg", "Laid by the farm's chickens. Fry two on a stove, or leave them in the stores for a Cook.", ItemDefinition.Category.FOOD, 0.06, 30, 1, "egg"],
	&"raw_hide": ["Raw Hide", "A cow's hide, salted and rolled. Kept for making clothing and armour later.", ItemDefinition.Category.RESOURCE, 2.0, 10, 8, "hide"],
}

## Cooking (all on a stove or a workbench, all burning a Wood Plank):
## id: [inputs {item: n}, output, seconds]
const RECIPES := {
	&"vegetable_stew": [{&"vegetables": 3}, &"vegetable_stew", 4.0],
	&"meat_stew": [{&"raw_meat": 1, &"vegetables": 2}, &"meat_stew", 5.0],
	&"cooked_meat": [{&"raw_meat": 1}, &"cooked_meat", 3.0],
	&"fried_eggs": [{&"egg": 2}, &"fried_eggs", 2.0],
}


## Canned food added to these loot tables: [item, weight, min, max]. (The
## tables build_sites.gd makes have theirs in its LOOT list.)
const LOOT := {
	"town_household": [["canned_beans", 2.0, 1, 2], ["canned_peaches", 2.0, 1, 2]],
	"town_supplies": [["canned_beans", 2.0, 1, 3], ["canned_peaches", 1.0, 1, 2]],
	"scavenger_stash": [["canned_beans", 2.0, 1, 2], ["canned_peaches", 1.0, 1, 1]],
	"raider_camp_cache": [["canned_beans", 1.5, 1, 2], ["canned_peaches", 1.0, 1, 1]],
	"military_crate": [["canned_beans", 2.0, 1, 3]],
	"footlocker": [["canned_peaches", 1.0, 1, 1]],
}


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	for id: StringName in FOODS:
		var spec: Array = FOODS[id]
		var model := _model(spec[8])
		var packed := PackedScene.new()
		packed.pack(model)
		var model_path := MODELS + String(id) + ".tscn"
		ResourceSaver.save(packed, model_path)
		model.free()
		var path := ITEMS + String(id) + ".tres"
		var item: ItemDefinition = load(path) if ResourceLoader.exists(path) else ItemDefinition.new()
		item.id = id
		item.display_name = spec[0]
		item.description = spec[1]
		item.category = ItemDefinition.Category.FOOD
		item.food_value = spec[2]
		item.use_time = spec[3]
		item.weight = spec[4]
		item.max_stack = spec[5]
		item.base_value = spec[6]
		item.use_sound = load("res://assets/audio/%s.wav" % spec[7])
		item.pickup_sound = load("res://assets/ashfall_pack_v3/sets/pickup_metal.tres" if spec[7] == "eat_can" else "res://assets/ashfall_pack_v3/sets/pickup_soft.tres")
		item.world_model = load(model_path)
		item.settler_meals = spec[9] if spec.size() > 9 else 0.0
		var icon := "res://assets/icons/%s.png" % String(id)
		if ResourceLoader.exists(icon):
			item.icon = load(icon)
		ResourceSaver.save(item, path)
		print("item ", id)
	for id: StringName in RAW:
		var spec: Array = RAW[id]
		var model := _model(spec[6])
		var packed := PackedScene.new()
		packed.pack(model)
		var model_path := MODELS + String(id) + ".tscn"
		ResourceSaver.save(packed, model_path)
		model.free()
		var path := ITEMS + String(id) + ".tres"
		var item: ItemDefinition = load(path) if ResourceLoader.exists(path) else ItemDefinition.new()
		item.id = id
		item.display_name = spec[0]
		item.description = spec[1]
		item.category = spec[2]
		item.weight = spec[3]
		item.max_stack = spec[4]
		item.base_value = spec[5]
		item.pickup_sound = load("res://assets/ashfall_pack_v3/sets/pickup_soft.tres")
		item.world_model = load(model_path)
		var icon := "res://assets/icons/%s.png" % String(id)
		if ResourceLoader.exists(icon):
			item.icon = load(icon)
		ResourceSaver.save(item, path)
		print("raw ", id)
	# Fresh Vegetables: food now (12 each, 1.5 s, crunchy)
	var veg: ItemDefinition = load(ITEMS + "vegetables.tres")
	veg.food_value = 12.0
	veg.use_time = 1.5
	veg.use_sound = load("res://assets/audio/eat.wav")
	veg.description = "Cabbages, carrots and potatoes from Ash Creek Farms. Settlers eat one every 4 hours; the farmers grow more with water. Eat with J, or cook 3 into a stew."
	ResourceSaver.save(veg, ITEMS + "vegetables.tres")
	# Cooking: every recipe burns a Wood Plank (21.5)
	var plank: ItemDefinition = load(ITEMS + "wood_plank.tres")
	for rid: StringName in RECIPES:
		var spec: Array = RECIPES[rid]
		var r := RecipeDefinition.new()
		r.id = rid
		r.category = RecipeDefinition.Category.FOOD
		r.station = RecipeDefinition.Station.STOVE
		var inputs: Dictionary[ItemDefinition, int] = {}
		for iid: StringName in spec[0]:
			inputs[load(ITEMS + String(iid) + ".tres") as ItemDefinition] = spec[0][iid]
		inputs[plank] = 1
		r.inputs = inputs
		r.output = load(ITEMS + String(spec[1]) + ".tres")
		r.output_quantity = 1
		r.craft_time = spec[2]
		ResourceSaver.save(r, "res://resources/recipes/%s.tres" % String(rid))
		print("recipe ", rid)
	# Canned food in the loot (once each: re-running doesn't add it twice)
	for table: String in LOOT:
		var path := "res://resources/loot/%s.tres" % table
		var lt: LootTable = load(path)
		for e: Array in LOOT[table]:
			var item: ItemDefinition = load(ITEMS + e[0] + ".tres")
			if lt.entries.any(func(x: LootEntry) -> bool: return x.item == item):
				continue
			var le := LootEntry.new()
			le.item = item
			le.weight = e[1]
			le.min_quantity = e[2]
			le.max_quantity = e[3]
			lt.entries.append(le)
		ResourceSaver.save(lt, path)
		print("loot ", table)
	# The stove
	var stove := _stove()
	var ps := PackedScene.new()
	ps.pack(stove)
	ResourceSaver.save(ps, "res://scenes/world/stations/cooking_stove.tscn")
	stove.free()
	print("stove")
	var fridge := _fridge()
	var fp := PackedScene.new()
	fp.pack(fridge)
	ResourceSaver.save(fp, "res://scenes/world/containers/fridge.tscn")
	fridge.free()
	print("fridge")
	quit()


# ---------------------------------------------------------------- models

func _mat(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _cyl(parent: Node3D, name: String, r: float, h: float, at: Vector3, mat: Material, top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var m := CylinderMesh.new()
	m.top_radius = r if top < 0.0 else top
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 14
	m.rings = 1
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	mi.owner = parent if parent.owner == null else parent.owner
	return mi


func _box(parent: Node3D, name: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	mi.owner = parent if parent.owner == null else parent.owner
	return mi


func _model(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind.capitalize().replace(" ", "")
	var tin := _mat(Color(0.72, 0.72, 0.7), 0.35, 0.8)
	match kind:
		"can_beans", "can_peaches":
			var label := _mat(Color(0.75, 0.25, 0.15) if kind == "can_beans" else Color(0.95, 0.65, 0.2), 0.8)
			var band := _mat(Color(0.92, 0.88, 0.75) if kind == "can_beans" else Color(0.3, 0.45, 0.25), 0.8)
			_cyl(root, "Tin", 0.042, 0.11, Vector3(0, 0.055, 0), tin)
			_cyl(root, "Label", 0.0435, 0.08, Vector3(0, 0.055, 0), label)
			_cyl(root, "Band", 0.044, 0.022, Vector3(0, 0.06, 0), band)
			_cyl(root, "RimTop", 0.043, 0.006, Vector3(0, 0.111, 0), tin)
		"stew":
			var bowl := _mat(Color(0.55, 0.57, 0.6), 0.45, 0.6)
			var stew := _mat(Color(0.55, 0.32, 0.15), 0.6)
			_cyl(root, "Bowl", 0.06, 0.06, Vector3(0, 0.03, 0), bowl, 0.085)
			_cyl(root, "Stew", 0.078, 0.01, Vector3(0, 0.055, 0), stew)
			var bits := _mat(Color(0.9, 0.5, 0.15), 0.6)
			var greens := _mat(Color(0.42, 0.62, 0.28), 0.8)
			_box(root, "Carrot", Vector3(0.02, 0.012, 0.02), Vector3(0.025, 0.062, 0.01), bits)
			_box(root, "Carrot2", Vector3(0.018, 0.012, 0.018), Vector3(-0.03, 0.062, -0.02), bits)
			_box(root, "Cabbage", Vector3(0.025, 0.01, 0.02), Vector3(-0.005, 0.062, 0.035), greens)
			var spoon := _mat(Color(0.75, 0.75, 0.72), 0.3, 0.9)
			var handle := _box(root, "Spoon", Vector3(0.012, 0.006, 0.13), Vector3(0.05, 0.085, -0.02), spoon)
			handle.rotation_degrees = Vector3(-25, 30, 0)
		"meat_stew":
			var bowl := _mat(Color(0.55, 0.57, 0.6), 0.45, 0.6)
			_cyl(root, "Bowl", 0.06, 0.06, Vector3(0, 0.03, 0), bowl, 0.085)
			_cyl(root, "Stew", 0.078, 0.01, Vector3(0, 0.055, 0), _mat(Color(0.42, 0.2, 0.1), 0.6))
			var meat := _mat(Color(0.5, 0.25, 0.15), 0.7)
			for i in 4:
				_box(root, "Chunk%d" % i, Vector3(0.026, 0.018, 0.022), Vector3(cos(i * 1.7) * 0.035, 0.064, sin(i * 1.7) * 0.035), meat)
			_box(root, "Carrot", Vector3(0.018, 0.012, 0.018), Vector3(0.0, 0.063, 0.0), _mat(Color(0.9, 0.5, 0.15), 0.6))
		"cooked_meat", "raw_meat":
			var raw := kind == "raw_meat"
			if not raw:
				_cyl(root, "Plate", 0.1, 0.012, Vector3(0, 0.006, 0), _mat(Color(0.85, 0.85, 0.8), 0.4))
			var slab := _box(root, "Slab", Vector3(0.14, 0.035, 0.09), Vector3(0, 0.03 if not raw else 0.018, 0),
				_mat(Color(0.75, 0.2, 0.2) if raw else Color(0.45, 0.24, 0.12), 0.6))
			slab.rotation_degrees.y = 15
			_box(root, "Fat", Vector3(0.14, 0.036, 0.015), Vector3(0, 0.03 if not raw else 0.018, 0.045) , _mat(Color(0.95, 0.88, 0.8) if raw else Color(0.7, 0.5, 0.3), 0.6)).rotation_degrees.y = 15
		"fried_eggs":
			_cyl(root, "Plate", 0.1, 0.012, Vector3(0, 0.006, 0), _mat(Color(0.85, 0.85, 0.8), 0.4))
			for i in 2:
				var x := -0.035 + i * 0.075
				_cyl(root, "White%d" % i, 0.04, 0.006, Vector3(x, 0.015, 0.0), _mat(Color(0.97, 0.96, 0.92), 0.5))
				_cyl(root, "Yolk%d" % i, 0.016, 0.012, Vector3(x, 0.02, 0.0), _mat(Color(1.0, 0.7, 0.1), 0.4))
		"egg":
			var mi := MeshInstance3D.new()
			mi.name = "Egg"
			var sm := SphereMesh.new()
			sm.radius = 0.025
			sm.height = 0.065
			mi.mesh = sm
			mi.material_override = _mat(Color(0.93, 0.85, 0.7), 0.6)
			mi.position = Vector3(0, 0.033, 0)
			root.add_child(mi)
			mi.owner = root
		"hide":
			_cyl(root, "Roll", 0.06, 0.32, Vector3(0, 0.06, 0), _mat(Color(0.55, 0.38, 0.22), 0.9)).rotation_degrees.z = 90
			_box(root, "Patch", Vector3(0.1, 0.002, 0.12), Vector3(0.05, 0.121, 0), _mat(Color(0.95, 0.93, 0.88), 0.9))
			_box(root, "Tie", Vector3(0.02, 0.125, 0.125), Vector3(-0.08, 0.06, 0), _mat(Color(0.3, 0.2, 0.12), 0.9))
	return root


## The Fridge (21.5): a settlement kitchen's store of cooked food, 30 slots.
## Its door swings open about its left edge.
func _fridge() -> SalvageContainer:
	var f := SalvageContainer.new()
	f.name = "Fridge"
	f.collision_layer = 16
	f.collision_mask = 0
	f.monitoring = false
	f.container_name = "Fridge"
	f.search_time = 0.0
	f.set("lid_open_rotation", Vector3(0, -100, 0))
	f.set("focus_offset", Vector3(0, 1.0, 0.3))
	var area := CollisionShape3D.new()
	area.name = "Shape"
	var ash := BoxShape3D.new()
	ash.size = Vector3(0.85, 1.8, 0.9)
	area.shape = ash
	area.position = Vector3(0, 0.9, 0.1)
	f.add_child(area)
	area.owner = f
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 2
	body.collision_mask = 0
	f.add_child(body)
	body.owner = f
	var bs := CollisionShape3D.new()
	bs.name = "BodyShape"
	var bb := BoxShape3D.new()
	bb.size = Vector3(0.8, 1.75, 0.7)
	bs.shape = bb
	bs.position = Vector3(0, 0.875, 0)
	body.add_child(bs)
	bs.owner = f
	var enamel := _mat(Color(0.88, 0.88, 0.84), 0.35, 0.2)
	var chrome := _mat(Color(0.8, 0.8, 0.82), 0.25, 0.9)
	var dark := _mat(Color(0.12, 0.12, 0.12), 0.6)
	_box(body, "Cabinet", Vector3(0.8, 1.7, 0.66), Vector3(0, 0.88, -0.02), enamel)
	_box(body, "Inside", Vector3(0.7, 1.55, 0.02), Vector3(0, 0.88, 0.31), dark)
	_box(body, "Plinth", Vector3(0.76, 0.04, 0.6), Vector3(0, 0.02, -0.02), dark)
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(-0.4, 0, 0.33)
	f.add_child(lid)
	lid.owner = f
	lid.unique_name_in_owner = true
	_box(lid, "Door", Vector3(0.8, 1.7, 0.05), Vector3(0.4, 0.88, 0.0), enamel)
	_box(lid, "Handle", Vector3(0.03, 0.4, 0.04), Vector3(0.72, 1.1, 0.04), chrome)
	_box(lid, "Badge", Vector3(0.18, 0.04, 0.01), Vector3(0.4, 1.6, 0.03), chrome)
	var inv := InventoryComponent.new()
	inv.name = "Inventory"
	inv.slot_count = 30
	inv.max_weight = 0.0
	f.add_child(inv)
	inv.owner = f
	inv.unique_name_in_owner = true
	for spec in [["OpenSound", "res://assets/ashfall_pack_v3/audio/crate_open.wav"], ["CloseSound", "res://assets/ashfall_pack_v3/audio/crate_close.wav"]]:
		var a := AudioStreamPlayer3D.new()
		a.name = spec[0]
		a.stream = load(spec[1])
		a.unit_size = 5.0
		a.bus = &"SFX"
		a.position.y = 1.0
		f.add_child(a)
		a.owner = f
		a.unique_name_in_owner = true
	return f


func _stove() -> CraftingStation:
	var st := CraftingStation.new()
	st.name = "CookingStove"
	st.station = RecipeDefinition.Station.STOVE
	st.collision_layer = 16
	st.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.1, 1.3, 0.9)
	shape.shape = bs
	shape.position = Vector3(0, 0.6, 0)
	st.add_child(shape)
	shape.owner = st
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 2
	body.collision_mask = 0
	st.add_child(body)
	body.owner = st
	var bshape := CollisionShape3D.new()
	bshape.name = "BodyShape"
	var bb := BoxShape3D.new()
	bb.size = Vector3(0.95, 0.85, 0.65)
	bshape.shape = bb
	bshape.position = Vector3(0, 0.425, 0)
	body.add_child(bshape)
	bshape.owner = st
	var iron := _mat(Color(0.16, 0.16, 0.17), 0.65, 0.6)
	var plate := _mat(Color(0.1, 0.1, 0.1), 0.5, 0.7)
	var brass := _mat(Color(0.7, 0.55, 0.25), 0.35, 0.9)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.45, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.4, 0.08)
	glow.emission_energy_multiplier = 2.0
	_box(body, "Firebox", Vector3(0.95, 0.7, 0.65), Vector3(0, 0.45, 0), iron)
	_box(body, "Top", Vector3(1.0, 0.05, 0.7), Vector3(0, 0.825, 0), plate)
	for x in [-0.35, 0.35]:
		for z in [-0.25, 0.25]:
			_box(body, "Leg", Vector3(0.06, 0.12, 0.06), Vector3(x, 0.06, z), iron)
	_box(body, "Door", Vector3(0.36, 0.28, 0.02), Vector3(-0.18, 0.45, 0.335), plate)
	_box(body, "Glow", Vector3(0.26, 0.05, 0.01), Vector3(-0.18, 0.37, 0.347), glow)
	_box(body, "Handle", Vector3(0.1, 0.025, 0.03), Vector3(-0.05, 0.5, 0.355), brass)
	_box(body, "OvenDoor", Vector3(0.36, 0.28, 0.02), Vector3(0.22, 0.45, 0.335), plate)
	_cyl(body, "Chimney", 0.07, 1.5, Vector3(0.32, 1.6, -0.22), iron)
	_cyl(body, "Pot", 0.16, 0.2, Vector3(-0.2, 0.95, 0.0), _mat(Color(0.35, 0.36, 0.38), 0.4, 0.8), 0.17)
	_cyl(body, "PotStew", 0.155, 0.01, Vector3(-0.2, 1.045, 0.0), _mat(Color(0.5, 0.3, 0.14), 0.6))
	_cyl(body, "Kettle", 0.09, 0.16, Vector3(0.22, 0.93, 0.08), _mat(Color(0.45, 0.2, 0.15), 0.5, 0.5), 0.06)
	return st
