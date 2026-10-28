class_name MapScreen
extends Control
## The map window (M, Increment 17): the zone from above, filling in as you
## explore, with a side panel listing the places (click one to look at it),
## your pins and a key to the symbols.
##
## Pins you drop also go on the compass. While the map is open the mouse is
## free and gameplay input is ignored, but the world keeps running.
##
## Built in code by the HUD. Pin requests go through PlayerController.

const SIDEBAR_WIDTH := 300.0
const PAN_SPEED := 700.0  ## screen units a second, with WASD / arrows
const STYLE_COLOR := Color(0.95, 0.8, 0.45)

## Set by the HUD.
var player: PlayerController:
	set(value):
		if player == value:
			return
		_unbind()
		player = value
		_bind()

var view := MapView.new()
var _title: Label
var _where: Label
var _places_box: VBoxContainer
var _pins_box: VBoxContainer
var _pins_hint: Label
## Pin number -> its compass Landmark (in the zone, so the compass sees it).
var _pin_marks := {}
var _zone_id := ""
var _list_left := 0.0
## The side panel's rows, to update their distances: [Button, title, at]
var _rows: Array = []


func _init() -> void:
	name = "MapScreen"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var window := PanelContainer.new()
	window.name = "Window"
	window.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.offset_left = 18
	window.offset_top = 14
	window.offset_right = -18
	window.offset_bottom = -14
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.065, 0.97)
	style.set_border_width_all(1)
	style.border_color = Color(0.45, 0.4, 0.3)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	window.add_theme_stylebox_override("panel", style)
	add_child(window)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	window.add_child(layout)
	# Header
	var header := HBoxContainer.new()
	layout.add_child(header)
	_title = _label("MAP", 26, STYLE_COLOR)
	_title.name = "Title"
	header.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "Close  (M)"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 16)
	close.pressed.connect(func() -> void: self.close())
	header.add_child(close)
	# The map and the side panel
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	layout.add_child(body)
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.13, 0.12, 0.105)
	frame_style.set_border_width_all(1)
	frame_style.border_color = Color(0.3, 0.27, 0.22)
	frame.add_theme_stylebox_override("panel", frame_style)
	body.add_child(frame)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.pin_add_requested.connect(request_add_pin)
	view.pin_remove_requested.connect(request_remove_pin)
	frame.add_child(view)
	var side_scroll := ScrollContainer.new()
	side_scroll.name = "Side"
	side_scroll.custom_minimum_size.x = SIDEBAR_WIDTH
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 4)
	side_scroll.add_child(side)
	_where = _label("", 16, Color(0.95, 0.93, 0.87))
	_where.name = "Where"
	_where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_where)
	side.add_child(_heading("PLACES"))
	_places_box = VBoxContainer.new()
	_places_box.name = "Places"
	_places_box.add_theme_constant_override("separation", 0)
	side.add_child(_places_box)
	side.add_child(_heading("PINS"))
	_pins_hint = _label("", 13, Color(0.7, 0.68, 0.62))
	_pins_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_pins_hint)
	_pins_box = VBoxContainer.new()
	_pins_box.name = "Pins"
	_pins_box.add_theme_constant_override("separation", 0)
	side.add_child(_pins_box)
	side.add_child(_heading("KEY"))
	for row in [["you", Color.WHITE, "", "You"],
			["place", MapView.PLACE_COLOR, "", "A place you've been"],
			["place", Settlement.CLAIMED_COLOR, "", "Your settlement"],
			["settler", Settlement.CLAIMED_COLOR, "", "Your settlers"],
			["place_unvisited", MapView.UNVISITED_COLOR, "", "Not been there yet"],
			["gear", MapView.GEAR_COLOR, "", "Your dropped gear"],
			["truck", MapView.TRUCK_COLOR, "", "Your truck"],
			["station", MapView.STATION_COLORS[RecipeDefinition.Station.WORKBENCH], "W", "Workbench"],
			["station", MapView.STATION_COLORS[RecipeDefinition.Station.WEAPONS_BENCH], "G", "Weapons bench"],
			["pin", MapKnowledge.pin_color(1), "1", "Your pins"],
			["built", MapView.BUILT_COLOR, "", "Things you've built"],
			["storm", MapView.STORM_COLOR, "", "Ash storm edge"]]:
		side.add_child(_key_row(row[0], row[1], row[2], row[3]))
	var help := _label("Drag, scroll or WASD to move  ·  Wheel, pinch or + / - to zoom  ·  Right-click (or Ctrl-click) to drop or remove a pin  ·  Space: back to you",
		14, Color(0.72, 0.7, 0.64))
	help.name = "Help"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(help)


func is_open() -> bool:
	return visible


func open() -> void:
	if player == null or player.is_dead() or player.current_container != null:
		return
	_sync_zone()
	if view.zone_map == null:
		return
	visible = true
	player.player_input.set_ui_open(true)
	view.player = player
	# Size the view first, so the zoom limits are right
	await get_tree().process_frame
	if not visible:
		return
	view.zoom = clampf(view.zoom, view.min_zoom(), MapView.ZOOM_MAX)
	centre_on_player()
	_rebuild_lists()


func close() -> void:
	if not visible:
		return
	visible = false
	if player != null:
		player.player_input.set_ui_open(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func centre_on_player() -> void:
	if player != null:
		view.centre_on(Vector2(player.global_position.x, player.global_position.z))


func request_add_pin(at: Vector2) -> void:
	if player != null and player.request_add_pin(at) > 0:
		_rebuild_lists()


func request_remove_pin(number: int) -> void:
	if player != null and player.request_remove_pin(number):
		_rebuild_lists()


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if player == null or not player.controlled_locally:
		return
	if not visible:
		if event.is_action_pressed("map") and not player.player_input.ui_open and player.current_container == null and not player.is_dead():
			open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("map") or event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") or event.is_action_pressed("crafting"):
		close()  # and let the inventory or crafting open
	var k := event as InputEventKey
	if k != null and k.pressed and not (k.ctrl_pressed or k.meta_pressed):
		match k.physical_keycode:
			KEY_EQUAL, KEY_KP_ADD:
				view.zoom_by(MapView.ZOOM_STEP, view.size / 2.0)
			KEY_MINUS, KEY_KP_SUBTRACT:
				view.zoom_by(1.0 / MapView.ZOOM_STEP, view.size / 2.0)
			KEY_SPACE:
				centre_on_player()
			_:
				return
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	# A different zone (travel, or a load): a different map and pins
	if player.is_inside_tree() and player.map_zone_id() != _zone_id:
		_sync_zone()
	if not visible:
		return
	if player.is_dead():
		close()
		return
	# WASD / arrows move the map (gameplay ignores them while it's open)
	var dir := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if dir != Vector2.ZERO:
		view.pan_by(-dir.normalized() * PAN_SPEED * delta)
	_list_left -= delta
	if _list_left <= 0.0:
		_list_left = 0.5
		_refresh_distances()


# ---------------------------------------------------------------- binding

func _bind() -> void:
	if player == null:
		return
	player.map_pins_changed.connect(_on_pins_changed)
	player.place_discovered.connect(_on_place_discovered)
	view.player = player
	_zone_id = ""


func _unbind() -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.map_pins_changed.is_connected(_on_pins_changed):
		player.map_pins_changed.disconnect(_on_pins_changed)
		player.place_discovered.disconnect(_on_place_discovered)
	_clear_pin_marks()


## Picks up the map and knowledge for the zone the player is in.
func _sync_zone() -> void:
	if player == null or not player.is_inside_tree():
		return
	_zone_id = player.map_zone_id()
	var zone := Zone.of(player)
	var map := zone.get_map() if zone != null else Zone.map_for(get_tree().current_scene.scene_file_path if get_tree().current_scene != null else "")
	view.setup(map, player.map_knowledge)
	_title.text = "MAP  ·  %s" % map.title.to_upper() if map != null else "MAP"
	_sync_pin_marks()


func _on_pins_changed() -> void:
	_sync_pin_marks()
	if visible:
		_rebuild_lists()


func _on_place_discovered(_place: String) -> void:
	if visible:
		_rebuild_lists()


## One compass marker per pin, kept in step with the map.
func _sync_pin_marks() -> void:
	_clear_pin_marks()
	if player == null or not player.is_inside_tree():
		return
	var parent := Zone.of(player) as Node
	if parent == null:
		parent = player.get_parent()
	for pin in player.map_knowledge.pins:
		var mark := Landmark.new()
		var n: int = pin["number"]
		mark.name = "MapPin%d" % n
		mark.display_name = "Pin %d" % n
		mark.compass_name = "Pin %d" % n
		mark.radius = 0.0
		mark.marker_color = MapKnowledge.pin_color(n)
		var at: Vector2 = pin["at"]
		mark.position = Vector3(at.x, 0.0, at.y)
		parent.add_child(mark)
		_pin_marks[n] = mark


func _clear_pin_marks() -> void:
	for n in _pin_marks:
		var m := _pin_marks[n] as Node
		if is_instance_valid(m):
			m.get_parent().remove_child(m)
			m.queue_free()
	_pin_marks.clear()


## The compass marker for pin `number`, or null (for tests).
func pin_mark(number: int) -> Landmark:
	return _pin_marks.get(number) as Landmark


# ---------------------------------------------------------------- side panel

## Updates where you are and the distances in the lists (twice a second
## while open; the rows themselves stay, so clicks on them aren't lost).
func _refresh_distances() -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	var you := Vector2(player.global_position.x, player.global_position.z)
	for r in _rows:
		var b := r[0] as Button
		if is_instance_valid(b):
			b.text = "%s   %s" % [r[1], CompassBar._distance_text((r[2] as Vector2).distance_to(you))]
	# Where you are
	var here := Landmark.at(player.get_tree(), player.global_position)
	if here != null and here.radius > 0.0:
		_where.text = "You're at %s." % here.display_name
	else:
		var nearest: Landmark = null
		for n in player.get_tree().get_nodes_in_group("landmarks"):
			var l := n as Landmark
			if l != null and l.radius > 0.0 and (nearest == null or l.flat_distance(player.global_position) < nearest.flat_distance(player.global_position)):
				nearest = l
		_where.text = "In the open, %s from %s." % [CompassBar._distance_text(nearest.flat_distance(player.global_position)), nearest.display_name] if nearest != null else "In the open."


## Rebuilds the places and pins lists (on opening, and when they change).
func _rebuild_lists() -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	var k := player.map_knowledge
	_rows.clear()
	# Places, nearest first
	for c in _places_box.get_children():
		_places_box.remove_child(c)
		c.queue_free()
	var places: Array[Landmark] = []
	for n in player.get_tree().get_nodes_in_group("landmarks"):
		if n is Landmark and (n as Landmark).radius > 0.0:
			places.append(n)
	places.sort_custom(func(a: Landmark, b: Landmark) -> bool: return a.flat_distance(player.global_position) < b.flat_distance(player.global_position))
	var visited := 0
	for l in places:
		var been := k.has_visited(l.display_name)
		visited += int(been)
		var at := Vector2(l.global_position.x, l.global_position.z)
		var yours := view._is_yours(l.display_name)
		_places_box.add_child(_list_row("place" if been or yours else "place_unvisited",
			Settlement.CLAIMED_COLOR if yours else (MapView.PLACE_COLOR if been else MapView.UNVISITED_COLOR), "",
			l.display_name + ("  (yours)" if yours else ("" if been else "  ?")), at, -1))
	var counter := _label("Been to %d of %d" % [visited, places.size()], 13, Color(0.7, 0.68, 0.62))
	counter.name = "PlacesCount"
	_places_box.add_child(counter)
	# Pins
	for c in _pins_box.get_children():
		_pins_box.remove_child(c)
		c.queue_free()
	_pins_hint.text = ("Right-click the map to drop a pin. Pins show on your compass too (up to %d)." % MapKnowledge.MAX_PINS) if k.pins.is_empty() \
		else "%d of %d. Right-click a pin to remove it." % [k.pins.size(), MapKnowledge.MAX_PINS]
	var pins := k.pins.duplicate()
	pins.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["number"]) < int(b["number"]))
	for pin in pins:
		var n: int = pin["number"]
		var at: Vector2 = pin["at"]
		_pins_box.add_child(_list_row("pin", MapKnowledge.pin_color(n), str(n), "Pin %d" % n, at, n))
	_refresh_distances()


## A row in the side panel: symbol, name and distance (click to look at it
## on the map), and for a pin a Remove button.
func _list_row(kind: String, color: Color, text: String, title: String, at: Vector2, pin_number: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_key_icon(kind, color, text))
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.text = title
	_rows.append([b, title, at])
	b.tooltip_text = "Show it on the map"
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(func() -> void: view.centre_on(at))
	row.add_child(b)
	if pin_number > 0:
		var x := Button.new()
		x.name = "Remove"
		x.text = "Remove"
		x.focus_mode = Control.FOCUS_NONE
		x.add_theme_font_size_override("font_size", 13)
		x.pressed.connect(func() -> void: request_remove_pin(pin_number))
		row.add_child(x)
	return row


func _key_row(kind: String, color: Color, text: String, title: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_key_icon(kind, color, text))
	row.add_child(_label(title, 14, Color(0.85, 0.83, 0.78)))
	return row


func _key_icon(kind: String, color: Color, text: String) -> Control:
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func() -> void:
		MapView.draw_icon(icon, kind, Vector2(14, 22 if kind == "pin" else (18 if kind == "gear" else 14)), color, text, PI / 2.0 if kind == "truck" else 0.0))
	return icon


func _heading(text: String) -> Label:
	var l := _label(text, 15, STYLE_COLOR)
	l.custom_minimum_size.y = 30
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
