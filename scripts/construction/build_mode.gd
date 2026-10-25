class_name BuildMode
extends Node
## Build mode, on the local player (B to enter and leave).
##
##   Left click        place the selected structure where the ghost is
##   Mouse wheel / [ ] choose which kit to place (only kits you carry)
##   R                 rotate 15° (Shift+R the other way)
##   E                 repair the structure you're looking at
##   X                 dismantle the structure you're looking at
##   B                 leave build mode
##
## Shows a see-through ghost at the spot you look at: green if it can go
## there, red with the reason if not. Looking at a structure you've built
## shows its health and the repair/dismantle keys instead.
##
## This is the client side only: placing, repairing and dismantling all go
## through PlayerController.request_* (validated, host-side in co-op).
##
## Lives on the player: res://scenes/player/player.tscn → %BuildMode.

signal changed

var player: PlayerController
var active := false
var kits: Array[ItemDefinition] = []
var selected := 0
var yaw := 0.0
## Under the crosshair: a built structure (repair/dismantle) or null.
var target: Structure = null
var ghost_transform := Transform3D.IDENTITY
var ghost_reason := "Look at the ground"
var ghost_valid := false

var _ghost: Node3D
var _ghost_kit: ItemDefinition
var _mat_ok: StandardMaterial3D
var _mat_bad: StandardMaterial3D
var _last_wheel_msec := -1000


func _ready() -> void:
	player = get_parent() as PlayerController
	_mat_ok = _ghost_material(Color(0.35, 1.0, 0.45, 0.38))
	_mat_bad = _ghost_material(Color(1.0, 0.3, 0.25, 0.38))


static func _ghost_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# ---------------------------------------------------------------- control

func toggle() -> void:
	if active:
		exit()
	else:
		enter()


func enter() -> bool:
	if active or player == null or player.is_dead() or player.ladder != null:
		return false
	refresh_kits()
	if kits.is_empty():
		player.build_refused.emit("No structure kits: craft one first (K)")
		return false
	active = true
	player.building = true
	player.player_input.build_mode = true
	player.cancel_item_use()
	_rebuild_ghost()
	update_preview()
	changed.emit()
	return true


func exit() -> void:
	if not active:
		return
	active = false
	target = null
	if player != null:
		player.building = false
		player.player_input.build_mode = false
	_free_ghost()
	changed.emit()


func current_kit() -> ItemDefinition:
	return kits[selected] if selected >= 0 and selected < kits.size() else null


func select(direction: int) -> void:
	if kits.is_empty():
		return
	selected = wrapi(selected + direction, 0, kits.size())
	_rebuild_ghost()
	update_preview()
	changed.emit()


func rotate(steps: int = 1) -> void:
	yaw = wrapf(yaw + steps * ConstructionRules.ROTATE_STEP, 0.0, 360.0)
	update_preview()
	changed.emit()


## Places the selected kit at the ghost. Returns the structure or null.
func place() -> Structure:
	if not active:
		return null
	update_preview()
	var kit := current_kit()
	if kit == null or target != null:
		return null
	var s := player.request_place_structure(kit, ghost_transform)
	refresh_kits()
	if kits.is_empty():
		exit()
	else:
		_rebuild_ghost()
		update_preview()
	changed.emit()
	return s


func repair() -> bool:
	if not active or target == null:
		return false
	var ok := player.request_repair_structure(target)
	changed.emit()
	return ok


func dismantle() -> bool:
	if not active or target == null:
		return false
	var ok := player.request_dismantle_structure(target)
	target = null
	refresh_kits()
	changed.emit()
	return ok


## The kits in the inventory (one entry per kind), keeping the selection.
func refresh_kits() -> void:
	var before := current_kit()
	kits.clear()
	if player == null or player.inventory == null:
		return
	for i in player.inventory.slot_count:
		var item := player.inventory.get_slot_item(i)
		if item != null and item.structure != null and not kits.has(item):
			kits.append(item)
	kits.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool: return a.display_name < b.display_name)
	selected = maxi(kits.find(before), 0) if before != null else 0
	if selected >= kits.size():
		selected = 0


# ---------------------------------------------------------------- preview

## Works out what's under the crosshair and where the ghost goes.
func update_preview() -> void:
	if not active:
		return
	var kit := current_kit()
	var cam := player.camera
	var from := cam.global_position
	var forward := -cam.global_basis.z
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + forward * (ConstructionRules.REACH + 1.0), PhysicsLayers.WORLD_SOLID)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	target = Structure.from_collider(hit["collider"]) if not hit.is_empty() else null
	if target == null:
		# Low structures you walk through (spike traps) are on the
		# interactables layer: pick them out too
		q.collision_mask = PhysicsLayers.INTERACTABLES
		var low := space.intersect_ray(q)
		if not low.is_empty() and (hit.is_empty() or from.distance_to(low["position"]) < from.distance_to(hit["position"])):
			target = Structure.from_collider(low["collider"])
	if target != null or kit == null:
		_show_ghost(false)
		return
	# Where the ghost stands: the ground you look at, or the ground in front
	# of the wall you look at, or the ground at arm's length
	var point: Vector3
	if hit.is_empty():
		point = from + forward * ConstructionRules.REACH
	else:
		point = hit["position"]
		var normal: Vector3 = hit["normal"]
		if normal.y < 0.6:
			point += Vector3(normal.x, 0, normal.z).normalized() * (kit.structure.footprint.z * 0.5 + 0.1)
	var y := ConstructionRules.ground_y(space, point)
	if is_nan(y):
		ghost_valid = false
		ghost_reason = "Look at the ground"
		_show_ghost(false)
		return
	point.y = y
	# Face the structure across your view unless you've rotated it yourself
	var xform := ConstructionRules.snap(point, yaw + rad_to_deg(player.rotation.y))
	var gy := ConstructionRules.ground_y(space, xform.origin)
	if not is_nan(gy):
		xform.origin.y = gy
	ghost_transform = xform
	ghost_reason = player.place_refusal_reason(kit, xform)
	ghost_valid = ghost_reason == ""
	_show_ghost(true)


func _show_ghost(on: bool) -> void:
	if _ghost == null:
		return
	_ghost.visible = on
	if on:
		_ghost.global_transform = ghost_transform
		var m := _mat_ok if ghost_valid else _mat_bad
		for mi in _ghost.get_children():
			(mi as MeshInstance3D).material_override = m


func _rebuild_ghost() -> void:
	var kit := current_kit()
	if kit == _ghost_kit and _ghost != null:
		return
	_free_ghost()
	_ghost_kit = kit
	if kit == null:
		return
	_ghost = Node3D.new()
	_ghost.name = "BuildGhost"
	_ghost.top_level = true
	# Copy just the meshes (never instance the real scene into the world: it
	# would save itself and change the navmesh)
	var scene := (load(kit.structure.scene_path) as PackedScene).instantiate()
	_copy_meshes(scene, Transform3D.IDENTITY, _ghost)
	scene.free()
	player.add_child(_ghost)


func _copy_meshes(node: Node, parent_xform: Transform3D, into: Node3D) -> void:
	for c in node.get_children():
		var xf := parent_xform
		if c is Node3D:
			xf = parent_xform * (c as Node3D).transform
		if c is MeshInstance3D:
			var mi := MeshInstance3D.new()
			mi.mesh = (c as MeshInstance3D).mesh
			mi.transform = xf
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			into.add_child(mi)
		_copy_meshes(c, xf, into)


func _free_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
	_ghost = null
	_ghost_kit = null


# ---------------------------------------------------------------- HUD text

## One line for the HUD: the kit and count, or the targeted structure.
func title_text() -> String:
	if target != null:
		return "%s  ·  %d%%" % [target.definition.display_name, roundi(target.get_health_fraction() * 100.0)]
	var kit := current_kit()
	if kit == null:
		return "No kits"
	return "%s ×%d%s" % [kit.structure.display_name, player.inventory.count_of(kit.id), "   (%d/%d)" % [selected + 1, kits.size()] if kits.size() > 1 else ""]


## The second line: what's possible here, or why not.
func status_text() -> String:
	if target != null:
		var parts: PackedStringArray = []
		if target.is_damaged():
			parts.append("[E] Repair (%s)" % StructureDefinition.cost_text(target.definition.repair_cost))
		parts.append("[X] Dismantle (get back %s)" % StructureDefinition.cost_text(target.definition.dismantle_return))
		return "   ".join(parts)
	return "Click to build" if ghost_valid else ghost_reason


# ---------------------------------------------------------------- input

func _process(_delta: float) -> void:
	if not active:
		return
	if player.is_dead() or player.ladder != null or player.player_input.ui_open:
		exit()
		return
	update_preview()


func _input(event: InputEvent) -> void:
	if player == null or not player.controlled_locally or player.player_input.ui_open:
		return
	if event.is_action_pressed("build_mode"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not active or not player.player_input.is_mouse_captured():
		return
	if event is InputEventMouseButton and event.pressed and \
			(event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var now := Time.get_ticks_msec()
		if now - _last_wheel_msec > 180:  # a Magic Mouse swipe is one step
			_last_wheel_msec = now
			select(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_next"):
		select(1)
	elif event.is_action_pressed("build_previous"):
		select(-1)
	elif event.is_action_pressed("build_rotate"):
		rotate(-1 if (event as InputEventWithModifiers).shift_pressed else 1)
	elif event.is_action_pressed("fire"):
		place()
	elif event.is_action_pressed("interact"):
		repair()
	elif event.is_action_pressed("build_dismantle"):
		dismantle()
