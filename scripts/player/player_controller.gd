class_name PlayerController
extends CharacterBody3D
## First-person character: mouse look, walk, sprint, crouch, jump, an equipped
## HitscanWeapon (fire, reload, recoil), health, fall damage, death, an
## inventory (ammo comes from it), using items such as medkits, aiming down
## sights and climbing ladders.
##
## Movement is driven only by InputFrames passed to simulate(). The local
## player gathers its own frames from PlayerInput; remote players (co-op,
## later) and automated tests call simulate() directly with
## controlled_locally = false.
##
## Death and respawn: when health reaches zero the player enters the DEAD
## state (no movement, no weapon). Pressing jump while dead emits
## respawn_requested; the level's GameMode decides whether it is allowed yet
## and calls respawn_at(). Keeping that decision in GameMode means the host
## can enforce it in co-op.
##
## Scene: res://scenes/player/player.tscn

signal jumped
signal landed(impact_speed: float)            ## Vertical speed at touchdown (m/s).
signal stance_changed(is_crouching: bool)
signal movement_state_changed(state: MovementState)
signal died(info: DamageInfo)
signal respawn_requested
signal respawned
## Using an item (e.g. a medkit) takes time; these report its progress.
signal item_use_started(item: ItemDefinition, duration: float)
signal item_use_finished(item: ItemDefinition)
signal item_use_cancelled(item: ItemDefinition)
signal item_use_refused(reason: String)
signal item_dropped(item: ItemDefinition, quantity: int)
signal aim_changed(aiming: bool)
signal ladder_grabbed(ladder: Ladder)
signal ladder_released
## Emitted every `ladder_step_distance` metres climbed (for sound).
signal ladder_step
## A salvage container was opened / closed (the HUD shows the transfer screen).
signal container_opened(container: SalvageContainer)
signal container_closed(container: SalvageContainer)
## A take/store was refused ("Too heavy", "Inventory full", "Container full").
signal transfer_refused(reason: String)
## A new gun joined the loadout (HUD notice, sound).
signal weapon_picked_up(weapon: WeaponDefinition)
## Crafting: one unit started / finished; the queue was cancelled or refused.
signal crafting_started(recipe: RecipeDefinition, duration: float)
signal crafting_finished(recipe: RecipeDefinition)
signal crafting_cancelled(recipe: RecipeDefinition)
signal craft_refused(reason: String)
## A bench was opened / closed (the HUD shows the crafting screen).
signal station_opened(station: CraftingStation)
signal station_closed(station: CraftingStation)
## Fitting or removing an attachment was refused.
signal attachment_refused(reason: String)
## Construction (Increment 13)
signal structure_placed(structure: Structure)
signal structure_repaired(structure: Structure)
signal structure_dismantled(definition: StructureDefinition)
signal structure_moved(structure: Structure)
signal build_refused(reason: String)

enum MovementState { IDLE, WALKING, SPRINTING, CROUCHING, AIRBORNE, DEAD, CLIMBING }

@export_group("Speeds (m/s)")
@export var walk_speed := 4.5
@export var sprint_speed := 7.5
@export var crouch_speed := 2.2
@export var jump_velocity := 4.8

@export_group("Acceleration")
@export var ground_acceleration := 12.0
@export var ground_deceleration := 14.0
@export var air_acceleration := 2.0

@export_group("Stance (m)")
@export var stand_height := 1.8
@export var crouch_height := 1.1
## Distance from the top of the capsule down to the eyes.
@export var eye_offset := 0.12
@export var stance_transition_speed := 10.0

@export_group("Look")
@export_range(10.0, 89.0) var max_pitch_degrees := 89.0

@export_group("Head bob")
@export var head_bob_enabled := true
@export var head_bob_amplitude := 0.035
## Metres travelled per full left-right step cycle.
@export var head_bob_stride := 1.5

@export_group("Weapon handling")
## Spread multipliers by movement state (1.0 = the weapon's own spread).
@export var spread_idle := 1.0
@export var spread_walking := 1.8
@export var spread_crouching := 0.6
@export var spread_airborne := 3.0

@export_group("Fall damage (m/s)")
## Landing slower than this does no damage (≈ a 3.3 m drop).
@export var safe_fall_speed := 8.0
## Landing at this speed or faster is lethal (≈ a 16.5 m drop).
@export var lethal_fall_speed := 18.0

@export_group("Using items")
## Movement speed multiplier while using an item (bandaging, etc.).
@export var use_move_multiplier := 0.5

@export_group("Ladders")
@export var climb_speed := 2.6
## Can't grab a ladder again for this long after letting go (s).
@export var ladder_regrab_delay := 0.4
@export var ladder_step_distance := 0.45
## Looking further down than this while facing the ladder makes W climb down.
@export var ladder_look_down_degrees := 40.0
## Push away from the ladder when jumping off (m/s).
@export var ladder_jump_off_speed := 3.0

@export_group("Control")
## True for the player at this keyboard. False for remote players and tests,
## which drive the character by calling simulate().
@export var controlled_locally := true
## Falling below this height kills the player (out of the world).
@export var kill_plane_y := -30.0

var movement_state: MovementState = MovementState.IDLE
var is_crouching := false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _current_height := 0.0
var _bob_distance := 0.0
var _death_tween: Tween
var _using_item: ItemDefinition = null
var _use_left := 0.0

## The ladder being climbed, or null.
var ladder: Ladder = null
## 0..1, how far the sights are raised (simulated, so the host agrees).
var aim_amount := 0.0
var is_aiming := false
var _base_fov := 75.0
var _ladder_cooldown := 0.0
var _climb_distance := 0.0
## The salvage container whose contents are open, or null.
var current_container: SalvageContainer = null
## The crafting bench in use, or null (hand crafting).
var current_station: CraftingStation = null
## In build mode (B): weapon lowered, no firing. Set by BuildMode.
var building := false
var _craft_recipe: RecipeDefinition = null
var _craft_left := 0.0
var _craft_count := 0

@onready var collision_shape: CollisionShape3D = %CollisionShape
@onready var head: Node3D = %Head
@onready var camera: Camera3D = %Camera
@onready var head_clearance: ShapeCast3D = %HeadClearance
@onready var player_input: PlayerInput = %PlayerInput
@onready var health: HealthComponent = %HealthComponent
## The gun in hand, if any. Set by WeaponSlots when you switch.
var weapon: HitscanWeapon
## The loadout (%WeaponSlots): up to four guns, number keys / mouse wheel.
@onready var weapon_slots: WeaponSlots = get_node_or_null("%WeaponSlots")
@onready var interactor: PlayerInteractor = get_node_or_null("%Interactor")
@onready var inventory: PlayerInventory = get_node_or_null("%Inventory")


func _ready() -> void:
	add_to_group("players")
	add_to_group("persist")
	_current_height = stand_height
	_apply_height(stand_height)
	_base_fov = camera.fov
	health.died.connect(_on_health_died)
	landed.connect(_on_landed)
	if weapon_slots != null:
		weapon_slots.setup(self, camera.get_node("WeaponMount"))
	else:
		# Older scenes: a single %Weapon under the camera
		weapon = get_node_or_null("%Weapon")
		if weapon != null:
			weapon.aim_camera = camera
			if inventory != null:
				weapon.set_ammo_source(inventory)
	if controlled_locally:
		camera.make_current()
	else:
		player_input.process_mode = Node.PROCESS_MODE_DISABLED
		camera.current = false


func _physics_process(delta: float) -> void:
	if controlled_locally:
		simulate(player_input.gather(), delta)
	if global_position.y < kill_plane_y and not is_dead():
		var info := DamageInfo.create(health.max_health * 10.0, DamageInfo.Type.ENVIRONMENT)
		health.apply_damage(info)


func is_dead() -> bool:
	return health.is_dead()


## Advances the character by one physics tick. The same frames always give
## the same result, so the host can re-run a guest's movement.
func simulate(frame: InputFrame, delta: float) -> void:
	if is_dead():
		if interactor != null:
			interactor.tick(delta, false, null)
		_simulate_dead(frame, delta)
		return

	# Mouse look is slowed while zoomed so aiming feels the same
	_apply_look(frame.look * lerpf(1.0, 1.0 / _ads_zoom(), aim_amount))
	_update_stance(frame.crouch and ladder == null, delta)
	_update_item_use(frame, delta)
	_update_crafting(delta)
	_update_aim(frame, delta)

	_ladder_cooldown = maxf(_ladder_cooldown - delta, 0.0)
	if ladder == null:
		_try_grab_ladder(frame)
	if ladder != null:
		_simulate_ladder(frame, delta)
	else:
		_simulate_walking(frame, delta)
		if is_dead():
			return  # killed by the landing

	_update_movement_state()
	_update_head_bob(delta)

	_update_weapon_selection(frame, delta)
	if weapon != null:
		# Aim from the head (not the bobbing camera). Can't shoot mid-sprint;
		# pressing fire cancels sprint, so there is a short sprint-to-fire delay.
		# Hands are busy on a ladder, while using an item or switching guns.
		var switching := is_switching_weapon()
		var hands_busy := is_using_item() or ladder != null or switching or building
		if not switching:
			weapon.lowered = hands_busy  # WeaponSlots animates switches itself
		weapon.aim_amount = aim_amount
		var spread := _spread_multiplier() * lerpf(1.0, weapon.definition.ads_spread_multiplier, aim_amount)
		var recoil := weapon.tick(delta, frame.fire, frame.reload and not hands_busy, head.global_transform, self,
			spread, movement_state != MovementState.SPRINTING and not hands_busy)
		if recoil != Vector2.ZERO:
			recoil *= lerpf(1.0, weapon.definition.ads_recoil_multiplier, aim_amount)
			_apply_look(Vector2(recoil.x, -recoil.y))

	if interactor != null:
		interactor.tick(delta, frame.interact, self)

	# Walked away from an open container or bench
	if current_container != null and (not is_instance_valid(current_container)
			or not current_container.is_within_reach(head.global_position)):
		close_container()
	if current_station != null and (not is_instance_valid(current_station)
			or not current_station.is_within_reach(head.global_position)):
		close_station()


## Brings the player back to life at `spawn` with full health. Called by
## GameMode (the authority), not directly by input.
func respawn_at(spawn: Transform3D) -> void:
	if _death_tween != null:
		_death_tween.kill()
	health.revive(1.0)
	global_transform = spawn
	velocity = Vector3.ZERO
	head.rotation = Vector3.ZERO
	camera.position = Vector3.ZERO
	camera.fov = _base_fov
	aim_amount = 0.0
	is_aiming = false
	ladder = null
	is_crouching = false
	_current_height = stand_height
	_apply_height(stand_height)
	if weapon_slots != null and weapon_slots.current_slot > 0:
		weapon_slots.equip_immediately(weapon_slots.pending_slot if weapon_slots.pending_slot != 0 else weapon_slots.current_slot)
	# Never respawn without ammo; the inventory itself is kept on death for now
	for w in _owned_weapons():
		if inventory != null and w.definition.starting_reserve > 0 and not w.definition.melee:
			inventory.ensure_minimum_ammo(w.definition.ammo_type, w.definition.starting_reserve)
		w.restock()
	if weapon != null:
		weapon.visible = true
		weapon.lowered = false
	movement_state = MovementState.IDLE
	movement_state_changed.emit(movement_state)
	respawned.emit()


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func get_state_name() -> String:
	return MovementState.keys()[movement_state]


## Fall damage for a given landing speed (0 when safe).
func fall_damage_for_speed(impact_speed: float) -> float:
	if impact_speed <= safe_fall_speed:
		return 0.0
	var t := (impact_speed - safe_fall_speed) / maxf(lethal_fall_speed - safe_fall_speed, 0.01)
	return health.max_health * t


# ---------------------------------------------------------------- items

func is_using_item() -> bool:
	return _using_item != null


## 0..1 progress of the current item use (-1 when not using one).
func get_item_use_progress() -> float:
	if _using_item == null:
		return -1.0
	return 1.0 - _use_left / maxf(_using_item.use_time, 0.001)


func get_item_in_use() -> ItemDefinition:
	return _using_item


## Starts using an item from the inventory (validated). Returns true if begun.
## Called for the quick-heal key and from the inventory screen.
func request_use_item(item: ItemDefinition) -> bool:
	var reason := _use_refusal_reason(item)
	if reason != "":
		item_use_refused.emit(reason)
		return false
	_using_item = item
	_use_left = item.use_time
	item_use_started.emit(item, item.use_time)
	if item.use_time <= 0.0:
		_finish_item_use()
	return true


func cancel_item_use() -> void:
	if _using_item == null:
		return
	var item := _using_item
	_using_item = null
	_use_left = 0.0
	item_use_cancelled.emit(item)


## Drops (part of) an inventory slot on the ground in front of the player.
## Returns the Pickup created, or null.
func request_drop_slot(index: int, quantity: int = -1) -> Pickup:
	if inventory == null or is_dead():
		return null
	var taken := inventory.take_from_slot(index, quantity)
	if taken.is_empty():
		return null
	var forward := -global_basis.z
	forward.y = 0.0
	var at := global_position + forward.normalized() * 1.0 + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 3.0, PhysicsLayers.WORLD_SOLID)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		at = hit["position"]
	var parent := get_parent() if get_parent() != null else get_tree().current_scene
	var pickup := Pickup.spawn(parent, taken["item"], taken["qty"], at)
	item_dropped.emit(taken["item"], taken["qty"])
	return pickup


func _use_refusal_reason(item: ItemDefinition) -> String:
	if is_dead():
		return "Can't do that now"
	if item == null:
		return "No medkits"
	if inventory == null or inventory.count_of(item.id) <= 0:
		return "You don't have that"
	if is_using_item():
		return "Already busy"
	if ladder != null:
		return "Can't do that now"
	match item.category:
		ItemDefinition.Category.MEDICAL:
			if health.current_health >= health.max_health:
				return "Already at full health"
		_:
			return "Can't use that"
	return ""


func _update_item_use(frame: InputFrame, delta: float) -> void:
	if frame.use_heal:
		if is_using_item():
			cancel_item_use()
		elif inventory != null:
			request_use_item(inventory.find_best_medical())
		return
	if not is_using_item():
		return
	var sprinting := frame.sprint and frame.move.y < -0.3
	if frame.fire or sprinting:
		cancel_item_use()
		return
	_use_left -= delta
	if _use_left <= 0.0:
		_finish_item_use()


func _finish_item_use() -> void:
	var item := _using_item
	_using_item = null
	_use_left = 0.0
	# Validate again: the item could have been dropped or health topped up
	if inventory == null or inventory.count_of(item.id) <= 0:
		item_use_cancelled.emit(item)
		return
	inventory.remove_item(item.id, 1)
	if item.heal_amount > 0.0:
		health.heal(item.heal_amount)
	item_use_finished.emit(item)


# ---------------------------------------------------------------- containers

## Called by SalvageContainer after a validated interaction.
func open_container(container: SalvageContainer) -> void:
	if container == current_container or container == null:
		return
	close_container()
	close_station()
	cancel_item_use()
	current_container = container
	container_opened.emit(container)


func close_container() -> void:
	if current_container == null:
		return
	var c := current_container
	current_container = null
	if is_instance_valid(c):
		c.release(self)
	container_closed.emit(c)


## Moves (part of) a container slot into the player's inventory. Validated:
## the container must be open by this player and in reach. Returns the
## number moved; a refusal emits transfer_refused.
func request_take(slot: int, quantity: int = -1) -> int:
	if not _can_transfer():
		return 0
	var c := current_container
	var item := c.inventory.get_slot_item(slot)
	if item == null:
		return 0
	var want := c.inventory.get_slot_quantity(slot) if quantity < 0 else mini(quantity, c.inventory.get_slot_quantity(slot))
	var moved := c.inventory.transfer_slot_to(slot, inventory, want)
	if moved < want:
		var reason := inventory.get_refusal_reason(item, want - moved)
		transfer_refused.emit(reason if reason != "" else "Inventory full")
	return moved


## Moves (part of) a player inventory slot into the open container.
func request_store(slot: int, quantity: int = -1) -> int:
	if not _can_transfer():
		return 0
	var c := current_container
	var item := inventory.get_slot_item(slot)
	if item == null:
		return 0
	var want := inventory.get_slot_quantity(slot) if quantity < 0 else mini(quantity, inventory.get_slot_quantity(slot))
	var moved := inventory.transfer_slot_to(slot, c.inventory, want)
	if moved < want:
		transfer_refused.emit("Container full")
	return moved


## Takes everything that fits. Returns the number of items moved.
func request_take_all() -> int:
	if not _can_transfer():
		return 0
	var total := 0
	var refusal := ""
	for i in current_container.inventory.slot_count:
		var item := current_container.inventory.get_slot_item(i)
		if item == null:
			continue
		var want := current_container.inventory.get_slot_quantity(i)
		var moved := current_container.inventory.transfer_slot_to(i, inventory, want)
		total += moved
		if moved < want and refusal == "":
			refusal = inventory.get_refusal_reason(item, want - moved)
			if refusal == "":
				refusal = "Inventory full"
	if refusal != "":
		transfer_refused.emit(refusal)
	return total


func _can_transfer() -> bool:
	return not is_dead() and inventory != null and current_container != null \
		and is_instance_valid(current_container) and current_container.users.has(self) \
		and current_container.is_within_reach(head.global_position)


# ---------------------------------------------------------------- saving

## Plain data for SaveManager: where you are, where you're looking, health,
## inventory and the rounds in the magazine.
func save_state() -> Dictionary:
	var p := global_position
	return {
		"position": [p.x, p.y, p.z],
		"yaw": rotation.y,
		"pitch": head.rotation.x,
		"health": health.current_health,
		"inventory": inventory.to_data() if inventory != null else [],
		"magazine": weapon.ammo_in_magazine if weapon != null else 0,
		"loadout": weapon_slots.save_state() if weapon_slots != null else {},
	}


## Restores save_state() data. Anything missing or malformed keeps its
## current value; the player always ends up alive with at least 1 health.
func load_state(data: Dictionary) -> void:
	var pos := global_position
	var raw_pos: Variant = data.get("position")
	if raw_pos is Array and raw_pos.size() == 3 and raw_pos.all(func(v: Variant) -> bool: return v is float or v is int):
		pos = Vector3(raw_pos[0], raw_pos[1], raw_pos[2])
	var yaw := _number(data.get("yaw"), rotation.y)
	# respawn_at resets everything transient: death camera, ladder, crouch...
	close_container()
	cancel_crafting()
	close_station()
	cancel_item_use()
	ladder = null
	respawn_at(Transform3D(Basis(Vector3.UP, yaw), pos))
	var limit := deg_to_rad(max_pitch_degrees)
	head.rotation.x = clampf(_number(data.get("pitch"), 0.0), -limit, limit)
	if inventory != null and data.get("inventory") is Array:
		inventory.from_data(data["inventory"])
	var loadout: Variant = data.get("loadout")
	if weapon_slots != null and loadout is Dictionary and not (loadout as Dictionary).is_empty():
		weapon_slots.load_state(loadout)
	elif weapon != null:
		# Version-1 saves from before the loadout: one magazine for the rifle
		weapon.cancel_reload()
		weapon.ammo_in_magazine = clampi(int(_number(data.get("magazine"), weapon.ammo_in_magazine)), 0, weapon.definition.magazine_size)
	if weapon != null:
		weapon.ammo_changed.emit(weapon.ammo_in_magazine, weapon.reserve_ammo)
	var hp := _number(data.get("health"), health.max_health)
	health.revive(clampf(hp, 1.0, health.max_health) / health.max_health)


static func _number(value: Variant, fallback: float) -> float:
	return float(value) if (value is float or value is int) and is_finite(float(value)) else fallback


# ---------------------------------------------------------------- weapons

func is_switching_weapon() -> bool:
	return weapon_slots != null and weapon_slots.is_switching()


## Picks up a gun (validated in WeaponSlots). Returns true if it was new.
## With only a blade in hand, the new gun comes straight out.
func give_weapon(def: WeaponDefinition) -> bool:
	if weapon_slots == null or is_dead():
		return false
	if not weapon_slots.give_weapon(def):
		return false
	var w := weapon_slots.get_weapon(def.slot)
	if inventory != null and w != null:
		w.set_ammo_source(inventory)
	if weapon != null and weapon.definition.melee and not def.melee:
		weapon_slots.request_slot(def.slot)
	return true


## Why a crafted or found gun can't be added ("" = it can).
func weapon_refusal_reason(def: WeaponDefinition) -> String:
	if weapon_slots == null:
		return "Can't carry that"
	var existing := weapon_slots.get_weapon(def.slot)
	if existing == null:
		return ""
	if existing.base_definition.id == def.id:
		return "You already have a " + def.display_name
	if existing.base_definition.tier > def.tier:
		return "Your %s is better" % existing.base_definition.display_name
	return ""


# ---------------------------------------------------------------- construction

## "" if `kit` can be placed at `xform`, otherwise why not.
func place_refusal_reason(kit: ItemDefinition, xform: Transform3D) -> String:
	if kit == null or kit.structure == null:
		return "That can't be built"
	if inventory == null or inventory.count_of(kit.id) <= 0:
		return "You don't have a " + kit.display_name
	return ConstructionRules.refusal_reason(self, kit.structure, xform)


## Uses one kit from the inventory and builds its structure (validated).
func request_place_structure(kit: ItemDefinition, xform: Transform3D) -> Structure:
	var reason := place_refusal_reason(kit, xform)
	if reason != "":
		build_refused.emit(reason)
		return null
	var root := ConstructionRules.structures_root(get_parent())
	inventory.remove_item(kit.id, 1)
	var s := (load(kit.structure.scene_path) as PackedScene).instantiate() as Structure
	s.name = "%s_%d" % [kit.structure.id, Time.get_ticks_usec() % 100000000]
	s.transform = root.global_transform.affine_inverse() * xform
	s.kit = kit
	s.placed_msec = Time.get_ticks_msec()
	root.add_child(s)
	s._one_shot(load("res://assets/audio/build_place.wav"))
	structure_placed.emit(s)
	return s


## "" if `s` can be repaired now, otherwise why not.
func repair_refusal_reason(s: Structure) -> String:
	if is_dead() or inventory == null or s == null or not is_instance_valid(s) or s.is_queued_for_deletion():
		return "Can't do that now"
	if head.global_position.distance_to(s.global_position + Vector3.UP) > ConstructionRules.REACH:
		return "Too far away"
	if not s.is_damaged():
		return "Not damaged"
	for item: ItemDefinition in s.definition.repair_cost:
		var have := inventory.count_of(item.id)
		if have < s.definition.repair_cost[item]:
			return "Need %d %s" % [s.definition.repair_cost[item] - have, item.display_name]
	return ""


## Repairs `s` to full, using its repair cost (validated).
func request_repair_structure(s: Structure) -> bool:
	var reason := repair_refusal_reason(s)
	if reason != "":
		build_refused.emit(reason)
		return false
	for item: ItemDefinition in s.definition.repair_cost:
		inventory.remove_item(item.id, s.definition.repair_cost[item])
	s.repair_full()
	s._one_shot(load("res://assets/audio/build_place.wav"))
	structure_repaired.emit(s)
	return true


## "" if `s` can be dismantled now, otherwise why not.
func dismantle_refusal_reason(s: Structure) -> String:
	if is_dead() or inventory == null or s == null or not is_instance_valid(s) or s.is_queued_for_deletion():
		return "Can't do that now"
	if head.global_position.distance_to(s.global_position + Vector3.UP) > ConstructionRules.REACH:
		return "Too far away"
	var blocked := s.dismantle_block_reason()
	if blocked != "":
		return blocked
	if s.can_undo():
		return "" if inventory.can_add(s.kit, 1) >= 1 else "No room for " + s.kit.display_name
	for item: ItemDefinition in s.definition.dismantle_return:
		if inventory.can_add(item, s.definition.dismantle_return[item]) < s.definition.dismantle_return[item]:
			return "No room for " + item.display_name
	return ""


## Takes `s` apart and gives back its dismantle return (validated).
func request_dismantle_structure(s: Structure) -> bool:
	var reason := dismantle_refusal_reason(s)
	if reason != "":
		build_refused.emit(reason)
		return false
	var def := s.definition
	if s.can_undo():
		inventory.receive(s.kit, 1)  # changed your mind: the kit back
	else:
		for item: ItemDefinition in def.dismantle_return:
			inventory.receive(item, def.dismantle_return[item])
	s._one_shot(load("res://assets/audio/build_place.wav"))
	s.queue_free()
	structure_dismantled.emit(def)
	return true


## "" if `s` can be moved to `xform` now, otherwise why not.
func move_refusal_reason(s: Structure, xform: Transform3D) -> String:
	if is_dead() or s == null or not is_instance_valid(s) or s.is_queued_for_deletion() or not s.is_inside_tree():
		return "Can't do that now"
	if ConstructionRules.structures_root(get_parent()) != s.get_parent():
		return "Can't move that"
	var blocked := s.move_block_reason()
	if blocked != "":
		return blocked
	return ConstructionRules.refusal_reason(self, s.definition, xform, s)


## Moves `s` (with its damage and contents) to `xform` (validated).
func request_move_structure(s: Structure, xform: Transform3D) -> bool:
	var reason := move_refusal_reason(s, xform)
	if reason != "":
		build_refused.emit(reason)
		return false
	s.global_transform = xform
	if s.definition.blocks_navigation:
		NavRebaker.request(s)
	s._one_shot(load("res://assets/audio/build_place.wav"))
	structure_moved.emit(s)
	return true


# ---------------------------------------------------------------- attachments

## "" if `item` can be fitted to the gun in `weapon_slot`, otherwise why not.
## Only at a weapons bench.
func attachment_refusal_reason(weapon_slot: int, item: ItemDefinition) -> String:
	if is_dead() or inventory == null or weapon_slots == null:
		return "Can't do that now"
	if get_crafting_station() != RecipeDefinition.Station.WEAPONS_BENCH:
		return "Needs a Weapons Bench"
	var w := weapon_slots.get_weapon(weapon_slot)
	if w == null:
		return "No weapon in that slot"
	if item == null or item.attachment == null:
		return "That isn't an attachment"
	if inventory.count_of(item.id) <= 0:
		return "You don't have a " + item.display_name
	if not item.attachment.fits(w.base_definition.id):
		return "Doesn't fit the " + w.base_definition.display_name
	var old := w.get_attachment(item.attachment.slot)
	if old == item.attachment:
		return "Already fitted"
	if old != null:
		var old_item := ItemDatabase.find_attachment_item(old.id)
		var remove: Dictionary[ItemDefinition, int] = {item: 1}
		if old_item != null and not inventory.can_exchange(remove, old_item, 1):
			return "No room for the " + old_item.display_name
	return ""


## Fits an attachment from the inventory (validated). Whatever it replaces
## goes back into the inventory.
func request_fit_attachment(weapon_slot: int, item: ItemDefinition) -> bool:
	var reason := attachment_refusal_reason(weapon_slot, item)
	if reason != "":
		attachment_refused.emit(reason)
		return false
	var w := weapon_slots.get_weapon(weapon_slot)
	inventory.remove_item(item.id, 1)
	var old := w.fit_attachment(item.attachment)
	if old != null:
		var old_item := ItemDatabase.find_attachment_item(old.id)
		if old_item != null:
			inventory.add_item(old_item, 1)
	return true


## Takes an attachment off and puts it in the inventory (validated).
func request_remove_attachment(weapon_slot: int, slot: AttachmentDefinition.Slot) -> bool:
	var reason := ""
	var w := weapon_slots.get_weapon(weapon_slot) if weapon_slots != null else null
	if is_dead() or inventory == null or w == null:
		reason = "Can't do that now"
	elif get_crafting_station() != RecipeDefinition.Station.WEAPONS_BENCH:
		reason = "Needs a Weapons Bench"
	elif w.get_attachment(slot) == null:
		reason = "Nothing fitted there"
	else:
		var item := ItemDatabase.find_attachment_item(w.get_attachment(slot).id)
		if item == null or inventory.can_add(item, 1) < 1:
			reason = inventory.get_refusal_reason(item, 1) if item != null else "Can't remove that"
	if reason != "":
		attachment_refused.emit(reason)
		return false
	var att := w.remove_attachment(slot)
	inventory.add_item(ItemDatabase.find_attachment_item(att.id), 1)
	return true


func _owned_weapons() -> Array[HitscanWeapon]:
	if weapon_slots != null:
		return weapon_slots.owned()
	var single: Array[HitscanWeapon] = []
	if weapon != null:
		single.append(weapon)
	return single


func _update_weapon_selection(frame: InputFrame, delta: float) -> void:
	if weapon_slots == null:
		return
	# Number keys pick a slot, the wheel cycles; not while healing
	if not is_using_item():
		if frame.slot > 0:
			weapon_slots.request_slot(frame.slot)
		elif frame.cycle != 0:
			weapon_slots.cycle(signi(frame.cycle))
	weapon_slots.tick(delta)


# ---------------------------------------------------------------- crafting

## Called by CraftingStation after a validated interaction.
func open_station(station: CraftingStation) -> void:
	if station == current_station or station == null:
		return
	close_container()
	close_station()
	current_station = station
	station_opened.emit(station)


func close_station() -> void:
	if current_station == null:
		return
	var s := current_station
	current_station = null
	# Bench recipes need the bench; hand recipes keep going
	if _craft_recipe != null and _craft_recipe.station != RecipeDefinition.Station.HAND:
		cancel_crafting()
	station_closed.emit(s)


## The station you're crafting with right now (HAND if no bench is open).
func get_crafting_station() -> RecipeDefinition.Station:
	if current_station != null and is_instance_valid(current_station) and current_station.is_within_reach(head.global_position):
		return current_station.station
	return RecipeDefinition.Station.HAND


func is_crafting() -> bool:
	return _craft_recipe != null


func get_crafting_recipe() -> RecipeDefinition:
	return _craft_recipe


## How many more are queued, including the one in progress.
func get_crafting_count() -> int:
	return _craft_count


## 0..1 progress of the unit being made (-1 when idle).
func get_crafting_progress() -> float:
	if _craft_recipe == null:
		return -1.0
	return 1.0 - _craft_left / maxf(_craft_recipe.craft_time, 0.001)


## "" if one of `recipe` could be crafted right now, otherwise why not.
func craft_refusal_reason(recipe: RecipeDefinition) -> String:
	if recipe == null or recipe.output == null:
		return "Unknown recipe"
	if is_dead() or inventory == null:
		return "Can't do that now"
	if not recipe.can_make_at(get_crafting_station()):
		return "Needs a " + RecipeDefinition.station_name(recipe.station)
	for item: ItemDefinition in recipe.inputs:
		var have := inventory.count_of(item.id)
		if have < recipe.inputs[item]:
			return "Missing %d %s" % [recipe.inputs[item] - have, item.display_name]
	if recipe.output.weapon != null:
		return weapon_refusal_reason(recipe.output.weapon)
	if not inventory.can_exchange(recipe.inputs, recipe.output, recipe.output_quantity):
		return "Inventory full"
	return ""


## Starts crafting `count` of a recipe (validated). Adding to the same
## recipe extends the queue; a different recipe replaces it.
func request_craft(recipe: RecipeDefinition, count: int = 1) -> bool:
	var reason := craft_refusal_reason(recipe)
	if reason != "":
		craft_refused.emit(reason)
		return false
	count = clampi(count, 1, 99)
	if _craft_recipe == recipe:
		_craft_count = mini(_craft_count + count, 99)
		return true
	if _craft_recipe != null:
		cancel_crafting()
	_craft_recipe = recipe
	_craft_count = count
	_craft_left = recipe.craft_time
	crafting_started.emit(recipe, recipe.craft_time)
	return true


func cancel_crafting() -> void:
	if _craft_recipe == null:
		return
	var r := _craft_recipe
	_craft_recipe = null
	_craft_count = 0
	_craft_left = 0.0
	crafting_cancelled.emit(r)


func _update_crafting(delta: float) -> void:
	if _craft_recipe == null:
		return
	_craft_left -= delta
	if _craft_left > 0.0:
		return
	# Check again: materials may have been dropped, the bench left behind
	var recipe := _craft_recipe
	var reason := craft_refusal_reason(recipe)
	if reason != "":
		craft_refused.emit(reason)
		cancel_crafting()
		return
	for item: ItemDefinition in recipe.inputs:
		inventory.remove_item(item.id, recipe.inputs[item])
	if recipe.output.weapon != null:
		# A gun goes into its loadout slot, not the bag
		give_weapon(recipe.output.weapon)
		weapon_picked_up.emit(recipe.output.weapon)
	else:
		inventory.receive(recipe.output, recipe.output_quantity)
	crafting_finished.emit(recipe)
	_craft_count -= 1
	if _craft_count <= 0:
		_craft_recipe = null
		_craft_left = 0.0
		return
	if craft_refusal_reason(recipe) != "":
		# Out of materials for the rest of the queue
		_craft_recipe = null
		_craft_count = 0
		_craft_left = 0.0
		crafting_cancelled.emit(recipe)
		return
	_craft_left = recipe.craft_time
	crafting_started.emit(recipe, recipe.craft_time)


# ---------------------------------------------------------------- walking

func _simulate_walking(frame: InputFrame, delta: float) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= _gravity * delta
	elif frame.jump and not is_crouching:
		velocity.y = jump_velocity
		on_floor = false
		jumped.emit()

	# Horizontal movement relative to where the body faces
	var wish := global_basis * Vector3(frame.move.x, 0.0, frame.move.y)
	wish.y = 0.0
	wish = wish.limit_length(1.0)
	var target := wish * _target_speed(frame)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if on_floor:
		var rate := ground_acceleration if target.length() > 0.01 else ground_deceleration
		horizontal = horizontal.lerp(target, 1.0 - exp(-rate * delta))
	elif target.length() > 0.01:
		horizontal = horizontal.lerp(target, 1.0 - exp(-air_acceleration * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	var was_on_floor := is_on_floor()
	var impact_speed := -velocity.y
	move_and_slide()
	if not was_on_floor and is_on_floor():
		landed.emit(impact_speed)


# ---------------------------------------------------------------- aiming

func _ads_zoom() -> float:
	return weapon.definition.ads_zoom if weapon != null else 1.0


func _update_aim(frame: InputFrame, delta: float) -> void:
	var can_aim := frame.aim and weapon != null and not weapon.definition.melee and ladder == null \
		and not is_using_item() and not weapon.is_reloading and not is_switching_weapon()
	var ads_time := weapon.definition.ads_time if weapon != null else 0.2
	aim_amount = move_toward(aim_amount, 1.0 if can_aim else 0.0, delta / maxf(ads_time, 0.01))
	if can_aim != is_aiming:
		is_aiming = can_aim
		aim_changed.emit(is_aiming)
	var eased := aim_amount * aim_amount * (3.0 - 2.0 * aim_amount)
	camera.fov = lerpf(_base_fov, _base_fov / _ads_zoom(), eased)


# ---------------------------------------------------------------- ladders

## Attaches to a ladder the player is moving into: towards it from in front,
## or off the top edge towards it.
func _try_grab_ladder(frame: InputFrame) -> void:
	if _ladder_cooldown > 0.0 or frame.move.length() < 0.3:
		return
	var wish := global_basis * Vector3(frame.move.x, 0.0, frame.move.y)
	wish.y = 0.0
	wish = wish.normalized()
	for node in get_tree().get_nodes_in_group("ladders"):
		var l := node as Ladder
		if l == null or not l.is_in_reach(global_position):
			continue
		var out := l.get_outward()
		var at_top := global_position.y >= l.get_top_y() - 0.3
		if (at_top and wish.dot(out) > 0.5) or (not at_top and wish.dot(-out) > 0.5):
			_grab_ladder(l)
			return


func _grab_ladder(l: Ladder) -> void:
	cancel_item_use()
	ladder = l
	velocity = Vector3.ZERO
	_climb_distance = 0.0
	ladder_grabbed.emit(l)


func _release_ladder() -> void:
	ladder = null
	_ladder_cooldown = ladder_regrab_delay
	ladder_released.emit()


func _simulate_ladder(frame: InputFrame, delta: float) -> void:
	var l := ladder
	var out := l.get_outward()
	var top := l.get_top_y()

	if frame.jump:
		_release_ladder()
		velocity = out * ladder_jump_off_speed + Vector3.UP * 2.0
		jumped.emit()
		move_and_slide()
		return

	# W climbs up when facing the ladder, down with your back to it (stepping
	# off the top) or when looking well down. S is the reverse.
	var facing := -global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var direction := 1.0
	if facing.dot(-out) < -0.2 or head.rotation.x < -deg_to_rad(ladder_look_down_degrees):
		direction = -1.0
	var climb := -frame.move.y * direction * climb_speed

	# Keep the body on the climbing line in front of the ladder
	var error := l.get_climb_point(global_position.y) - global_position
	error.y = 0.0
	var horizontal := (error * 10.0).limit_length(4.0)
	if error.length() > 0.2:
		climb = 0.0  # still moving onto the ladder (e.g. from the top)

	# Over the top: step forward onto the floor
	if climb > 0.0 and global_position.y >= top + 0.05:
		_release_ladder()
		velocity = -out * 3.0 + Vector3.UP * 1.0
		move_and_slide()
		return

	velocity = Vector3(horizontal.x, climb, horizontal.z)
	move_and_slide()

	# Reached the ground while climbing down
	if climb < 0.0 and is_on_floor():
		_release_ladder()
		return

	_climb_distance += absf(get_real_velocity().y) * delta
	if _climb_distance >= ladder_step_distance:
		_climb_distance = 0.0
		ladder_step.emit()


# ---------------------------------------------------------------- internals

func _simulate_dead(frame: InputFrame, delta: float) -> void:
	# The body still falls and slides to a stop, but ignores all other input.
	if not is_on_floor():
		velocity.y -= _gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, ground_deceleration * delta)
	move_and_slide()
	if frame.jump:
		respawn_requested.emit()


func _on_landed(impact_speed: float) -> void:
	var damage := fall_damage_for_speed(impact_speed)
	if damage > 0.0:
		var info := DamageInfo.create(damage, DamageInfo.Type.FALL)
		info.direction = Vector3.DOWN
		health.apply_damage(info)


func _on_health_died(info: DamageInfo) -> void:
	cancel_item_use()
	close_container()
	cancel_crafting()
	close_station()
	if ladder != null:
		_release_ladder()
	aim_amount = 0.0
	is_aiming = false
	camera.fov = _base_fov
	movement_state = MovementState.DEAD
	movement_state_changed.emit(movement_state)
	if weapon != null:
		weapon.visible = false
		weapon.cancel_reload()
	# Death camera: drop towards the ground and roll onto one side
	if _death_tween != null:
		_death_tween.kill()
	_death_tween = create_tween().set_parallel()
	_death_tween.tween_property(head, "position:y", 0.35, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_tween.tween_property(head, "rotation:z", deg_to_rad(70.0), 0.7)
	_death_tween.tween_property(head, "rotation:x", deg_to_rad(-20.0), 0.7)
	died.emit(info)


func _apply_look(look: Vector2) -> void:
	rotate_y(-look.x)
	var limit := deg_to_rad(max_pitch_degrees)
	head.rotation.x = clampf(head.rotation.x - look.y, -limit, limit)


func _target_speed(frame: InputFrame) -> float:
	var speed := walk_speed
	if is_crouching:
		speed = crouch_speed
	elif frame.sprint and frame.move.y < -0.3 and not frame.fire and not is_aiming and not is_using_item():
		# Sprint only while moving mostly forward, not while aiming
		return sprint_speed
	if is_using_item():
		speed *= use_move_multiplier
	if weapon != null:
		speed *= lerpf(1.0, weapon.definition.ads_move_multiplier, aim_amount)
	return speed


func _spread_multiplier() -> float:
	match movement_state:
		MovementState.CROUCHING:
			return spread_crouching
		MovementState.WALKING, MovementState.SPRINTING:
			return spread_walking
		MovementState.AIRBORNE:
			return spread_airborne
	return spread_idle


func _update_stance(wants_crouch: bool, delta: float) -> void:
	var crouch := wants_crouch
	if not crouch and is_crouching and _is_head_blocked():
		crouch = true  # can't stand up under a low ceiling
	if crouch != is_crouching:
		is_crouching = crouch
		stance_changed.emit(is_crouching)

	var target_height := crouch_height if is_crouching else stand_height
	_current_height = lerpf(_current_height, target_height, 1.0 - exp(-stance_transition_speed * delta))
	if absf(_current_height - target_height) < 0.002:
		_current_height = target_height
	_apply_height(_current_height)


func _apply_height(height: float) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	capsule.height = height
	collision_shape.position.y = height / 2.0
	head.position.y = height - eye_offset


func _is_head_blocked() -> bool:
	head_clearance.force_shapecast_update()
	return head_clearance.is_colliding()


func _update_movement_state() -> void:
	var state: MovementState
	var speed := get_horizontal_speed()
	if ladder != null:
		state = MovementState.CLIMBING
	elif not is_on_floor():
		state = MovementState.AIRBORNE
	elif is_crouching:
		state = MovementState.CROUCHING
	elif speed < 0.2:
		state = MovementState.IDLE
	elif speed > walk_speed + 0.5:
		state = MovementState.SPRINTING
	else:
		state = MovementState.WALKING
	if state != movement_state:
		movement_state = state
		movement_state_changed.emit(state)


func _update_head_bob(delta: float) -> void:
	var target := Vector3.ZERO
	var speed := get_horizontal_speed()
	if head_bob_enabled and is_on_floor() and speed > 0.2:
		_bob_distance += speed * delta
		var phase := _bob_distance / head_bob_stride * TAU
		var amplitude := head_bob_amplitude * clampf(speed / walk_speed, 0.0, 1.5)
		target = Vector3(sin(phase) * amplitude * 0.6, absf(sin(phase)) * amplitude, 0.0)
	camera.position = camera.position.lerp(target, 1.0 - exp(-12.0 * delta))
