class_name InventoryComponent
extends Node
## A grid of item slots with stack limits and an optional weight limit.
## Used by the player now; by salvage containers, settlers, vehicles and
## storage buildings later.
##
## Each slot is either null or a Dictionary {"item": ItemDefinition, "qty": int}.
## A gun's slot also carries its own "state" (Increment 32): the rounds in
## its magazine and its attachments, {"magazine": int, "attachments": [ids]},
## kept wherever it goes (backpack, quick bar, a chest, your gear). Things
## with a state never stack.
##
## AUTHORITY: every method that changes contents (add_item, remove_item,
## move_slot, transfer_slot_to, receive…) runs only where the game state
## lives (single-player, or the co-op host). They validate their arguments,
## so the host can call them with a guest's request directly.

## Emitted after any change; `slots` lists the indices that changed.
signal contents_changed(slots: PackedInt32Array)
## Emitted when items come in from outside (pickups, transfers in).
signal item_received(item: ItemDefinition, quantity: int)
## The number of slots or the weight limit changed (a different backpack).
signal capacity_changed

@export_range(1, 200) var slot_count := 24
## Kilograms. 0 = no weight limit.
@export var max_weight := 30.0

var _slots: Array = []


func _init() -> void:
	_resize()


func _ready() -> void:
	_resize()


func _resize() -> void:
	if _slots.size() != slot_count:
		_slots.resize(slot_count)


# ---------------------------------------------------------------- queries

func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= _slots.size() or _slots[index] == null:
		return {}
	return _slots[index]


func get_slot_item(index: int) -> ItemDefinition:
	return get_slot(index).get("item")


func get_slot_quantity(index: int) -> int:
	return get_slot(index).get("qty", 0)


## A gun's own state in slot `index` (a copy), or {} for anything else.
func get_slot_state(index: int) -> Dictionary:
	var st: Variant = get_slot(index).get("state")
	return (st as Dictionary).duplicate(true) if st is Dictionary else {}


## Things that carry a state of their own (guns: Increment 32).
static func has_state(item: ItemDefinition) -> bool:
	return item != null and item.weapon != null


## A gun's state, checked and filled in: {"magazine", "attachments"}. A gun
## with none (found in a crate, or saved before Increment 32) is as found:
## loaded, with nothing fitted.
static func clean_state(item: ItemDefinition, raw: Variant) -> Dictionary:
	if not has_state(item):
		return {}
	var d: Dictionary = raw if raw is Dictionary and not (raw as Dictionary).is_empty() else {"magazine": item.weapon.magazine_size}
	var mag: Variant = d.get("magazine", 0)
	var atts: Array = []
	if d.get("attachments") is Array:
		for a in d["attachments"]:
			if a is String or a is StringName:
				atts.append(String(a))
	return {"magazine": maxi(int(mag), 0) if (mag is int or mag is float) else 0, "attachments": atts}


func is_slot_empty(index: int) -> bool:
	return get_slot(index).is_empty()


func count_of(id: StringName) -> int:
	var total := 0
	for s in _slots:
		if s != null and (s["item"] as ItemDefinition).id == id:
			total += s["qty"]
	return total


func get_total_weight() -> float:
	var total := 0.0
	for s in _slots:
		if s != null:
			total += (s["item"] as ItemDefinition).weight * s["qty"]
	return total


func get_free_slot_count() -> int:
	return _slots.count(null)


## How many of `item` could be added right now (slots, stacks and weight).
func can_add(item: ItemDefinition, quantity: int) -> int:
	if item == null or quantity <= 0:
		return 0
	var room := 0
	for s in _slots:
		if s == null:
			room += item.max_stack if not has_state(item) else 1
		elif s["item"] == item and not has_state(item):
			room += item.max_stack - s["qty"]
	var fit := mini(quantity, room)
	if max_weight > 0.0 and item.weight > 0.0:
		var by_weight := int(floor((max_weight - get_total_weight()) / item.weight + 0.0001))
		fit = mini(fit, maxi(by_weight, 0))
	return fit


## True if, after removing `remove` ({ItemDefinition: qty}), all of
## `quantity` × `item` would fit. Changes nothing and emits nothing (used to
## check a crafting recipe's output before starting it).
func can_exchange(remove: Dictionary, item: ItemDefinition, quantity: int) -> bool:
	# (The same entries put back as they were: a gun's entry is followed by
	# its live weapon, so it mustn't be swapped for a copy)
	var saved := _slots.duplicate()
	var qtys := _slots.map(func(e: Variant) -> int: return e["qty"] if e != null else 0)
	set_block_signals(true)
	for it: ItemDefinition in remove:
		remove_item(it.id, int(remove[it]))
	var fits := can_add(item, quantity) >= quantity
	_slots = saved
	for i in _slots.size():
		if _slots[i] != null:
			_slots[i]["qty"] = qtys[i]
	set_block_signals(false)
	return fits


## "" if at least one could be added, otherwise why not.
func get_refusal_reason(item: ItemDefinition, quantity: int) -> String:
	if item == null or quantity <= 0:
		return "Nothing to take"
	if can_add(item, 1) > 0:
		return ""
	if max_weight > 0.0 and get_total_weight() + item.weight > max_weight:
		return "Too heavy"
	return "Inventory full"


# ---------------------------------------------------------------- changes

## Adds up to `quantity`, filling existing stacks first. Returns how many fit.
## A gun goes in with `state` (or as found: loaded, nothing fitted).
func add_item(item: ItemDefinition, quantity: int, state: Dictionary = {}) -> int:
	var to_add := can_add(item, quantity)
	if to_add <= 0:
		return 0
	var left := to_add
	var changed := PackedInt32Array()
	for i in _slots.size():
		if left == 0 or has_state(item):
			break
		var s = _slots[i]
		if s != null and s["item"] == item and s["qty"] < item.max_stack:
			var n := mini(left, item.max_stack - s["qty"])
			s["qty"] += n
			left -= n
			changed.append(i)
	for i in _slots.size():
		if left == 0:
			break
		if _slots[i] == null:
			var n := mini(left, item.max_stack) if not has_state(item) else 1
			_slots[i] = _entry(item, n, state)
			left -= n
			changed.append(i)
	contents_changed.emit(changed)
	return to_add


func _entry(item: ItemDefinition, qty: int, state: Variant) -> Dictionary:
	var e := {"item": item, "qty": qty}
	if has_state(item):
		e["state"] = clean_state(item, state)
	return e


## Puts `quantity` of `item` into empty slot `index` (if it's empty and it
## fits). Returns how many went in.
## `ignore_weight`: it's moving within what you carry (no heavier).
func add_to_slot(index: int, item: ItemDefinition, quantity: int, state: Dictionary = {}, ignore_weight := false) -> int:
	if index < 0 or index >= _slots.size() or _slots[index] != null:
		return 0
	var limit := max_weight
	if ignore_weight:
		max_weight = 0.0
	var n := mini(can_add(item, quantity), item.max_stack if not has_state(item) else 1)
	max_weight = limit
	if n <= 0:
		return 0
	_slots[index] = _entry(item, n, state)
	contents_changed.emit(PackedInt32Array([index]))
	return n


## Tops up the stack in slot `index` with up to `quantity` more of what's
## in it (not guns: each is its own). Returns how many went on. Weight isn't
## checked: for moving what's already carried.
func add_to_stack(index: int, quantity: int) -> int:
	var s := get_slot(index)
	if s.is_empty() or has_state(s["item"]) or quantity <= 0:
		return 0
	var n := mini(quantity, (s["item"] as ItemDefinition).max_stack - int(s["qty"]))
	if n <= 0:
		return 0
	s["qty"] += n
	contents_changed.emit(PackedInt32Array([index]))
	return n


## Why the contents wouldn't fit in `slots` slots and `weight` kg (0 = no
## limit), "" if they would. Leaves everything as it is.
func capacity_refusal_reason(slots: int, weight: float) -> String:
	var used := slot_count - get_free_slot_count()
	if used > slots:
		return "Too many things: empty %d slot%s first" % [used - slots, "" if used - slots == 1 else "s"]
	var w := get_total_weight()
	if weight > 0.0 and w > weight + 0.001:
		return "Too heavy: drop %.1f kg first" % (w - weight)
	return ""


## Changes how many slots there are and the weight limit (a backpack,
## Increment 16.8). Shrinking moves things out of the slots that go into
## empty ones that stay. Returns false (and changes nothing) if the
## contents wouldn't fit.
func set_capacity(slots: int, weight: float) -> bool:
	slots = clampi(slots, 1, 200)
	if capacity_refusal_reason(slots, weight) != "":
		return false
	if slots < _slots.size():
		var free: Array[int] = []
		for i in slots:
			if _slots[i] == null:
				free.append(i)
		for i in range(slots, _slots.size()):
			if _slots[i] != null:
				_slots[free.pop_front()] = _slots[i]
				_slots[i] = null
	slot_count = slots
	max_weight = weight
	_resize()
	capacity_changed.emit()
	contents_changed.emit(PackedInt32Array(range(_slots.size())))
	return true


## Pickups and other outside sources use this: adds and announces.
func receive(item: ItemDefinition, quantity: int, state: Dictionary = {}) -> int:
	var added := add_item(item, quantity, state)
	if added > 0:
		item_received.emit(item, added)
	return added


## Removes up to `quantity` of the item (last stacks first). Returns how many.
func remove_item(id: StringName, quantity: int) -> int:
	var left := quantity
	var changed := PackedInt32Array()
	for i in range(_slots.size() - 1, -1, -1):
		if left <= 0:
			break
		var s = _slots[i]
		if s != null and (s["item"] as ItemDefinition).id == id:
			var n := mini(left, s["qty"])
			s["qty"] -= n
			left -= n
			if s["qty"] <= 0:
				_slots[i] = null
			changed.append(i)
	if not changed.is_empty():
		contents_changed.emit(changed)
	return quantity - left


## Takes up to `quantity` from one slot. Returns {"item", "qty"} taken ({} if
## none), and a gun's "state".
func take_from_slot(index: int, quantity: int = -1) -> Dictionary:
	var s := get_slot(index)
	if s.is_empty():
		return {}
	var n: int = s["qty"] if quantity < 0 else mini(quantity, s["qty"])
	if n <= 0:
		return {}
	s["qty"] -= n
	if s["qty"] <= 0:
		_slots[index] = null
	contents_changed.emit(PackedInt32Array([index]))
	var out := {"item": s["item"], "qty": n}
	if s.has("state"):
		out["state"] = (s["state"] as Dictionary).duplicate(true)
	return out


## Moves a slot onto another: merges same items (up to the stack limit),
## swaps different items, or moves into an empty slot. `quantity` < 0 moves
## the whole stack; a smaller number splits it (only into an empty or
## matching slot). Returns true if anything changed.
func move_slot(from: int, to: int, quantity: int = -1) -> bool:
	if from == to or from < 0 or to < 0 or from >= _slots.size() or to >= _slots.size():
		return false
	var src = _slots[from]
	if src == null:
		return false
	var amount: int = src["qty"] if quantity < 0 else clampi(quantity, 1, src["qty"])
	var dst = _slots[to]
	if dst == null:
		if amount == src["qty"]:
			_slots[to] = src
			_slots[from] = null
		else:
			_slots[to] = {"item": src["item"], "qty": amount}
			src["qty"] -= amount
	elif dst["item"] == src["item"] and not has_state(src["item"]):
		var n := mini(amount, (src["item"] as ItemDefinition).max_stack - dst["qty"])
		if n <= 0:
			return false
		dst["qty"] += n
		src["qty"] -= n
		if src["qty"] <= 0:
			_slots[from] = null
	else:
		if amount != src["qty"]:
			return false  # can't split onto a different item
		_slots[to] = src
		_slots[from] = dst
	contents_changed.emit(PackedInt32Array([from, to]))
	return true


## Moves (part of) a slot into another inventory, respecting its limits.
## Returns how many moved.
func transfer_slot_to(index: int, other: InventoryComponent, quantity: int = -1) -> int:
	var s := get_slot(index)
	if s.is_empty() or other == null or other == self:
		return 0
	var want: int = s["qty"] if quantity < 0 else mini(quantity, s["qty"])
	var moved := other.receive(s["item"], want, get_slot_state(index))
	if moved > 0:
		take_from_slot(index, moved)
	return moved


func clear() -> void:
	for i in _slots.size():
		_slots[i] = null
	contents_changed.emit(PackedInt32Array(range(_slots.size())))


# ---------------------------------------------------------------- saving

## Plain data for saves and the network: [{"id", "qty", "slot"}, ...].
func to_data() -> Array:
	var out := []
	for i in _slots.size():
		var s = _slots[i]
		if s != null:
			var e := {"id": String((s["item"] as ItemDefinition).id), "qty": s["qty"], "slot": i}
			if s.has("state"):
				e["state"] = (s["state"] as Dictionary).duplicate(true)
			out.append(e)
	return out


## Restores from to_data(). Unknown ids and bad numbers are skipped.
func from_data(data: Array) -> void:
	for i in _slots.size():
		_slots[i] = null
	for entry in data:
		if not entry is Dictionary:
			continue
		var item := ItemDatabase.get_item(StringName(str(entry.get("id", ""))))
		var slot := int(entry.get("slot", -1))
		var qty := int(entry.get("qty", 0))
		if item == null or slot < 0 or slot >= _slots.size() or qty <= 0 or _slots[slot] != null:
			continue
		_slots[slot] = _entry(item, mini(qty, item.max_stack) if not has_state(item) else 1, entry.get("state"))
	contents_changed.emit(PackedInt32Array(range(_slots.size())))


# ---------------------------------------------------------------- ammo

## Total rounds of `ammo_type` (sums every AMMO item that feeds it).
func count_ammo(ammo_type: StringName) -> int:
	var total := 0
	for s in _slots:
		if s != null and (s["item"] as ItemDefinition).category == ItemDefinition.Category.AMMO \
				and (s["item"] as ItemDefinition).ammo_type == ammo_type:
			total += s["qty"]
	return total


## Removes up to `amount` rounds of `ammo_type`. Returns how many were taken.
func take_ammo(ammo_type: StringName, amount: int) -> int:
	var left := amount
	var changed := PackedInt32Array()
	for i in range(_slots.size() - 1, -1, -1):
		if left <= 0:
			break
		var s = _slots[i]
		if s != null and (s["item"] as ItemDefinition).category == ItemDefinition.Category.AMMO \
				and (s["item"] as ItemDefinition).ammo_type == ammo_type:
			var n := mini(left, s["qty"])
			s["qty"] -= n
			left -= n
			if s["qty"] <= 0:
				_slots[i] = null
			changed.append(i)
	if not changed.is_empty():
		contents_changed.emit(changed)
	return amount - left


## Finds the InventoryComponent that is a direct child of `node`.
static func find_on(node: Node) -> InventoryComponent:
	if node == null:
		return null
	for child in node.get_children():
		if child is InventoryComponent:
			return child
	return null
