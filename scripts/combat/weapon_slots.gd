class_name WeaponSlots
extends Node
## What's in your hands, from the quick bar (Increment 32): eight slots,
## keys 1-8 or the mouse wheel. Any slot can hold any gun or blade (two
## pistols if you like), or a medkit, food or the Field Manual to use.
##
## The QuickBar holds the items; each gun on it has a live HitscanWeapon
## under the camera's WeaponMount, tied to its bar entry, so its rounds and
## attachments follow it wherever it's moved, and are written back into the
## entry as they change (the entry's "state" is always current). Only the
## selected one is visible and ticked. Switching takes the old gun down
## (holster_time) and brings the new one up (its draw_time); you can't fire,
## aim or reload in between.
##
## Lives in the player scene as %WeaponSlots. PlayerController calls setup()
## from _ready and tick() every simulation step.

signal weapon_added(weapon: HitscanWeapon)
## Emitted when a switch starts (the new weapon isn't usable yet).
signal switch_started(to_slot: int)
## The new weapon is up and usable.
signal weapon_equipped(weapon: HitscanWeapon)
## The selected slot changed (a gun, an item, or empty hands).
signal selection_changed(slot: int)

const SLOT_COUNT := QuickBar.SIZE
## Seconds to bring up something that isn't a gun (a medkit, food).
const ITEM_DRAW := 0.15

## Guns and blades you start with, in slots 1, 2… (and get back on a new game).
@export var starting_weapons: Array[WeaponDefinition] = []
## Seconds to put the current gun away before the next comes up.
@export var holster_time := 0.2

## Slot number (1-8) → its live gun, or null (empty, or an item).
var weapons: Array[HitscanWeapon] = []
## Slot in hand (0 = none).
var current_slot := 0
## Slot being switched to (0 = not switching).
var pending_slot := 0
## The quick bar (PlayerController sets it up).
var bar: QuickBar

var _player: PlayerController
var _mount: Node3D
var _phase_left := 0.0
var _holstering := false
## The bar entry in hand: selection follows it when it's moved.
var _held_entry: Variant = null
## The bar entry being switched to (follows it if it moves mid-switch).
var _pending_entry: Variant = null


func _init() -> void:
	weapons.resize(SLOT_COUNT + 1)


## Called by PlayerController._ready once the quick bar exists. Puts the
## starting guns on the bar and takes the first out (no draw delay at spawn).
func setup(player: PlayerController, mount: Node3D) -> void:
	_player = player
	_mount = mount
	if bar != null and not bar.contents_changed.is_connected(_on_bar_changed):
		bar.contents_changed.connect(_on_bar_changed)
		bar.sync = sync_states
	give_starting_weapons()
	var first := first_owned_slot()
	if first > 0:
		equip_immediately(first)


## The starting guns, into the first free slots (a new game, or after a save
## left you with nothing). `blades_only`: just the blade (respawning).
func give_starting_weapons(blades_only := false) -> void:
	for def in starting_weapons:
		if find_slot(def.id) == 0 and (def.melee or not blades_only):
			give_weapon(def)


# ---------------------------------------------------------------- queries

func get_current() -> HitscanWeapon:
	return weapons[current_slot] if current_slot > 0 else null


func get_weapon(slot: int) -> HitscanWeapon:
	return weapons[slot] if slot >= 1 and slot <= SLOT_COUNT else null


## The item in `slot` (a gun's item too), or null.
func get_item(slot: int) -> ItemDefinition:
	return bar.get_slot_item(slot - 1) if bar != null and slot >= 1 and slot <= SLOT_COUNT else null


## The item in your hands that isn't a gun (a medkit, food…), or null.
func held_item() -> ItemDefinition:
	if current_slot == 0 or pending_slot != 0 or get_current() != null:
		return null
	return get_item(current_slot)


func has_weapon(id: StringName) -> bool:
	return find_slot(id) > 0


## The first slot holding the gun `id` (0 = none).
func find_slot(id: StringName) -> int:
	for s in range(1, SLOT_COUNT + 1):
		if weapons[s] != null and weapons[s].base_definition.id == id:
			return s
	return 0


## The slot `w` is in (0 = not on the bar).
func slot_of(w: HitscanWeapon) -> int:
	return weapons.find(w) if w != null else 0


func first_owned_slot() -> int:
	for s in range(1, SLOT_COUNT + 1):
		if weapons[s] != null:
			return s
	return 0


## The first slot with anything in it (0 = an empty bar).
func first_filled_slot() -> int:
	for s in range(1, SLOT_COUNT + 1):
		if get_item(s) != null:
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


# ---------------------------------------------------------------- changes

## Puts a gun on the bar, loaded, in the first empty slot. Returns false if
## the bar is full (or the definition is bad). With nothing in your hands it
## comes straight out.
func give_weapon(def: WeaponDefinition, state: Dictionary = {}) -> bool:
	var item := ItemDatabase.find_weapon_item(def.id) if def != null else null
	if item == null or def.scene_path == "" or bar == null:
		return false
	var at := bar.first_empty()
	if at < 0:
		return false
	if state.is_empty():
		state = {"magazine": def.magazine_size, "attachments": []}
	var limit := bar.owner_inventory.max_weight if bar.owner_inventory != null else 0.0
	if bar.owner_inventory != null:
		bar.owner_inventory.max_weight = 0.0  # never refused for weight here
	bar.add_to_slot(at, item, 1, state)
	if bar.owner_inventory != null:
		bar.owner_inventory.max_weight = limit
	if current_slot == 0 or (get_current() == null and held_item() == null):
		equip_immediately(at + 1)
	return true


## Takes away everything on the bar but blades (dying: it goes into your
## dropped gear, Increment 16.6). A blade, if any, comes out.
func remove_guns() -> void:
	if bar == null:
		return
	for i in bar.slot_count:
		var item := bar.get_slot_item(i)
		if item != null and not (item.weapon != null and item.weapon.melee):
			bar.take_from_slot(i)
	pending_slot = 0
	_holstering = false
	var first := first_owned_slot()
	if first > 0:
		equip_immediately(first)
	else:
		_select_nothing()


## Removes whatever is in `slot` from the bar (it's gone: the caller has put
## it somewhere).
func remove_weapon(slot: int) -> void:
	if bar != null and get_item(slot) != null:
		bar.take_from_slot(slot - 1)


## Starts switching to a slot (validated: something there, not already in hand).
func request_slot(slot: int) -> bool:
	if slot < 1 or slot > SLOT_COUNT or get_item(slot) == null:
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
	_pending_entry = bar.entry(slot - 1)
	_holstering = current != null and slot != current_slot
	_phase_left = holster_time if _holstering else 0.0
	switch_started.emit(slot)
	if not _holstering:
		_begin_draw()
	return true


## Next/previous slot with something in it (mouse wheel). direction = +1 or -1.
func cycle(direction: int) -> bool:
	var from := pending_slot if pending_slot != 0 else current_slot
	for i in range(1, SLOT_COUNT + 1):
		var s := wrapi(from + direction * i, 1, SLOT_COUNT + 1)
		if get_item(s) != null and s != from:
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
		var w := get_current()
		if w != null:
			weapon_equipped.emit(w)
		selection_changed.emit(current_slot)


## Instantly takes out a slot (respawn, loading a save).
func equip_immediately(slot: int) -> void:
	if get_item(slot) == null:
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
	_held_entry = bar.entry(current_slot - 1)
	var w := get_current()
	if w != null:
		w.visible = true
		w.lowered = true
		w.snap_lowered()
		w.lowered = false
		_phase_left = w.definition.draw_time
	else:
		_phase_left = ITEM_DRAW
	_player.weapon = w


func _equip_now(slot: int) -> void:
	for s in range(1, SLOT_COUNT + 1):
		if weapons[s] != null:
			weapons[s].visible = s == slot
	current_slot = slot
	_held_entry = bar.entry(slot - 1)
	var w := get_current()
	if w != null:
		w.lowered = false
	_player.weapon = w
	if w != null:
		weapon_equipped.emit(w)
	selection_changed.emit(current_slot)


func _select_nothing() -> void:
	for s in range(1, SLOT_COUNT + 1):
		if weapons[s] != null:
			weapons[s].visible = false
	current_slot = 0
	pending_slot = 0
	_holstering = false
	_held_entry = null
	if _player != null:
		_player.weapon = null
	selection_changed.emit(0)


# ---------------------------------------------------------------- the bar's guns

## Something on the bar changed: guns that arrived get a live weapon, guns
## that left have theirs freed, and what's in your hands follows its entry.
func _on_bar_changed(_slots: PackedInt32Array) -> void:
	reconcile()


func reconcile() -> void:
	if bar == null or _mount == null:
		return
	var live := {}
	for s in range(1, SLOT_COUNT + 1):
		var e: Variant = bar.entry(s - 1)
		var w: HitscanWeapon = null
		if e != null and (e["item"] as ItemDefinition).weapon != null:
			var tied: Variant = e.get("live")
			if tied is HitscanWeapon and is_instance_valid(tied) and (tied as HitscanWeapon).base_definition == (e["item"] as ItemDefinition).weapon:
				w = tied
			else:
				w = _instance(e)
		weapons[s] = w
		if w != null:
			live[w] = true
	var lost_hand := false
	for c in _mount.get_children():
		if c is HitscanWeapon and not live.has(c):
			if c == _player.weapon:
				lost_hand = true
			_mount.remove_child(c)
			c.queue_free()
	# What's in your hands follows its entry; if it's gone, the slot it was
	# in stays selected (empty hands if nothing's there now)
	var at := _find_entry(_held_entry)
	if pending_slot != 0:
		# A switch under way carries on if what it's switching to is still
		# on the bar (wherever it is now)
		var to := _find_entry(_pending_entry)
		if to > 0:
			pending_slot = to
			if _holstering and (lost_hand or at <= 0):
				_holstering = false
				_begin_draw()
			elif not _holstering:
				current_slot = to
			elif at > 0:
				current_slot = at
			return
		pending_slot = 0
		_holstering = false
		if at > 0:
			_equip_now(at)
			return
	if at > 0:
		if at != current_slot or lost_hand or _player.weapon != get_current():
			_equip_now(at)
		return
	if current_slot > 0 and get_item(current_slot) != null:
		_equip_now(current_slot)
	elif current_slot > 0 or lost_hand:
		_select_nothing()
		# Never left empty-handed with a blade on the bar after losing a gun
		if lost_hand and first_owned_slot() > 0:
			_equip_now(first_owned_slot())


## The slot (1-8) holding bar entry `e` (0 = it's gone).
func _find_entry(e: Variant) -> int:
	if e == null or bar == null:
		return 0
	for i in bar.slot_count:
		if is_same(bar.entry(i), e):
			return i + 1
	return 0


## A live gun for bar entry `e`, set up from its state.
func _instance(e: Dictionary) -> HitscanWeapon:
	var def := (e["item"] as ItemDefinition).weapon
	var w := def.instantiate_weapon()
	w.name = "%s_%d" % [String(def.id).to_pascal_case(), Time.get_ticks_usec() % 1000000]
	w.visible = false
	_mount.add_child(w)
	w.aim_camera = _player.camera
	if _player.inventory != null:
		w.set_ammo_source(_player.inventory)
	apply_state(w, e.get("state", {}))
	e["live"] = w
	w.set_meta("entry", e)
	w.ammo_changed.connect(func(_m: int, _r: int) -> void: _write_state(w))
	w.attachments_changed.connect(func() -> void: _write_state(w))
	weapon_added.emit(w)
	return w


## Fits a gun out as a saved state says: attachments, then its magazine.
static func apply_state(w: HitscanWeapon, state: Variant) -> void:
	var st: Dictionary = state if state is Dictionary else {}
	for slot in w.attachments.keys():
		w.remove_attachment(slot)
	if st.get("attachments") is Array:
		for att_id in st["attachments"]:
			var att := ItemDatabase.get_attachment(StringName(str(att_id)))
			if att != null and att.fits(w.base_definition.id):
				w.fit_attachment(att)
	var mag: Variant = st.get("magazine", 0)
	w.cancel_reload()
	w.ammo_in_magazine = clampi(int(mag), 0, w.definition.magazine_size) if (mag is int or mag is float) else 0


## A gun's state as it is now.
static func state_of(w: HitscanWeapon) -> Dictionary:
	var atts := []
	for slot in w.attachments:
		atts.append(String((w.attachments[slot] as AttachmentDefinition).id))
	return {"magazine": w.ammo_in_magazine, "attachments": atts}


## Writes every live gun's rounds and attachments into its bar entry.
func sync_states() -> void:
	for w in owned():
		_write_state(w)


func _write_state(w: HitscanWeapon) -> void:
	if not is_instance_valid(w) or not w.has_meta("entry"):
		return
	var e: Dictionary = w.get_meta("entry")
	if is_same(e.get("live"), w):
		e["state"] = state_of(w)


# ---------------------------------------------------------------- saving

## The selected slot (the bar itself is saved by the player, with its items).
func save_state() -> Dictionary:
	return {"equipped": current_slot}


func load_state(data: Dictionary) -> void:
	reconcile()
	var equip := int(data.get("equipped", 0)) if (data.get("equipped") is float or data.get("equipped") is int) else 0
	if get_item(equip) != null:
		equip_immediately(equip)
	elif first_owned_slot() > 0:
		equip_immediately(first_owned_slot())
	elif first_filled_slot() > 0:
		equip_immediately(first_filled_slot())
	else:
		_select_nothing()


## Saves from before the quick bar (Increment 32): {"weapons": [{"id",
## "magazine", "attachments"}], "equipped": slot}. Each gun goes into the bar
## slot of its old weapon slot (1 rifle … 5 blade), as it was.
func migrate_loadout(data: Dictionary) -> void:
	var list: Variant = data.get("weapons")
	if not list is Array or bar == null:
		return
	bar.clear()
	var placed := 0
	for e in list:
		if not e is Dictionary:
			continue
		var def := ItemDatabase.get_weapon(StringName(str(e.get("id", ""))))
		var item := ItemDatabase.find_weapon_item(def.id) if def != null else null
		if item == null or def.slot < 1 or def.slot > SLOT_COUNT:
			continue
		if not bar.is_slot_empty(def.slot - 1):
			bar.take_from_slot(def.slot - 1)
		bar.add_to_slot(def.slot - 1, item, 1, {"magazine": e.get("magazine", 0), "attachments": e.get("attachments", [])}, true)
		placed += 1
	if placed == 0:
		give_starting_weapons()
	reconcile()
	var old := int(data.get("equipped", 0)) if (data.get("equipped") is float or data.get("equipped") is int) else 0
	load_state({"equipped": old})
