class_name WeaponSlots
extends Node
## The player's loadout: up to five weapons, one per slot (1 rifle, 2 sidearm,
## 3 shotgun, 4 marksman, 5 melee), switched with the number keys or the
## mouse wheel.
##
## Owned weapons are HitscanWeapon instances under the camera's WeaponMount;
## only the equipped one is visible and ticked. Switching takes the old gun
## down (holster_time) and brings the new one up (its draw_time); you can't
## fire, aim or reload in between.
##
## Lives in the player scene as %WeaponSlots. PlayerController calls setup()
## from _ready and tick() every simulation step. give_weapon() is validated
## and host-side in co-op, like every other state change.

signal weapon_added(weapon: HitscanWeapon)
## Emitted when a switch starts (the new weapon isn't usable yet).
signal switch_started(to_slot: int)
## The new weapon is up and usable.
signal weapon_equipped(weapon: HitscanWeapon)

const SLOT_COUNT := 5

## Guns you start with (and get back on a new game).
@export var starting_weapons: Array[WeaponDefinition] = []
## Seconds to put the current gun away before the next comes up.
@export var holster_time := 0.2

## Slot number (1-4) → HitscanWeapon, or null.
var weapons: Array[HitscanWeapon] = [null, null, null, null, null, null]
## Slot currently in hand (0 = none).
var current_slot := 0
## Slot being switched to (0 = not switching).
var pending_slot := 0

var _player: PlayerController
var _mount: Node3D
var _phase_left := 0.0
var _holstering := false


## Called by PlayerController._ready. Instances the starting guns and equips
## the lowest slot immediately (no draw delay at spawn).
func setup(player: PlayerController, mount: Node3D) -> void:
	_player = player
	_mount = mount
	for def in starting_weapons:
		_add(def)
	var first := first_owned_slot()
	if first > 0:
		_equip_now(first)


func get_current() -> HitscanWeapon:
	return weapons[current_slot] if current_slot > 0 else null


func get_weapon(slot: int) -> HitscanWeapon:
	return weapons[slot] if slot >= 1 and slot <= SLOT_COUNT else null


func has_weapon(id: StringName) -> bool:
	return find_slot(id) > 0


func find_slot(id: StringName) -> int:
	for s in range(1, SLOT_COUNT + 1):
		if weapons[s] != null and weapons[s].base_definition.id == id:
			return s
	return 0


func first_owned_slot() -> int:
	for s in range(1, SLOT_COUNT + 1):
		if weapons[s] != null:
			return s
	return 0


func owned() -> Array[HitscanWeapon]:
	var out: Array[HitscanWeapon] = []
	for s in range(1, SLOT_COUNT + 1):
		if weapons[s] != null:
			out.append(weapons[s])
	return out


func is_switching() -> bool:
	return pending_slot != 0


## Adds a gun to its slot. Returns false if that slot already holds this gun
## (the caller turns the pickup into ammo instead) or the definition is bad.
func give_weapon(def: WeaponDefinition) -> bool:
	if def == null or def.scene_path == "" or def.slot < 1 or def.slot > SLOT_COUNT:
		return false
	if weapons[def.slot] != null and weapons[def.slot].base_definition.id == def.id:
		return false
	_add(def)
	if current_slot == 0:
		_equip_now(def.slot)
	return true


## Takes away every gun, keeping blades (dying: the guns go into your
## dropped gear, Increment 16.6). The blade, if any, comes out.
func remove_guns() -> void:
	for s in range(1, SLOT_COUNT + 1):
		var w := weapons[s]
		if w != null and not w.definition.melee:
			w.get_parent().remove_child(w)
			w.queue_free()
			weapons[s] = null
	pending_slot = 0
	_holstering = false
	var first := first_owned_slot()
	if first > 0:
		_equip_now(first)
	else:
		current_slot = 0
		if _player != null:
			_player.weapon = null


## Removes the gun in `slot` (put away into the backpack, Increment 16.7).
## If it was in your hands, the next gun you have comes out.
func remove_weapon(slot: int) -> void:
	var w := get_weapon(slot)
	if w == null:
		return
	var was_current := slot == current_slot or slot == pending_slot
	w.get_parent().remove_child(w)
	w.queue_free()
	weapons[slot] = null
	if not was_current:
		return
	pending_slot = 0
	_holstering = false
	var next := first_owned_slot()
	if next > 0:
		_equip_now(next)
	else:
		current_slot = 0
		if _player != null:
			_player.weapon = null


## Starts switching to a slot (validated: owned, not already in hand).
func request_slot(slot: int) -> bool:
	if slot < 1 or slot > SLOT_COUNT or weapons[slot] == null:
		return false
	if slot == current_slot and pending_slot == 0:
		return false
	if slot == pending_slot:
		return false
	var current := get_current()
	if current != null:
		current.cancel_reload()
		current.lowered = true
	pending_slot = slot
	_holstering = current != null and slot != current_slot
	_phase_left = holster_time if _holstering else 0.0
	switch_started.emit(slot)
	if not _holstering:
		_begin_draw()
	return true


## Next/previous owned slot (mouse wheel). direction = +1 or -1.
func cycle(direction: int) -> bool:
	var from := pending_slot if pending_slot != 0 else current_slot
	for i in range(1, SLOT_COUNT + 1):
		var s := wrapi(from + direction * i, 1, SLOT_COUNT + 1)
		if weapons[s] != null and s != from:
			return request_slot(s)
	return false


## Advances a switch in progress. Called every simulation step.
func tick(delta: float) -> void:
	if pending_slot == 0:
		return
	_phase_left -= delta
	if _phase_left > 0.0:
		return
	if _holstering:
		_holstering = false
		_begin_draw()
	else:
		pending_slot = 0
		weapon_equipped.emit(get_current())


## Instantly equips a slot (respawn, loading a save).
func equip_immediately(slot: int) -> void:
	if get_weapon(slot) == null:
		return
	pending_slot = 0
	_holstering = false
	_equip_now(slot)


func _begin_draw() -> void:
	var old := get_current()
	if old != null:
		old.visible = false
		old.cancel_reload()
	current_slot = pending_slot
	var w := get_current()
	w.visible = true
	w.lowered = true
	w.snap_lowered()
	w.lowered = false
	_phase_left = w.definition.draw_time
	_player.weapon = w


func _equip_now(slot: int) -> void:
	for s in range(1, SLOT_COUNT + 1):
		if weapons[s] != null:
			weapons[s].visible = s == slot
	current_slot = slot
	var w := get_current()
	w.lowered = false
	_player.weapon = w
	weapon_equipped.emit(w)


func _add(def: WeaponDefinition) -> HitscanWeapon:
	var was_in_hand := def.slot == current_slot and weapons[def.slot] != null
	if weapons[def.slot] != null:
		# An upgrade replaces the gun in that slot (pipe pistol → pistol)
		weapons[def.slot].queue_free()
		weapons[def.slot] = null
	var w := def.instantiate_weapon()
	w.name = String(def.id).to_pascal_case()
	w.visible = false
	_mount.add_child(w)
	w.aim_camera = _player.camera
	if _player.inventory != null:
		w.set_ammo_source(_player.inventory)
	weapons[def.slot] = w
	weapon_added.emit(w)
	if was_in_hand:
		_equip_now(def.slot)
	return w


# ---------------------------------------------------------------- saving

## [{"id", "magazine"}, ...] plus which slot is in hand.
func save_state() -> Dictionary:
	var list := []
	for w in owned():
		var atts := []
		for slot in w.attachments:
			atts.append(String((w.attachments[slot] as AttachmentDefinition).id))
		list.append({"id": String(w.base_definition.id), "magazine": w.ammo_in_magazine, "attachments": atts})
	return {"weapons": list, "equipped": current_slot}


func load_state(data: Dictionary) -> void:
	var list: Variant = data.get("weapons")
	if not list is Array:
		return
	var wanted := {}
	for e in list:
		if not e is Dictionary:
			continue
		var def := ItemDatabase.get_weapon(StringName(str(e.get("id", ""))))
		if def == null or def.scene_path == "":
			continue
		wanted[def.slot] = [def, e.get("magazine"), e.get("attachments", [])]
	if wanted.is_empty():
		return  # never leave the player unarmed because of a bad save
	for s in range(1, SLOT_COUNT + 1):
		if not wanted.has(s) and weapons[s] != null:
			weapons[s].queue_free()
			weapons[s] = null
	for s in wanted:
		var def: WeaponDefinition = wanted[s][0]
		var w := weapons[s] if weapons[s] != null and weapons[s].base_definition.id == def.id else _add(def)
		# Attachments first: they can change the magazine size
		for slot in w.attachments.keys():
			w.remove_attachment(slot)
		var atts: Variant = wanted[s][2]
		if atts is Array:
			for att_id in atts:
				var att := ItemDatabase.get_attachment(StringName(str(att_id)))
				if att != null and att.fits(def.id):
					w.fit_attachment(att)
		var mag: Variant = wanted[s][1]
		if mag is float or mag is int:
			w.cancel_reload()
			w.ammo_in_magazine = clampi(int(mag), 0, w.definition.magazine_size)
	var equip := int(data.get("equipped", 0)) if (data.get("equipped") is float or data.get("equipped") is int) else 0
	equip_immediately(equip if get_weapon(equip) != null else first_owned_slot())
