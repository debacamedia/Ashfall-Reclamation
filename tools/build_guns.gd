extends SceneTree
## Increment 30: real guns from Quaternius's Ultimate Gun Pack (CC0).
##
## 1. Makes each gun's mesh (assets/models/quaternius/guns/built/<key>.res)
##    from the pack's OBJ: its flat colours brought into the right colour
##    space (the OBJs' colours are linear, read as sRGB they come out nearly
##    black), metal shinier than wood; the marksman rifle with its built-in
##    scope cut off (the 4× scope is an attachment in the game).
## 2. Fits each into the game's gun scenes in place of the box models: the
##    muzzle where the old muzzle was, as long as the old gun, the bore at
##    the old bore's height; the iron sights, sight anchor and mounts moved
##    onto the new gun's top and underside. The same in the gun's world
##    model (lying on the ground, and the inventory icon).
## 3. The 4× scope, suppressor and foregrip attachments from the pack.
##
##   godot --headless --path . -s res://tools/build_guns.gd
## then (in a window) tools/render_item_icons.gd for the guns' icons.

const SRC := "res://assets/models/quaternius/guns/"
const OUT := "res://assets/models/quaternius/guns/built/"

## key: [pack model, cut away triangles reaching above this height (model
## units; INF none), x range of the cut]
const MESHES := {
	"pistol": ["Pistol_2", INF, Vector2.ZERO],
	"shotgun": ["Shotgun_3", INF, Vector2.ZERO],
	"service_rifle": ["AssaultRifle_2", INF, Vector2.ZERO],
	"scoped_rifle": ["SniperRifle_6", 0.30, Vector2(-0.3, 2.5)],
	"scope": ["accessories/Scope_1", INF, Vector2.ZERO],
	"suppressor": ["accessories/Silencer_1", INF, Vector2.ZERO],
	"grip": ["accessories/Grip", INF, Vector2.ZERO],
}

## Gun scene, its world model, the mesh key. Extra Model children kept as
## part of the sights (the shotgun's bead).
const GUNS := {
	"pistol": ["res://scenes/weapons/pistol.tscn", "res://scenes/items/models/pistol_world.tscn", []],
	"shotgun": ["res://scenes/weapons/shotgun.tscn", "res://scenes/items/models/shotgun_world.tscn", ["Bead"]],
	"service_rifle": ["res://scenes/weapons/service_rifle.tscn", "res://scenes/items/models/service_rifle_world.tscn", []],
	"scoped_rifle": ["res://scenes/weapons/scoped_rifle.tscn", "res://scenes/items/models/scoped_rifle_world.tscn", []],
}

## Kept in a gun's Model: markers and what hangs off them
const KEEP := ["Muzzle", "IronSights", "SightAnchor", "OpticMount", "MuzzleMount", "UnderMount"]
## Clear air between the gun's top and the sight line (m)
const SIGHT_CLEARANCE := 0.004

var _mats := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for key: String in MESHES:
		var spec: Array = MESHES[key]
		var m := _prepare(load(SRC + String(spec[0]) + ".obj") as ArrayMesh, spec[1], spec[2])
		var err := ResourceSaver.save(m, OUT + key + ".res")
		print(key, ": ", error_string(err), " ", m.get_aabb().size)
	for key: String in GUNS:
		_fit_gun(key)
	_attachments()
	quit()


# ---------------------------------------------------------------- meshes

## The pack's mesh with good materials, and anything above `cut` (inside
## the x range) removed.
func _prepare(src: ArrayMesh, cut: float, cut_x: Vector2) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		if cut < INF:
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx.resize(v.size())
				for i in v.size():
					idx[i] = i
			var keep := PackedInt32Array()
			for t in range(0, idx.size(), 3):
				var a := v[idx[t]]
				var b := v[idx[t + 1]]
				var c := v[idx[t + 2]]
				var above := maxf(a.y, maxf(b.y, c.y)) > cut
				var inside := minf(a.x, minf(b.x, c.x)) > cut_x.x and maxf(a.x, maxf(b.x, c.x)) < cut_x.y
				if not (above and inside):
					keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			if keep.is_empty():
				continue
			# Only the vertices still used (so the bounds are the cut gun's)
			var remap := {}
			var order := PackedInt32Array()
			for i in keep.size():
				if not remap.has(keep[i]):
					remap[keep[i]] = order.size()
					order.append(keep[i])
				keep[i] = remap[keep[i]]
			for k in Mesh.ARRAY_MAX:
				if k == Mesh.ARRAY_INDEX or arrays[k] == null:
					continue
				var src_arr: Variant = arrays[k]
				var stride: int = src_arr.size() / v.size()
				var dst: Variant = src_arr.duplicate()
				dst.resize(order.size() * stride)
				for i in order.size():
					for j in stride:
						dst[i * stride + j] = src_arr[order[i] * stride + j]
				arrays[k] = dst
			arrays[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, _material(src.surface_get_material(s)))
	return out


## The OBJ's colour (Kd) is linear; Godot's importer took it as sRGB.
func _material(src: Material) -> StandardMaterial3D:
	var name := src.resource_name if src != null else "Metal"
	var kd := (src as StandardMaterial3D).albedo_color if src is StandardMaterial3D else Color(0.05, 0.05, 0.05)
	var key := "%s_%s" % [name, kd.to_html(false)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.resource_name = name
	var c := kd.linear_to_srgb()
	m.albedo_color = Color(c.r, c.g, c.b, 1.0)
	var n := name.to_lower()
	if n.contains("glass"):
		m.albedo_color = Color(0.12, 0.16, 0.2)
		m.metallic = 0.3
		m.roughness = 0.15
	elif n.contains("metal") or n.contains("grey"):
		m.metallic = 0.55
		m.roughness = 0.45
	elif n.contains("wood") or n == "green":
		m.roughness = 0.8
	else:
		m.metallic = 0.2
		m.roughness = 0.6
	_mats[key] = m
	return m


# ---------------------------------------------------------------- guns

func _fit_gun(key: String) -> void:
	var spec: Array = GUNS[key]
	var mesh := load(OUT + key + ".res") as ArrayMesh
	var scene := (load(spec[0]) as PackedScene).instantiate() as Node3D
	var model := scene.get_node("Model") as Node3D
	var keep: Array = KEEP + (spec[2] as Array)
	# How big the old gun was, and where its bore and sights were
	var old := AABB()
	var first := true
	for c in model.get_children():
		if c is MeshInstance3D and not (String(c.name) in keep):
			var box := _bounds(c as MeshInstance3D, model)
			old = box if first else old.merge(box)
			first = false
	var muzzle := model.get_node("Muzzle") as Node3D
	var sight := model.get_node("SightAnchor") as Node3D
	var fit := _fit(mesh, old, muzzle.position)
	# Out with the boxes, in with the gun
	for c in model.get_children():
		if c is MeshInstance3D and not (String(c.name) in keep):
			model.remove_child(c)
			c.free()
	var gun := MeshInstance3D.new()
	gun.name = "Gun"
	gun.mesh = mesh
	gun.transform = fit
	gun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(gun)
	model.move_child(gun, 0)
	gun.owner = scene
	# The sight line over the new gun's top, between the rear sight and the
	# muzzle; the iron sights, the anchor (and the bead) lifted or lowered
	# onto it
	var pts := _points(mesh, fit)
	var rear_z := sight.position.z
	var top := -INF
	for p in pts:
		if p.z < rear_z + 0.01 and p.z > muzzle.position.z + 0.01 and absf(p.x) < 0.03:
			top = maxf(top, p.y)
	var line := top + SIGHT_CLEARANCE + 0.006
	var dy := line - sight.position.y
	sight.position.y += dy
	var sights := model.get_node_or_null("IronSights") as Node3D
	if sights != null:
		sights.position.y += dy
	for n: String in spec[2]:
		(model.get_node(n) as Node3D).position.y += dy
	# The optic sits on the top where it's mounted, the underbarrel under
	# the gun where it's mounted
	var optic := model.get_node_or_null("OpticMount") as Node3D
	if optic != null:
		optic.position.y = _top_at(pts, optic.position.z, 0.08)
	var under := model.get_node_or_null("UnderMount") as Node3D
	if under != null:
		under.position.y = _bottom_at(pts, under.position.z, 0.04)
	print("%s: scale %.4f, sight line %+.3f m (was %.3f), optic %s, under %s" % [key, fit.basis.get_scale().x, line, line - dy,
		optic.position if optic else "-", under.position if under else "-"])
	_save(scene, spec[0])
	# The world model: the gun as it lies (its Gun node keeps its own turn
	# and scale)
	var world := (load(spec[1]) as PackedScene).instantiate() as Node3D
	var holder := world.get_node("Gun") as Node3D
	for c in holder.get_children():
		holder.remove_child(c)
		c.free()
	var wg := MeshInstance3D.new()
	wg.name = "Model"
	wg.mesh = mesh
	wg.transform = fit
	holder.add_child(wg)
	wg.owner = world
	_save(world, spec[1])


## The transform putting `mesh` (muzzle along +X) where the old gun was:
## muzzle forward (-Z) at the old muzzle, as long as the old gun, the bore
## at the old bore's height.
func _fit(mesh: ArrayMesh, old: AABB, muzzle: Vector3) -> Transform3D:
	var a := mesh.get_aabb()
	var length := old.size.z
	var s := length / a.size.x
	var basis := Basis(Vector3.UP, PI / 2.0).scaled(Vector3.ONE * s)
	# The bore: the middle of what's at the very muzzle
	var tip := a.position.x + a.size.x
	var lo := INF
	var hi := -INF
	for p in _points(mesh, Transform3D.IDENTITY):
		if p.x > tip - a.size.x * 0.02:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
	var bore := Vector3(tip, (lo + hi) / 2.0, a.get_center().z)
	var origin := muzzle - basis * bore
	return Transform3D(basis, origin)


func _points(mesh: ArrayMesh, xf: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in mesh.get_surface_count():
		for p: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			out.append(xf * p)
	return out


func _top_at(pts: PackedVector3Array, z: float, reach: float) -> float:
	var y := -INF
	for p in pts:
		if absf(p.z - z) < reach and absf(p.x) < 0.03:
			y = maxf(y, p.y)
	return y


func _bottom_at(pts: PackedVector3Array, z: float, reach: float) -> float:
	var y := INF
	for p in pts:
		if absf(p.z - z) < reach and absf(p.x) < 0.03:
			y = minf(y, p.y)
	return y


func _bounds(mi: MeshInstance3D, space: Node3D) -> AABB:
	var xf := space.global_transform.affine_inverse() * mi.global_transform if mi.is_inside_tree() else _rel(mi, space)
	return xf * mi.mesh.get_aabb()


func _rel(n: Node3D, space: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != space:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


# ---------------------------------------------------------------- attachments

func _attachments() -> void:
	# 4× scope: the pack's scope along the old tube, the eye at its back
	_swap_attachment("res://scenes/weapons/attachments/scope_4x.tscn", "scope", ["Sight"])
	_swap_attachment("res://scenes/items/models/scope_4x_item.tscn", "scope", [])
	_swap_attachment("res://scenes/weapons/attachments/suppressor.tscn", "suppressor", [])
	_swap_attachment("res://scenes/items/models/suppressor_item.tscn", "suppressor", [])
	_swap_attachment("res://scenes/weapons/attachments/foregrip.tscn", "grip", [])
	_swap_attachment("res://scenes/items/models/foregrip_item.tscn", "grip", [])


## Replaces an attachment scene's box meshes with the pack's, fitted to the
## boxes' bounds (as long, front and back in the same places; the grip as
## tall). The scope's Sight marker moves onto its tube's axis.
func _swap_attachment(path: String, key: String, keep: Array) -> void:
	if not ResourceLoader.exists(path):
		print("no ", path)
		return
	var scene := (load(path) as PackedScene).instantiate() as Node3D
	var holder: Node3D = scene
	# Item models hold the attachment under one node
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		scene.free()
		return
	holder = (meshes[0] as Node).get_parent() as Node3D
	var old := AABB()
	var first := true
	for c in holder.get_children():
		if c is MeshInstance3D:
			var box := (c as MeshInstance3D).transform * (c as MeshInstance3D).mesh.get_aabb()
			old = box if first else old.merge(box)
			first = false
	for c in holder.get_children():
		if c is MeshInstance3D:
			holder.remove_child(c)
			c.free()
	var mesh := load(OUT + key + ".res") as ArrayMesh
	var a := mesh.get_aabb()
	var xf: Transform3D
	if key == "grip":
		# Upright: as tall as the old grip, hanging from the mount
		var s := old.size.y / a.size.y
		xf = Transform3D(Basis(Vector3.UP, PI / 2.0).scaled(Vector3.ONE * s), Vector3.ZERO)
		xf.origin = Vector3(0, old.position.y + old.size.y, old.get_center().z) - xf.basis * Vector3(a.get_center().x, a.position.y + a.size.y, a.get_center().z)
	else:
		# Lengthwise (+X forward becomes -Z): the front where the old front was
		var s := old.size.z / a.size.x
		xf = Transform3D(Basis(Vector3.UP, PI / 2.0).scaled(Vector3.ONE * s), Vector3.ZERO)
		# (the scope sits on its mounts' base)
		var axis_y := old.position.y if key == "scope" else old.get_center().y
		xf.origin = Vector3(0, axis_y, old.position.z) - xf.basis * Vector3(a.position.x + a.size.x, _axis_y(mesh, key), a.get_center().z)
	var mi := MeshInstance3D.new()
	mi.name = "Model"
	mi.mesh = mesh
	mi.transform = xf
	holder.add_child(mi)
	mi.owner = scene
	if key == "scope":
		var sight := scene.get_node_or_null("Sight") as Node3D
		if sight != null:
			var eye := xf * Vector3(a.position.x, _scope_axis(mesh), a.get_center().z)
			sight.position = Vector3(0, eye.y, eye.z + 0.01)
	print(path.get_file(), ": fitted to ", old.size)
	_save(scene, path)


## Height of a scope's tube axis (model units): the middle of the eyepiece.
func _scope_axis(mesh: ArrayMesh) -> float:
	var a := mesh.get_aabb()
	var lo := INF
	var hi := -INF
	for p in _points(mesh, Transform3D.IDENTITY):
		if p.x < a.position.x + a.size.x * 0.05:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
	return (lo + hi) / 2.0


func _axis_y(mesh: ArrayMesh, key: String) -> float:
	if key == "scope":
		return mesh.get_aabb().position.y
	return mesh.get_aabb().get_center().y


func _save(scene: Node, path: String) -> void:
	for n in scene.find_children("*", "", true, false):
		if n.owner == null:
			n.owner = scene
	var packed := PackedScene.new()
	var err := packed.pack(scene)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("  wrote ", path, ": ", error_string(err))
	scene.free()
