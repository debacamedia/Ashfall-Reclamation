extends "res://tests/test_case.gd"
## Increment 30: real guns and farm buildings. The player's guns, their
## attachments, guns on the ground and in settlers' hands are Quaternius's
## Ultimate Gun Pack (CC0); Ash Creek's silo, a wind pump and the chicken
## pen's hen house are his Farm Buildings (CC0).

const GUNS := "res://assets/models/quaternius/guns/"
const FARM := "res://assets/models/quaternius/farm/"
const SCENES := {
	"pistol": "res://scenes/weapons/pistol.tscn",
	"shotgun": "res://scenes/weapons/shotgun.tscn",
	"service_rifle": "res://scenes/weapons/service_rifle.tscn",
	"scoped_rifle": "res://scenes/weapons/scoped_rifle.tscn",
}


func _gun_points(model: Node3D) -> PackedVector3Array:
	var g := model.get_node("Gun") as MeshInstance3D
	var out := PackedVector3Array()
	for s in g.mesh.get_surface_count():
		var arrays := g.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i: int in arrays[Mesh.ARRAY_INDEX]:
			out.append(g.transform * v[i])
	return out


func test_the_packs() -> void:
	for f in [GUNS + "LICENSE_Ultimate_Gun_Pack.txt", FARM + "LICENSE_Farm_Buildings.txt"]:
		check(FileAccess.get_file_as_string(f).contains("CC0"), "%s: CC0 (free in a game that's sold)" % f.get_file())
	var register := FileAccess.get_file_as_string("res://docs/ASSET_LICENSES.md")
	check(register.contains("Ultimate Gun Pack") and register.contains("Farm Buildings"), "both in the asset licence register")
	# The OBJs' colours were linear: the made-ready guns aren't near black
	var wood := 0.0
	for s in (load(GUNS + "built/service_rifle.res") as ArrayMesh).get_surface_count():
		var m := (load(GUNS + "built/service_rifle.res") as ArrayMesh).surface_get_material(s) as StandardMaterial3D
		if m.resource_name.to_lower().contains("wood"):
			wood = maxf(wood, m.albedo_color.get_luminance())
	check(wood > 0.2, "the rifle's wood is brown, not black (%.2f)" % wood)
	# The marksman rifle's own scope is cut off (the 4× scope is fitted)
	var mr := load(GUNS + "built/scoped_rifle.res") as ArrayMesh
	var glass := false
	for s in mr.get_surface_count():
		glass = glass or mr.surface_get_material(s).resource_name == "Glass"
	check(not glass and mr.get_aabb().size.y < 1.3, "the marksman rifle without its built-in scope")


func test_guns_fitted() -> void:
	for key: String in SCENES:
		var w := (load(SCENES[key]) as PackedScene).instantiate() as Node3D
		var model := w.get_node("Model") as Node3D
		var boxes := model.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D and c.name != "Gun" and (c.get_meta("keep", false) == false) and c.name != "Bead")
		check(model.has_node("Gun") and boxes.is_empty(), "%s: the pack's gun, no boxes left (%s)" % [key, boxes.map(func(c: Node) -> String: return c.name)])
		var pts := _gun_points(model)
		var front := INF
		var back := -INF
		for p in pts:
			front = minf(front, p.z)
			back = maxf(back, p.z)
		var muzzle := (model.get_node("Muzzle") as Node3D).position
		check(absf(front - muzzle.z) < 0.02, "%s: the muzzle at the gun's front (%.3f v %.3f)" % [key, front, muzzle.z])
		# The sight line clears the gun between the rear sight and the muzzle
		var sight := (model.get_node("SightAnchor") as Node3D).position
		var blocking := 0
		for p in pts:
			if p.z < sight.z and p.z > muzzle.z + 0.02 and absf(p.x) < 0.01 and p.y > sight.y:
				blocking += 1
		check(blocking == 0, "%s: nothing of the gun stands above the sight line (%d points)" % [key, blocking])
		check(back - front > 0.2, "%s: a gun's length (%.2f m)" % [key, back - front])
		w.free()


func test_attachments_and_the_ground() -> void:
	for path in ["res://scenes/weapons/attachments/scope_4x.tscn", "res://scenes/weapons/attachments/suppressor.tscn", "res://scenes/weapons/attachments/foregrip.tscn"]:
		var a := (load(path) as PackedScene).instantiate() as Node3D
		var meshes := a.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() == 1 and (meshes[0] as MeshInstance3D).mesh.resource_path.begins_with(GUNS + "built/"), "%s: the pack's model" % path.get_file())
		if path.contains("scope"):
			var sight := a.get_node("Sight") as Node3D
			var box := (meshes[0] as MeshInstance3D).transform * (meshes[0] as MeshInstance3D).mesh.get_aabb()
			check(sight.position.y > box.position.y and sight.position.y < box.position.y + box.size.y and sight.position.z >= box.position.z + box.size.z - 0.02,
				"the scope's eye on its tube, at the back (%s in %s)" % [sight.position, box])
		a.free()
	for id in ["service_rifle", "pistol", "shotgun", "scoped_rifle"]:
		var item := ItemDatabase.get_item(StringName(id))
		var m := item.world_model.instantiate() as Node3D
		var g := m.find_child("Model", true, false) as MeshInstance3D
		check(g != null and g.mesh.resource_path == GUNS + "built/%s.res" % id, "%s on the ground: the pack's gun" % id)
		m.free()
	# In use: a rifle with its scope, suppressor and grip fitted
	var rifle := (load(SCENES["service_rifle"]) as PackedScene).instantiate() as HitscanWeapon
	add_child(rifle)
	for att in ["scope_4x", "suppressor", "foregrip"]:
		rifle.fit_attachment(ItemDatabase.get_attachment(StringName(att)))
	await wait_physics(2)
	check(rifle.get_sight_node().name == "Sight" and not rifle.get_node("%IronSights").visible, "scoped: the eye at the scope, iron sights put away")
	var muzzle := rifle.get_node("%MuzzleMount").get_child(0) as Node3D
	check(muzzle != null and muzzle.find_children("*", "MeshInstance3D", true, false).size() == 1, "the suppressor on the muzzle")
	rifle.queue_free()


func test_settlers_and_the_farm() -> void:
	# A guard's rifle is the pack's
	var s := (load("res://scenes/npcs/settler.tscn") as PackedScene).instantiate() as Settler
	add_child(s)
	s.role = Settler.Role.GUARD
	s.arm(load("res://resources/items/weapons/service_rifle_item.tres"), 30)
	s.set_physics_process(false)
	await wait_physics(2)
	var r := s.part("Gun").get_node_or_null("Rifle") as MeshInstance3D
	check(r != null and r.mesh.resource_path == GUNS + "built/service_rifle.res" and s.part("Gun").visible, "a guard carries the pack's rifle")
	var length := (r.transform * r.mesh.get_aabb()).size.z
	check_between(length, 0.7, 0.9, "a rifle's length (%.2f m)" % length)
	s.queue_free()
	# Ash Creek: the silo and a wind pump
	var farm := (load("res://levels/ash_creek_farms/ash_creek_farms.tscn") as PackedScene).instantiate() as Node3D
	var silo := farm.find_child("Silo", true, false) as Node3D
	var body := silo.get_node("Body") as MeshInstance3D
	check(body.mesh.resource_path == FARM + "built/silo.res" and silo.has_node("BodyCol"), "Ash Creek's silo: the pack's, as solid as before")
	var pump := farm.find_child("WindPump", true, false) as Node3D
	check(pump != null and (pump.get_node("Tower") as MeshInstance3D).mesh.resource_path == FARM + "built/windmill.res" and pump.has_node("TowerCol"),
		"a wind pump by the pump house, its legs solid")
	farm.free()
	# The chicken pen's hen house
	var pen := (load("res://scenes/settlement/chicken_coop.tscn") as PackedScene).instantiate() as Node3D
	var hen := pen.find_child("HenHouse", true, false) as MeshInstance3D
	check(hen != null and hen.mesh.resource_path == FARM + "built/chicken_coop.res" and pen.find_child("HenHouseCol", true, false) != null,
		"the chicken pen's hen house is the pack's coop, still solid")
	pen.free()
