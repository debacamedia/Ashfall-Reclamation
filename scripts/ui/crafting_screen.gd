class_name CraftingScreen
extends Control
## The crafting window. K opens hand crafting anywhere; using a bench (E)
## opens it with that bench's recipes too. Recipes that need a different
## bench are listed greyed out ("Needs a Workbench") so you can see what
## exists.
##
##   Click a recipe   details: ingredients you have / need, time, output
##   Craft / ×5       queue it (validated by PlayerController.request_craft)
##   Cancel           stop the queue
##   K / Tab / Esc    close (hand crafting keeps going in the background;
##                    E also closes when at a bench)
##
## Lives under the HUD: res://scenes/ui/hud.tscn → Root/%CraftingScreen.

## Set by the HUD.
var player: PlayerController:
	set(value):
		if player == value:
			return
		_unbind()
		player = value
		_bind()

var selected: RecipeDefinition

var _buttons: Dictionary = {}  # RecipeDefinition → Button
var _message_left := 0.0

@onready var _title: Label = %CraftTitle
@onready var _list: VBoxContainer = %RecipeList
@onready var _name: Label = %RecipeName
@onready var _icon: TextureRect = %RecipeIcon
@onready var _desc: Label = %RecipeDescription
@onready var _ingredients: Label = %RecipeIngredients
@onready var _info: Label = %RecipeInfo
@onready var _status: Label = %RecipeStatus
@onready var _craft: Button = %CraftButton
@onready var _craft5: Button = %Craft5Button
@onready var _cancel: Button = %CancelCraftButton
@onready var _progress: ProgressBar = %CraftProgress
@onready var _queue: Label = %CraftQueue
## Weapons bench only: Crafting / Modify Weapons tabs.
@onready var _tabs: Control = get_node_or_null("%CraftTabs")
@onready var _craft_tab: Button = get_node_or_null("%CraftTab")
@onready var _modify_tab: Button = get_node_or_null("%ModifyTab")
@onready var _body: Control = get_node_or_null("%CraftBody")
@onready var gunsmith: GunsmithPanel = get_node_or_null("%GunsmithPanel")


func _ready() -> void:
	visible = false
	_craft.pressed.connect(func() -> void: request_craft(1))
	_craft5.pressed.connect(func() -> void: request_craft(5))
	_cancel.pressed.connect(func() -> void:
		if player != null:
			player.cancel_crafting())
	if _craft_tab != null:
		_craft_tab.pressed.connect(func() -> void: show_gunsmith(false))
		_modify_tab.pressed.connect(func() -> void: show_gunsmith(true))


## Switches between the recipe list and the Modify Weapons tab.
func show_gunsmith(on: bool) -> void:
	if gunsmith == null:
		return
	var allowed := on and player != null and player.current_station != null \
		and player.current_station.station == RecipeDefinition.Station.WEAPONS_BENCH
	gunsmith.visible = allowed
	_body.visible = not allowed
	_craft_tab.button_pressed = not allowed
	_modify_tab.button_pressed = allowed
	if allowed:
		gunsmith.player = player
		gunsmith.refresh()


func is_open() -> bool:
	return visible


## Hand crafting (K) or the current bench.
func open() -> void:
	if player == null or player.is_dead() or player.current_container != null:
		return
	visible = true
	player.player_input.set_ui_open(true)
	_title.text = RecipeDefinition.station_name(player.get_crafting_station()).to_upper() if player.current_station != null else "CRAFTING"
	_build_list()
	if selected == null or not _buttons.has(selected):
		selected = _first_craftable()
	if _tabs != null:
		_tabs.visible = player.current_station != null and player.current_station.station == RecipeDefinition.Station.WEAPONS_BENCH
		show_gunsmith(false)
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	if player != null:
		player.player_input.set_ui_open(false)
		if player.current_station != null:
			player.close_station()


func request_craft(count: int) -> void:
	if player == null or selected == null:
		return
	player.request_craft(selected, count)
	_refresh()


func select(recipe: RecipeDefinition) -> void:
	selected = recipe
	_refresh()


func _input(event: InputEvent) -> void:
	if player == null:  # the HUD only ever binds its own (local) player
		return
	if not visible:
		if event.is_action_pressed("crafting") and not player.player_input.ui_open and player.current_container == null:
			open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("crafting") or event.is_action_pressed("pause") or event.is_action_pressed("inventory") \
			or (player.current_station != null and event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	if player == null or player.is_dead():
		close()
		return
	_update_progress()
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_refresh()


# ---------------------------------------------------------------- binding

func _bind() -> void:
	if player == null or not is_node_ready():
		return
	player.station_opened.connect(_on_station_opened)
	player.station_closed.connect(_on_station_closed)
	player.craft_refused.connect(_on_refused)
	player.crafting_finished.connect(func(_r: RecipeDefinition) -> void: _refresh())
	player.crafting_cancelled.connect(func(_r: RecipeDefinition) -> void: _refresh())
	player.attachment_refused.connect(func(reason: String) -> void:
		if gunsmith != null and gunsmith.visible:
			gunsmith.show_message(reason))
	if player.inventory != null:
		player.inventory.contents_changed.connect(func(_s: PackedInt32Array) -> void:
			if visible:
				_refresh()
				if gunsmith != null and gunsmith.visible:
					gunsmith.refresh())


func _unbind() -> void:
	if player == null:
		return
	if player.station_opened.is_connected(_on_station_opened):
		player.station_opened.disconnect(_on_station_opened)
		player.station_closed.disconnect(_on_station_closed)
		player.craft_refused.disconnect(_on_refused)


func _on_station_opened(_station: CraftingStation) -> void:
	if visible:
		visible = false  # reopen with the bench's recipes
	open()


func _on_station_closed(_station: CraftingStation) -> void:
	if visible:
		visible = false
		player.player_input.set_ui_open(false)


func _on_refused(reason: String) -> void:
	if not visible:
		return
	_status.text = reason
	_message_left = 2.0


# ---------------------------------------------------------------- display

func _build_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_buttons.clear()
	var here := player.get_crafting_station()
	var last_category := -1
	# Recipes you can make here first, then the ones that need another bench
	var recipes := RecipeDatabase.all_recipes()
	var available := recipes.filter(func(r: RecipeDefinition) -> bool: return r.can_make_at(here))
	var elsewhere := recipes.filter(func(r: RecipeDefinition) -> bool: return not r.can_make_at(here))
	for r: RecipeDefinition in available:
		if r.category != last_category:
			last_category = r.category
			_header(RecipeDefinition.category_name(r.category).to_upper())
		_add_button(r)
	if not elsewhere.is_empty():
		_header("AT OTHER BENCHES")
		for r: RecipeDefinition in elsewhere:
			_add_button(r)


func _header(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.7, 0.68, 0.6))
	_list.add_child(l)


func _add_button(r: RecipeDefinition) -> void:
	var b := Button.new()
	b.text = "%s  ×%d" % [r.get_display_name(), r.output_quantity] if r.output_quantity > 1 else r.get_display_name()
	b.icon = r.output.icon if r.output != null else null
	b.expand_icon = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(250, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.add_theme_constant_override("icon_max_width", 26)
	b.pressed.connect(select.bind(r))
	_list.add_child(b)
	_buttons[r] = b


func _first_craftable() -> RecipeDefinition:
	for r: RecipeDefinition in _buttons:
		if player.craft_refusal_reason(r) == "":
			return r
	return _buttons.keys()[0] if not _buttons.is_empty() else null


func _refresh() -> void:
	if player == null or not visible:
		return
	for r: RecipeDefinition in _buttons:
		var b: Button = _buttons[r]
		b.button_pressed = r == selected
		b.modulate = Color.WHITE if player.craft_refusal_reason(r) == "" else Color(1, 1, 1, 0.45)
	if selected == null:
		_name.text = "Nothing to craft"
		_ingredients.text = ""
		_info.text = ""
		_desc.text = ""
		_icon.texture = null
		_status.text = ""
		_craft.disabled = true
		_craft5.disabled = true
		_update_progress()
		return
	var r := selected
	_name.text = r.get_display_name() + ("  ×%d" % r.output_quantity if r.output_quantity > 1 else "")
	_icon.texture = r.output.icon
	_desc.text = r.output.description
	var lines := []
	for item: ItemDefinition in r.inputs:
		var have := player.inventory.count_of(item.id)
		lines.append("%s  %d / %d" % [item.display_name, have, r.inputs[item]] + ("" if have >= r.inputs[item] else "   ✗"))
	_ingredients.text = "\n".join(lines)
	_info.text = "%s  ·  %.1f s  ·  %s" % [RecipeDefinition.category_name(r.category), r.craft_time,
		"by hand or at any bench" if r.station == RecipeDefinition.Station.HAND else "at a " + RecipeDefinition.station_name(r.station)]
	var reason := player.craft_refusal_reason(r)
	if _message_left <= 0.0:
		_status.text = reason
	_craft.disabled = reason != ""
	_craft5.disabled = reason != ""
	_update_progress()


func _update_progress() -> void:
	var crafting := player.is_crafting()
	_progress.visible = crafting
	_cancel.disabled = not crafting
	if crafting:
		_progress.value = player.get_crafting_progress() * 100.0
		_queue.text = "Crafting %s  (%d left)" % [player.get_crafting_recipe().get_display_name(), player.get_crafting_count()]
	else:
		_queue.text = ""
