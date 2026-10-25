class_name GunsmithPanel
extends HBoxContainer
## "Modify Weapons" tab of the crafting screen at a weapons bench: pick one of
## your guns, see its stats, fit attachments you carry and take them off.
## Every change goes through PlayerController.request_fit_attachment /
## request_remove_attachment (validated: weapons bench, compatible, room).
##
## Lives in the crafting screen: HUD/Root/%CraftingScreen/…/%GunsmithPanel.

var player: PlayerController
var selected_slot := 0

@onready var _guns: VBoxContainer = %GunList
@onready var _title: Label = %GunTitle
@onready var _stats: Label = %GunStats
@onready var _slots: VBoxContainer = %AttachmentSlots
@onready var _status: Label = %GunStatus

var _message_left := 0.0


func _process(delta: float) -> void:
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_status.text = ""


func show_message(text: String) -> void:
	_status.text = text
	_message_left = 2.5


func refresh() -> void:
	if player == null or player.weapon_slots == null:
		return
	for c in _guns.get_children():
		_guns.remove_child(c)
		c.queue_free()
	var guns: Array[HitscanWeapon] = player.weapon_slots.owned().filter(func(w: HitscanWeapon) -> bool: return not w.definition.melee)
	if guns.is_empty():
		_title.text = "No guns yet"
		_stats.text = "Craft a gun first, then fit attachments here."
		_clear_slots()
		return
	if player.weapon_slots.get_weapon(selected_slot) == null or player.weapon_slots.get_weapon(selected_slot).definition.melee:
		selected_slot = guns[0].base_definition.slot
	for w in guns:
		var b := Button.new()
		b.text = "%d  %s" % [w.base_definition.slot, w.base_definition.display_name]
		var item := ItemDatabase.find_weapon_item(w.base_definition.id)
		if item != null:
			b.icon = item.icon
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 34)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(250, 40)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = w.base_definition.slot == selected_slot
		b.pressed.connect(func() -> void:
			selected_slot = w.base_definition.slot
			refresh())
		_guns.add_child(b)
	_show_gun(player.weapon_slots.get_weapon(selected_slot))


func _clear_slots() -> void:
	for c in _slots.get_children():
		_slots.remove_child(c)
		c.queue_free()


func _show_gun(w: HitscanWeapon) -> void:
	var d := w.definition
	_title.text = d.display_name
	_stats.text = "Damage %d%s  ·  Magazine %d  ·  Zoom %.1f×%s\nRecoil %.2f°  ·  Heard at %d m  ·  Aimed spread %.2f°" % [
		roundi(d.damage), (" ×%d" % d.pellets) if d.pellets > 1 else "", d.magazine_size, d.ads_zoom,
		"  (scope)" if d.scope_overlay else "", d.recoil_pitch, roundi(d.noise_radius), d.base_spread * d.ads_spread_multiplier]
	_clear_slots()
	for slot in [AttachmentDefinition.Slot.OPTIC, AttachmentDefinition.Slot.MUZZLE, AttachmentDefinition.Slot.MAGAZINE, AttachmentDefinition.Slot.UNDERBARREL]:
		var fitting := _carried_for(w, slot)
		var fitted := w.get_attachment(slot)
		if fitted == null and fitting.is_empty() and not _any_exists_for(w, slot):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.custom_minimum_size = Vector2(250, 0)
		label.text = "%s:  %s" % [AttachmentDefinition.slot_name(slot), fitted.display_name if fitted != null else "—"]
		label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6) if fitted != null else Color(0.65, 0.63, 0.58))
		row.add_child(label)
		if fitted != null:
			row.add_child(_button("Remove", func() -> void:
				if not player.request_remove_attachment(w.base_definition.slot, slot):
					pass
				refresh()))
		for item: ItemDefinition in fitting:
			if fitted != null and item.attachment == fitted:
				continue
			row.add_child(_button("Fit " + item.display_name, func() -> void:
				player.request_fit_attachment(w.base_definition.slot, item)
				refresh()))
		_slots.add_child(row)
	if _slots.get_child_count() == 0:
		var none := Label.new()
		none.text = "No attachments fit this gun."
		_slots.add_child(none)


## Attachment items you carry that fit this gun in this slot.
func _carried_for(w: HitscanWeapon, slot: AttachmentDefinition.Slot) -> Array[ItemDefinition]:
	var out: Array[ItemDefinition] = []
	for i in player.inventory.slot_count:
		var item := player.inventory.get_slot_item(i)
		if item != null and item.attachment != null and item.attachment.slot == slot \
				and item.attachment.fits(w.base_definition.id) and not out.has(item):
			out.append(item)
	return out


## Whether any attachment in the game fits this gun in this slot (so the row
## is shown even when you have nothing for it yet).
func _any_exists_for(w: HitscanWeapon, slot: AttachmentDefinition.Slot) -> bool:
	for item in ItemDatabase.all_items():
		if item.attachment != null and item.attachment.slot == slot and item.attachment.fits(w.base_definition.id):
			return true
	return false


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 32)
	b.pressed.connect(action)
	return b
