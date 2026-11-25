class_name FieldManualProgress
extends Node
## What a player has of the Field Manual (Increment 33): which chapters are
## open, which tips they've been shown, the page they were on, and the book
## itself (on the quick bar in a new game).
##
## Chapters 1-4 are open from the start; 5-7 open the first time you need
## them (build mode, claiming a place, the map or the truck). The story opens
## them too, later. A game saved before the manual existed has them all.
##
## The first time you do something a chapter covers, a tip says where to
## read about it ("Field Manual · Building, p. 18"), once. N opens the
## manual at the last tip's page for a few seconds after.
##
## A child of the player, made by PlayerController.

signal chapter_opened(id: StringName)
signal tip(id: StringName)

const ITEM_PATH := "res://resources/items/field_manual.tres"
## The bar slot it goes on in a new game (0-based: slot 8).
const BAR_SLOT := 7
## How long after a tip N opens at its page (seconds).
const TIP_WINDOW := 12.0

var player: PlayerController
## Chapter ids you can read.
var opened: Array[StringName] = []
## Chapter ids you've had a tip for.
var tipped: Array[StringName] = []
## The chapter you were reading.
var page: StringName = &"staying_alive"
## Whether you've been given the book (a new game, or an old save loaded).
var given := false

var _tip_left := 0.0
var _tip_id: StringName = &""
var _poll := 0.0


func _init() -> void:
	name = "FieldManual"
	for c: Dictionary in FieldManualText.CHAPTERS:
		if c["open"]:
			opened.append(c["id"])


static func item() -> ItemDefinition:
	return load(ITEM_PATH) as ItemDefinition


func is_open(id: StringName) -> bool:
	return opened.has(id)


## Opens chapter `id` (quietly if `quiet`); a tip points to it.
func open_chapter(id: StringName, quiet := false) -> void:
	if FieldManualText.chapter(id).is_empty() or opened.has(id):
		return
	opened.append(id)
	chapter_opened.emit(id)
	if not quiet:
		note(id)


func open_all() -> void:
	for id in FieldManualText.ids():
		open_chapter(id, true)


## You've just done something chapter `id` covers: a tip, the first time.
func note(id: StringName) -> void:
	if not opened.has(id) or tipped.has(id):
		return
	tipped.append(id)
	_tip_id = id
	_tip_left = TIP_WINDOW
	tip.emit(id)


## The chapter N should open at: the last tip's, just after it, else the
## page you were on.
func page_to_open() -> StringName:
	return _tip_id if _tip_left > 0.0 and opened.has(_tip_id) else (page if opened.has(page) else opened[0])


## Read it: N used the tip.
func used_tip() -> void:
	_tip_left = 0.0


## Puts the book on the bar (slot 8, else the first empty slot, else the
## backpack). Once a game.
func give_book() -> void:
	given = true
	if player == null or player.quick_bar == null or _carried():
		return
	var book := item()
	var bar := player.quick_bar
	var at := BAR_SLOT if bar.is_slot_empty(BAR_SLOT) else bar.first_empty()
	if at >= 0:
		bar.add_to_slot(at, book, 1, {}, true)
	elif player.inventory != null:
		player.inventory.add_item(book, 1)  # (and if there's no room, N still opens it)


func _carried() -> bool:
	return player.inventory != null and player.inventory.count_of(item().id) > 0


func _physics_process(delta: float) -> void:
	_tip_left = maxf(_tip_left - delta, 0.0)
	_poll -= delta
	if _poll > 0.0 or player == null or player.is_dead():
		return
	_poll = 0.25
	# The first time you need a chapter
	if player.player_input != null and player.player_input.build_mode:
		open_chapter(&"building")
	if player.is_driving():
		open_chapter(&"getting_around")
	for s in get_tree().get_nodes_in_group("settlements"):
		if s is Settlement and (s as Settlement).is_claimed:
			open_chapter(&"settlements")
			open_chapter(&"building")
			break
	# Tips for the first four
	if player.hunger != null and player.hunger.stage != PlayerHunger.Stage.FED:
		note(&"staying_alive")
	if player.health != null and player.health.current_health < player.health.max_health * 0.75:
		note(&"staying_alive")
	if player.current_container != null:
		note(&"scavenging")
	if player.weapon != null and not player.weapon.definition.melee:
		note(&"guns_and_fighting")


## Something the HUD saw you do: the map open (`&"map"`) or the crafting
## screen (`&"crafting"`).
func saw(what: StringName) -> void:
	match what:
		&"map":
			open_chapter(&"getting_around")
		&"crafting":
			note(&"making_things")
		&"settlement_screen":
			note(&"settlements")


func save_state() -> Dictionary:
	return {"opened": opened.map(func(i: StringName) -> String: return String(i)),
		"tipped": tipped.map(func(i: StringName) -> String: return String(i)),
		"page": String(page), "given": given}


func load_state(data: Variant) -> void:
	if not data is Dictionary:
		# A game from before the manual: you're past the basics, so it's all
		# open, and the book's handed over
		open_all()
		tipped = FieldManualText.ids()
		give_book()
		return
	var d := data as Dictionary
	var known := FieldManualText.ids()
	opened.clear()
	for c: Dictionary in FieldManualText.CHAPTERS:
		if c["open"]:
			opened.append(c["id"])
	for raw in d.get("opened", []):
		var id := StringName(str(raw))
		if known.has(id) and not opened.has(id):
			opened.append(id)
	tipped.clear()
	for raw in d.get("tipped", []):
		var id := StringName(str(raw))
		if known.has(id) and not tipped.has(id):
			tipped.append(id)
	var p := StringName(str(d.get("page", "staying_alive")))
	page = p if known.has(p) else &"staying_alive"
	given = bool(d.get("given", true))
	if not given:
		give_book()
