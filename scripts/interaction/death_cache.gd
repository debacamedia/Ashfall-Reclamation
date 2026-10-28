class_name DeathCache
extends SalvageContainer
## Your gear, left where you died (Increment 16.6). When a player dies, the
## game mode moves everything in their backpack and every gun they carried
## (with its attachments and the rounds in its magazine) into one of these,
## and they come back with only their blade. Walk back and open it (no
## search) to take it all again. It shows on the compass, with a beam of
## light above it, and disappears once it's empty and closed.
##
## Saved like a pickup: recreated from its scene on load, and gone from a
## save once emptied. Several can exist (one per death).

const SCENE := "res://scenes/world/containers/death_cache.tscn"
## Never closer than this to the ash-storm edge (m), so fetching it is safe.
const EDGE_MARGIN := 12.0

## Weapon id -> {"attachments": [ids], "magazine": rounds}
var guns := {}


func _ready() -> void:
	is_searched = true
	search_time = 0.0
	super._ready()
	closed.connect(_on_closed)


func get_prompt(_interactor: Node3D) -> String:
	return "Open %s" % container_name


## Drops `player`'s gear at `at` (world space, usually where they fell) under
## `parent`, and takes it off them. Returns the cache, or null if they had
## nothing to drop. Runs on the authority (GameMode).
static func drop_for(player: PlayerController, parent: Node3D, at: Vector3) -> DeathCache:
	var stacks: Array = []  # [ItemDefinition, qty]
	if player.inventory != null:
		for i in player.inventory.slot_count:
			var item := player.inventory.get_slot_item(i)
			if item != null:
				stacks.append([item, player.inventory.get_slot_quantity(i)])
	var gun_states := {}
	if player.weapon_slots != null:
		for w in player.weapon_slots.owned():
			if w.definition.melee:
				continue
			var item := ItemDatabase.find_weapon_item(w.base_definition.id)
			if item == null:
				continue
			stacks.append([item, 1])
			var atts := []
			for slot in w.attachments:
				atts.append(String((w.attachments[slot] as AttachmentDefinition).id))
			gun_states[String(w.base_definition.id)] = {"attachments": atts, "magazine": w.ammo_in_magazine}
	if stacks.is_empty():
		return null
	var cache := (load(SCENE) as PackedScene).instantiate() as DeathCache
	cache.name = "DeathCache_%d" % (Time.get_ticks_usec() % 1000000000)
	cache.guns = gun_states
	var inv := cache.get_node("%Inventory") as InventoryComponent
	inv.slot_count = maxi(8, stacks.size())
	inv._resize()
	inv.max_weight = 0.0
	for s in stacks:
		inv.add_item(s[0], s[1])
	parent.add_child(cache)
	cache.global_position = resting_place(parent, at, player)
	cache.rotation.y = player.rotation.y
	# Now take it all off the player
	if player.inventory != null:
		player.inventory.clear()
	if player.weapon_slots != null:
		player.weapon_slots.remove_guns()
	return cache


## Where a cache dropped at `at` comes to rest: pulled back inside the zone
## if you died in the ash storm, then on the floor or ground below.
static func resting_place(parent: Node3D, at: Vector3, exclude: CollisionObject3D = null) -> Vector3:
	var p := at
	var edge := ZoneBoundary.find_in(parent.get_tree())
	if edge != null and edge.polygon.size() >= 3:
		var centre := Vector3.ZERO
		for v in edge.polygon:
			centre += Vector3(v.x, 0, v.y)
		centre /= edge.polygon.size()
		var steps := 0
		while edge.signed_distance(p) > -EDGE_MARGIN and steps < 400:
			var to := Vector3(centre.x - p.x, 0, centre.z - p.z)
			if to.length() < 1.0:
				break
			p += to.normalized()
			steps += 1
	var world := parent.get_world_3d()
	if world != null:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * 60.0, PhysicsLayers.WORLD_SOLID)
		if exclude != null:
			q.exclude = [exclude.get_rid()]
		var hit := world.direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			p = hit["position"]
	return p


## Puts a gun's attachments and loaded rounds back as they were.
func restore_gun(w: HitscanWeapon) -> void:
	var state: Variant = guns.get(String(w.base_definition.id))
	if not state is Dictionary:
		return
	for att_id in (state as Dictionary).get("attachments", []):
		var att := ItemDatabase.get_attachment(StringName(str(att_id)))
		if att != null and att.fits(w.base_definition.id):
			w.fit_attachment(att)
	var mag: Variant = (state as Dictionary).get("magazine")
	if mag is int or mag is float:
		w.cancel_reload()
		w.ammo_in_magazine = clampi(int(mag), 0, w.definition.magazine_size)
		w.ammo_changed.emit(w.ammo_in_magazine, w.reserve_ammo)
	guns.erase(String(w.base_definition.id))


func is_empty() -> bool:
	return inventory.get_free_slot_count() == inventory.slot_count


func _on_closed(_by: Node3D) -> void:
	if is_empty() and users.is_empty():
		queue_free()


# ---------------------------------------------------------------- saving

func save_state() -> Dictionary:
	var d := super.save_state()
	var p := global_position
	d["position"] = [p.x, p.y, p.z]
	d["yaw"] = rotation.y
	d["slots"] = inventory.slot_count
	d["guns"] = guns.duplicate(true)
	return d


func load_state(data: Dictionary) -> void:
	var slots: Variant = data.get("slots")
	if slots is int or slots is float:
		inventory.slot_count = clampi(int(slots), 1, 200)
		inventory._resize()
	super.load_state(data)
	is_searched = true
	_update_prompt()
	var raw: Variant = data.get("position")
	if raw is Array and raw.size() == 3 and raw.all(func(v: Variant) -> bool: return v is float or v is int):
		global_position = Vector3(raw[0], raw[1], raw[2])
	var yaw: Variant = data.get("yaw")
	if yaw is float or yaw is int:
		rotation.y = float(yaw)
	var g: Variant = data.get("guns")
	if g is Dictionary:
		guns = (g as Dictionary).duplicate(true)
	if is_empty():
		queue_free()


## Gone once emptied, so a save that doesn't list it removes it.
func is_save_removable() -> bool:
	return true
