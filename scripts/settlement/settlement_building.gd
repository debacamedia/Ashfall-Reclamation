class_name SettlementBuilding
extends Structure
## Something your settlers built at a settlement (Increment 19.6): a length
## of farm fence, a guard post or tower, a bunkhouse, a storehouse or a farm
## plot. It's a Structure like the walls you build yourself (saved under the
## level's "Structures" node, in the navmesh, raiders can break it), and it
## counts toward the settlement it stands in:
##
##   beds         more people can live there (bunkhouse)
##   %Storage     a SalvageContainer added to the settlement's stores
##                (storehouse shelves)
##   GuardSpots/* where guards stand (guard post, tower)
##   FarmSpots/*  where farmers work: two per field (farm plot)
##   %Fridge      the kitchen's store of cooked food (21.5): not one of the
##                settlement's stores (raiders don't look in it); settlers
##                eat from it first
##   CookSpots/*  where a Cook works (kitchen)
##   animal_kind  a pen (21.5): chickens, pigs or cows, up to
##                `animal_capacity`; they wander inside AnimalArea. The count,
##                and how close the next birth and egg are, are saved with it.
##   TendSpots/*  where a Rancher feeds them
##
## Built by ConstructionSite when a site's work is done. Scenes are made by
## tools/build_settlement_buildings.gd.

## More beds for the settlement.
@export var beds := 0
## A pen (21.5): what lives in it, and how many it holds.
@export var animal_kind: StringName = &""
@export var animal_capacity := 0

@onready var storage: SalvageContainer = get_node_or_null("%Storage")
@onready var fridge: SalvageContainer = get_node_or_null("%Fridge")

## Animals in the pen. -1: just built, nobody's arrived yet (the settlement
## brings a pair).
var animal_count := -1
## Fed by a Rancher in the last hour or so.
var animals_fed := false
## Progress (0-1) toward the next birth, and toward each egg; vegetables owed.
var breed_progress := 0.0
var egg_progress := 0.0
var feed_owed := 0.0
var _animal_seed := 0


func _ready() -> void:
	super._ready()
	add_to_group("settlement_buildings")
	if storage != null:
		var proxy := storage.get_node_or_null("Prop")
		if proxy != null:
			storage.remove_child(proxy)
			proxy.queue_free()
		storage.is_searched = true
		storage.inventory.max_weight = 0.0
		storage.call("_update_prompt")
	if fridge != null:
		fridge.is_searched = true
		fridge.inventory.max_weight = 0.0
		fridge.call("_update_prompt")
	if is_pen():
		_sync_animals.call_deferred()


## The settlement it stands in (within that settlement's claim radius), or null.
func settlement() -> Settlement:
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group("settlements"):
		var s := n as Settlement
		if s != null and Vector2(global_position.x - s.global_position.x, global_position.z - s.global_position.z).length() <= s.claim_radius:
			return s
	return null


func guard_spots() -> Array[Node3D]:
	return _markers("GuardSpots")


func farm_spots() -> Array[Node3D]:
	return _markers("FarmSpots")


func _markers(group: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var g := get_node_or_null(group)
	if g != null:
		for c in g.get_children():
			if c is Node3D:
				out.append(c)
	return out


## Broken by raiders: the settlement puts it back on the building list.
func destroy() -> void:
	if is_queued_for_deletion():
		return
	var st := settlement()
	if st != null:
		st.on_building_destroyed(self)
	super.destroy()


# ---------------------------------------------------------------- pens (21.5)

func is_pen() -> bool:
	return animal_kind != &""


func is_kitchen() -> bool:
	return fridge != null


func cook_spots() -> Array[Node3D]:
	return _markers("CookSpots")


func tend_spots() -> Array[Node3D]:
	return _markers("TendSpots")


func animals() -> Array[FarmAnimal]:
	var out: Array[FarmAnimal] = []
	var g := get_node_or_null("Animals")
	if g != null:
		for c in g.get_children():
			if c is FarmAnimal and not c.is_queued_for_deletion():
				out.append(c)
	return out


## How many there are (0 while the first pair's still on its way).
func count() -> int:
	return maxi(animal_count, 0)


func set_count(n: int) -> void:
	animal_count = clampi(n, 0, animal_capacity)
	_sync_animals()


## A random point inside the pen's AnimalArea, for an animal to wander to.
func random_animal_spot(rng: RandomNumberGenerator) -> Vector3:
	var area := get_node_or_null("AnimalArea") as Node3D
	if area == null:
		return global_position
	var size: Vector2 = area.get_meta("size", Vector2(4, 4))
	return area.global_transform * Vector3(rng.randf_range(-size.x, size.x) * 0.5, 0.0, rng.randf_range(-size.y, size.y) * 0.5)


## Makes as many animals as the count says (more or fewer).
func _sync_animals() -> void:
	if not is_inside_tree() or not is_pen():
		return
	var g := get_node_or_null("Animals")
	if g == null:
		g = Node3D.new()
		g.name = "Animals"
		add_child(g)
	var have := animals()
	while have.size() > count():
		var a: FarmAnimal = have.pop_back()
		a.queue_free()
	var rng := RandomNumberGenerator.new()
	while have.size() < count():
		_animal_seed += 1
		var a := FarmAnimal.make(animal_kind, self, hash([name, _animal_seed]) & 0x7fffffff)
		g.add_child(a)
		rng.seed = a._rng.seed
		a.global_position = random_animal_spot(rng)
		have.append(a)


## One fewer (butchered): this one, if given.
func remove_animal(which: FarmAnimal = null) -> void:
	if count() <= 0:
		return
	animal_count = count() - 1
	if which != null and is_instance_valid(which):
		which.queue_free()
	_sync_animals.call_deferred()


func save_state() -> Dictionary:
	var d := super.save_state()
	if is_pen():
		d["animals"] = animal_count
		d["breed"] = breed_progress
		d["eggs"] = egg_progress
		d["feed_owed"] = feed_owed
		d["fed"] = animals_fed
	return d


func load_state(data: Dictionary) -> void:
	super.load_state(data)
	if is_pen() and data.has("animals"):
		animal_count = clampi(int(data["animals"]) if _is_number(data["animals"]) else 0, -1, animal_capacity)
		breed_progress = clampf(float(data.get("breed", 0.0)) if _is_number(data.get("breed", 0.0)) else 0.0, 0.0, 1.0)
		egg_progress = clampf(float(data.get("eggs", 0.0)) if _is_number(data.get("eggs", 0.0)) else 0.0, 0.0, 1000.0)
		feed_owed = clampf(float(data.get("feed_owed", 0.0)) if _is_number(data.get("feed_owed", 0.0)) else 0.0, 0.0, 100.0)
		animals_fed = data.get("fed") is bool and data["fed"]
		_sync_animals.call_deferred()


func dismantle_block_reason() -> String:
	if fridge != null and fridge.inventory.get_free_slot_count() < fridge.inventory.slot_count:
		return "Empty the fridge first"
	if storage != null:
		if storage.inventory.get_free_slot_count() < storage.inventory.slot_count:
			return "Empty it first"
		if storage.is_open():
			return "Someone's using it"
	return ""


func move_block_reason() -> String:
	return "Too big to move"
