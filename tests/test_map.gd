extends "res://tests/test_case.gd"
## Increment 17: the map (M). The zone from above, filling in as you
## explore, with places, benches, dropped gear and your own pins (which go
## on the compass too).

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ZONE_SCENE := "res://levels/early_zone/early_zone.tscn"


func _player() -> PlayerController:
	make_static_box(Vector3(400, 1, 400), Vector3(0, -0.5, 0), PhysicsLayers.TERRAIN)
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.controlled_locally = false
	p.head_bob_enabled = false
	p.position = Vector3(0, 0.05, 0)
	add_child(p)
	await wait_physics(3)
	return p


func _action(name: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = true
	return e


# ---------------------------------------------------------------- knowledge

func test_reveals_the_ground_round_you() -> void:
	var k := MapKnowledge.new()
	var fresh := k.reveal_around(Vector3(100, 0, -100))
	check(fresh.size() > 200 and fresh.size() == k.cells.size(), "the first look reveals the ground round you (%d cells)" % fresh.size())
	check(k.is_revealed(Vector2(100, -100)) and k.is_revealed(Vector2(150, -100)), "where you stand, and 50 m away")
	check(not k.is_revealed(Vector2(190, -100)), "but not 90 m away")
	check(k.reveal_around(Vector3(102, 0, -100)).is_empty(), "nothing more until you've moved a few metres")
	var more := k.reveal_around(Vector3(130, 0, -100))
	check(not more.is_empty() and k.is_revealed(Vector2(190, -100)), "walk on and more of the map fills in")
	# Up high you see further
	check_near(MapKnowledge.reveal_radius_at(0.0), 70.0, 0.01, "70 m on the ground")
	check_near(MapKnowledge.reveal_radius_at(9.0), 124.0, 0.01, "124 m from the top of Halden's water tower")
	check_near(MapKnowledge.reveal_radius_at(100.0), MapKnowledge.REVEAL_MAX, 0.01, "never more than %d m" % MapKnowledge.REVEAL_MAX)
	var high := MapKnowledge.new()
	high.reveal_around(Vector3(0, 9, 0))
	check(high.is_revealed(Vector2(110, 0)) and not k.is_revealed(Vector2(-110, -100)), "from up high, 110 m off is on the map")


func test_places_you_have_been() -> void:
	var k := MapKnowledge.new()
	var heard := []
	k.place_visited.connect(func(n: String) -> void: heard.append(n))
	check(k.visit("Ash Creek Farms"), "first visit")
	check(not k.visit("Ash Creek Farms"), "only once")
	check(k.has_visited("Ash Creek Farms") and not k.has_visited("Northwatch Outpost"), "remembered")
	check(heard == ["Ash Creek Farms"], "announced once")


func test_pins_up_to_ten_numbered() -> void:
	var k := MapKnowledge.new()
	for i in MapKnowledge.MAX_PINS:
		check(k.add_pin(Vector2(i * 10, 0)) == i + 1, "pin %d" % (i + 1))
	check(k.pin_refusal_reason(Vector2(5, 5)) != "" and k.add_pin(Vector2(5, 5)) == 0, "an 11th is refused: %s" % k.pin_refusal_reason(Vector2(5, 5)))
	check(k.remove_pin(3) and k.pins.size() == 9, "remove Pin 3")
	check(k.add_pin(Vector2(1, 1)) == 3, "the next pin takes the free number 3")
	check(not k.remove_pin(42), "there's no Pin 42")
	check(k.add_pin(Vector2(NAN, 0)) == 0, "not at a nonsense spot")
	check(MapKnowledge.pin_color(1) != MapKnowledge.pin_color(2), "each pin has its own colour")


func test_knowledge_saves_and_loads() -> void:
	var k := MapKnowledge.new()
	k.reveal_around(Vector3(0, 0, 0))
	k.reveal_around(Vector3(300, 0, -250))
	k.visit("Outpost 17")
	k.visit("Halden's Crossing")
	k.add_pin(Vector2(150.25, -395.5))
	k.add_pin(Vector2(262, -552))
	k.remove_pin(1)
	# Through JSON, like a save file
	var json := JSON.stringify(k.to_data())
	var back := MapKnowledge.new()
	back.from_data(JSON.parse_string(json))
	check(back.cells.size() == k.cells.size(), "the explored ground (%d cells)" % k.cells.size())
	var same := true
	for c in k.cells:
		same = same and back.cells.has(c)
	check(same, "exactly the same cells")
	check(back.has_visited("Halden's Crossing") and back.places.size() == 2, "the places you've been")
	check(back.pins.size() == 1 and int(back.pins[0]["number"]) == 2 and (back.pins[0]["at"] as Vector2).is_equal_approx(Vector2(262, -552)), "Pin 2, where you put it")
	check(json.length() < 6000, "small in the save (%d characters)" % json.length())
	# Nonsense is skipped, not trusted
	var bad := MapKnowledge.new()
	bad.from_data({"cells": {"x": 0, "z": 0, "w": 100000, "h": 100000, "bits": "AAAA"}, "places": [3, "", "Ok"],
		"pins": [[1, "x", 2], [0, 1, 1], [99, 1, 1], [2, 5, 5], [2, 6, 6], "junk"]})
	check(bad.cells.is_empty(), "an impossible cell area is ignored")
	check(bad.places.keys() == ["Ok"], "only real place names")
	check(bad.pins.size() == 1 and int(bad.pins[0]["number"]) == 2, "only valid, unique pins")
	bad.from_data("not a dictionary")
	check(bad.pins.is_empty() and bad.cells.is_empty(), "garbage clears it")


# ---------------------------------------------------------------- the player

func test_player_maps_as_they_go_and_saves_it() -> void:
	var p := await _player()
	var home := Landmark.new()
	home.display_name = "Test Camp"
	home.radius = 30.0
	home.position = Vector3(20, 0, 0)
	add_child(home)
	var found := []
	p.place_discovered.connect(func(n: String) -> void: found.append(n))
	await wait_physics(30)
	var k := p.map_knowledge
	check(k.is_revealed(Vector2(0, 0)) and k.is_revealed(Vector2(40, 40)), "the ground round you is on the map within a moment")
	check(found == ["Test Camp"] and k.has_visited("Test Camp"), "standing in a place puts it on the map")
	p.global_position = Vector3(150, 0.05, 0)
	await wait_physics(30)
	check(k.is_revealed(Vector2(200, 0)), "walk on and it fills in")
	check(p.request_add_pin(Vector2(100, -100)) == 1, "drop a pin")
	var refused := []
	p.pin_refused.connect(func(r: String) -> void: refused.append(r))
	for i in MapKnowledge.MAX_PINS:
		p.request_add_pin(Vector2(i, i))
	check(refused.size() == 1 and k.pins.size() == MapKnowledge.MAX_PINS, "the 11th pin is refused, with a reason")
	# Saved with you
	var data := p.save_state()
	check(data.has("maps") and (data["maps"] as Dictionary).has(p.map_zone_id()), "the map is in the save, under this zone (%s)" % p.map_zone_id())
	var copy := JSON.parse_string(JSON.stringify(data)) as Dictionary
	p.request_remove_pin(1)
	k.cells.clear()
	p.load_state(copy)
	check(p.map_knowledge.find_pin(1) >= 0 and p.map_knowledge.pins.size() == MapKnowledge.MAX_PINS, "pins come back")
	check(p.map_knowledge.is_revealed(Vector2(200, 0)) and p.map_knowledge.has_visited("Test Camp"), "explored ground and places come back")
	# A save from before the map: you start mapping afresh
	copy.erase("maps")
	p.load_state(copy)
	check(p.map_knowledge.pins.is_empty() and p.map_knowledge.cells.is_empty(), "an older save starts with a blank map")
	await wait_physics(30)
	check(p.map_knowledge.is_revealed(Vector2(p.global_position.x, p.global_position.z)), "…which fills in from where you are")


func test_dead_players_dont_map() -> void:
	var p := await _player()
	await wait_physics(20)
	p.health.apply_damage(DamageInfo.create(1000.0, DamageInfo.Type.ENVIRONMENT))
	var before := p.map_knowledge.cells.size()
	p.global_position = Vector3(160, 0.05, 160)
	await wait_physics(30)
	check(p.map_knowledge.cells.size() == before, "nothing new while dead")


# ---------------------------------------------------------------- the picture

func test_the_zone_has_a_map_picture() -> void:
	var map := Zone.map_for(ZONE_SCENE)
	check(map != null and map.texture != null, "levels/early_zone/map.tres with its picture")
	if map == null:
		return
	check(map.title == "Early Zone", "titled")
	check_near(map.texture.get_width() / map.world_rect.size.x, 2.0, 0.01, "2 pixels a metre across")
	check_near(map.texture.get_height() / map.world_rect.size.y, 2.0, 0.01, "and down")
	var zone := instance_zone()
	var boundary := zone.get_node("Boundary") as ZoneBoundary
	var inside := true
	for pt in boundary.polygon:
		inside = inside and map.world_rect.grow(-40.0).has_point(pt)
	check(inside, "it covers the whole playable area, with the storm round it")
	for c in [map.world_rect.position, map.world_rect.size]:
		check(is_equal_approx(fmod(c.x, MapKnowledge.CELL), 0.0) and is_equal_approx(fmod(c.y, MapKnowledge.CELL), 0.0), "lined up with the map cells")
	check(map.uv_of(map.world_of(Vector2(0.25, 0.75))).is_equal_approx(Vector2(0.25, 0.75)), "picture and world positions convert both ways")
	# North is up: Northwatch near the top, Outpost 17 near the bottom
	check(map.uv_of(Vector2(400, -680)).y < 0.25 and map.uv_of(Vector2(0, 5)).y > 0.7, "north is up")
	zone.free()


# ---------------------------------------------------------------- the screen

func test_map_screen_in_the_zone() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var hud := zone.get_node("HUD") as HUD
	var screen := hud.map_screen
	check(screen != null and not screen.visible, "the HUD has a map, closed")
	await wait_physics(20)
	await screen.open()
	await get_tree().process_frame
	check(screen.visible and p.player_input.ui_open, "M opens it: the mouse is free")
	check(hud.is_window_open(), "the HUD counts it as an open window")
	check(screen._title.text.contains("EARLY ZONE"), "titled with the zone")
	var view := screen.view
	check(view.zone_map != null and view.size.x > 400.0, "showing the zone's map")
	var you := Vector2(p.global_position.x, p.global_position.z)
	check(view.to_screen(you).distance_to(view.size / 2.0) < 2.0, "centred on you")
	check(view.fog_at(you) > 0.5 and view.fog_at(Vector2(400, -680)) < 0.5, "Outpost 17 is explored, Northwatch isn't")
	# Markers
	var kinds := {}
	for m in view.markers():
		kinds[m["kind"]] = int(kinds.get(m["kind"], 0)) + 1
	check(int(kinds.get("place", 0)) == 1 and int(kinds.get("place_unvisited", 0)) == 6, "7 places: Outpost 17 visited, 6 not yet")
	var stations: Array = view.markers().filter(func(m: Dictionary) -> bool: return m["kind"] == "station")
	check(not stations.is_empty() and stations.all(func(m: Dictionary) -> bool: return p.map_knowledge.is_revealed(m["at"])), "only benches you've seen (%d)" % stations.size())
	view.reveal_all = true
	var all_stations := view.markers().filter(func(m: Dictionary) -> bool: return m["kind"] == "station").size()
	check(all_stations > stations.size(), "more benches out there (%d in all)" % all_stations)
	view.reveal_all = false
	# Zoom and pan
	view.zoom = 1.0
	view.zoom_by(100.0, view.size / 2.0)
	check_near(view.zoom, MapView.ZOOM_MAX, 0.001, "zoom in up to %dx" % MapView.ZOOM_MAX)
	view.zoom_by(0.0001, view.size / 2.0)
	check_near(view.zoom, view.min_zoom(), 0.001, "zoom out until the whole map fits")
	var spot := Vector2(300, -300)
	view.zoom = 2.0
	var at := view.to_screen(spot)
	view.zoom_by(1.25, at)
	check(view.to_screen(spot).distance_to(at) < 0.5, "zooming keeps the ground under the cursor still")
	view.pan_by(Vector2(1e6, 1e6))
	check(view.zone_map.world_rect.grow(1.0).has_point(view.centre), "you can't drag the map away")
	# Pins: right-click to drop, on the compass, right-click again to remove
	view.zoom = 1.0
	view.centre_on(Vector2(250, -250))
	await get_tree().process_frame
	view.pin_action(view.to_screen(Vector2(150, -395)))
	check(p.map_knowledge.pins.size() == 1, "right-click drops a pin")
	var pin_at: Vector2 = p.map_knowledge.pins[0]["at"]
	check(pin_at.distance_to(Vector2(150, -395)) < 1.0, "where you clicked")
	var mark := screen.pin_mark(1)
	check(mark != null and mark.is_in_group("landmarks") and mark.get_compass_name() == "Pin 1", "it's on the compass")
	check(mark != null and mark.marker_color == MapKnowledge.pin_color(1) and mark.radius == 0.0, "in its colour, and never 'arrived at'")
	check(screen._pins_box.get_child_count() == 1, "listed in the side panel")
	view.pin_action(view.to_screen(pin_at) + Vector2(0, -16))  # its head
	check(p.map_knowledge.pins.is_empty() and screen.pin_mark(1) == null, "right-click it again to remove it (and from the compass)")
	# Side panel: places, nearest first; clicking one looks at it
	check(screen._places_box.get_child_count() == 8, "7 places and a count")
	var first := screen._places_box.get_child(0).get_child(1) as Button
	check(first.text.begins_with("Outpost 17"), "nearest first: %s" % first.text)
	var last := screen._places_box.get_child(6).get_child(1) as Button
	last.pressed.emit()
	check(view.centre.distance_to(Vector2(400, -680)) < 1.0, "click a place to look at it: %s" % last.text)
	# Keys: Tab swaps to the inventory, M closes
	p.controlled_locally = true
	screen._input(_action("inventory"))
	check(not screen.visible, "Tab closes the map…")
	hud.inventory_screen._input(_action("inventory"))
	check(hud.inventory_screen.visible, "…and opens the inventory")
	screen._input(_action("map"))
	check(not screen.visible, "M doesn't open over the inventory")
	hud.inventory_screen.close()
	screen._input(_action("map"))
	await get_tree().process_frame
	await get_tree().process_frame
	check(screen.visible, "M opens it")
	hud.inventory_screen._input(_action("inventory"))
	check(not hud.inventory_screen.visible, "the inventory stays shut while it's open")
	screen._input(_action("map"))
	check(not screen.visible and not p.player_input.ui_open, "M closes it again")
	p.controlled_locally = false


func test_pins_survive_a_save_in_the_zone() -> void:
	var zone := await load_zone()
	var p := zone.get_node("Player") as PlayerController
	var hud := zone.get_node("HUD") as HUD
	await wait_physics(10)
	p.request_add_pin(Vector2(262, -552))
	await get_tree().process_frame
	check(hud.map_screen.pin_mark(1) != null, "a pin on the compass without opening the map")
	var data := SaveManager.build_save_data(zone)
	p.request_remove_pin(1)
	check(hud.map_screen.pin_mark(1) == null, "removed")
	SaveManager.apply_save_data(data, zone)
	await get_tree().process_frame
	check(p.map_knowledge.pins.size() == 1 and hud.map_screen.pin_mark(1) != null, "loading brings it back, compass and all")
