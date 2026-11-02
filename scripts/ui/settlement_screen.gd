class_name SettlementScreen
extends Control
## The settlement window (L, Increment 19): your settlement's stocks, what's
## being built (19.6), what's happened there (the log, 20.5) and the people
## who live there. Give each a job
## (farmer, guard, builder), hand guards a spare gun and rounds from your
## backpack, or take a gun back; call off something planned. Talking to a
## settler, or using the notice board, opens it too.
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
var _sites_list: VBoxContainer
var _sites_key := ""
## ConstructionSite -> {"status": Label}
var _site_rows := {}
var _log_list: VBoxContainer
var _log_key := ""
## One button per settlement you hold (23): which one the screen shows.
var _tabs: HBoxContainer
var _tabs_key := ""
var _how: Label


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
	var gap := Control.new()
	gap.custom_minimum_size.x = 24
	header.add_child(gap)
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override("separation", 6)
	header.add_child(_tabs)
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
	left.custom_minimum_size.x = 300
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
	_water_bar.custom_minimum_size = Vector2(280, 10)
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
	_how = _label("", 13, DIM)
	_how.name = "How"
	_how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_how)
	# Middle: what's being built
	var mid := VBoxContainer.new()
	mid.name = "Building"
	mid.custom_minimum_size.x = 320
	mid.add_theme_constant_override("separation", 6)
	body.add_child(mid)
	mid.add_child(_label("BUILDING", 16, STYLE_COLOR))
	var about := _label("Builders put these up in order, once each has its materials: hand them over at the site (E), "
		+ "or leave them in the stores. Plan buildings (a bunkhouse, storehouse, guard tower…) in build mode (B).", 13, DIM)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(about)
	var sites_scroll := ScrollContainer.new()
	sites_scroll.name = "SitesScroll"
	sites_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sites_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(sites_scroll)
	_sites_list = VBoxContainer.new()
	_sites_list.name = "Sites"
	_sites_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sites_list.add_theme_constant_override("separation", 6)
	sites_scroll.add_child(_sites_list)
	# Under it: the log, with what happened while you were away first (20.5)
	mid.add_child(_label("LOG", 16, STYLE_COLOR))
	var log_scroll := ScrollContainer.new()
	log_scroll.name = "LogScroll"
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(log_scroll)
	_log_list = VBoxContainer.new()
	_log_list.name = "Log"
	_log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_list.add_theme_constant_override("separation", 4)
	log_scroll.add_child(_log_list)
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
	settlement = s if s != null else _default_settlement()
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


## The one you're at, else the nearest you hold, else the nearest (23).
func _default_settlement() -> Settlement:
	var best: Settlement = null
	var best_d := INF
	var at := player.global_position if player != null else Vector3.ZERO
	for n in get_tree().get_nodes_in_group("settlements"):
		var s := n as Settlement
		var d := s.global_position.distance_to(at) - (100000.0 if s.is_claimed else 0.0)
		if d < best_d:
			best_d = d
			best = s
	return best


## Settlements you hold, in the order they sit in the zone (23).
func _held() -> Array[Settlement]:
	var out: Array[Settlement] = []
	for n in get_tree().get_nodes_in_group("settlements"):
		if (n as Settlement).is_claimed:
			out.append(n)
	return out


## Shows `s` instead (a tab).
func show_settlement(s: Settlement) -> void:
	if s == null or s == settlement:
		return
	settlement = s
	focus = null
	_rows_key = ""
	_sites_key = ""
	_log_key = ""
	refresh()


func _refresh_tabs() -> void:
	var held := _held()
	if settlement != null and not held.has(settlement):
		held.append(settlement)
	var key := ""
	for h in held:
		key += "%d:%s|" % [h.get_instance_id(), h == settlement]
	if key == _tabs_key:
		return
	_tabs_key = key
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_tabs.visible = held.size() > 1
	for h in held:
		var b := Button.new()
		b.name = "Tab_%s" % h.settlement_id
		b.text = h.settlement_name
		b.toggle_mode = true
		b.button_pressed = h == settlement
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func() -> void: show_settlement(h))
		_tabs.add_child(b)


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
	_refresh_tabs()
	if not claimed:
		if s == null:
			_empty.text = "No settlements here."
		else:
			var raiders := s.raiders_here()
			_empty.text = ("%s isn't yours yet.\n\nClear the raiders, then %s to claim it." % [s.settlement_name, s.claim_hint]) + ("\n\nRaiders there now: %d" % raiders if raiders > 0 else "")
		return
	# Stocks
	var r := s.rates()
	var people := s.members()
	var here := people.filter(func(p: Settler) -> bool: return p.has_arrived()).size()
	var lines := []
	var cap := s.food_capacity()
	lines.append("Fresh Vegetables:  %d / %d   (%s / hour)%s" % [s.food(), cap, _signed(r["food"]),
		"   Store full" if cap > 0 and s.food() >= cap else ""])
	var dishes := s.stored_dishes()
	if dishes[0] > 0 or s.farm_spots().is_empty():
		lines.append("Cooked food in the stores:  %d dishes   (%d meals)" % [dishes[0], floori(dishes[1])])
	lines.append("Water:  %d / %d L   (%s / hour)" % [roundi(s.water), roundi(s.water_capacity), _signed(r["water"])])
	lines.append("Wood Planks:  %d   (%s / hour)" % [s.planks(), _signed(r["planks"])])
	lines.append("Beds:  %d / %d in use%s" % [people.size(), s.total_beds(), "" if here == people.size() else "  (%d on the way)" % (people.size() - here)])
	if not s.farm_spots().is_empty() or r["farmers"] > 0:
		lines.append("Farmers working:  %d   (fields for %d)" % [r["farmers"], s.farm_spots().size()])
	if not s.mine_spots().is_empty():
		lines.append("Scrap Metal:  %d   (%s / hour)" % [s.scrap(), _signed(r["scrap"])])
		lines.append("Miners working:  %d   (rock faces for %d)" % [r["miners"], s.mine_spots().size()])
	var posts := s.guard_posts().size()
	if posts > 0:
		lines.append("Guard posts:  %d" % posts)
	lines.append("Armory:  %s" % _armory_text(s))
	match s.raid_phase:
		Settlement.RaidPhase.WARNED:
			lines.append("RAIDERS COMING from %s: %d, in about %d min" % [s.raid_from_name, s.raid_size, maxi(ceili(s.next_raid_in * s.hour_seconds / 60.0), 1)])
			if not s.player_near():
				lines.append("You're %d m away: be back within %d m or the guards face them without you" % [snappedi(roundi(s.player_distance()), 10), roundi(s.away_range)])
		Settlement.RaidPhase.ACTIVE:
			lines.append("RAID UNDER WAY: %d raider%s left" % [s.raiders.size(), "" if s.raiders.size() == 1 else "s"])
		_:
			lines.append("Raiders:  none in sight")
	# The kitchen and the animals (21.5)
	if not s.kitchens().is_empty():
		var in_fridge := 0
		var fridge_meals := 0.0
		for f in s.fridges():
			for i in f.inventory.slot_count:
				var it := f.inventory.get_slot_item(i)
				if it != null and it.settler_meals > 0.0:
					in_fridge += f.inventory.get_slot_quantity(i)
					fridge_meals += it.settler_meals * f.inventory.get_slot_quantity(i)
		lines.append("Fridge:  %d dishes  (%d meals; settlers eat these first)" % [in_fridge, floori(fridge_meals)])
	var herd := s.animal_counts()
	if not herd.is_empty():
		var parts: PackedStringArray = []
		for kind in herd:
			parts.append("%d / %d %s" % [herd[kind][0], herd[kind][1], Settlement.ANIMALS[kind]["many"]])
		lines.append("Animals:  " + ",  ".join(parts))
		lines.append("Eggs:  %d   Raw Meat:  %d   Raw Hides:  %d" % [s._stores_count(Settlement.EGG), s._stores_count(Settlement.MEAT), s._stores_count(Settlement.HIDE)])
	var hurt := s.damaged_structures().size()
	if hurt > 0:
		lines.append("Repairs:  %d damaged (Builders mend them with materials from the stores)" % hurt)
	var aid := s.first_aid_stock()
	lines.append("First aid:  %d Bandage%s, %d Medkit%s in the stores%s" % [aid[0], "" if aid[0] == 1 else "s", aid[1], "" if aid[1] == 1 else "s",
		"   (put some in for the hurt)" if aid[0] + aid[1] == 0 else ""])
	var down := s.members().filter(func(m: Settler) -> bool: return m.is_down()).size()
	if down > 0:
		lines.append("Wounded:  %d down, help them up (E, a Bandage), or leave Bandages in the stores" % down)
	if s.free_beds() <= 0:
		lines.append("Newcomers:  no free bed")
	elif s.food() < s.arrival_food_needed:
		lines.append("Newcomers:  need %d+ vegetables in store" % s.arrival_food_needed)
	else:
		lines.append("Next newcomer:  in about %d min" % ceili(maxf(s.arrival_in, 0.0) * s.hour_seconds / 60.0))
	_stocks.text = "\n".join(lines)
	_how.text = _how_text(s)
	_water_bar.value = s.water / s.water_capacity * 100.0
	if s.pump_working:
		var up := s.next_pump_upgrade()
		_pump.text = "Pump: %s, %d L an hour" % [Settlement.PUMP_LEVELS[s.pump_level][0], roundi(s.pump_rate())] \
			+ ("" if up.is_empty() else ". Upgrade to a %s (%d L an hour) %s with %s." % [up[0], roundi(float(up[2])), s.pump_where, Settlement.parts_text(up[1])])
	else:
		_pump.text = "Pump: broken. Repair it %s with %s." % [s.pump_where, Settlement.pump_parts_text()]
	_pump.add_theme_color_override("font_color", GOOD if s.pump_working else BAD)
	_refresh_sites(s)
	_refresh_log(s)
	# People: rebuild the rows when who's here or what they have changes
	people.sort_custom(func(a: Settler, b: Settler) -> bool:
		return (a == focus) if (a == focus) != (b == focus) else a.settler_name < b.settler_name)
	var key := ""
	for p in people:
		key += "%s|%d|%s|%s|" % [p.get_instance_id(), p.role, p.gun.id if p.gun != null else "", str(p.armour.slots.size())]
	key += str(_spares().size()) + "|" + str(_armour_pieces().size()) + "|%d|%d" % [s.kitchens().size(), s.pens().size()]
	if key != _rows_key:
		_rows_key = key
		_build_rows(people)
	for p: Settler in _rows:
		if is_instance_valid(p):
			var row: Dictionary = _rows[p]
			_show_health(row["health"] as ProgressBar, p)
			(row["status"] as Label).text = p.status_text()
			(row["status"] as Label).add_theme_color_override("font_color", BAD if p.is_hungry() or p.short_of_water else GOOD)
			(row["gun"] as Label).text = p.gun_text() if p.role == Settler.Role.GUARD or p.gun != null else ""
			(row["armour"] as Label).text = p.armour.describe()


## How the place works, in a few lines under the stocks (23: per place).
func _how_text(s: Settlement) -> String:
	var parts: PackedStringArray = ["A settlement hour is a minute of play."]
	if not s.farm_spots().is_empty():
		parts.append("Farmers turn water into vegetables in the stores.")
	if not s.mine_spots().is_empty():
		parts.append("Miners dig Scrap Metal out of the tunnel into the stores.")
	parts.append("Everyone eats a meal every %d hours from the stores%s." % [roundi(s.meal_every_hours),
		"" if not s.farm_spots().is_empty() else ": bring food (the truck carries plenty)"])
	parts.append("Guards take guns and rounds from the Armory Locker by themselves; in a raid everyone else shelters in %s." % s.shelter_name)
	return " ".join(parts)


## A settler's health on their row: a bar and "74 / 100" (22.1).
func _show_health(bar: ProgressBar, p: Settler) -> void:
	var h := p.health
	var frac := h.get_fraction() if not p.is_dead() else 0.0
	bar.value = frac * 100.0
	var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = BAD if frac < 0.35 else (Color(0.95, 0.75, 0.3) if frac < 0.7 else GOOD)
	var text := bar.get_node("Text") as Label
	if p.is_dead():
		text.text = "Dead"
	elif p.is_down():
		text.text = "Down"
	else:
		text.text = "%d / %d" % [ceili(h.current_health), roundi(h.max_health)]
	bar.tooltip_text = "Health. Hurt settlers patch themselves up with Bandages and Medkits left in the stores"


func _build_rows(people: Array[Settler]) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	if people.is_empty():
		var nobody := _label("Nobody lives here yet. Newcomers come when there's a free bed and food; "
			+ "survivors you meet out in the world will come if you ask (they go where there's a free bed).", 15, DIM)
		nobody.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(nobody)
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
		# Health (22.1)
		var hp := ProgressBar.new()
		hp.name = "Health"
		hp.custom_minimum_size = Vector2(120, 20)
		hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hp.show_percentage = false
		hp.max_value = 100.0
		var hp_bg := StyleBoxFlat.new()
		hp_bg.bg_color = Color(0.06, 0.06, 0.055)
		hp_bg.set_corner_radius_all(3)
		hp.add_theme_stylebox_override("background", hp_bg)
		var hp_fill := StyleBoxFlat.new()
		hp_fill.bg_color = GOOD
		hp_fill.set_corner_radius_all(3)
		hp.add_theme_stylebox_override("fill", hp_fill)
		var hp_text := _label("", 13, TEXT)
		hp_text.name = "Text"
		hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
		hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hp_text.add_theme_color_override("font_outline_color", Color.BLACK)
		hp_text.add_theme_constant_override("outline_size", 4)
		hp.add_child(hp_text)
		top.add_child(hp)
		var gap := Control.new()
		gap.custom_minimum_size.x = 10
		top.add_child(gap)
		var status := _label("", 15, GOOD)
		status.name = "Status"
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(status)
		var jobs := HBoxContainer.new()
		jobs.add_theme_constant_override("separation", 6)
		col.add_child(jobs)
		for r in [Settler.Role.FARMER, Settler.Role.GUARD, Settler.Role.BUILDER, Settler.Role.WOODCUTTER, Settler.Role.MINER, Settler.Role.COOK, Settler.Role.RANCHER, Settler.Role.NONE]:
			var b := Button.new()
			b.name = "Job_%s" % Settler.ROLE_NAMES[r]
			b.text = Settler.ROLE_NAMES[r]
			b.toggle_mode = true
			b.button_pressed = p.role == r
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 13)
			var why := settlement.role_refusal_reason(r) if settlement != null else ""
			if why != "" and p.role != r:
				b.disabled = true
				b.tooltip_text = why
			b.pressed.connect(func() -> void: request_role(p, r))
			jobs.add_child(b)
		var gun := _label("", 14, DIM)
		gun.name = "Gun"
		col.add_child(gun)
		var arms := HBoxContainer.new()
		arms.add_theme_constant_override("separation", 6)
		col.add_child(arms)
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
		# Armour (22)
		var wear := HBoxContainer.new()
		wear.add_theme_constant_override("separation", 6)
		col.add_child(wear)
		var pieces := _armour_pieces()
		var give_a := MenuButton.new()
		give_a.name = "GiveArmour"
		give_a.text = "Give armour"
		give_a.flat = false
		give_a.focus_mode = Control.FOCUS_NONE
		give_a.add_theme_font_size_override("font_size", 14)
		give_a.disabled = pieces.is_empty()
		give_a.tooltip_text = "No clothing or armour in your backpack" if pieces.is_empty() else "A piece from your backpack"
		var popa := give_a.get_popup()
		for pc in pieces:
			popa.add_item((pc[1] as ItemDefinition).display_name, pc[0])
		popa.id_pressed.connect(func(index: int) -> void: request_give_armour(p, index))
		wear.add_child(give_a)
		var take_a := Button.new()
		take_a.name = "TakeArmour"
		take_a.text = "Take armour back"
		take_a.focus_mode = Control.FOCUS_NONE
		take_a.add_theme_font_size_override("font_size", 14)
		take_a.disabled = p.armour.is_empty()
		take_a.pressed.connect(func() -> void: request_take_armour(p))
		wear.add_child(take_a)
		var worn := _label("", 13, DIM)
		worn.name = "Armour"
		worn.clip_text = true
		worn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wear.add_child(worn)
		_rows[p] = {"status": status, "gun": gun, "give": give, "armour": worn, "health": hp}


func _refresh_sites(s: Settlement) -> void:
	var sites := s.sites()
	var key := ""
	for site in sites:
		key += str(site.get_instance_id()) + "|"
	if key != _sites_key:
		_sites_key = key
		for c in _sites_list.get_children():
			_sites_list.remove_child(c)
			c.queue_free()
		_site_rows.clear()
		if sites.is_empty():
			_sites_list.add_child(_label("Nothing planned.", 15, DIM))
		for site in sites:
			var row := HBoxContainer.new()
			row.name = "Site_%s" % site.name
			row.add_theme_constant_override("separation", 6)
			_sites_list.add_child(row)
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(col)
			var title := site.display_name()
			if site.plan_id == &"fence":
				title = "%s (%d m)" % [title, site.pieces.size() * 4]
			col.add_child(_label(title, 15, TEXT))
			var st := _label("", 13, DIM)
			st.name = "Status"
			st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(st)
			var off := Button.new()
			off.name = "CallOff"
			off.text = "Call off"
			off.focus_mode = Control.FOCUS_NONE
			off.add_theme_font_size_override("font_size", 13)
			off.tooltip_text = "Stop building this: what was handed over goes back in the stores"
			off.pressed.connect(func() -> void: request_cancel_site(site))
			row.add_child(off)
			_site_rows[site] = {"status": st}
	var builders := s.count_role(Settler.Role.BUILDER)
	var current := s.current_site()
	for site: ConstructionSite in _site_rows:
		if not is_instance_valid(site):
			continue
		var st: Label = _site_rows[site]["status"]
		if not site.is_supplied():
			st.text = "Needs " + SettlementPlans.cost_text(site.missing())
			st.add_theme_color_override("font_color", BAD)
		elif site == current and builders > 0:
			st.text = "Being built: %d%%" % roundi(site.progress() * 100.0)
			st.add_theme_color_override("font_color", GOOD)
		elif builders == 0:
			st.text = "Ready: make someone a Builder  (%d%%)" % roundi(site.progress() * 100.0)
			st.add_theme_color_override("font_color", STYLE_COLOR)
		else:
			st.text = "Ready, next in line  (%d%%)" % roundi(site.progress() * 100.0)
			st.add_theme_color_override("font_color", TEXT)


## The log, newest first. What happened since you last left is headed
## "While you were away" and shown first.
func _refresh_log(s: Settlement) -> void:
	var entries := s.log_entries
	var away := s.away_entries()
	var key := "%d|%d|%s" % [entries.size(), away.size(), str(entries[-1].get("hour", 0.0)) if not entries.is_empty() else ""]
	if key == _log_key:
		return
	_log_key = key
	for c in _log_list.get_children():
		_log_list.remove_child(c)
		c.queue_free()
	if entries.is_empty():
		_log_list.add_child(_label("Nothing yet.", 14, DIM))
		return
	if not away.is_empty():
		_log_list.add_child(_label("While you were away (since %s)" % Settlement.clock_text(s.left_at_hour), 14, BAD))
		for i in range(away.size() - 1, -1, -1):
			_log_list.add_child(_log_line(away[i], TEXT))
		_log_list.add_child(_label("Earlier", 14, DIM))
	var shown := 0
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if away.has(e):
			continue
		_log_list.add_child(_log_line(e, DIM))
		shown += 1
		if shown >= 12:
			break


func _log_line(e: Dictionary, color: Color) -> Label:
	var l := _label("%s   %s" % [Settlement.clock_text(float(e.get("hour", 0.0))), str(e.get("text", ""))], 13, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Clothing and armour in your backpack: [slot index, item] (22).
func _armour_pieces() -> Array:
	var out := []
	if player == null or player.inventory == null:
		return out
	for i in player.inventory.slot_count:
		var it := player.inventory.get_slot_item(i)
		if it != null and it.is_armour():
			out.append([i, it])
	return out


func request_give_armour(p: Settler, index: int) -> void:
	if settlement != null and player != null:
		settlement.request_give_armour(player, p, index)
		_rows_key = ""


func request_take_armour(p: Settler) -> void:
	if settlement != null and player != null:
		settlement.request_take_armour(player, p)
		_rows_key = ""


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


func request_cancel_site(site: ConstructionSite) -> void:
	if settlement != null and is_instance_valid(site):
		settlement.request_cancel_site(player, site)
	_sites_key = ""
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
