class_name InventoryComponent
extends Node
## A grid of item slots with stack limits and an optional weight limit.
## Used by the player now; by salvage containers, settlers, vehicles and
## storage buildings later.
##
## Each slot is either null or a Dictionary {"item": ItemDefinition, "qty": int}.
##
## AUTHORITY: every method that changes contents (add_item, remove_item,
## move_slot, transfer_slot_to, receive…) runs only where the game state
## lives (single-player, or the co-op host). They validate their arguments,
## so the host can call them with a guest's request directly.

## Emitted after any change; `slots` lists the indices that changed.
signal contents_changed(slots: PackedInt32Array)
## Emitted when items come in from outside (pickups, transfers in).
signal item_received(item: ItemDefinition, quantity: int)

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
			room += item.max_stack
		elif s["item"] == item:
			room += item.max_stack - s["qty"]
	var fit := mini(quantity, room)
	if max_weight > 0.0 and item.weight > 0.0:
		var by_weight := int(floor((max_weight - get_total_weight()) / item.weight + 0.0001))
		fit = mini(fit, maxi(by_weight, 0))
	return fit


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
func add_item(item: ItemDefinition, quantity: int) -> int:
	var to_add := can_add(item, quantity)
	if to_add <= 0:
		return 0
	var left := to_add
	var changed := PackedInt32Array()
	for i in _slots.size():
		if left == 0:
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
			var n := mini(left, item.max_stack)
			_slots[i] = {"item": item, "qty": n}
			left -= n
			changed.append(i)
	contents_changed.emit(changed)
	return to_add


## Pickups and other outside sources use this: adds and announces.
func receive(item: ItemDefinition, quantity: int) -> int:
	var added := add_item(item, quantity)
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


## Takes up to `quantity` from one slot. Returns {"item", "qty"} taken ({} if none).
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
	return {"item": s["item"], "qty": n}


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
	elif dst["item"] == src["item"]:
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
	var moved := other.receive(s["item"], want)
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
			out.append({"id": String((s["item"] as ItemDefinition).id), "qty": s["qty"], "slot": i})
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
		_slots[slot] = {"item": item, "qty": mini(qty, item.max_stack)}
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
