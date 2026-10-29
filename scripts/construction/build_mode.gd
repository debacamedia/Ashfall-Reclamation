class_name BuildMode
extends Node
## Build mode, on the local player (B to enter and leave).
##
##   Left click        place the selected structure where the ghost is
##   Mouse wheel / [ ] choose which kit to place (only kits you carry)
##   R                 rotate 15° (Shift+R the other way). When the ghost has
##                     snapped onto a wall's end, this is the angle of the
##                     joint: 0° straight on, 45°, 90°...
##   V                 choose the variant (wall / window / doorway, ladder height)
##   F                 pick up the structure you're looking at and move it
##                     (click to put it down, F again to cancel)
##   E                 repair the structure you're looking at
##   X                 dismantle the structure you're looking at (within 30 s
##                     of placing it, undamaged: you get the kit back)
##   B                 leave build mode
##
## Inside a settlement you hold, the list also has its buildings
## (Increment 19.6: bunkhouse, storehouse, guard tower, guard post, farm
## plot): placing one plans it, as a ConstructionSite your Builders put up
## once it has its materials. Nothing is used from your backpack.
##
## Shows a see-through ghost at the spot you look at: green if it can go
## there, red with the reason if not. Looking at a structure you've built
## shows its health and the move/repair/dismantle keys instead.
##
## You can enter build mode with kits to place, or with none to move, repair
## or dismantle what's already built. The level's own props (barrels,
## fences, trucks...) can be moved (F) and scrapped (X) the same way.
##
## Snapping: walls, fences and barricades hinge onto the end of one already
## built; platforms join edge to edge (or stack); stairs and ladders go
## against a platform's edge. See ConstructionRules.snap_to_built.
##
## This is the client side only: placing, moving, repairing and dismantling
## all go through PlayerController.request_* (validated, host-side in co-op).
##
## Lives on the player: res://scenes/player/player.tscn → %BuildMode.

signal changed

var player: PlayerController
var active := false
var kits: Array[ItemDefinition] = []
## Settlement buildings you can plan here (after the kits in the list).
var plans: Array[StringName] = []
var selected := 0
var yaw := 0.0
## Under the crosshair: a built structure (move/repair/dismantle) or null.
var target: Structure = null
## The structure being moved (picked up with F), or null.
var moving: Structure = null
## What the ghost has snapped onto this frame (or null).
var snapped_to: Structure = null
## Chosen variant index per kit (V).
var _variant := {}
var ghost_transform := Transform3D.IDENTITY
var ghost_reason := "Look at the ground"
var ghost_valid := false

var _ghost: Node3D
var _ghost_def: StructureDefinition
var _mat_ok: StandardMaterial3D
var _mat_bad: StandardMaterial3D
var _scroll := ScrollStepper.new()


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
	if active or player == null or player.is_dead() or player.ladder != null or player.vehicle != null:
		return false
	refresh_kits()
	var root := ConstructionRules.structures_root(player.get_parent())
	if kits.is_empty() and plans.is_empty() and (root == null or root.get_child_count() == 0) and not _level_has_props():
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


func _level_has_props() -> bool:
	for n in get_tree().get_nodes_in_group("level_props"):
		if player.get_parent().is_ancestor_of(n):
			return true
	return false


func exit() -> void:
	if not active:
		return
	cancel_move()
	active = false
	target = null
	if player != null:
		player.building = false
		player.player_input.build_mode = false
	_free_ghost()
	changed.emit()


func current_kit() -> ItemDefinition:
	return kits[selected] if selected >= 0 and selected < kits.size() else null


## The settlement building selected (or &"" when it's a kit or nothing).
func current_plan() -> StringName:
	var i := selected - kits.size()
	return plans[i] if i >= 0 and i < plans.size() else &""


func entry_count() -> int:
	return kits.size() + plans.size()


func select(direction: int) -> void:
	if entry_count() == 0 or moving != null:
		return
	selected = wrapi(selected + direction, 0, entry_count())
	yaw = 0.0
	_rebuild_ghost()
	update_preview()
	changed.emit()


func rotate(steps: int = 1) -> void:
	yaw = wrapf(yaw + steps * ConstructionRules.ROTATE_STEP, 0.0, 360.0)
	update_preview()
	changed.emit()


## The variant of the selected kit that will be placed (or null).
func current_variant() -> StructureDefinition:
	var kit := current_kit()
	if kit == null or kit.structure == null:
		return null
	var vs := kit.structure.get_variants()
	return vs[clampi(int(_variant.get(kit, 0)), 0, vs.size() - 1)]


## Next variant of the selected kit (V).
func cycle_variant() -> void:
	var kit := current_kit()
	if kit == null or moving != null or kit.structure.get_variants().size() < 2:
		return
	_variant[kit] = wrapi(int(_variant.get(kit, 0)) + 1, 0, kit.structure.get_variants().size())
	_rebuild_ghost()
	update_preview()
	changed.emit()


## Places the selected kit at the ghost, or puts down the structure being
## moved. Returns the structure, or null if nothing happened.
func place() -> Structure:
	if not active:
		return null
	update_preview()
	if moving != null:
		var m := moving
		if not player.request_move_structure(m, ghost_transform):
			return null
		_end_move()
		changed.emit()
		return m
	var plan := current_plan()
	if plan != &"":
		if target == null:
			player.request_place_site(plan, ghost_transform)
			update_preview()
			changed.emit()
		return null
	var kit := current_kit()
	if kit == null or target != null:
		return null
	var s := player.request_place_structure(kit, ghost_transform, current_variant())
	refresh_kits()
	if entry_count() == 0:
		exit()
	else:
		_rebuild_ghost()
		update_preview()
	changed.emit()
	return s


## Picks up the targeted structure: the ghost becomes it until you click
## to put it down (or F / B to cancel). Its damage and contents come along.
func start_move() -> bool:
	if not active or moving != null or target == null:
		return false
	var reason := "Can't move that" if target.definition == null or not target.definition.movable else target.move_block_reason()
	if reason != "":
		player.build_refused.emit(reason)
		return false
	moving = target
	target = null
	# Keep its facing: the ghost yaw is relative to the way you look
	yaw = wrapf(snappedf(rad_to_deg(moving.global_rotation.y - player.rotation.y), ConstructionRules.ROTATE_STEP), 0.0, 360.0)
	moving.get_visual_root().visible = false
	_rebuild_ghost()
	update_preview()
	changed.emit()
	return true


## Puts the structure back where it was.
func cancel_move() -> void:
	if moving == null:
		return
	_end_move()
	changed.emit()


func _end_move() -> void:
	if is_instance_valid(moving):
		moving.get_visual_root().visible = true
	moving = null
	yaw = 0.0
	_rebuild_ghost()
	update_preview()


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
	_rebuild_ghost()
	changed.emit()
	return ok


## The kits in the inventory (one entry per kind), then the settlement
## buildings you can plan where you stand, keeping the selection.
func refresh_kits() -> void:
	var before := current_kit()
	var before_plan := current_plan()
	kits.clear()
	plans.clear()
	if player == null or player.inventory == null:
		return
	for i in player.inventory.slot_count:
		var item := player.inventory.get_slot_item(i)
		if item != null and item.structure != null and not kits.has(item):
			kits.append(item)
	kits.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool: return a.display_name < b.display_name)
	if player.is_inside_tree() and player.settlement_at(player.global_position) != null:
		plans = SettlementPlans.placeable()
	selected = maxi(kits.find(before), 0) if before != null else 0
	if before_plan != &"" and plans.has(before_plan):
		selected = kits.size() + plans.find(before_plan)
	if selected >= entry_count():
		selected = 0


# ---------------------------------------------------------------- preview

## The definition the ghost shows: the structure being moved, or the kit's.
func ghost_definition() -> StructureDefinition:
	if moving != null:
		return moving.definition
	if current_plan() != &"":
		return SettlementPlans.structure(current_plan())
	return current_variant()


## Works out what's under the crosshair and where the ghost goes.
func update_preview() -> void:
	if not active:
		return
	var def := ghost_definition()
	var cam := player.camera
	var from := cam.global_position
	var forward := -cam.global_basis.z
	var space := player.get_world_3d().direct_space_state
	var exclude: Array[RID] = [player.get_rid()]
	if moving != null:
		exclude.append_array(moving.get_collision_rids())
	var plan := current_plan() if moving == null else &""
	var reach := Settlement.PLAN_REACH if plan != &"" else ConstructionRules.REACH
	var q := PhysicsRayQueryParameters3D.create(from, from + forward * (reach + 1.0), PhysicsLayers.WORLD_SOLID, exclude)
	var hit := space.intersect_ray(q)
	target = null
	if moving == null:
		target = Structure.from_collider(hit["collider"]) if not hit.is_empty() else null
		if target == null:
			# Low structures you walk through (spike traps) are on the
			# interactables layer: pick them out too
			q.collision_mask = PhysicsLayers.INTERACTABLES
			var low := space.intersect_ray(q)
			if not low.is_empty() and (hit.is_empty() or from.distance_to(low["position"]) < from.distance_to(hit["position"])):
				target = Structure.from_collider(low["collider"])
	if target != null or def == null:
		_show_ghost(false)
		return
	# Where the ghost stands: the ground you look at, or the ground in front
	# of the wall you look at, or the ground at arm's length
	var point: Vector3
	if hit.is_empty():
		point = from + forward * reach
	else:
		point = hit["position"]
		var normal: Vector3 = hit["normal"]
		if normal.y < 0.6:
			point += Vector3(normal.x, 0, normal.z).normalized() * (def.footprint.z * 0.5 + 0.1)
	var y := _ground_y(space, point, exclude)
	if is_nan(y):
		ghost_valid = false
		ghost_reason = "Look at the ground"
		_show_ghost(false)
		return
	point.y = y
	if plan != &"":
		# A building: its near side where you look, its front (door) to you
		var flat := Vector3(forward.x, 0, forward.z).normalized()
		point += flat * (def.footprint.z * 0.5)
	# Face the structure across your view unless you've rotated it yourself
	var xform := ConstructionRules.snap(point, yaw + rad_to_deg(player.rotation.y))
	var gy := _ground_y(space, xform.origin, exclude)
	if not is_nan(gy):
		xform.origin.y = gy
	# Join onto what's already built nearby (R then sets the joint's angle)
	snapped_to = null
	var snap := ConstructionRules.snap_to_built(ConstructionRules.structures_root(player.get_parent()), def, point, yaw, moving) if plan == &"" else {}
	if not snap.is_empty():
		xform = snap["xform"]
		snapped_to = snap["to"]
	ghost_transform = xform
	if moving != null:
		ghost_reason = player.move_refusal_reason(moving, xform)
	elif plan != &"":
		ghost_reason = player.site_refusal_reason(plan, xform)
	else:
		ghost_reason = player.place_refusal_reason(current_kit(), xform, current_variant())
	ghost_valid = ghost_reason == ""
	_show_ghost(true)


static func _ground_y(space: PhysicsDirectSpaceState3D, at: Vector3, exclude: Array[RID]) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 1.5, PhysicsLayers.WORLD_SOLID, exclude))
	return (hit["position"] as Vector3).y if not hit.is_empty() else NAN


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
	var def := ghost_definition()
	if def == _ghost_def and _ghost != null:
		return
	_free_ghost()
	_ghost_def = def
	if def == null:
		return
	_ghost = Node3D.new()
	_ghost.name = "BuildGhost"
	_ghost.top_level = true
	# Copy just the meshes (never instance the real scene into the world: it
	# would save itself and change the navmesh)
	var scene := (load(def.scene_path) as PackedScene).instantiate()
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
	_ghost_def = null


# ---------------------------------------------------------------- HUD text

## One line for the HUD: the kit and count, what you're moving, or the
## targeted structure.
func title_text() -> String:
	if moving != null:
		return "Moving " + moving.definition.display_name
	if target != null:
		if target is LevelProp:
			return target.definition.display_name
		return "%s  ·  %d%%" % [target.definition.display_name, roundi(target.get_health_fraction() * 100.0)]
	var plan := current_plan()
	if plan != &"":
		return "Plan: %s  ·  needs %s%s" % [SettlementPlans.display_name(plan), SettlementPlans.cost_text(SettlementPlans.cost(plan)),
			"   (%d/%d)" % [selected + 1, entry_count()] if entry_count() > 1 else ""]
	var kit := current_kit()
	if kit == null:
		return "No kits"
	var v := current_variant()
	var variant := ""
	if kit.structure.get_variants().size() > 1:
		variant = "  ·  %s [V]" % v.variant_name
	return "%s ×%d%s%s" % [kit.structure.display_name, player.inventory.count_of(kit.id), variant, "   (%d/%d)" % [selected + 1, entry_count()] if entry_count() > 1 else ""]


## The second line: what's possible here, or why not.
func status_text() -> String:
	if moving != null:
		return ("Click to put it here" if ghost_valid else ghost_reason) + "   [F] Cancel"
	if target is LevelProp:
		var prop: PackedStringArray = []
		if target.definition.movable:
			prop.append("[F] Move")
		prop.append("[X] Scrap (get %s)" % StructureDefinition.cost_text(target.definition.dismantle_return))
		return "   ".join(prop)
	if target != null:
		var parts: PackedStringArray = ["[F] Move"]
		if target.is_damaged():
			parts.append("[E] Repair (%s)" % StructureDefinition.cost_text(target.definition.repair_cost))
		if target.can_undo():
			parts.append("[X] Dismantle (get the kit back)")
		else:
			parts.append("[X] Dismantle (get back %s)" % StructureDefinition.cost_text(target.definition.dismantle_return))
		return "   ".join(parts)
	if current_plan() != &"":
		if not ghost_valid:
			return ghost_reason
		return "Click to plan it here (%s); your Builders put it up" % SettlementPlans.about(current_plan()).to_lower()
	if current_kit() == null:
		return "Look at something you've built"
	if not ghost_valid:
		return ghost_reason
	return "Click to build" + ("  (joined)" if snapped_to != null else "")


# ---------------------------------------------------------------- input

func _process(_delta: float) -> void:
	if not active:
		return
	if player.is_dead() or player.ladder != null or player.player_input.ui_open:
		exit()
		return
	if moving != null and (not is_instance_valid(moving) or moving.is_queued_for_deletion()):
		moving = null  # broken while we were carrying it
		_rebuild_ghost()
	# Walking into or out of a settlement you hold changes what can be planned
	if moving == null and (player.settlement_at(player.global_position) != null) == plans.is_empty():
		refresh_kits()
		_rebuild_ghost()
		changed.emit()
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
	if ScrollStepper.is_scroll(event):
		# Mouse wheel or Magic Mouse / trackpad swipe: one kit per swipe
		var step := _scroll.feed(event)
		if step != 0:
			select(step)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_next"):
		select(1)
	elif event.is_action_pressed("build_previous"):
		select(-1)
	elif event.is_action_pressed("build_rotate"):
		rotate(-1 if (event as InputEventWithModifiers).shift_pressed else 1)
	elif event.is_action_pressed("build_variant"):
		cycle_variant()
	elif event.is_action_pressed("build_move"):
		if moving != null:
			cancel_move()
		else:
			start_move()
	elif event.is_action_pressed("fire"):
		place()
	elif event.is_action_pressed("interact"):
		repair()
	elif event.is_action_pressed("build_dismantle"):
		dismantle()
