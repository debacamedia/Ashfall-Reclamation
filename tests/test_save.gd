extends "res://tests/test_case.gd"
## Increment 8: SaveManager — versioned JSON round trips for the player,
## containers and pickups; missing / damaged / newer files; quick save and
## quick load keys; the full Outpost 17 level.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CRATE := preload("res://scenes/world/containers/supply_crate.tscn")
const PICKUP := preload("res://scenes/items/pickup.tscn")
const LEVEL := preload("res://levels/outpost_17/outpost_17.tscn")
const DT := 1.0 / 60.0
const TEST_DIR := "user://test_saves"

var SCRAP: ItemDefinition = load("res://resources/items/scrap_metal.tres")
var MEDKIT: ItemDefinition = load("res://resources/items/medkit.tres")
var FUEL: ItemDefinition = load("res://resources/items/fuel.tres")

var saves: Node
var _old_dir := ""


func _init() -> void:
	tree_entered.connect(func() -> void:
		saves = get_node("/root/SaveManager")
		_old_dir = saves.save_dir
		saves.save_dir = TEST_DIR
		_clean())
	tree_exiting.connect(func() -> void:
		_clean()
		saves.save_dir = _old_dir)


func _clean() -> void:
	var d := DirAccess.open(TEST_DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)


func _player(at := Vector3(0, 0.05, 0)) -> PlayerController:
	make_static_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.name = "Player"
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = at
	add_child(p)
	return p


func _tick(p: PlayerController, ticks: int) -> void:
	var f := InputFrame.new()
	for i in ticks:
		await get_tree().physics_frame
		p.simulate(f, DT)


func _pickup(item: ItemDefinition, qty: int, at: Vector3, node_name: String) -> Pickup:
	var pk := PICKUP.instantiate() as Pickup
	pk.name = node_name
	pk.item = item
	pk.quantity = qty
	pk.position = at
	add_child(pk)
	return pk


# ---------------------------------------------------------------- basics

func test_save_manager_autoload() -> void:
	check(saves != null, "SaveManager autoload exists")
	check(saves.SAVE_VERSION == 1, "save version 1")
	check(saves.slot_path("quicksave") == TEST_DIR + "/quicksave.json", "slot path: %s" % saves.slot_path("quicksave"))
	check(InputMap.has_action("quick_save") and InputMap.has_action("quick_load"), "quick save / load actions")
	var f5 := InputEventKey.new()
	f5.physical_keycode = KEY_F5
	f5.pressed = true
	var f9 := InputEventKey.new()
	f9.physical_keycode = KEY_F9
	f9.pressed = true
	check(InputMap.event_is_action(f5, "quick_save") and InputMap.event_is_action(f9, "quick_load"), "F5 saves, F9 loads")


func test_player_round_trip() -> void:
	var p := _player()
	await _tick(p, 5)
	p.global_position = Vector3(3.5, 0.05, -2.25)
	p.rotation.y = 1.2
	p.head.rotation.x = -0.3
	p.health.apply_damage(DamageInfo.create(45.0, DamageInfo.Type.FALL))
	p.inventory.add_item(SCRAP, 7)
	p.weapon.ammo_in_magazine = 12
	await _tick(p, 2)
	var saved_inventory := str(p.inventory.to_data())
	var saved_pos := p.global_position
	check(saves.save_game("t1", self) == OK, "saved")
	check(FileAccess.file_exists(TEST_DIR + "/t1.json"), "file written")
	check(not FileAccess.file_exists(TEST_DIR + "/t1.json.tmp"), "temporary file cleaned up")
	# Change everything
	p.global_position = Vector3(-8, 0.05, 6)
	p.rotation.y = -2.0
	p.head.rotation.x = 0.4
	p.health.heal(100.0)
	p.inventory.add_item(MEDKIT, 3)
	p.weapon.ammo_in_magazine = 30
	var events := []
	saves.loaded.connect(func(path: String) -> void: events.append(path), CONNECT_ONE_SHOT)
	check(saves.load_game("t1", self) == OK, "loaded")
	check(p.global_position.distance_to(saved_pos) < 0.01, "position restored (%s)" % p.global_position)
	check_near(p.rotation.y, 1.2, 0.001, "facing restored")
	check_near(p.head.rotation.x, -0.3, 0.001, "view pitch restored")
	check_near(p.health.current_health, 55.0, 0.01, "health restored")
	check(str(p.inventory.to_data()) == saved_inventory, "inventory restored exactly")
	check(p.weapon.ammo_in_magazine == 12, "magazine restored")
	check(events.size() == 1, "loaded signal")
	await _tick(p, 5)
	check(p.is_on_floor(), "standing on the floor after loading")


func test_file_format_and_version() -> void:
	var p := _player()
	await _tick(p, 3)
	saves.save_game("fmt", self)
	var data: Dictionary = saves.read_save_file(TEST_DIR + "/fmt.json")
	check(data.get("format") == "ashfall_save", "format tag")
	check(int(data.get("version", 0)) == 1, "version field = 1")
	check(data.get("saved_at") is String and str(data["saved_at"]).length() >= 19, "timestamp: %s" % data.get("saved_at"))
	check(data.has("level"), "level field")
	var player_entry: Array = (data["nodes"] as Array).filter(func(e: Dictionary) -> bool: return e["path"] == "Player")
	check(player_entry.size() == 1, "player saved under its path")
	if player_entry.size() == 1:
		var d: Dictionary = player_entry[0]["data"]
		for key in ["position", "yaw", "pitch", "health", "inventory", "magazine"]:
			check(d.has(key), "player data has %s" % key)


func test_missing_damaged_and_newer_saves() -> void:
	var p := _player()
	await _tick(p, 3)
	var reasons := []
	saves.failed.connect(func(r: String) -> void: reasons.append(r))
	check(saves.load_game("quicksave", self) == ERR_FILE_NOT_FOUND, "missing file → ERR_FILE_NOT_FOUND")
	check(reasons.back() == "No quick save yet (F5 to save)", "told: %s" % reasons.back())
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var cases := [
		["junk", "{ this is not json", ERR_FILE_CORRUPT, "Save file is damaged"],
		["array", "[1, 2, 3]", ERR_FILE_CORRUPT, "Save file is damaged"],
		["other", '{"format": "something_else", "version": 1, "nodes": []}', ERR_INVALID_DATA, "Not an Ashfall save"],
		["noversion", '{"format": "ashfall_save", "nodes": []}', ERR_INVALID_DATA, "Save has no version"],
		["newer", '{"format": "ashfall_save", "version": 99, "nodes": []}', ERR_INVALID_DATA, "Save is from a newer version of the game"],
		["nonodes", '{"format": "ashfall_save", "version": 1}', ERR_INVALID_DATA, "Save file is damaged"],
	]
	var hp := p.health.current_health
	var pos := p.global_position
	for c in cases:
		var f := FileAccess.open(TEST_DIR + "/%s.json" % c[0], FileAccess.WRITE)
		f.store_string(c[1])
		f.close()
		check(saves.load_game(c[0], self) == c[2], "%s → error %d" % [c[0], c[2]])
		check(reasons.back() == c[3], "%s → '%s'" % [c[0], reasons.back()])
	check(p.health.current_health == hp and p.global_position == pos, "a bad save changes nothing")


func test_malformed_entries_are_ignored() -> void:
	var p := _player()
	await _tick(p, 3)
	var pos := p.global_position
	var bad := {"format": "ashfall_save", "version": 1, "level": "", "nodes": [
		"not a dict", {"path": "Nope/Missing", "data": {}},
		{"path": "Player", "data": {"position": ["a", "b", "c"], "health": "lots", "inventory": "x", "magazine": 1e9, "yaw": INF}},
		{"path": "Player", "scene": "user://evil.tscn", "parent": ".", "data": {}},
	]}
	saves.apply_save_data(bad, self)
	check(p.global_position.distance_to(pos) < 0.01, "bad position ignored")
	check(p.health.current_health > 0.0 and not p.is_dead(), "player alive")
	check(p.weapon.ammo_in_magazine <= p.weapon.definition.magazine_size, "magazine clamped")
	check(is_finite(p.rotation.y), "non-finite yaw ignored")


func test_cannot_save_while_dead_and_load_revives() -> void:
	var p := _player()
	await _tick(p, 3)
	p.health.apply_damage(DamageInfo.create(30.0, DamageInfo.Type.FALL))
	saves.save_game("alive", self)
	p.health.apply_damage(DamageInfo.create(500.0, DamageInfo.Type.FALL))
	await _tick(p, 30)
	var reasons := []
	saves.failed.connect(func(r: String) -> void: reasons.append(r), CONNECT_ONE_SHOT)
	check(saves.save_game("dead", self) == ERR_UNAVAILABLE and reasons == ["Can't save while dead"], "no saving while dead")
	check(saves.load_game("alive", self) == OK, "loading while dead works")
	check(not p.is_dead() and p.movement_state != PlayerController.MovementState.DEAD, "back alive")
	check_near(p.health.current_health, 70.0, 0.01, "with the saved health")
	check(p.weapon.visible, "weapon back in hand")


# ---------------------------------------------------------------- world state

func test_containers_and_pickups_round_trip() -> void:
	var p := _player()
	var crate := CRATE.instantiate() as SalvageContainer
	crate.name = "Crate"
	crate.loot_seed = 77
	crate.position = Vector3(0, 0, -6)
	add_child(crate)
	var a := _pickup(SCRAP, 4, Vector3(2, 0, 2), "LootA")
	var gone := _pickup(MEDKIT, 1, Vector3(-2, 0, 2), "LootGone")
	await _tick(p, 3)
	crate.search()
	crate.inventory.remove_item(crate.inventory.get_slot_item(0).id, 1)
	var crate_contents := str(crate.inventory.to_data())
	gone.get_parent().remove_child(gone)   # taken before saving
	gone.free()
	check(saves.save_game("world", self) == OK, "saved")
	# After saving: take LootA, drop a fuel can, empty the crate
	a.get_parent().remove_child(a)
	a.free()
	var dropped := p.request_drop_slot(0, 10)
	check(dropped != null, "dropped some ammo")
	crate.inventory.clear()
	# ...and pretend the level was reloaded fresh: the taken medkit is back
	var fresh_gone := _pickup(MEDKIT, 1, Vector3(-2, 0, 2), "LootGone")
	check(saves.load_game("world", self) == OK, "loaded")
	await get_tree().process_frame
	var restored := get_node_or_null("LootA") as Pickup
	check(restored != null and restored.item == SCRAP and restored.quantity == 4, "pickup taken after saving is back")
	if restored != null:
		check(restored.global_position.distance_to(Vector3(2, 0, 2)) < 0.01, "in the same place")
	check(not is_instance_valid(dropped) or dropped.is_queued_for_deletion(), "item dropped after saving is gone")
	check(not is_instance_valid(fresh_gone) or fresh_gone.is_queued_for_deletion(), "pickup taken before saving stays taken")
	check(crate.is_searched and str(crate.inventory.to_data()) == crate_contents, "crate contents restored")


func test_dropped_items_are_saved() -> void:
	var p := _player()
	await _tick(p, 3)
	var dropped := p.request_drop_slot(1)  # the medkit
	check(dropped != null, "dropped the medkit")
	var at := dropped.global_position
	saves.save_game("drop", self)
	dropped.get_parent().remove_child(dropped)
	dropped.free()
	saves.load_game("drop", self)
	var found: Array = get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool: return is_ancestor_of(n) and not n.is_queued_for_deletion())
	check(found.size() == 1, "the dropped medkit was re-created (%d)" % found.size())
	if found.size() == 1:
		var pk := found[0] as Pickup
		check(pk.item == MEDKIT and pk.quantity == 1 and pk.global_position.distance_to(at) < 0.01, "same item, same place")


# ---------------------------------------------------------------- keys + HUD

func test_quick_save_and_load_keys_with_hud_notice() -> void:
	var p := _player()
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as HUD
	hud.player = p
	add_child(hud)
	var previous_scene := get_tree().current_scene
	get_tree().current_scene = self
	await _tick(p, 3)
	var press := func(action: String) -> void:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = true
		Input.parse_input_event(e)
		var up := InputEventAction.new()
		up.action = action
		up.pressed = false
		Input.parse_input_event(up)
	press.call("quick_load")
	await wait_physics(2)
	var notices := hud.get_node("%Notices") as VBoxContainer
	var texts := func() -> Array:
		return notices.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()).map(func(n: Label) -> String: return n.text)
	check(texts.call().has("No quick save yet (F5 to save)"), "F9 with no save explains: %s" % [texts.call()])
	p.health.apply_damage(DamageInfo.create(20.0, DamageInfo.Type.FALL))
	press.call("quick_save")
	await wait_physics(2)
	check(saves.has_save(), "F5 wrote the quick save")
	check(texts.call().has("Game saved"), "notice: Game saved")
	p.health.heal(50.0)
	press.call("quick_load")
	await wait_physics(2)
	check_near(p.health.current_health, 80.0, 0.01, "F9 restored health")
	check(texts.call().has("Game loaded"), "notice: Game loaded")
	get_tree().current_scene = previous_scene


func test_outpost_17_round_trip() -> void:
	var level := LEVEL.instantiate() as Node3D
	var p := level.get_node("Player") as PlayerController
	p.controlled_locally = false
	(level.get_node("RaiderSpawner") as EnemySpawner).enabled = false
	add_child(level)
	await wait_physics(10)
	var crate := level.get_node("SalvageContainers/WarehouseCrateNorth") as SalvageContainer
	crate.search()
	var crate_data := str(crate.inventory.to_data())
	var shelf := level.get_node("Loot/WarehouseShelfScrap")
	shelf.get_parent().remove_child(shelf)
	shelf.free()
	p.global_position = Vector3(-17, 0.05, 11)
	p.inventory.add_item(FUEL, 1)
	await _tick(p, 5)
	var pos := p.global_position
	check(saves.save_game("level", level) == OK, "level saved")
	var data: Dictionary = saves.read_save_file(TEST_DIR + "/level.json")
	check(data["level"] == "res://levels/outpost_17/outpost_17.tscn", "level path recorded")
	var paths: Array = (data["nodes"] as Array).map(func(e: Dictionary) -> String: return e["path"])
	check(paths.has("Player") and paths.has("SalvageContainers/WarehouseCrateNorth") and paths.has("Loot/GateMedkit"), "player, containers and loot saved")
	check(not paths.has("Loot/WarehouseShelfScrap"), "taken loot not listed")
	level.queue_free()
	await get_tree().process_frame
	# A fresh copy of the level, as after restarting the game
	var level2 := LEVEL.instantiate() as Node3D
	var p2 := level2.get_node("Player") as PlayerController
	p2.controlled_locally = false
	(level2.get_node("RaiderSpawner") as EnemySpawner).enabled = false
	add_child(level2)
	await wait_physics(10)
	check(saves.load_game("level", level2) == OK, "loaded into a fresh level")
	await get_tree().process_frame
	check(p2.global_position.distance_to(pos) < 0.05, "player back in the warehouse")
	check(p2.inventory.count_of(&"fuel") == 1, "carrying the fuel can")
	var crate2 := level2.get_node("SalvageContainers/WarehouseCrateNorth") as SalvageContainer
	check(crate2.is_searched and str(crate2.inventory.to_data()) == crate_data, "crate searched with the same loot (not re-rolled)")
	var shelf2 := level2.get_node_or_null("Loot/WarehouseShelfScrap")
	check(shelf2 == null or shelf2.is_queued_for_deletion(), "taken shelf scrap stays taken")
	check(level2.get_node_or_null("Loot/GateMedkit") != null, "untouched loot still there")
	var unsearched := level2.get_node("SalvageContainers/BarracksLocker") as SalvageContainer
	check(not unsearched.is_searched, "unsearched containers stay unsearched")
