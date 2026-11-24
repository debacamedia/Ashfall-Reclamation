extends SceneTree
## Increment 32: the machete becomes an item you can move about on your
## quick bar (and see in your inventory). Builds its world model from the
## held machete's parts, lying flat, and its ItemDefinition. Run once:
##   godot --headless --path . -s res://tools/make_machete_item.gd
## then render its icon: godot --path . -s res://tools/render_item_icons.gd -- machete_item
## Leaves existing files alone.

const MODEL := "res://scenes/items/models/machete_world.tscn"
const ITEM := "res://resources/items/weapons/machete_item.tres"


func _initialize() -> void:
	if not ResourceLoader.exists(MODEL):
		var held := (load("res://scenes/weapons/machete.tscn") as PackedScene).instantiate()
		var root := Node3D.new()
		root.name = "MacheteWorld"
		var blade := Node3D.new()
		blade.name = "Machete"
		# Lying on its side, centred on the pickup
		blade.transform = Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(0, 0.03, 0.2))
		root.add_child(blade)
		blade.owner = root
		for part in ["Blade", "Spine", "Guard", "Handle", "Wrap"]:
			var src := held.get_node("Model/" + part) as MeshInstance3D
			var mi := MeshInstance3D.new()
			mi.name = part
			mi.mesh = src.mesh
			mi.material_override = src.material_override
			mi.transform = src.transform
			blade.add_child(mi)
			mi.owner = root
		var ps := PackedScene.new()
		ps.pack(root)
		ResourceSaver.save(ps, MODEL)
		held.free()
		root.free()
		print("wrote ", MODEL)
	if not ResourceLoader.exists(ITEM):
		var it := ItemDefinition.new()
		it.id = &"machete"
		it.display_name = "Machete"
		it.description = "A heavy blade with a taped grip. Quiet, and it never runs dry."
		it.category = ItemDefinition.Category.WEAPON
		it.max_stack = 1
		it.weight = 0.8
		it.base_value = 40
		it.world_model = load(MODEL)
		it.pickup_hold_time = 0.4
		var pistol := load("res://resources/items/weapons/pistol_item.tres") as ItemDefinition
		it.pickup_sound = pistol.pickup_sound
		it.weapon = load("res://resources/items/weapons/machete.tres")
		ResourceSaver.save(it, ITEM)
		print("wrote ", ITEM)
	quit()
