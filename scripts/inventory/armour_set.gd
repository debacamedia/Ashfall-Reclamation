class_name ArmourSet
extends RefCounted
## What someone wears (Increment 22): a head, body and legs piece, each with
## how much wear it has left. Worn by the player (PlayerController.armour)
## and by settlers (guards).
##
## A hit (bullets, blades, blasts: not falls, the storm or hunger) loses
## `protection()` of its damage, at most MAX_PROTECTION; each piece wears by
## its share of what it stopped. A piece worn out (no wear left) protects
## nothing until it's repaired at a workbench.

signal changed

const HEAD := 1
const BODY := 2
const LEGS := 3
const SLOTS := [HEAD, BODY, LEGS]
const SLOT_NAMES := {HEAD: "Head", BODY: "Body", LEGS: "Legs"}
const MAX_PROTECTION := 0.6

## slot -> {"item": ItemDefinition, "wear": float (durability left)}
var slots := {}


func worn(slot: int) -> ItemDefinition:
	return (slots[slot]["item"] as ItemDefinition) if slots.has(slot) else null


## Durability left on the piece in `slot` (0 if none).
func wear_left(slot: int) -> float:
	return float(slots[slot]["wear"]) if slots.has(slot) else 0.0


## 0-1: how much wear the piece in `slot` has left.
func condition(slot: int) -> float:
	var it := worn(slot)
	if it == null or it.armour_durability <= 0.0:
		return 0.0
	return clampf(wear_left(slot) / it.armour_durability, 0.0, 1.0)


func is_worn_out(slot: int) -> bool:
	return worn(slot) != null and wear_left(slot) <= 0.0


func is_empty() -> bool:
	return slots.is_empty()


## Share of a hit taken off now (pieces that aren't worn out).
func protection() -> float:
	var p := 0.0
	for slot in slots:
		if wear_left(slot) > 0.0:
			p += worn(slot).armour_protection
	return minf(p, MAX_PROTECTION)


## Walking and running speed multiplier (plated pieces are heavier).
func speed() -> float:
	var m := 1.0
	for slot in slots:
		m *= worn(slot).armour_speed
	return m


## Puts `item` on (with `wear` left: -1 = new). Returns what was there:
## {"item", "wear"} or {}.
func put_on(item: ItemDefinition, wear := -1.0) -> Dictionary:
	if item == null or not item.is_armour():
		return {}
	var slot := item.armour_slot
	var old: Dictionary = slots.get(slot, {})
	slots[slot] = {"item": item, "wear": item.armour_durability if wear < 0.0 else clampf(wear, 0.0, item.armour_durability)}
	changed.emit()
	return old


## Takes off what's in `slot`: {"item", "wear"} or {}.
func take_off(slot: int) -> Dictionary:
	if not slots.has(slot):
		return {}
	var old: Dictionary = slots[slot]
	slots.erase(slot)
	changed.emit()
	return old


func clear() -> void:
	slots.clear()
	changed.emit()


## Repairs the piece in `slot` to new.
func repair(slot: int) -> void:
	if slots.has(slot):
		slots[slot]["wear"] = worn(slot).armour_durability
		changed.emit()


## How much of a hit of `amount` (of `type`) gets through, wearing the
## pieces down by what they stop.
func absorb(amount: float, type: DamageInfo.Type) -> float:
	if amount <= 0.0 or slots.is_empty():
		return amount
	if type == DamageInfo.Type.FALL or type == DamageInfo.Type.ENVIRONMENT:
		return amount
	var p := protection()
	if p <= 0.0:
		return amount
	var stopped := amount * p
	var total := 0.0
	for slot in slots:
		if wear_left(slot) > 0.0:
			total += worn(slot).armour_protection
	for slot in slots:
		if wear_left(slot) > 0.0:
			slots[slot]["wear"] = maxf(wear_left(slot) - stopped * worn(slot).armour_protection / total, 0.0)
	changed.emit()
	return amount - stopped


## Wears the pieces as if they'd stopped `stopped` damage (a raid settled on
## paper, 20.5).
func wear_down(stopped: float) -> void:
	var total := 0.0
	for slot in slots:
		if wear_left(slot) > 0.0:
			total += worn(slot).armour_protection
	if total <= 0.0 or stopped <= 0.0:
		return
	for slot in slots:
		if wear_left(slot) > 0.0:
			slots[slot]["wear"] = maxf(wear_left(slot) - stopped * worn(slot).armour_protection / total, 0.0)
	changed.emit()


## "Leather Jacket, Scrap Helmet: 26%" or "".
func describe() -> String:
	if slots.is_empty():
		return ""
	var names: PackedStringArray = []
	for slot in SLOTS:
		if slots.has(slot):
			names.append(worn(slot).display_name + (" (worn out)" if is_worn_out(slot) else ""))
	return "%s: %d%%" % [", ".join(names), roundi(protection() * 100.0)]


func to_data() -> Dictionary:
	var out := {}
	for slot in slots:
		out[str(slot)] = {"item": String(worn(slot).id), "wear": wear_left(slot)}
	return out


func from_data(data: Variant) -> void:
	slots.clear()
	if data is Dictionary:
		for k in data:
			var e: Variant = data[k]
			if not (e is Dictionary):
				continue
			var item := ItemDatabase.get_item(StringName(str(e.get("item", ""))))
			var w: Variant = e.get("wear", -1.0)
			if item != null and item.is_armour():
				put_on(item, float(w) if (w is float or w is int) and is_finite(float(w)) else -1.0)
	changed.emit()
