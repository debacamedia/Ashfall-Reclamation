class_name MapKnowledge
extends RefCounted
## What one player knows of one zone's map (Increment 17):
##   - the ground they've seen, in 8 m cells, revealed round them as they
##     move (further from up high: a rooftop or the water tower),
##   - the places they've been,
##   - the pins they've dropped (up to 10; they show on the compass too).
##
## Kept by the host on the PlayerController (one per zone) and saved with
## the player. Requests to change pins go through PlayerController, which
## validates them.

signal revealed(cells: Array[Vector2i])
signal place_visited(place_name: String)
signal pins_changed

## Size of one map cell (m).
const CELL := 8.0
## You see this far round you on the ground (m)…
const REVEAL_RADIUS := 70.0
## …this much further for every metre you are up…
const REVEAL_PER_METRE_UP := 6.0
## …up to this.
const REVEAL_MAX := 150.0
## Move this far (or climb half of it) before revealing again (m).
const REVEAL_STEP := 4.0
const MAX_PINS := 10
## A pin's colour comes from its number.
const PIN_COLORS := [
	Color(0.35, 0.85, 1.0), Color(1.0, 0.45, 0.75), Color(0.6, 1.0, 0.4), Color(1.0, 0.62, 0.25),
	Color(0.75, 0.6, 1.0), Color(1.0, 0.95, 0.4), Color(0.4, 1.0, 0.85), Color(1.0, 0.4, 0.4),
	Color(0.55, 0.75, 1.0), Color(0.85, 0.85, 0.85),
]
## Saved cell areas larger than this are ignored as corrupt.
const MAX_SAVED_CELLS := 1_000_000

## Vector2i cell -> true
var cells := {}
## Place display name -> true
var places := {}
## Each pin: {"number": 1–10, "at": Vector2(x, z)}, in the order dropped.
var pins: Array[Dictionary] = []

var _last_reveal := Vector3(INF, INF, INF)


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


## The middle of `cell` (x, z).
static func centre_of(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


static func reveal_radius_at(height: float) -> float:
	return minf(REVEAL_RADIUS + maxf(height, 0.0) * REVEAL_PER_METRE_UP, REVEAL_MAX)


static func pin_color(number: int) -> Color:
	return PIN_COLORS[(number - 1) % PIN_COLORS.size()]


func is_revealed(p: Vector2) -> bool:
	return cells.has(cell_of(p))


func is_cell_revealed(cell: Vector2i) -> bool:
	return cells.has(cell)


func has_visited(place_name: String) -> bool:
	return places.has(place_name)


## Reveals the ground round `p` (world position). Does nothing until you've
## moved REVEAL_STEP since last time, unless `force`. Returns the new cells.
func reveal_around(p: Vector3, force := false) -> Array[Vector2i]:
	var fresh: Array[Vector2i] = []
	if not force and Vector2(p.x - _last_reveal.x, p.z - _last_reveal.z).length() < REVEAL_STEP \
			and absf(p.y - _last_reveal.y) < REVEAL_STEP * 0.5:
		return fresh
	_last_reveal = p
	var r := reveal_radius_at(p.y)
	var flat := Vector2(p.x, p.z)
	var lo := cell_of(flat - Vector2(r, r))
	var hi := cell_of(flat + Vector2(r, r))
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var c := Vector2i(cx, cz)
			if not cells.has(c) and centre_of(c).distance_to(flat) <= r:
				cells[c] = true
				fresh.append(c)
	if not fresh.is_empty():
		revealed.emit(fresh)
	return fresh


## Marks a place as visited. True if it's the first time.
func visit(place_name: String) -> bool:
	if place_name == "" or places.has(place_name):
		return false
	places[place_name] = true
	place_visited.emit(place_name)
	return true


# ---------------------------------------------------------------- pins

## Why a pin can't go at `at` ("" = it can).
func pin_refusal_reason(at: Vector2) -> String:
	if not (is_finite(at.x) and is_finite(at.y)):
		return "Can't put a pin there"
	if pins.size() >= MAX_PINS:
		return "Your map has %d pins: remove one first" % MAX_PINS
	return ""


## Drops a pin; returns its number, or 0 if refused. The lowest free number
## is used, so removing Pin 2 and dropping another gives Pin 2 again.
func add_pin(at: Vector2) -> int:
	if pin_refusal_reason(at) != "":
		return 0
	var number := 1
	while find_pin(number) >= 0:
		number += 1
	pins.append({"number": number, "at": at})
	pins_changed.emit()
	return number


func remove_pin(number: int) -> bool:
	var i := find_pin(number)
	if i < 0:
		return false
	pins.remove_at(i)
	pins_changed.emit()
	return true


## Index in `pins` of pin `number`, or -1.
func find_pin(number: int) -> int:
	for i in pins.size():
		if int(pins[i]["number"]) == number:
			return i
	return -1


# ---------------------------------------------------------------- saving

## Plain JSON-safe data. The cells are a bitmap over the box they fill.
func to_data() -> Dictionary:
	var data := {"places": places.keys(), "pins": []}
	for pin in pins:
		var at: Vector2 = pin["at"]
		data["pins"].append([int(pin["number"]), snappedf(at.x, 0.1), snappedf(at.y, 0.1)])
	if not cells.is_empty():
		var lo := Vector2i(1 << 30, 1 << 30)
		var hi := -lo
		for c: Vector2i in cells:
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		var w := hi.x - lo.x + 1
		var h := hi.y - lo.y + 1
		var bits := PackedByteArray()
		bits.resize((w * h + 7) / 8)
		for c: Vector2i in cells:
			var i := (c.y - lo.y) * w + (c.x - lo.x)
			bits[i >> 3] |= 1 << (i & 7)
		data["cells"] = {"x": lo.x, "z": lo.y, "w": w, "h": h, "bits": Marshalls.raw_to_base64(bits)}
	return data


## Restores to_data(). Anything malformed is skipped.
func from_data(data: Variant) -> void:
	cells.clear()
	places.clear()
	pins.clear()
	_last_reveal = Vector3(INF, INF, INF)
	if not data is Dictionary:
		return
	var raw_cells: Variant = data.get("cells")
	if raw_cells is Dictionary and raw_cells.get("bits") is String:
		var x0 := int(_num(raw_cells.get("x")))
		var z0 := int(_num(raw_cells.get("z")))
		var w := int(_num(raw_cells.get("w")))
		var h := int(_num(raw_cells.get("h")))
		var bits := Marshalls.base64_to_raw(raw_cells["bits"])
		if w > 0 and h > 0 and w * h <= MAX_SAVED_CELLS and bits.size() >= (w * h + 7) / 8:
			for i in w * h:
				if bits[i >> 3] & (1 << (i & 7)):
					cells[Vector2i(x0 + i % w, z0 + i / w)] = true
	var raw_places: Variant = data.get("places")
	if raw_places is Array:
		for p in raw_places:
			if p is String and p != "":
				places[p] = true
	var raw_pins: Variant = data.get("pins")
	if raw_pins is Array:
		for e in raw_pins:
			if not (e is Array and e.size() == 3):
				continue
			var number := int(_num(e[0]))
			var at := Vector2(_num(e[1], NAN), _num(e[2], NAN))
			if number >= 1 and number <= MAX_PINS and find_pin(number) < 0 and pins.size() < MAX_PINS \
					and is_finite(at.x) and is_finite(at.y):
				pins.append({"number": number, "at": at})
	pins_changed.emit()


static func _num(v: Variant, fallback := 0.0) -> float:
	return float(v) if (v is int or v is float) and is_finite(float(v)) else fallback
