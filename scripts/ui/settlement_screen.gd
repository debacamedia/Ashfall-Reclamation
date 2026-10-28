class_name SettlementScreen
extends Control
## The settlement window (L, Increment 19): your settlement's stocks and the
## people who live there. Give each a job (farmer, guard), hand guards a
## spare gun and rounds from your backpack, or take a gun back. Talking to
## a settler, or using the notice board, opens it too.
##
## While it's open the mouse is free and gameplay input is ignored; the
## world keeps running. Built in code by the HUD; every change goes through
## the Settlement's request_* methods.

const STYLE_COLOR := Color(0.95, 0.8, 0.45)
const GOOD := Color(0.6, 0.95, 0.6)
const BAD := Color(1.0, 0.55, 0.45)
const TEXT := Color(0.92, 0.9, 0.84)
const DIM := Color(0.7, 0.68, 0.62)

## Set by the HUD.
var player: PlayerController
var settlement: Settlement
## The settler shown first and outlined (who you talked to).
var focus: Settler

var _title: Label
var _empty: Label
var _body: Control
var _stocks: Label
var _pump: Label
var _water_bar: ProgressBar
var _list: VBoxContainer
var _message: Label
var _message_left := 0.0
var _refresh_left := 0.0
var _rows_key := ""
## Settler -> {"status": Label, "gun": Label, "give": MenuButton}
var _rows := {}


func _init() -> void:
	name = "SettlementScreen"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var window := PanelContainer.new()
	window.name = "Window"
	window.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.offset_left = 60
	window.offset_top = 30
	window.offset_right = -60
	window.offset_bottom = -30
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.065, 0.97)
	style.set_border_width_all(1)
	style.border_color = Color(0.45, 0.4, 0.3)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	window.add_theme_stylebox_override("panel", style)
	add_child(window)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	window.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	_title = _label("SETTLEMENT", 26, STYLE_COLOR)
	_title.name = "Title"
	header.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "Close  (L)"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 16)
	close.pressed.connect(func() -> void: self.close())
	header.add_child(close)
	# With nothing claimed yet: how to get one
	_empty = _label("", 18, TEXT)
	_empty.name = "Empty"
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_empty)
	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	layout.add_child(body)
	_body = body
	# Left: stocks
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 330
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	left.add_child(_label("STOCKS", 16, STYLE_COLOR))
	_stocks = _label("", 16, TEXT)
	_stocks.name = "Stocks"
	_stocks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_stocks)
	_water_bar = ProgressBar.new()
	_water_bar.name = "WaterBar"
	_water_bar.show_percentage = false
	_water_bar.custom_minimum_size = Vector2(300, 10)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.4, 0.65, 0.9)
	_water_bar.add_theme_stylebox_override("background", bg)
	_water_bar.add_theme_stylebox_override("fill", fill)
	left.add_child(_water_bar)
	_pump = _label("", 15, DIM)
	_pump.name = "Pump"
	_pump.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_pump)
	var how := _label("A settlement hour is a minute of play. Farmers turn water into vegetables in the Farm Store (the barn); "
		+ "everyone eats one every 4 hours. Guards take guns and rounds from the Armory Locker (the farmhouse) by themselves.", 13, DIM)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(how)
	# Right: people
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	right.add_child(_label("SETTLERS", 16, STYLE_COLOR))
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_message = _label("", 16, BAD)
	_message.name = "Message"
	layout.add_child(_message)


func is_open() -> bool:
	return visible


## Opens on `s` (default: your first settlement), with `who` first.
func open(s: Settlement = null, who: Settler = null) -> void:
	if player == null or player.is_dead():
		return
	settlement = s if s != null else _first_settlement()
	focus = who
	visible = true
	player.player_input.set_ui_open(true)
	_rows_key = ""
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	if player != null:
		player.player_input.set_ui_open(false)


func _first_settlement() -> Settlement:
	var any: Settlement = null
	for n in get_tree().get_nodes_in_group("settlements"):
		var s := n as Settlement
		if s.is_claimed:
			return s
		any = s if any == null else any
	return any


func show_message(text: String) -> void:
	_message.text = text
	_message_left = 3.0


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if player == null or not player.controlled_locally:
		return
	if not visible:
		if event.is_action_pressed("settlement") and not player.player_input.ui_open and player.current_container == null and not player.is_dead():
			open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("settlement") or event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") or event.is_action_pressed("crafting") or event.is_action_pressed("map"):
		close()  # and let that window open


func _process(delta: float) -> void:
	if not visible:
		return
	if player == null or player.is_dead():
		close()
		return
	_message_left -= delta
	if _message_left <= 0.0:
		_message.text = ""
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.5
		refresh()


# ---------------------------------------------------------------- display

func refresh() -> void:
	var s := settlement
	var claimed := s != null and s.is_claimed
	_body.visible = claimed
	_empty.visible = not claimed
	_title.text = ("SETTLEMENT  ·  %s" % s.settlement_name.to_upper()) if s != null else "SETTLEMENT"
	if not claimed:
		if s == null:
			_empty.text = "No settlements here."
		else:
			var raiders := s.raiders_here()
			_empty.text = ("You haven't claimed a settlement yet.\n\n%s: clear the raiders, then hold E at the notice board in front of the farmhouse porch to claim it."
				% s.settlement_name) + ("\n\nRaiders there now: %d" % raiders if raiders > 0 else "")
		return
	# Stocks
	var r := s.rates()
	var people := s.members()
	var here := people.filter(func(p: Settler) -> bool: return p.has_arrived()).size()
	var lines := []
	lines.append("Fresh Vegetables:  %d   (%s / hour)" % [s.food(), _signed(r["food"])])
	lines.append("Water:  %d / %d L   (%s / hour)" % [roundi(s.water), roundi(s.water_capacity), _signed(r["water"])])
	lines.append("Beds:  %d / %d in use%s" % [people.size(), s.beds, "" if here == people.size() else "  (%d on the way)" % (people.size() - here)])
	lines.append("Farmers working:  %d" % r["farmers"])
	lines.append("Armory:  %s" % _armory_text(s))
	if s.free_beds() <= 0:
		lines.append("Newcomers:  no free bed")
	elif s.food() < s.arrival_food_needed:
		lines.append("Newcomers:  need %d+ vegetables in store" % s.arrival_food_needed)
	else:
		lines.append("Next newcomer:  in about %d min" % ceili(maxf(s.arrival_in, 0.0) * s.hour_seconds / 60.0))
	_stocks.text = "\n".join(lines)
	_water_bar.value = s.water / s.water_capacity * 100.0
	_pump.text = "Pump: running" if s.pump_working else "Pump: broken. Repair it in the pump house with %s." % Settlement.pump_parts_text()
	_pump.add_theme_color_override("font_color", GOOD if s.pump_working else BAD)
	# People: rebuild the rows when who's here or what they have changes
	people.sort_custom(func(a: Settler, b: Settler) -> bool:
		return (a == focus) if (a == focus) != (b == focus) else a.settler_name < b.settler_name)
	var key := ""
	for p in people:
		key += "%s|%d|%s|" % [p.get_instance_id(), p.role, p.gun.id if p.gun != null else ""]
	key += str(_spares().size())
	if key != _rows_key:
		_rows_key = key
		_build_rows(people)
	for p: Settler in _rows:
		if is_instance_valid(p):
			var row: Dictionary = _rows[p]
			(row["status"] as Label).text = p.status_text()
			(row["status"] as Label).add_theme_color_override("font_color", BAD if p.is_hungry() or p.short_of_water else GOOD)
			(row["gun"] as Label).text = p.gun_text() if p.role == Settler.Role.GUARD or p.gun != null else ""


func _build_rows(people: Array[Settler]) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	if people.is_empty():
		_list.add_child(_label("Nobody lives here yet. Newcomers come when there's a free bed and food; "
			+ "survivors you meet elsewhere (Saint Mercy, Halden's, Black Ridge) will come if you ask.", 15, DIM))
		return
	var spares := _spares()
	for p in people:
		var panel := PanelContainer.new()
		panel.name = "Row_%s" % p.settler_name
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.11, 0.11, 0.1)
		st.set_border_width_all(2 if p == focus else 1)
		st.border_color = STYLE_COLOR if p == focus else Color(0.28, 0.26, 0.22)
		st.set_corner_radius_all(4)
		st.set_content_margin_all(8)
		panel.add_theme_stylebox_override("panel", st)
		_list.add_child(panel)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		panel.add_child(col)
		var top := HBoxContainer.new()
		col.add_child(top)
		var nm := _label(p.settler_name, 18, TEXT)
		nm.custom_minimum_size.x = 140
		top.add_child(nm)
		var status := _label("", 15, GOOD)
		status.name = "Status"
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(status)
		var jobs := HBoxContainer.new()
		jobs.add_theme_constant_override("separation", 6)
		col.add_child(jobs)
		for r in [Settler.Role.FARMER, Settler.Role.GUARD, Settler.Role.NONE]:
			var b := Button.new()
			b.name = "Job_%s" % Settler.ROLE_NAMES[r]
			b.text = Settler.ROLE_NAMES[r]
			b.toggle_mode = true
			b.button_pressed = p.role == r
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 14)
			b.pressed.connect(func() -> void: request_role(p, r))
			jobs.add_child(b)
		var arms := HBoxContainer.new()
		arms.add_theme_constant_override("separation", 6)
		col.add_child(arms)
		var gun := _label("", 14, DIM)
		gun.name = "Gun"
		gun.custom_minimum_size.x = 210
		arms.add_child(gun)
		var give := MenuButton.new()
		give.name = "GiveGun"
		give.text = "Give a gun"
		give.flat = false
		give.focus_mode = Control.FOCUS_NONE
		give.add_theme_font_size_override("font_size", 14)
		give.disabled = spares.is_empty()
		give.tooltip_text = "No spare guns in your backpack" if spares.is_empty() else "One of the spare guns in your backpack"
		var pop := give.get_popup()
		for sp in spares:
			pop.add_item((sp[1] as ItemDefinition).display_name, sp[0])
		pop.id_pressed.connect(func(index: int) -> void: request_give_gun(p, index))
		arms.add_child(give)
		var ammo := Button.new()
		ammo.name = "GiveAmmo"
		ammo.text = "Give rounds"
		ammo.focus_mode = Control.FOCUS_NONE
		ammo.add_theme_font_size_override("font_size", 14)
		ammo.disabled = p.gun == null
		ammo.pressed.connect(func() -> void: request_give_ammo(p))
		arms.add_child(ammo)
		var take := Button.new()
		take.name = "TakeGun"
		take.text = "Take gun back"
		take.focus_mode = Control.FOCUS_NONE
		take.add_theme_font_size_override("font_size", 14)
		take.disabled = p.gun == null
		take.pressed.connect(func() -> void: request_take_gun(p))
		arms.add_child(take)
		_rows[p] = {"status": status, "gun": gun, "give": give}


## Spare guns in your backpack: [slot index, item].
func _spares() -> Array:
	var out := []
	var inv := player.inventory if player != null else null
	if inv == null:
		return out
	for i in inv.slot_count:
		var it := inv.get_slot_item(i)
		if it != null and it.weapon != null and not it.weapon.melee:
			out.append([i, it])
	return out


static func _armory_text(s: Settlement) -> String:
	if s.armory == null:
		return "none"
	var guns := 0
	var rounds := 0
	var inv := s.armory.inventory
	for i in inv.slot_count:
		var it := inv.get_slot_item(i)
		if it == null:
			continue
		if it.weapon != null:
			guns += inv.get_slot_quantity(i)
		elif it.category == ItemDefinition.Category.AMMO:
			rounds += inv.get_slot_quantity(i)
	return "%d gun%s, %d rounds" % [guns, "" if guns == 1 else "s", rounds]


static func _signed(v: float) -> String:
	return ("+%.1f" % v) if v >= 0.0 else ("%.1f" % v)


# ---------------------------------------------------------------- requests

func request_role(p: Settler, r: Settler.Role) -> void:
	if settlement != null:
		settlement.request_set_role(player, p, r)
	_rows_key = ""
	refresh()


func request_give_gun(p: Settler, index: int) -> void:
	if settlement != null:
		settlement.request_give_gun(player, p, index)
	_rows_key = ""
	refresh()


func request_give_ammo(p: Settler) -> void:
	if settlement != null:
		settlement.request_give_ammo(player, p)
	refresh()


func request_take_gun(p: Settler) -> void:
	if settlement != null:
		settlement.request_take_gun(player, p)
	_rows_key = ""
	refresh()


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
