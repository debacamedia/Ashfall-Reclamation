extends SceneTree
## Builds the Scorch Marauder (Increment 26): the mid zone's tougher raider,
## from the Raider Veteran. Scrap plate on its chest, shoulders and head
## takes a quarter off bullets, blows and blasts (Raider.armour); it's
## tougher, hits harder, sees and hears further, and always drops loot,
## sometimes a piece of armour.
##
##     godot --headless --path . -s res://tools/build_marauder.gd
##
## Writes scenes/enemies/raider_marauder.tscn.

const FROM := "res://scenes/enemies/raider_veteran.tscn"
const OUT := "res://scenes/enemies/raider_marauder.tscn"
const DROPS := ["rifle_ammo", "rifle_ammo", "shotgun_shells", "gunpowder", "metal_plate", "leather",
	"gun_barrel", "trigger_group", "medkit", "canned_beans", "scrap_helmet", "pistol_ammo"]


func _initialize() -> void:
	var r := (load(FROM) as PackedScene).instantiate() as Raider
	r.name = "RaiderMarauder"
	r.display_name = "Scorch Marauder"
	r.run_speed = 5.6
	r.sight_range = 42.0
	r.hearing_multiplier = 1.4
	r.attack_damage = 34.0
	r.attack_windup = 0.38
	r.armour = 0.25
	r.drop_chance = 1.0
	r.drop_min = 1
	r.drop_max = 3
	var drops: Array[ItemDefinition] = []
	for id in DROPS:
		var item := load("res://resources/items/%s.tres" % id) as ItemDefinition
		assert(item != null, id)
		drops.append(item)
	r.drop_items = drops
	(r.get_node("HealthComponent") as HealthComponent).max_health = 260.0
	# Scorch colours: soot-black clothes, rust-red plate
	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color(0.42, 0.17, 0.09)
	plate.metallic = 0.5
	plate.roughness = 0.6
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.62, 0.12, 0.06)
	# (29: on the Veteran's HumanBody) soot-black clothes, the plate and
	# pads rust-red, the bandana red; plates on both shoulders, a scrap helmet
	var body := r.get_node("Visual/Body") as HumanBody
	body.shirt = Color(0.13, 0.11, 0.1)
	body.trousers = Color(0.11, 0.1, 0.09)
	body.colour_jitter = 0.1
	body.cloth_tint = Color(0.3, 0.28, 0.27)  # 29.1: soot-black clothes
	# 29.1: rust-red pauldrons (the Veteran's) for the shoulder plates
	body.pauldron_tint = Color(0.85, 0.42, 0.3)
	for n in ["KneePadLeft", "KneePadRight"]:
		for mi in body.get_node(n).find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = plate
	for mi in body.get_node("Bandana").find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = red
	var helmet := Node3D.new()
	helmet.name = "ScrapHelmet"
	helmet.set_meta("slot", "Head")
	helmet.position = Vector3(0, 0.165, 0.02)
	body.add_child(helmet)
	var hmi := MeshInstance3D.new()
	hmi.name = "Shell"
	var hm := BoxMesh.new()
	hm.size = Vector3(0.2, 0.08, 0.23)
	hmi.mesh = hm
	hmi.material_override = plate
	helmet.add_child(hmi)
	_own(r, r)
	var packed := PackedScene.new()
	assert(packed.pack(r) == OK)
	assert(ResourceSaver.save(packed, OUT) == OK)
	r.free()
	print("wrote ", OUT)
	quit()


func _own(node: Node, owner_root: Node) -> void:
	for c in node.get_children():
		if c.owner == null:
			c.owner = owner_root
		_own(c, owner_root)
