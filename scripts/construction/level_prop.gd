class_name LevelProp
extends Structure
## One of a level's own props that you can move (F) or scrap (X) in build
## mode: fuel drums, crates, sandbag walls, jersey barriers, chain-link
## fences, the Pack 2 generator/radio/toolbox/water tank, and trucks (scrap
## only). Raiders don't break them.
##
## The script sits on the prop's scene root (often a StaticBody3D), so every
## copy in every level gets it. Props stay in the level when scrapped: they're
## hidden with their collision off and saved as "scrapped", so saves from
## before this update (which don't mention props) leave them all in place.
##
## Scenes: res://scenes/world/props/*.tscn, scenes/vehicles/military_truck.tscn,
## assets/ashfall_pack_v2/scenes/*.tscn. Definitions:
## res://resources/structures/props/*.tres.

var scrapped := false

var _layers := {}  # CollisionObject3D -> original collision_layer


func _ready() -> void:
	add_to_group("level_props")
	add_to_group("persist")
	_init_common()
	# Part of the baked navmesh already: no rebake until it's moved or scrapped


func _exit_tree() -> void:
	pass


func is_breakable() -> bool:
	return false


func apply_damage(_amount: float, _source: Node = null) -> void:
	pass  # set dressing: raiders walk round it, they don't chop it up


func take_down() -> void:
	scrap()


## Gone: hidden, no collision, out of the navmesh. Stays in the save.
func scrap() -> void:
	if scrapped:
		return
	scrapped = true
	visible = false
	for c in _collision_objects():
		_layers[c] = c.collision_layer
		c.collision_layer = 0
	if is_inside_tree():
		NavRebaker.request(self)


func _restore() -> void:
	scrapped = false
	visible = true
	for c in _layers:
		if is_instance_valid(c):
			(c as CollisionObject3D).collision_layer = _layers[c]
	_layers.clear()
	if is_inside_tree():
		NavRebaker.request(self)


func _collision_objects() -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	var me: Node = self
	if me is CollisionObject3D:
		out.append(me as CollisionObject3D)
	for c in find_children("*", "CollisionObject3D", true, false):
		out.append(c as CollisionObject3D)
	return out


func is_save_removable() -> bool:
	return false


func save_state() -> Dictionary:
	var data := super.save_state()
	data["scrapped"] = scrapped
	return data


func load_state(data: Dictionary) -> void:
	if data.get("scrapped") == true:
		scrap()
		return
	if scrapped:
		_restore()  # loading a save from before it was scrapped
	var o: Variant = data.get("origin")
	var b: Variant = data.get("basis")
	if o is Array and o.size() == 3 and b is Array and b.size() == 9 \
			and (o as Array).all(_is_number) and (b as Array).all(_is_number):
		var basis := Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])).orthonormalized()
		var t := Transform3D(basis, Vector3(o[0], o[1], o[2]))
		if not t.is_equal_approx(global_transform):
			global_transform = t
			NavRebaker.request(self)
