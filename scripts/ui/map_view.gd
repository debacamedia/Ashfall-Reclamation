class_name MapView
extends Control
## The map itself, inside the map screen (Increment 17): the zone's picture
## with the ground you haven't explored hidden, and on top the ash-storm
## edge, the places, crafting benches, things you've built, your dropped
## gear, your pins and you.
##
## Drag (or two-finger scroll on a trackpad or Magic Mouse) to move, wheel,
## pinch or the + / - buttons to zoom, right-click (or Ctrl-click) to drop a
## pin or remove one. Built in
## code by MapScreen. Purely presentation: pins go through PlayerController.

signal pin_add_requested(at: Vector2)
signal pin_remove_requested(number: int)

const ZOOM_MAX := 4.0
const ZOOM_STEP := 1.25
const LABEL_SIZE := 17
const SMALL_SIZE := 13
## How close (px) the cursor must be to pick out a marker.
const PICK_RADIUS := 13.0
const PLACE_COLOR := Color(0.95, 0.75, 0.35)
const UNVISITED_COLOR := Color(0.62, 0.6, 0.56)
const STORM_COLOR := Color(1.0, 0.45, 0.2, 0.85)
const GEAR_COLOR := Color(1, 1, 1)
const BUILT_COLOR := Color(0.85, 0.78, 0.6)
const TRUCK_COLOR := Color(0.55, 0.8, 1.0)
const STATION_COLORS := {
	RecipeDefinition.Station.WORKBENCH: Color(0.78, 0.6, 0.38),
	RecipeDefinition.Station.WEAPONS_BENCH: Color(0.55, 0.7, 0.85),
}

var player: PlayerController
var zone_map: ZoneMap
## Map scale: screen units per metre.
var zoom := 1.0
## The world point (x, z) at the middle of the view.
var centre := Vector2.ZERO
## Shows everything, explored or not (tests, and a debug toggle).
var reveal_all := false:
	set(value):
		reveal_all = value
		if _material != null:
			_material.set_shader_parameter("reveal_all", value)
## What the cursor is over: {"kind", "name", "at", "number"?}, or {}.
var hovered := {}

var _picture := TextureRect.new()
var _overlay := Control.new()
var _material := ShaderMaterial.new()
var _knowledge: MapKnowledge
var _fog_image: Image
var _fog_texture: ImageTexture
var _fog_origin := Vector2i.ZERO
var _dragging := false
var _drag_moved := 0.0
var _mouse := Vector2(-1, -1)


func _init() -> void:
	name = "MapView"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_picture.name = "Picture"
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material.shader = preload("res://assets/shaders/map_fog.gdshader")
	var noise := FastNoiseLite.new()
	noise.seed = 17
	noise.frequency = 0.04
	noise.fractal_octaves = 3
	var grain := NoiseTexture2D.new()
	grain.noise = noise
	grain.seamless = true
	grain.width = 128
	grain.height = 128
	_material.set_shader_parameter("grain", grain)
	_picture.material = _material
	add_child(_picture)
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	# Zoom buttons, for a mouse without a wheel (a Magic Mouse scrolls the map)
	var buttons := VBoxContainer.new()
	buttons.name = "ZoomButtons"
	buttons.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	buttons.offset_left = -54
	buttons.offset_right = -10
	buttons.offset_top = 10
	buttons.add_theme_constant_override("separation", 4)
	add_child(buttons)
	for spec in [["ZoomIn", "+", "Zoom in"], ["ZoomOut", "-", "Zoom out"], ["Recentre", "Me", "Back to you (Space)"]]:
		var b := Button.new()
		b.name = spec[0]
		b.text = spec[1]
		b.tooltip_text = spec[2]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(44, 36)
		b.add_theme_font_size_override("font_size", 18)
		buttons.add_child(b)
	(buttons.get_node("ZoomIn") as Button).pressed.connect(func() -> void: zoom_by(ZOOM_STEP, size / 2.0))
	(buttons.get_node("ZoomOut") as Button).pressed.connect(func() -> void: zoom_by(1.0 / ZOOM_STEP, size / 2.0))
	(buttons.get_node("Recentre") as Button).pressed.connect(func() -> void:
		if player != null and is_instance_valid(player):
			centre_on(Vector2(player.global_position.x, player.global_position.z)))


## Shows `map` with what `knowledge` has revealed (either may be null).
func setup(map: ZoneMap, knowledge: MapKnowledge) -> void:
	if _knowledge != null and _knowledge.revealed.is_connected(_on_revealed):
		_knowledge.revealed.disconnect(_on_revealed)
	zone_map = map
	_knowledge = knowledge
	_picture.texture = map.texture if map != null else null
	if map == null:
		return
	# The fog: one pixel per map cell over the picture's ground
	_fog_origin = MapKnowledge.cell_of(map.world_rect.position)
	var cells := Vector2i((map.world_rect.size / MapKnowledge.CELL).ceil())
	_fog_image = Image.create(maxi(cells.x, 1), maxi(cells.y, 1), false, Image.FORMAT_L8)
	if knowledge != null:
		for c: Vector2i in knowledge.cells:
			_mark(c)
		knowledge.revealed.connect(_on_revealed)
	_fog_texture = ImageTexture.create_from_image(_fog_image)
	_material.set_shader_parameter("fog", _fog_texture)
	# The fog image is a whole number of cells; the picture may end mid-cell
	_material.set_shader_parameter("reveal_all", reveal_all)
	zoom = clampf(zoom, min_zoom(), ZOOM_MAX)


func _on_revealed(cells: Array[Vector2i]) -> void:
	for c in cells:
		_mark(c)
	if _fog_texture != null:
		_fog_texture.update(_fog_image)


func _mark(c: Vector2i) -> void:
	var p := c - _fog_origin
	if p.x >= 0 and p.y >= 0 and p.x < _fog_image.get_width() and p.y < _fog_image.get_height():
		_fog_image.set_pixel(p.x, p.y, Color.WHITE)


## How revealed the fog shows at world point `p` (0–1), for tests.
func fog_at(p: Vector2) -> float:
	if _fog_image == null:
		return 0.0
	var c := MapKnowledge.cell_of(p) - _fog_origin
	if c.x < 0 or c.y < 0 or c.x >= _fog_image.get_width() or c.y >= _fog_image.get_height():
		return 0.0
	return _fog_image.get_pixel(c.x, c.y).r


# ---------------------------------------------------------------- view

## The smallest zoom: the whole map fits.
func min_zoom() -> float:
	if zone_map == null or size.x <= 0.0 or size.y <= 0.0:
		return 0.25
	return minf(size.x / zone_map.world_rect.size.x, size.y / zone_map.world_rect.size.y)


func to_screen(world: Vector2) -> Vector2:
	return size / 2.0 + (world - centre) * zoom


func to_world(screen: Vector2) -> Vector2:
	return centre + (screen - size / 2.0) / zoom


func centre_on(world: Vector2) -> void:
	centre = world
	_clamp()


## Zooms by `factor`, keeping the ground under `around` (screen) still.
func zoom_by(factor: float, around: Vector2) -> void:
	var before := to_world(around)
	zoom = clampf(zoom * factor, min_zoom(), ZOOM_MAX)
	centre += before - to_world(around)
	_clamp()


func pan_by(screen_delta: Vector2) -> void:
	centre -= screen_delta / zoom
	_clamp()


## Keeps the middle of the view on the map.
func _clamp() -> void:
	if zone_map == null:
		return
	var r := zone_map.world_rect
	centre = Vector2(clampf(centre.x, r.position.x, r.end.x), clampf(centre.y, r.position.y, r.end.y))


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or zone_map == null:
		return
	zoom = clampf(zoom, min_zoom(), ZOOM_MAX)
	_picture.position = to_screen(zone_map.world_rect.position)
	_picture.size = zone_map.world_rect.size * zoom
	if _mouse.x >= 0.0:
		hovered = pick(_mouse)
	_overlay.queue_redraw()


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		var pin_click := mb.button_index == MOUSE_BUTTON_RIGHT \
			or (mb.button_index == MOUSE_BUTTON_LEFT and (mb.ctrl_pressed or mb.meta_pressed))
		if mb.pressed and pin_click:
			pin_action(mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_drag_moved = 0.0
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			# A smooth wheel sends small steps (factor < 1)
			var step := pow(ZOOM_STEP, mb.factor if mb.factor > 0.0 else 1.0)
			zoom_by(step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / step, mb.position)
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		_mouse = mm.position
		if _dragging and mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			pan_by(mm.relative)
			_drag_moved += mm.relative.length()
		accept_event()
		return
	# Trackpad: two-finger scroll moves the map, pinch zooms
	var pan := event as InputEventPanGesture
	if pan != null:
		pan_by(-pan.delta * 12.0)
		accept_event()
		return
	var mag := event as InputEventMagnifyGesture
	if mag != null:
		zoom_by(mag.factor, mag.position)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_mouse = Vector2(-1, -1)
		hovered = {}
		_dragging = false


## Right-click at `screen`: removes the pin there, or drops a new one.
func pin_action(screen: Vector2) -> void:
	var hit := pick(screen)
	if hit.get("kind") == "pin":
		pin_remove_requested.emit(int(hit["number"]))
	else:
		pin_add_requested.emit(to_world(screen))


## The marker nearest `screen` within PICK_RADIUS, or {}.
func pick(screen: Vector2) -> Dictionary:
	var best := {}
	var best_d := PICK_RADIUS
	for m in markers():
		var d := to_screen(m["at"]).distance_to(screen)
		# A pin is picked by its head, above the point it marks
		if m["kind"] == "pin":
			d = minf(d, (to_screen(m["at"]) + Vector2(0, -16)).distance_to(screen))
		if d < best_d:
			best_d = d
			best = m
	return best


## Everything shown on the map that you can point at, each
## {"kind", "name", "at"(x, z), …}.
func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return out
	var tree := player.get_tree()
	for n in tree.get_nodes_in_group("landmarks"):
		var l := n as Landmark
		if l != null and l.radius > 0.0:
			var visited := _knowledge != null and _knowledge.has_visited(l.display_name)
			out.append({"kind": "place" if visited else "place_unvisited", "name": l.display_name,
				"at": Vector2(l.global_position.x, l.global_position.z), "visited": visited})
	for n in tree.get_nodes_in_group("crafting_stations"):
		var s := n as CraftingStation
		if s != null and _seen(s.global_position):
			out.append({"kind": "station", "name": RecipeDefinition.station_name(s.station), "station": s.station,
				"at": Vector2(s.global_position.x, s.global_position.z)})
	for n in tree.get_nodes_in_group("salvage_containers"):
		if n is DeathCache:
			var c := n as DeathCache
			out.append({"kind": "gear", "name": "Your gear", "at": Vector2(c.global_position.x, c.global_position.z)})
	for n in tree.get_nodes_in_group("vehicles"):
		var t := n as Truck
		if t != null:
			out.append({"kind": "truck", "name": "Your truck" if t.driver == null else "Your truck (you're driving)",
				"at": Vector2(t.global_position.x, t.global_position.z), "heading": t.map_heading()})
	if _knowledge != null:
		for pin in _knowledge.pins:
			out.append({"kind": "pin", "name": "Pin %d" % pin["number"], "number": pin["number"], "at": pin["at"]})
	return out


func _seen(p: Vector3) -> bool:
	return reveal_all or (_knowledge != null and _knowledge.is_revealed(Vector2(p.x, p.z)))


# ---------------------------------------------------------------- drawing

func _draw_overlay() -> void:
	if zone_map == null or player == null or not is_instance_valid(player):
		return
	var ci := _overlay
	var font := get_theme_default_font()
	# The ash-storm edge
	var boundary := ZoneBoundary.find_in(player.get_tree())
	if boundary != null:
		var poly := boundary.polygon
		for i in poly.size():
			var a := to_screen(poly[i])
			var b := to_screen(poly[(i + 1) % poly.size()])
			var sea := boundary.edge_kinds.size() > i and boundary.edge_kinds[i] == ZoneBoundary.Kind.SEA
			ci.draw_dashed_line(a, b, Color(0.55, 0.75, 0.95, 0.7) if sea else STORM_COLOR, 2.0, 9.0)
	# Things you've built (not the places' own props)
	for n in player.get_tree().get_nodes_in_group("structures"):
		var st := n as Structure
		if st != null and not st is LevelProp and is_instance_valid(st) and _seen(st.global_position):
			draw_icon(ci, "built", to_screen(Vector2(st.global_position.x, st.global_position.z)), BUILT_COLOR)
	var all := markers()
	# Places under everything else; their names last, on top
	for m in all:
		if m["kind"] == "station":
			draw_icon(ci, "station", to_screen(m["at"]), STATION_COLORS.get(m["station"], Color.WHITE),
				"G" if m["station"] == RecipeDefinition.Station.WEAPONS_BENCH else "W")
	for m in all:
		if m["kind"] == "place" or m["kind"] == "place_unvisited":
			draw_icon(ci, m["kind"], to_screen(m["at"]), PLACE_COLOR if m["visited"] else UNVISITED_COLOR)
	for m in all:
		if m["kind"] == "place" or m["kind"] == "place_unvisited":
			var text: String = m["name"] if m["visited"] else m["name"] + "  ?"
			_label(ci, font, to_screen(m["at"]) + Vector2(0, -14), text, LABEL_SIZE,
				Color(1.0, 0.93, 0.78) if m["visited"] else Color(0.72, 0.7, 0.66))
	for m in all:
		if m["kind"] == "gear":
			draw_icon(ci, "gear", to_screen(m["at"]), GEAR_COLOR)
			_label(ci, font, to_screen(m["at"]) + Vector2(0, 22), "Your gear", SMALL_SIZE, Color.WHITE)
	for m in all:
		if m["kind"] == "truck":
			draw_icon(ci, "truck", to_screen(m["at"]), TRUCK_COLOR, "", -float(m["heading"]))
	for m in all:
		if m["kind"] == "pin":
			draw_icon(ci, "pin", to_screen(m["at"]), MapKnowledge.pin_color(m["number"]), str(m["number"]))
	# You
	var you := Vector2(player.global_position.x, player.global_position.z)
	draw_icon(ci, "you", to_screen(you), Color.WHITE, "", -player.rotation.y)
	_draw_scale(ci, font)
	_draw_north(ci, font)
	# What the cursor is over, or how far the cursor is from you
	if _mouse.x >= 0.0:
		var at: Vector2 = hovered["at"] if not hovered.is_empty() else to_world(_mouse)
		var dist := CompassBar._distance_text(at.distance_to(you))
		var text := ("%s  ·  %s from you" % [hovered["name"], dist]) if not hovered.is_empty() else "%s from you" % dist
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE + 1).x
		var box := Rect2(size.x - w - 24, size.y - 30, w + 16, 24)
		ci.draw_rect(box, Color(0.05, 0.05, 0.04, 0.8))
		ci.draw_string(font, box.position + Vector2(8, 17), text, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE + 1, Color(0.95, 0.93, 0.87))


func _label(ci: CanvasItem, font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var p := at + Vector2(-w / 2.0, 0)
	ci.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(0, 0, 0, 0.75))
	ci.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## A scale bar in the bottom-left corner: 50, 100, 250 or 500 m.
func _draw_scale(ci: CanvasItem, font: Font) -> void:
	var metres := 50.0
	for m in [50.0, 100.0, 250.0, 500.0]:
		metres = m
		if m * zoom >= 70.0:
			break
	var length := metres * zoom
	var o := Vector2(16, size.y - 18)
	ci.draw_rect(Rect2(o + Vector2(-6, -24), Vector2(length + 12, 30)), Color(0.05, 0.05, 0.04, 0.7))
	ci.draw_line(o, o + Vector2(length, 0), Color(0.95, 0.93, 0.87), 3.0)
	for x in [0.0, length]:
		ci.draw_line(o + Vector2(x, -6), o + Vector2(x, 2), Color(0.95, 0.93, 0.87), 2.0)
	ci.draw_string(font, o + Vector2(0, -9), "%d m" % metres, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, Color(0.95, 0.93, 0.87))


func _draw_north(ci: CanvasItem, font: Font) -> void:
	var c := Vector2(30, 34)
	ci.draw_circle(c, 18, Color(0.05, 0.05, 0.04, 0.7))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -13), c + Vector2(6, 4), c + Vector2(0, 0), c + Vector2(-6, 4)]), Color(1.0, 0.82, 0.45))
	var w := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE).x
	ci.draw_string(font, c + Vector2(-w / 2.0, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, Color(1.0, 0.82, 0.45))


## Draws a map symbol on `ci` at `at`. Kinds: you (an arrow turned by
## `angle`), place, place_unvisited, gear, station (with a letter), pin
## (with its number), truck (turned by `angle`), built, storm. Also used by the map screen's key.
static func draw_icon(ci: CanvasItem, kind: String, at: Vector2, color := Color.WHITE, text := "", angle := 0.0) -> void:
	var outline := Color(0, 0, 0, 0.8)
	match kind:
		"you":
			var pts := PackedVector2Array([Vector2(0, -12), Vector2(8, 9), Vector2(0, 4), Vector2(-8, 9)])
			for i in pts.size():
				pts[i] = at + pts[i].rotated(angle)
			var ring := pts.duplicate()
			ring.append(pts[0])
			ci.draw_circle(at, 15, Color(1, 1, 1, 0.16))
			ci.draw_colored_polygon(pts, color)
			ci.draw_polyline(ring, outline, 2.0)
		"place", "place_unvisited":
			var d := 8.0
			var pts := PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0), at + Vector2(0, -d)])
			if kind == "place":
				ci.draw_colored_polygon(pts.slice(0, 4), color)
				ci.draw_polyline(pts, outline, 1.5)
			else:
				ci.draw_colored_polygon(pts.slice(0, 4), Color(0, 0, 0, 0.5))
				ci.draw_polyline(pts, color, 2.0)
		"gear":
			ci.draw_line(at + Vector2(0, -8), at + Vector2(0, -22), Color(1, 1, 1, 0.5), 3.0)
			ci.draw_rect(Rect2(at - Vector2(8, 6), Vector2(16, 12)), Color(0.15, 0.13, 0.1))
			ci.draw_rect(Rect2(at - Vector2(8, 6), Vector2(16, 12)), color, false, 2.0)
			ci.draw_line(at + Vector2(-8, -1), at + Vector2(8, -1), color, 1.5)
		"station":
			ci.draw_circle(at, 9, outline)
			ci.draw_circle(at, 7.5, color)
			_icon_text(ci, at, text, Color(0.08, 0.07, 0.06))
		"pin":
			var head := at + Vector2(0, -16)
			ci.draw_colored_polygon(PackedVector2Array([at, head + Vector2(6, 3), head + Vector2(-6, 3)]), color.darkened(0.25))
			ci.draw_circle(head, 9.5, outline)
			ci.draw_circle(head, 8, color)
			_icon_text(ci, head, text, Color(0.06, 0.06, 0.06))
		"truck":
			# A box with a cab end, nose along `angle` (a player's yaw)
			var pts := PackedVector2Array([Vector2(-6, -12), Vector2(6, -12), Vector2(7, 11), Vector2(-7, 11)])
			for i in pts.size():
				pts[i] = at + pts[i].rotated(angle)
			ci.draw_colored_polygon(pts, color)
			var ring := pts.duplicate()
			ring.append(pts[0])
			ci.draw_polyline(ring, outline, 2.0)
			ci.draw_line(at + Vector2(-6, -4).rotated(angle), at + Vector2(6, -4).rotated(angle), outline, 2.0)
		"built":
			ci.draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), color)
			ci.draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), outline, false, 1.0)
		"storm":
			ci.draw_dashed_line(at - Vector2(10, 0), at + Vector2(10, 0), color, 2.0, 5.0)


static func _icon_text(ci: CanvasItem, at: Vector2, text: String, color: Color) -> void:
	if text == "":
		return
	var font := ThemeDB.fallback_font
	var s := 11
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	ci.draw_string(font, at + Vector2(-w / 2.0, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, s, color)
