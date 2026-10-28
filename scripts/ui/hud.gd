class_name HUD
extends CanvasLayer
## In-game overlay: health bar, damage feedback (red flash, low-health pulse,
## direction arcs), death screen with respawn countdown, dynamic crosshair
## with hit markers, weapon and ammo readout, interaction prompt with hold
## progress, pickup notices, carried resources, UI sounds, debug readout (F3),
## and the compass strip with the zone's landmarks (CompassBar).
##
## Scene: res://scenes/ui/hud.tscn

## Set in the Inspector (or by the level) to the local player.
@export var player: PlayerController
## The level's GameMode, for the respawn countdown and cause of death.
@export var game_mode: GameMode
## The interface size in use (see UiScale).
var ui_scale := UiScale.DEFAULT
var _wanted_ui_scale := UiScale.DEFAULT
## Health fraction below which the screen edges pulse red.
@export var low_health_threshold := 0.3

@onready var _debug_label: Label = %DebugLabel
@onready var _crosshair: Crosshair = %Crosshair
@onready var _ammo_label: Label = %AmmoLabel
@onready var _weapon_label: Label = %WeaponLabel
@onready var _health_label: Label = %HealthLabel
@onready var _health_fill: ColorRect = %HealthFill
@onready var _health_trail: ColorRect = %HealthTrail
@onready var _damage_vignette: TextureRect = %DamageVignette
@onready var _damage_indicator: DamageIndicator = %DamageIndicator
@onready var _death_screen: Control = %DeathScreen
@onready var _death_cause: Label = %DeathCause
@onready var _respawn_prompt: Label = %RespawnPrompt
@onready var _prompt_label: Label = %PromptLabel
@onready var _build_panel: Control = get_node_or_null("%BuildPanel")
@onready var _build_title: Label = get_node_or_null("%BuildTitle")
@onready var _build_status: Label = get_node_or_null("%BuildStatus")
@onready var _prompt_reason: Label = %PromptReason
@onready var _hold_bar: ProgressBar = %HoldBar
@onready var _notices: VBoxContainer = %Notices
@onready var _quick_slot: Label = %QuickSlotLabel
@onready var _use_label: Label = %UseLabel
@onready var _use_bar: ProgressBar = %UseBar
@onready var inventory_screen: InventoryScreen = %InventoryScreen
@onready var container_screen: ContainerScreen = get_node_or_null("%ContainerScreen")
@onready var _weapon_strip: Label = get_node_or_null("%WeaponStrip")
@onready var crafting_screen: CraftingScreen = get_node_or_null("%CraftingScreen")
@onready var _hint: Label = get_node_or_null("%HintLabel")
@onready var _scope: Control = get_node_or_null("%ScopeOverlay")
@onready var _ui_sound: AudioStreamPlayer = %UISound

const SOUND_HIT := preload("res://assets/ashfall_pack_v3/audio/ui_hitmarker.wav")
const SOUND_KILL := preload("res://assets/ashfall_pack_v3/audio/ui_kill_confirm.wav")
const SOUND_DENIED := preload("res://assets/ashfall_pack_v3/audio/ui_denied.wav")

var _weapon: HitscanWeapon
var _health: HealthComponent
var _interactor: PlayerInteractor
var _inventory: PlayerInventory
var _player_signals_bound: PlayerController = null
var _flash := 0.0
var _pulse_time := 0.0
var _trail_fraction := 1.0
var _bar_width := 0.0
## The compass strip (built in code).
var compass: CompassBar
## The map window, M (built in code, Increment 17).
var map_screen: MapScreen


func _ready() -> void:
	_bar_width = _health_fill.size.x
	# Interface size (Increment 16.7): saved, and re-fitted when the window changes
	_wanted_ui_scale = UiScale.saved()
	ui_scale = UiScale.apply(get_window(), _wanted_ui_scale)
	get_window().size_changed.connect(_refit_ui_scale)
	# Notices ("No room in your backpack") show over the inventory and other windows
	_notices.z_index = 5
	compass = CompassBar.new()
	compass.name = "Compass"
	add_child(compass)
	map_screen = MapScreen.new()
	add_child(map_screen)
	_death_screen.visible = false
	_damage_vignette.modulate.a = 0.0
	var saves := get_node_or_null("/root/SaveManager")
	if saves != null:
		saves.saved.connect(func(_path: String) -> void: show_notice("Game saved", Color(0.7, 0.95, 0.7)))
		saves.loaded.connect(func(_path: String) -> void: show_notice("Game loaded", Color(0.7, 0.95, 0.7)))
		saves.failed.connect(func(reason: String) -> void:
			show_notice(reason, Color(1.0, 0.5, 0.4))
			_play_ui(SOUND_DENIED))
	var world := get_node_or_null("/root/WorldManager")
	if world != null:
		world.arrived.connect(func(region: String) -> void: show_notice("Arrived at " + region, Color(0.95, 0.85, 0.6)))
		world.travel_refused.connect(func(reason: String) -> void:
			show_notice(reason, Color(1.0, 0.5, 0.4))
			_play_ui(SOUND_DENIED))


func _process(delta: float) -> void:
	compass.player = player
	map_screen.player = player
	if player == null:
		return
	if player.weapon != _weapon:
		_bind_weapon(player.weapon)
	if player.health != _health:
		_bind_health(player.health)
		_damage_indicator.player = player
	if player.interactor != _interactor:
		_bind_interactor(player.interactor)
	if player.inventory != _inventory:
		_bind_inventory(player.inventory)
	_update_build_panel()
	if _player_signals_bound != player:
		_player_signals_bound = player
		player.item_use_refused.connect(func(_r: String) -> void: _play_ui(SOUND_DENIED))
		player.transfer_refused.connect(func(_r: String) -> void: _play_ui(SOUND_DENIED))
		player.weapon_picked_up.connect(func(def: WeaponDefinition) -> void:
			show_notice("%s  →  slot %d" % [def.display_name, def.slot], Color(0.75, 0.9, 1.0)))
		player.gun_stowed.connect(func(def: WeaponDefinition) -> void:
			show_notice("%s  →  backpack (spare)" % def.display_name, Color(0.75, 0.9, 1.0)))
		player.gun_equipped.connect(func(def: WeaponDefinition) -> void:
			show_notice("%s  →  slot %d (unloaded: reload)" % [def.display_name, def.slot], Color(0.75, 0.9, 1.0)))
		player.pack_changed.connect(func(pack: ItemDefinition) -> void:
			show_notice("Wearing your %s: %.0f kg, %d slots" % [pack.display_name if pack != null else "satchel",
				PlayerInventory.weight_for(pack), PlayerInventory.slots_for(pack)], Color(0.75, 0.9, 1.0)))
		player.pack_refused.connect(func(reason: String) -> void:
			show_notice(reason, Color(1.0, 0.5, 0.4))
			_play_ui(SOUND_DENIED))
		player.gun_refused.connect(func(reason: String) -> void:
			show_notice(reason, Color(1.0, 0.5, 0.4))
			_play_ui(SOUND_DENIED))
		player.structure_placed.connect(func(st: Structure) -> void:
			show_notice("Built " + st.definition.display_name, Color(0.8, 0.95, 0.7)))
		player.structure_repaired.connect(func(st: Structure) -> void:
			show_notice("Repaired " + st.definition.display_name, Color(0.8, 0.95, 0.7)))
		player.structure_dismantled.connect(func(def: StructureDefinition) -> void:
			show_notice(("Scrapped " if def.is_level_prop else "Dismantled ") + def.display_name, Color(0.8, 0.95, 0.7)))
		player.structure_moved.connect(func(st: Structure) -> void:
			show_notice("Moved " + st.definition.display_name, Color(0.8, 0.95, 0.7)))
		player.build_refused.connect(func(reason: String) -> void:
			show_notice(reason, Color(1.0, 0.5, 0.4))
			_play_ui(SOUND_DENIED))
		inventory_screen.player = player
		if container_screen != null:
			container_screen.player = player
		if crafting_screen != null:
			crafting_screen.player = player
		player.craft_refused.connect(func(_r: String) -> void: _play_ui(SOUND_DENIED))
		player.place_discovered.connect(func(place: String) -> void:
			# Not for the place you start in: you haven't gone anywhere yet
			if player.map_knowledge.places.size() > 1:
				show_notice("%s is on your map  (M)" % place, Color(0.95, 0.85, 0.6)))
		player.pin_refused.connect(func(reason: String) -> void:
			show_notice(reason, Color(1.0, 0.5, 0.4))
			_play_ui(SOUND_DENIED))
		player.attachment_refused.connect(func(_r: String) -> void: _play_ui(SOUND_DENIED))
	_update_prompt()
	_update_item_use()
	_update_notices(delta)

	if _weapon != null:
		_crosshair.spread_degrees = _weapon.get_current_spread_degrees()
		_crosshair.camera_fov = player.camera.fov
		_crosshair.reticle_alpha = 1.0 - smoothstep(0.15, 0.6, player.aim_amount)
		if _weapon.is_reloading:
			if _weapon.definition.reload_per_round:
				_ammo_label.text = "LOADING  %d / %d" % [_weapon.ammo_in_magazine, _weapon.definition.magazine_size]
			else:
				_ammo_label.text = "RELOADING  %d%%" % roundi(_weapon.get_reload_progress() * 100.0)
		if _scope != null:
			_scope.visible = _weapon.definition.scope_overlay and player.aim_amount >= 0.95 and not player.is_dead()
	_update_weapon_strip()
	# Full-screen windows (inventory, container, crafting) hide the corner readouts
	var window_open := is_window_open()
	compass.get_node("PlaceBanner").visible = not window_open
	# The map covers the top of the screen, where the compass is
	compass.modulate.a = 0.0 if map_screen.visible else 1.0
	for c: CanvasItem in [_weapon_strip, _quick_slot, _weapon_label, _ammo_label]:
		if c != null:
			c.modulate.a = 0.0 if window_open else 1.0
	# …and the last two notices move down under the window, clear of its buttons
	_notices.offset_top = -86.0 if window_open else -316.0
	_notices.offset_bottom = -10.0 if window_open else -126.0
	var count := _notices.get_child_count()
	for i in count:
		(_notices.get_child(i) as CanvasItem).visible = not window_open or i >= count - 2
	_update_hint()

	_update_health_visuals(delta)
	_update_death_screen()

	if _debug_label.visible:
		_debug_label.text = "%s\n%.1f m/s\npos %s\nHP %.1f\n%d fps (%.1f ms a frame)\n%d objects, %d draw calls, %dk triangles" % [
			player.get_state_name(),
			player.get_horizontal_speed(),
			player.global_position.snappedf(0.1),
			player.health.current_health,
			Engine.get_frames_per_second(),
			1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
		]


## A full-screen window is open: inventory, container, crafting or the map.
func is_window_open() -> bool:
	return inventory_screen.visible or (container_screen != null and container_screen.visible) \
		or (crafting_screen != null and crafting_screen.visible) or (map_screen != null and map_screen.visible)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_label.visible = not _debug_label.visible
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and (k.ctrl_pressed or k.meta_pressed):
		match k.physical_keycode:
			KEY_EQUAL, KEY_KP_ADD:
				set_ui_scale(ui_scale + UiScale.STEP)
			KEY_MINUS, KEY_KP_SUBTRACT:
				set_ui_scale(ui_scale - UiScale.STEP)
			KEY_0, KEY_KP_0:
				set_ui_scale(UiScale.DEFAULT)
			_:
				return
		get_viewport().set_input_as_handled()


## A resized window keeps the size you chose, as far as it fits.
func _refit_ui_scale() -> void:
	var fitted := clampf(_wanted_ui_scale, UiScale.MIN, UiScale.largest_for(Vector2(get_window().size)))
	ui_scale = fitted
	if not is_equal_approx(get_window().content_scale_factor, fitted):
		get_window().content_scale_factor = fitted


## Sets, saves and announces the interface size (clamped to what fits).
func set_ui_scale(value: float) -> void:
	_wanted_ui_scale = clampf(snappedf(value, 0.01), UiScale.MIN, UiScale.largest_for(Vector2(get_window().size)))
	ui_scale = _wanted_ui_scale
	UiScale.apply(get_window(), _wanted_ui_scale)
	UiScale.save(ui_scale)
	show_notice("Interface size %d%%" % roundi(ui_scale * 100.0), Color(0.85, 0.9, 1.0))


# ---------------------------------------------------------------- health

func _bind_health(health: HealthComponent) -> void:
	if _health != null:
		_health.health_changed.disconnect(_on_health_changed)
		_health.damaged.disconnect(_on_damaged)
	_health = health
	if health == null:
		return
	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(_on_damaged)
	_trail_fraction = health.get_fraction()
	_on_health_changed(health.current_health, health.max_health)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_label.text = "%d" % ceili(current)
	var fraction := current / maximum if maximum > 0.0 else 0.0
	_health_fill.size.x = _bar_width * fraction
	_health_fill.color = Color(0.85, 0.2, 0.15) if fraction <= low_health_threshold else Color(0.85, 0.85, 0.8)


func _on_damaged(amount: float, info: DamageInfo) -> void:
	_flash = clampf(_flash + amount / 40.0, 0.25, 0.8)
	var direction := Vector3.ZERO
	if info.source is Node3D and is_instance_valid(info.source):
		direction = (info.source as Node3D).global_position - player.global_position
	elif info.direction != Vector3.ZERO and info.type != DamageInfo.Type.FALL:
		direction = -info.direction
	if direction != Vector3.ZERO:
		_damage_indicator.add_hit(direction)


func _update_health_visuals(delta: float) -> void:
	if _health == null:
		return
	# Damage flash plus a slow pulse while health is low
	_flash = move_toward(_flash, 0.0, delta * 1.2)
	var fraction := _health.get_fraction()
	var pulse := 0.0
	if fraction <= low_health_threshold and not _health.is_dead():
		_pulse_time += delta
		pulse = (0.25 + 0.15 * sin(_pulse_time * 4.0)) * (1.0 - fraction / low_health_threshold * 0.5)
	_damage_vignette.modulate.a = clampf(maxf(_flash, pulse), 0.0, 1.0)
	# The pale "trail" shows recent damage, catching up after a moment
	_trail_fraction = move_toward(_trail_fraction, fraction, delta * 0.6) if _trail_fraction > fraction else fraction
	_health_trail.size.x = _bar_width * _trail_fraction


func _update_death_screen() -> void:
	var dead := player.is_dead()
	_death_screen.visible = dead
	_crosshair.visible = not dead
	if not dead:
		return
	var left := game_mode.get_respawn_time_left(player) if game_mode != null else 0.0
	_death_cause.text = game_mode.get_death_cause(player) if game_mode != null else ""
	_respawn_prompt.text = "Respawn in %d" % ceili(left) if left > 0.0 else "Press SPACE to respawn"
	if game_mode != null and game_mode.get_dropped_gear(player) != null:
		_respawn_prompt.text += "\n\nYour gear is where you fell: follow \"Your gear\" on the compass"


# ---------------------------------------------------------------- weapon

func _bind_weapon(weapon: HitscanWeapon) -> void:
	if _weapon != null:
		_weapon.ammo_changed.disconnect(_on_ammo_changed)
		_weapon.hit_confirmed.disconnect(_on_hit_confirmed)
	_weapon = weapon
	_ammo_label.visible = weapon != null
	_weapon_label.visible = weapon != null
	if weapon == null:
		return
	weapon.ammo_changed.connect(_on_ammo_changed)
	weapon.hit_confirmed.connect(_on_hit_confirmed)
	_weapon_label.text = weapon.definition.display_name.to_upper()
	_on_ammo_changed(weapon.ammo_in_magazine, weapon.reserve_ammo)


func _on_ammo_changed(in_magazine: int, reserve: int) -> void:
	if _weapon != null and _weapon.definition.melee:
		_ammo_label.text = "—"
		_ammo_label.modulate = Color.WHITE
		return
	_ammo_label.text = "%d / %d" % [in_magazine, reserve]
	_ammo_label.modulate = Color(1.0, 0.4, 0.3) if in_magazine == 0 else Color.WHITE


func _on_hit_confirmed(_target: Node, _damage: float, killed: bool, zone_multiplier: float) -> void:
	_crosshair.show_hit_marker(killed, zone_multiplier > 1.0)
	_play_ui(SOUND_KILL if killed else SOUND_HIT)


# ---------------------------------------------------------------- interaction

func _bind_interactor(interactor: PlayerInteractor) -> void:
	if _interactor != null:
		_interactor.interaction_refused.disconnect(_on_interaction_refused)
	_interactor = interactor
	if interactor != null:
		interactor.interaction_refused.connect(_on_interaction_refused)


func _update_prompt() -> void:
	var target := _interactor.focused if _interactor != null else null
	if target == null or not is_instance_valid(target) or player.is_dead() or player.current_container != null \
			or (crafting_screen != null and crafting_screen.visible) or map_screen.visible:
		_prompt_label.visible = false
		_prompt_reason.visible = false
		_hold_bar.visible = false
		return
	_prompt_label.visible = true
	var key := "Hold E" if target.hold_time > 0.0 else "E"
	_prompt_label.text = "[%s]  %s" % [key, target.get_prompt(player)]
	var reason := target.get_block_reason(player)
	_prompt_reason.visible = reason != ""
	_prompt_reason.text = reason
	_prompt_label.modulate = Color(1, 1, 1, 0.5) if reason != "" else Color.WHITE
	_hold_bar.visible = _interactor.hold_progress >= 0.0
	_hold_bar.value = maxf(_interactor.hold_progress, 0.0) * 100.0


func _on_interaction_refused(_target: Interactable, _reason: String) -> void:
	_play_ui(SOUND_DENIED)


# ---------------------------------------------------------------- inventory

func _bind_inventory(inventory: PlayerInventory) -> void:
	if _inventory != null:
		_inventory.item_received.disconnect(_on_item_received)
		_inventory.contents_changed.disconnect(_on_inventory_changed)
	_inventory = inventory
	if inventory != null:
		inventory.item_received.connect(_on_item_received)
		inventory.contents_changed.connect(_on_inventory_changed)
	_on_inventory_changed(PackedInt32Array())


func _on_inventory_changed(_slots: PackedInt32Array) -> void:
	var medkits := _inventory.count_medical() if _inventory != null else 0
	_quick_slot.text = "[H]  MEDKIT ×%d" % medkits
	_quick_slot.modulate = Color.WHITE if medkits > 0 else Color(1, 1, 1, 0.35)


func _update_item_use() -> void:
	var progress := player.get_item_use_progress()
	if progress >= 0.0:
		_use_bar.visible = true
		_use_label.visible = true
		_use_bar.value = progress * 100.0
		_use_label.text = "Using %s…  (fire or sprint to cancel)" % player.get_item_in_use().display_name
		return
	# Hand crafting carries on with the menu closed: show it here
	var crafting := player.is_crafting() and not (crafting_screen != null and crafting_screen.visible)
	_use_bar.visible = crafting
	_use_label.visible = crafting
	if crafting:
		_use_bar.value = player.get_crafting_progress() * 100.0
		_use_label.text = "Crafting %s  (%d left)" % [player.get_crafting_recipe().get_display_name(), player.get_crafting_count()]


func _on_item_received(item: ItemDefinition, quantity: int) -> void:
	show_notice("+%d %s" % [quantity, item.display_name])


## Short message in the notice column (right side), fading after 2.5 s.
func show_notice(text: String, color := Color(0.95, 0.85, 0.55)) -> void:
	var notice := Label.new()
	notice.text = text
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	notice.add_theme_font_size_override("font_size", 20)
	notice.add_theme_constant_override("outline_size", 5)
	notice.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	notice.add_theme_color_override("font_color", color)
	notice.set_meta("time_left", 2.5)
	_notices.add_child(notice)
	while _notices.get_child_count() > 5:
		_notices.get_child(0).free()


func _update_notices(delta: float) -> void:
	for notice in _notices.get_children():
		var left: float = notice.get_meta("time_left") - delta
		notice.set_meta("time_left", left)
		notice.modulate.a = clampf(left / 0.6, 0.0, 1.0)
		if left <= 0.0:
			notice.queue_free()


func _play_ui(stream: AudioStream) -> void:
	_ui_sound.stream = stream
	_ui_sound.play()


## "1 RIFLE   2 PISTOL   3 —   4 —" with the gun in hand in brackets.
func _update_weapon_strip() -> void:
	if _weapon_strip == null:
		return
	var slots := player.weapon_slots
	if slots == null:
		_weapon_strip.text = ""
		return
	var parts := []
	var shown := slots.pending_slot if slots.pending_slot != 0 else slots.current_slot
	for s in range(1, WeaponSlots.SLOT_COUNT + 1):
		var w := slots.get_weapon(s)
		var label := "%d %s" % [s, w.definition.short_name if w != null else "—"]
		parts.append("[%s]" % label if s == shown else label)
	_weapon_strip.text = "   ".join(parts)


## Build mode (B): what's selected and what's possible where you look.
func _update_build_panel() -> void:
	if _build_panel == null:
		return
	var bm := player.get_node_or_null("%BuildMode") as BuildMode
	var on := bm != null and bm.active
	_build_panel.visible = on
	if not on:
		return
	_build_title.text = bm.title_text()
	_build_status.text = bm.status_text()
	var ok := bm.target != null or bm.ghost_valid
	_build_status.add_theme_color_override("font_color", Color(0.85, 0.95, 0.8) if ok else Color(1.0, 0.55, 0.45))


## First-minutes guidance: until you own a gun, tell the player how to make one.
func _update_hint() -> void:
	if _hint == null:
		return
	var has_gun := false
	if player.weapon_slots != null:
		for w in player.weapon_slots.owned():
			if not w.definition.melee:
				has_gun = true
	var window_open := is_window_open()
	_hint.visible = not has_gun and not player.is_dead() and not window_open
	if _hint.visible:
		var wood := player.inventory.count_of(&"wood") if player.inventory != null else 0
		_hint.text = ("You only have a machete.  Press K and craft a Pipe Pistol." if wood > 0
			else "You only have a machete.  Break down a pallet (hold E) for wood, then press K to craft a Pipe Pistol.")
