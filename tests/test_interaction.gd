extends "res://tests/test_case.gd"
## Interaction ray, prompts, pickups (instant and hold), item rules
## (resources, ammo, medkits), validation, raider loot drops.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const PICKUP_SCENE := preload("res://scenes/items/pickup.tscn")
const DT := 1.0 / 60.0

var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")
var FUEL: ItemDefinition = load("res://resources/items/fuel.tres")
var AMMO: ItemDefinition = load("res://resources/items/rifle_ammo.tres")
var MEDKIT: ItemDefinition = load("res://resources/items/medkit.tres")


## Player at the origin facing -Z, looking down at the floor 1.8 m ahead.
func _player() -> PlayerController:
	make_static_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := classic_kit(PLAYER_SCENE.instantiate() as PlayerController)
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	return p


func _look_at_point(p: PlayerController, point: Vector3) -> void:
	var eye := p.head.global_position
	var flat := Vector3(point.x - eye.x, 0, point.z - eye.z)
	p.rotation.y = atan2(-flat.x, -flat.z)
	p.head.rotation.x = atan2(point.y - eye.y, flat.length())


func _pickup(item: ItemDefinition, qty: int, at: Vector3) -> Pickup:
	var pk := PICKUP_SCENE.instantiate() as Pickup
	pk.item = item
	pk.quantity = qty
	pk.position = at
	add_child(pk)
	return pk


func _tick(p: PlayerController, ticks: int, interact := false) -> void:
	var f := InputFrame.new()
	f.interact = interact
	for i in ticks:
		await get_tree().physics_frame
		p.simulate(f, DT)


func _press(p: PlayerController) -> void:
	await _tick(p, 1, true)
	await _tick(p, 1, false)


func test_items_are_valid() -> void:
	for path in ["scrap_metal", "cloth", "fuel", "electronics", "rifle_ammo", "medkit"]:
		var item := load("res://resources/items/%s.tres" % path) as ItemDefinition
		check(item != null and item.id == StringName(path), "%s loads with matching id" % path)
		check(item.world_model != null and item.pickup_sound != null, "%s has a model and a sound" % path)
	var rifle := load("res://resources/items/weapons/service_rifle.tres") as WeaponDefinition
	check(AMMO.ammo_type == rifle.ammo_type, "rifle ammo matches the rifle's ammo type")


func test_focus_and_prompt() -> void:
	var p := _player()
	var pk := _pickup(SCRAP, 3, Vector3(0, 0, -1.8))
	await _tick(p, 3)
	_look_at_point(p, pk.global_position + Vector3(0, 0.2, 0))
	await _tick(p, 2)
	check(p.interactor.focused == pk, "looking at the pickup focuses it")
	check(pk.get_prompt(p) == "Pick up Scrap Metal ×3", "prompt: '%s'" % pk.get_prompt(p))


func test_out_of_reach_not_focused() -> void:
	var p := _player()
	var pk := _pickup(SCRAP, 1, Vector3(0, 0, -4.0))
	await _tick(p, 3)
	_look_at_point(p, pk.global_position + Vector3(0, 0.2, 0))
	await _tick(p, 2)
	check(p.interactor.focused == null, "a pickup 4 m away is out of reach (3 m)")


func test_wall_blocks_interaction() -> void:
	var p := _player()
	make_static_box(Vector3(4, 3, 0.2), Vector3(0, 1.5, -1.0))
	var pk := _pickup(SCRAP, 1, Vector3(0, 0, -1.8))
	await _tick(p, 3)
	_look_at_point(p, pk.global_position + Vector3(0, 0.2, 0))
	await _tick(p, 2)
	check(p.interactor.focused == null, "can't focus through a wall")


func test_instant_pickup_adds_resources() -> void:
	var p := _player()
	var pk := _pickup(SCRAP, 3, Vector3(0, 0, -1.8))
	await _tick(p, 3)
	_look_at_point(p, pk.global_position + Vector3(0, 0.2, 0))
	await _tick(p, 2)
	var received := []
	p.inventory.item_received.connect(func(i: ItemDefinition, q: int) -> void: received.append([i.id, q]))
	await _press(p)
	await wait_physics(2)
	check(p.inventory.count_of(&"scrap_metal") == 3, "3 scrap carried (got %d)" % p.inventory.count_of(&"scrap_metal"))
	check(not is_instance_valid(pk), "pickup removed from the world")
	check(received == [[&"scrap_metal", 3]], "item_received signal")


func test_holding_e_picks_up_only_one_item() -> void:
	var p := _player()
	var a := _pickup(SCRAP, 1, Vector3(0, 0, -1.8))
	_pickup(SCRAP, 1, Vector3(0, 0, -1.9))
	await _tick(p, 3)
	_look_at_point(p, a.global_position + Vector3(0, 0.2, 0))
	await _tick(p, 2)
	await _tick(p, 30, true)  # hold E
	check(p.inventory.count_of(&"scrap_metal") == 1, "holding E doesn't vacuum up a second item")


func test_hold_to_pick_up_fuel() -> void:
	var p := _player()
	var pk := _pickup(FUEL, 1, Vector3(0, 0, -1.8))
	await _tick(p, 3)
	_look_at_point(p, pk.global_position + Vector3(0, 0.2, 0))
	await _tick(p, 2)
	check(pk.hold_time > 0.5, "fuel needs a hold")
	await _tick(p, 20, true)   # 0.33 s
	check(p.interactor.hold_progress > 0.3 and p.interactor.hold_progress < 0.6, "hold progress reported (%.2f)" % p.interactor.hold_progress)
	await _tick(p, 2, false)   # let go early
	check(p.interactor.hold_progress < 0.0, "releasing cancels the hold")
	check(p.inventory.count_of(&"fuel") == 0, "not picked up after a short hold")
	await _tick(p, 55, true)   # 0.92 s
	await wait_physics(2)
	check(p.inventory.count_of(&"fuel") == 1, "picked up after holding for 0.8 s")


func test_medkit_is_stored_even_at_full_health() -> void:
	var p := _player()
	var pk := _pickup(MEDKIT, 1, Vector3(0, 0, -1.8))
	await _tick(p, 3)
	var before := p.inventory.count_of(&"medkit")
	_look_at_point(p, pk.global_position + Vector3(0, 0.2, 0))
	await _tick(p, 2)
	check(pk.get_block_reason(p) == "", "medkits can be picked up at full health")
	await _press(p)
	await wait_physics(2)
	check(p.inventory.count_of(&"medkit") == before + 1, "medkit stored in the inventory")
	check_near(p.health.current_health, 100.0, 0.01, "not used on pickup")
	check(not is_instance_valid(pk), "pickup removed")


func test_ammo_goes_into_inventory_and_full_inventory_leaves_remainder() -> void:
	var p := _player()
	await _tick(p, 2)
	var start := p.weapon.reserve_ammo
	check(start == p.inventory.count_ammo(&"rifle_556"), "weapon reserve reads the inventory")
	var pk := _pickup(AMMO, 30, Vector3(0, 0, -1.8))
	_look_at_point(p, pk.global_position + Vector3(0, 0.2, 0))
	await _tick(p, 2)
	await _press(p)
	await wait_physics(2)
	check(p.weapon.reserve_ammo == start + 30, "reserve +30 (%d -> %d)" % [start, p.weapon.reserve_ammo])
	# Fill every free slot with cloth, leaving room for only 10 more rounds
	p.inventory.max_weight = 0.0
	var cloth := load("res://resources/items/cloth.tres") as ItemDefinition
	p.inventory.add_item(cloth, cloth.max_stack * p.inventory.get_free_slot_count())
	var ammo_room := p.inventory.can_add(AMMO, 1000)
	var pk2 := _pickup(AMMO, ammo_room + 20, Vector3(0, 0, -1.8))
	await _tick(p, 2)
	await _press(p)
	await wait_physics(2)
	check(is_instance_valid(pk2) and pk2.quantity == 20, "the 20 that didn't fit stay on the ground")
	check(pk2.get_block_reason(p) == "Inventory full", "now refused: '%s'" % pk2.get_block_reason(p))


func test_try_interact_validates_distance() -> void:
	var p := _player()
	var pk := _pickup(SCRAP, 1, Vector3(0, 0, -10))
	await _tick(p, 2)
	check(not pk.try_interact(p, p.head.global_position), "a request from 10 m away is rejected")
	check(p.inventory.count_of(&"scrap_metal") == 0, "nothing received")


func test_dead_player_cannot_interact() -> void:
	var p := _player()
	var pk := _pickup(SCRAP, 1, Vector3(0, 0, -1.8))
	await _tick(p, 3)
	_look_at_point(p, pk.global_position + Vector3(0, 0.2, 0))
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.FALL))
	await _tick(p, 2)
	await _press(p)
	check(p.interactor.focused == null, "no focus while dead")
	check(is_instance_valid(pk), "pickup untouched")


func test_raider_drops_loot() -> void:
	await make_nav_floor()
	var r := (load("res://scenes/enemies/raider.tscn") as PackedScene).instantiate() as Raider
	r.drop_chance = 1.0
	r.position = Vector3(3, 0.1, 3)
	add_child(r)
	await wait_physics(5)
	var before := get_tree().get_nodes_in_group("pickups").size()
	r.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.BALLISTIC))
	await wait_physics(2)
	var pickups := get_tree().get_nodes_in_group("pickups")
	check(pickups.size() == before + 1, "one loot pickup dropped")
	if pickups.size() > before:
		var drop := pickups[pickups.size() - 1] as Pickup
		check(drop.global_position.distance_to(Vector3(3, 0, 3)) < 1.0, "dropped at the raider's feet")
		check(drop.quantity >= 1 and drop.item != null, "has an item and quantity")
