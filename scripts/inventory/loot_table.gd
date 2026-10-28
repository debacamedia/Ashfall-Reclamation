class_name LootTable
extends Resource
## What a container (or later, an enemy or a scavenging run) can hold.
## Rolled once by SalvageContainer the first time it's searched.
##
## Saved as .tres in resources/loot/. Tune in the Inspector.

## Always included, before the random rolls.
@export var guaranteed: Array[LootEntry] = []
## Exactly one of these, picked by weight, on top of the rest: "one gun
## from the rack". Empty = none.
@export var one_of: Array[LootEntry] = []
## Weighted random picks.
@export var entries: Array[LootEntry] = []
@export_range(0, 20) var min_rolls := 1
@export_range(0, 20) var max_rolls := 3
## Chance the container turns out to be empty (someone got here first).
@export_range(0.0, 1.0) var empty_chance := 0.0


## Returns [{"item": ItemDefinition, "qty": int}, ...] with repeats merged.
## The same RNG seed always gives the same result.
func roll(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var totals: Dictionary[ItemDefinition, int] = {}
	if rng.randf() < empty_chance:
		return []
	for e in guaranteed:
		_add(totals, e, rng)
	if not one_of.is_empty():
		_add(totals, _pick_from(one_of, rng), rng)
	var total_weight := 0.0
	for e in entries:
		if e != null and e.item != null:
			total_weight += maxf(e.weight, 0.0)
	if total_weight > 0.0:
		var rolls := rng.randi_range(mini(min_rolls, max_rolls), maxi(min_rolls, max_rolls))
		for i in rolls:
			_add(totals, _pick(rng, total_weight), rng)
	var out: Array[Dictionary] = []
	for item in totals:
		out.append({"item": item, "qty": totals[item]})
	return out


## Every item this table can produce (for tests and tooltips).
func possible_items() -> Array[ItemDefinition]:
	var out: Array[ItemDefinition] = []
	for e in guaranteed + one_of + entries:
		if e != null and e.item != null and not out.has(e.item):
			out.append(e.item)
	return out


func _pick_from(list: Array[LootEntry], rng: RandomNumberGenerator) -> LootEntry:
	var total := 0.0
	for e in list:
		if e != null and e.item != null:
			total += maxf(e.weight, 0.0)
	if total <= 0.0:
		return null
	var r := rng.randf() * total
	for e in list:
		if e == null or e.item == null:
			continue
		r -= maxf(e.weight, 0.0)
		if r <= 0.0:
			return e
	return list[list.size() - 1]


func _pick(rng: RandomNumberGenerator, total_weight: float) -> LootEntry:
	var r := rng.randf() * total_weight
	for e in entries:
		if e == null or e.item == null:
			continue
		r -= maxf(e.weight, 0.0)
		if r <= 0.0:
			return e
	return entries[entries.size() - 1]


func _add(totals: Dictionary[ItemDefinition, int], e: LootEntry, rng: RandomNumberGenerator) -> void:
	if e == null or e.item == null:
		return
	var qty := rng.randi_range(mini(e.min_quantity, e.max_quantity), maxi(e.min_quantity, e.max_quantity))
	totals[e.item] = totals.get(e.item, 0) + qty
