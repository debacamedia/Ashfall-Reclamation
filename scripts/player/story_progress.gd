class_name StoryProgress
extends Node
## Increment 34: your story so far: Story or Free Play, the orders done (The
## Last Order's Act 1, `Orders`), the order you track, the achievements
## earned (`Achievements`), and the counts both are checked against. A child
## of the player, saved with them ("story").
##
## Orders tick themselves off when the game sees them done, and anything
## already done counts: what you've done is counted from the start, and what
## the world shows (a place held, a pump mended) is looked at every half
## second. One chapter at a time; a compass marker for the order you track.
## No item rewards. In Free Play there are no orders, every chapter of the
## Field Manual is open, and the story's achievements can't be earned.

signal order_done(id: StringName)
signal chapter_done(id: StringName)
signal act_done
signal achievement_earned(id: StringName)
signal tracked_changed
## Something the story says to you (the radio at Northwatch)
signal message(text: String)

enum Mode { STORY, FREE_PLAY }

const MODE_NAMES := {Mode.STORY: "Story", Mode.FREE_PLAY: "Free Play"}
## How often the world is looked at.
const CHECK_EVERY := 0.5
## Hurt within this long, or a raider after you within FIGHT_RANGE: in a fight.
const FIGHT_WINDOW := 12.0
const FIGHT_RANGE := 35.0
const LONG_SHOT := 150.0
const TWO_PISTOLS_WINDOW := 10.0
const ROAD_TRIP := 10000.0
const FUMES_FROM_FUEL := 1000.0
const MAP_SHARE := 0.75
const HARVEST := 50
const FULL_HOUSE := 12
## Halden's water tower: its deck is 9 m up.
const TOWER_DECK := 8.0
const EARLY_PLACES := ["Outpost 17", "Halden's Crossing", "Saint Mercy Clinic", "Ash Creek Farms", "Smuggler's Gulch", "Black Ridge Mine", "Northwatch Outpost"]

var player: PlayerController
var mode: Mode = Mode.STORY
## Order id -> true
var done := {}
## The order you've picked to track (&"" = the next one)
var tracked: StringName = &""
## Achievement id -> when (unix seconds)
var earned := {}
## Counts: "searched" (paths), "kills", "kills_at" (place -> n), "veterans",
## "marauders", flags...
var stats := {}

var _check := 0.0
var _hurt_at := -INF
var _storm_at := -INF
var _storm_low := false
var _pistol_kills: Array = []  # [time, bar entry]
var _truck_last := Vector3.INF
var _fuel_was := -1.0
var _refuel_at := Vector3.INF
## Set by an old save (no "story"): what it had done is caught up quietly.
var _catch_up := false
var _marker: Landmark
## Settlements whose raids we hear about
var _heard := {}


func _ready() -> void:
	if player == null:
		player = get_parent() as PlayerController
	if player == null:
		return
	player.crafting_finished.connect(_on_crafted)
	player.container_opened.connect(_on_container)
	player.item_use_finished.connect(_on_item_used)
	player.settler_talked.connect(_on_talked)
	player.vehicle_refuelled.connect(func(t: Truck, _l: float) -> void: _refuel_at = t.global_position)
	if player.health != null:
		player.health.damaged.connect(_on_hurt)


# ---------------------------------------------------------------- what you do

## A raider died: credit the player who killed it (the shooter, or the
## truck's driver).
static func on_raider_killed(raider: Node3D, info: DamageInfo) -> void:
	if info == null or not (info.source is PlayerController):
		return
	var p := info.source as PlayerController
	if p.story != null:
		p.story._killed(raider, info)


func _killed(raider: Node3D, info: DamageInfo) -> void:
	_add(&"kills")
	var kind := str(raider.get("display_name"))
	if kind.contains("Veteran"):
		_add(&"veterans")
	if kind.contains("Marauder"):
		_add(&"marauders")
	var place := Landmark.at(get_tree(), raider.global_position)
	if place != null:
		var at: Dictionary = stats.get("kills_at", {})
		at[place.display_name] = int(at.get(place.display_name, 0)) + 1
		stats["kills_at"] = at
	earn(&"first_blood")
	if stats.get("veterans", 0) > 0:
		earn(&"old_hands")
	if stats.get("marauders", 0) > 0:
		earn(&"plate_breaker")
	if info.type == DamageInfo.Type.VEHICLE:
		earn(&"roadkill")
	elif player.global_position.distance_to(raider.global_position) > LONG_SHOT:
		earn(&"long_shot")
	# Two different pistols within ten seconds
	var gun := player.weapon
	if info.type == DamageInfo.Type.BALLISTIC and gun != null and gun.definition != null and String(gun.definition.id).contains("pistol"):
		var now := _now()
		var entry: Variant = player.weapon_slots.get("_held_entry") if player.weapon_slots != null else null
		_pistol_kills = _pistol_kills.filter(func(k: Array) -> bool: return now - float(k[0]) <= TWO_PISTOLS_WINDOW)
		for k: Array in _pistol_kills:
			if k[1] != entry:
				earn(&"two_of_a_kind")
		_pistol_kills.append([now, entry])


func _on_crafted(recipe: RecipeDefinition) -> void:
	if recipe == null or recipe.output == null:
		return
	var out := recipe.output
	if out.weapon != null and not out.weapon.melee:
		_add(&"guns_made")
		if recipe.station == RecipeDefinition.Station.WEAPONS_BENCH:
			earn(&"gunsmith")
		var here := Landmark.at(get_tree(), player.global_position)
		if here != null and here.display_name == "Outpost 17":
			earn(&"first_light")
	if out.id == &"pipe_pistol" and recipe.station == RecipeDefinition.Station.HAND:
		_flag(&"crafted_pipe_pistol")
		earn(&"pipe_dream")
	if out.category == ItemDefinition.Category.AMMO and recipe.station == RecipeDefinition.Station.WORKBENCH:
		_flag(&"crafted_rounds")
	if recipe.station == RecipeDefinition.Station.STOVE or (out.food_value > 0.0 and recipe.station != RecipeDefinition.Station.HAND):
		var cooked: Dictionary = stats.get("cooked", {})
		cooked[String(out.id)] = int(cooked.get(String(out.id), 0)) + 1
		stats["cooked"] = cooked


func _on_container(container: SalvageContainer) -> void:
	if container == null or container is DeathCache:
		return
	var seen: Dictionary = stats.get("searched", {})
	seen[str(container.get_path())] = true
	stats["searched"] = seen


func _on_item_used(item: ItemDefinition) -> void:
	if item == null:
		return
	if item.id == &"bandage":
		_flag(&"used_bandage")
	if item.id == &"medkit" and in_a_fight():
		earn(&"patched_up")
	var cooked: Dictionary = stats.get("cooked", {})
	if String(item.id).contains("stew") and int(cooked.get(String(item.id), 0)) > 0:
		earn(&"square_meal")


func _on_talked(settler: Settler) -> void:
	if settler != null:
		_met(settler.settler_name)


func _met(who: String) -> void:
	if who == "Tomas":
		_flag(&"met_tomas")
	elif who == "Old Jeb":
		_flag(&"met_jeb")


func _on_hurt(_amount: float, info: DamageInfo) -> void:
	_hurt_at = _now()
	if info != null and info.type == DamageInfo.Type.ENVIRONMENT:
		_storm_at = _now()


## Your gear chest emptied (16.6).
func got_gear_back() -> void:
	earn(&"back_for_it")


## The radio at Northwatch answered (the order, and what it says).
func answered_radio(line := "") -> void:
	_flag(&"answered_radio")
	if line != "":
		message.emit(line)


## In a fight: hurt lately, or a raider after you nearby.
func in_a_fight() -> bool:
	if _now() - _hurt_at < FIGHT_WINDOW:
		return true
	for e in get_tree().get_nodes_in_group("enemies"):
		var r := e as Raider
		if r != null and r.target == player and r.global_position.distance_to(player.global_position) < FIGHT_RANGE:
			return true
	return false


# ---------------------------------------------------------------- orders

func is_story() -> bool:
	return mode == Mode.STORY


func is_done(order_id: StringName) -> bool:
	return done.has(order_id)


## The chapter you're on (the first with something left to do), or {} once
## Act 1 is done (or in Free Play).
func current_chapter() -> Dictionary:
	if not is_story():
		return {}
	for c: Dictionary in Orders.CHAPTERS:
		for o: Dictionary in c["orders"]:
			if not done.has(o["id"]):
				return c
	return {}


func act_finished() -> bool:
	return is_story() and current_chapter().is_empty()


## The order shown on screen and marked on the compass: the one you track,
## else the first left in this chapter.
func tracked_order() -> Dictionary:
	var c := current_chapter()
	if c.is_empty():
		return {}
	if tracked != &"" and not done.has(tracked) and Orders.chapter_of(tracked) == c:
		return Orders.order(tracked)
	for o: Dictionary in c["orders"]:
		if not done.has(o["id"]):
			return o
	return {}


func track(order_id: StringName) -> void:
	var c := current_chapter()
	if c.is_empty() or Orders.chapter_of(order_id) != c or done.has(order_id):
		return
	tracked = order_id
	tracked_changed.emit()


## How far along an order with a count is: [have, need] (need 0: no count).
func progress_of(o: Dictionary) -> Array:
	var need := int(o.get("count", 0))
	if need <= 0:
		return [0, 0]
	match o["check"]:
		&"searched":
			return [mini((stats.get("searched", {}) as Dictionary).size(), need), need]
		&"kills":
			return [mini(int(stats.get("kills", 0)), need), need]
	return [0, need]


## Is `o` done, by what you've done and what the world shows?
func check(o: Dictionary) -> bool:
	var key: StringName = o["check"]
	if stats.has(String(key)) and stats[String(key)] is bool:
		return stats[String(key)]
	var need := int(o.get("count", 0))
	match key:
		&"in_barracks":
			return bool(stats.get("in_barracks", false))
		&"has_manual":
			return player.field_manual != null and player.field_manual._carried()
		&"has_weapon":
			return _carries_weapon()
		&"searched":
			return (stats.get("searched", {}) as Dictionary).size() >= need
		&"kills":
			return int(stats.get("kills", 0)) >= need
		&"visited_haldens":
			return _visited("Halden's Crossing")
		&"climbed_tower":
			return bool(stats.get("climbed_tower", false))
		&"met_tomas":
			return bool(stats.get("met_tomas", false)) or _recruited("Tomas")
		&"met_jeb":
			return bool(stats.get("met_jeb", false)) or _recruited("Old Jeb")
		&"cleared_haldens":
			return _cleared("HaldensCrossing", "Halden's Crossing")
		&"cleared_ash":
			return _claimed(&"ash_creek") or _cleared("AshCreekFarms", "Ash Creek Farms")
		&"claimed_ash":
			return _claimed(&"ash_creek")
		&"pump_fixed":
			var st := _settlement(&"ash_creek")
			return st != null and st.pump_level > 0
		&"has_farmer":
			return _has_role(&"ash_creek", Settler.Role.FARMER)
		&"armed_guard":
			return _armed_guard()
		&"farm_raided":
			return int((stats.get("raids_over", {}) as Dictionary).get("ash_creek", 0)) > 0
		&"drove_to_mine":
			return bool(stats.get("drove_to_mine", false))
		&"claimed_mine":
			return _claimed(&"black_ridge")
		&"has_miner":
			return _has_role(&"black_ridge", Settler.Role.MINER)
		&"mine_palisade":
			var st := _settlement(&"black_ridge")
			return st != null and st.is_claimed and st.defence_stage >= 2
		&"cleared_northwatch":
			return _claimed(&"northwatch") or _cleared("NorthwatchOutpost", "Northwatch Outpost")
		&"claimed_northwatch":
			return _claimed(&"northwatch")
		&"has_armorer":
			return _has_role(&"northwatch", Settler.Role.ARMORER)
		&"held_three":
			return _claimed(&"ash_creek") and _claimed(&"black_ridge") and _claimed(&"northwatch")
	return false


func _update_orders() -> void:
	var c := current_chapter()
	if c.is_empty():
		return
	var before := tracked_order()
	for o: Dictionary in c["orders"]:
		if not done.has(o["id"]) and check(o):
			done[o["id"]] = true
			if not _catch_up:
				order_done.emit(o["id"])
	if current_chapter() != c:
		if not _catch_up:
			chapter_done.emit(c["id"])
		earn(_story_achievement(c["id"]))
		if act_finished() and not _catch_up:
			act_done.emit()
		else:
			# The next chapter may be done already (anything done counts)
			_update_orders()
	if tracked_order() != before:
		tracked_changed.emit()


static func _story_achievement(chapter_id: StringName) -> StringName:
	return {&"first_light": &"first_light", &"crossing_over": &"crossing_over", &"roots": &"roots", &"deep_work": &"deep_work",
		&"northwatch": &"northwatch_stands"}.get(chapter_id, &"")


## Where the tracked order points (or INF).
func target_position() -> Vector3:
	var o := tracked_order()
	if o.is_empty() or not o.has("where"):
		return Vector3.INF
	var where := str(o["where"])
	if where.begins_with("survivor:"):
		var who := where.trim_prefix("survivor:")
		for n in get_tree().get_nodes_in_group("settlers"):
			var s := n as Settler
			if s != null and s.settler_name == who and is_instance_valid(s):
				return s.global_position
		return Vector3.INF
	var zone := _zone()
	if zone == null:
		return Vector3.INF
	var node := zone.get_node_or_null(where) as Node3D
	return node.global_position if node != null else Vector3.INF


func _update_marker() -> void:
	var at := target_position()
	if at == Vector3.INF or not is_story():
		if _marker != null:
			_marker.queue_free()
			_marker = null
		return
	if _marker == null:
		_marker = Landmark.new()
		_marker.name = "OrderMarker"
		_marker.radius = 0.0
		_marker.marker_color = Color(1.0, 0.86, 0.35)
		_marker.top_level = true
		add_child(_marker)
	var o := tracked_order()
	_marker.display_name = ""
	_marker.compass_name = "Order: %s" % o["text"]
	_marker.global_position = at


# ---------------------------------------------------------------- achievements

func has_earned(id: StringName) -> bool:
	return earned.has(id)


## Can `id` be earned in this game? (Not the story's in Free Play.)
func can_earn(id: StringName) -> bool:
	var a := Achievements.find(id)
	return not a.is_empty() and (is_story() or a["category"] != &"story")


func earn(id: StringName) -> bool:
	if id == &"" or earned.has(id) or not can_earn(id):
		return false
	earned[id] = int(Time.get_unix_time_from_system())
	if not _catch_up:
		achievement_earned.emit(id)
	return true


func _update_achievements() -> void:
	# The story's places
	if _claimed(&"ash_creek"):
		earn(&"roots")
	if _claimed(&"black_ridge"):
		earn(&"deep_work")
	if _claimed(&"northwatch"):
		earn(&"northwatch_stands")
	if _visited("Halden's Crossing"):
		earn(&"crossing_over")
	var level := get_tree().current_scene.scene_file_path if get_tree().current_scene != null else ""
	if level.contains("mid_zone"):
		_flag(&"been_beyond")
	if bool(stats.get("been_beyond", false)):
		earn(&"beyond_the_storm")
	# You
	if player.armour != null and player.armour.slots.size() >= 3:
		earn(&"dressed_for_trouble")
	if player.weapon != null and player.weapon.attachments.size() >= 3:
		earn(&"kitted_out")
	if _storm_low and _now() - _storm_at > 1.5 and not player.is_dead() and player.health.current_health < 10.0:
		earn(&"storm_chaser")
	_storm_low = _now() - _storm_at < 1.0 and player.health.current_health < 10.0
	# Places you hold
	var claimed := 0
	for n in get_tree().get_nodes_in_group("settlements"):
		var st := n as Settlement
		if st == null or not st.is_claimed:
			continue
		claimed += 1
		if st.settlement_id == &"ash_creek" and st.pump_level > 0:
			earn(&"running_water")
		if st.members().size() >= FULL_HOUSE:
			earn(&"full_house")
		for s in st.members():
			if s.role == Settler.Role.GUARD and s.gun != null:
				earn(&"armed_and_ready")
		if st.settlement_id == &"ash_creek" and st.store != null and _has_role(&"ash_creek", Settler.Role.FARMER) \
				and st.store.inventory.count_of(&"vegetables") >= HARVEST:
			earn(&"first_harvest")
		var kinds := {}
		for pen in st.pens():
			if pen.animal_count > 0:
				kinds[pen.animal_kind] = true
		if kinds.size() >= 4:
			earn(&"barnyard")
		if _reinforced(st):
			earn(&"walls_of_scrap")
	if claimed >= 3:
		earn(&"supply_line")
	# The map
	var m := player.map_knowledge
	if m != null:
		var seen := 0
		for place in EARLY_PLACES:
			if m.has_visited(place):
				seen += 1
		if seen >= EARLY_PLACES.size():
			earn(&"all_seven")
		if level.contains("early_zone") and _map_share(m) >= MAP_SHARE:
			earn(&"cartographer")
	if bool(stats.get("climbed_tower", false)):
		earn(&"high_ground")
	if float(stats.get("driven", 0.0)) >= ROAD_TRIP:
		earn(&"road_trip")


## A place's palisade all reinforced (28's last stage).
static func _reinforced(st: Settlement) -> bool:
	var plans := st.get_node_or_null("Plans")
	if plans == null:
		return false
	var want := 0
	for m in plans.get_children():
		if str(m.get_meta("plan", "")) == "reinforced_palisade":
			want += 1
	if want == 0 or st.defence_stage < 1:
		return false
	for site in st.sites():
		if site.plan_id == &"reinforced_palisade":
			return false
	var built := 0
	for b in st.buildings():
		if b.definition != null and b.definition.id == &"reinforced_palisade":
			built += 1
	return built > 0 and st._defence_markers(st.defence_stage + 1).is_empty()


var _map_total := -1


func _map_share(m: MapKnowledge) -> float:
	var b := ZoneBoundary.find_in(get_tree())
	if b == null:
		return 0.0
	if _map_total < 0:
		# Cells in the playable area, counted once
		_map_total = 0
		var zm := Zone.map_for(get_tree().current_scene.scene_file_path) if get_tree().current_scene != null else null
		var rect := zm.world_rect if zm != null else Rect2(-450, -1050, 1300, 1400)
		var x := rect.position.x
		while x < rect.end.x:
			var z := rect.position.y
			while z < rect.end.y:
				if b.is_inside(Vector3(x, 0, z)):
					_map_total += 1
				z += MapKnowledge.CELL
			x += MapKnowledge.CELL
	if _map_total <= 0:
		return 0.0
	return float(m.cells.size()) / float(_map_total)


# ---------------------------------------------------------------- each moment

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_EVERY
	for n in get_tree().get_nodes_in_group("settlements"):
		var st := n as Settlement
		if st != null and not _heard.has(st.get_instance_id()):
			_heard[st.get_instance_id()] = true
			st.raid_ended.connect(_on_raid_ended.bind(st))
	_look_around()
	if _catch_up:
		# The world's loaded by now: see how far the old game got
		_catch_up_orders()
	_update_orders()
	_update_achievements()
	_update_marker()
	if _catch_up:
		_catch_up = false


## What you're doing right now: where you stand, what you drive.
func _look_around() -> void:
	var zone := _zone()
	if zone == null:
		return
	var p := player.global_position
	var barracks := zone.get_node_or_null("Outpost17/Buildings/Barracks") as Node3D
	if barracks != null:
		var local := barracks.to_local(p)
		if absf(local.x) < 5.5 and absf(local.z) < 4.0 and local.y < 3.0:
			_flag(&"in_barracks")
	var tower := zone.get_node_or_null("HaldensCrossing/WaterTower") as Node3D
	if tower != null:
		var local := tower.to_local(p)
		if Vector2(local.x, local.z).length() < 3.5 and local.y > TOWER_DECK:
			_flag(&"climbed_tower")
	for n in get_tree().get_nodes_in_group("settlers"):
		var s := n as Settler
		if s != null and (s.settler_name == "Tomas" or s.settler_name == "Old Jeb") and s.global_position.distance_to(p) < 3.0:
			_met(s.settler_name)
	# Driving: the distance, the mine, the tank running dry
	var truck := player.vehicle
	if truck != null and is_instance_valid(truck):
		if _truck_last != Vector3.INF:
			var step := Vector2(truck.global_position.x - _truck_last.x, truck.global_position.z - _truck_last.z).length()
			if step < 50.0:
				stats["driven"] = float(stats.get("driven", 0.0)) + step
		_truck_last = truck.global_position
		var mine := zone.get_node_or_null("BlackRidgeMine") as Node3D
		if mine != null and Vector2(truck.global_position.x - mine.global_position.x, truck.global_position.z - mine.global_position.z).length() < 90.0:
			_flag(&"drove_to_mine")
		var fuel := float(truck.get("fuel"))
		if _refuel_at == Vector3.INF:
			_refuel_at = truck.global_position
		if fuel > _fuel_was + 0.01 and _fuel_was >= 0.0:
			_refuel_at = truck.global_position
		if fuel <= 0.0 and _fuel_was > 0.0 and truck.global_position.distance_to(_refuel_at) > FUMES_FROM_FUEL:
			earn(&"running_on_fumes")
		_fuel_was = fuel
	else:
		_truck_last = Vector3.INF


# ---------------------------------------------------------------- the world

func _zone() -> Node:
	var z := Zone.of(player)
	if z != null:
		return z
	var n: Node = player
	while n != null and n.get_parent() != get_tree().root:
		n = n.get_parent()
	return n


func _settlement(id: StringName) -> Settlement:
	return Settlement.find(get_tree(), id)


func _claimed(id: StringName) -> bool:
	var st := _settlement(id)
	return st != null and st.is_claimed


func _has_role(id: StringName, role: Settler.Role) -> bool:
	var st := _settlement(id)
	if st == null or not st.is_claimed:
		return false
	for s in st.members():
		if s.role == role:
			return true
	return false


func _armed_guard() -> bool:
	for n in get_tree().get_nodes_in_group("settlements"):
		var st := n as Settlement
		if st != null and st.is_claimed:
			for s in st.members():
				if s.role == Settler.Role.GUARD and s.gun != null:
					return true
	return false


func _visited(place: String) -> bool:
	return player.map_knowledge != null and player.map_knowledge.has_visited(place)


func _recruited(who: String) -> bool:
	for n in get_tree().get_nodes_in_group("settlements"):
		var st := n as Settlement
		if st != null:
			for s in st.members():
				if s.settler_name == who:
					return true
	return false


## Have you killed as many raiders at `place` as it keeps there (its
## spawners' numbers)?
func _cleared(site_path: String, place: String) -> bool:
	var zone := _zone()
	var site := zone.get_node_or_null(site_path) if zone != null else null
	if site == null:
		return false
	var keeps := 0
	for sp in site.find_children("*", "EnemySpawner", true, false):
		keeps += (sp as EnemySpawner).max_alive
	if keeps == 0:
		return false
	return int((stats.get("kills_at", {}) as Dictionary).get(place, 0)) >= keeps


func _carries_weapon() -> bool:
	for inv: InventoryComponent in [player.quick_bar, player.inventory]:
		if inv == null:
			continue
		for i in inv.slot_count:
			var it := inv.get_slot_item(i)
			if it != null and it.weapon != null:
				return true
	return false


## A raid at `settlement_id` is over (for "See the farm through its first
## raid" and "Held the Line").
func raid_over(settlement_id: StringName, report: Dictionary) -> void:
	var raids: Dictionary = stats.get("raids_over", {})
	raids[String(settlement_id)] = int(raids.get(String(settlement_id), 0)) + 1
	stats["raids_over"] = raids
	var wounded: Array = report.get("wounded", [])
	var stolen: Dictionary = report.get("stolen", {}) if report.get("stolen") is Dictionary else {}
	if wounded.is_empty() and stolen.is_empty() and int(report.get("killed", 0)) > 0:
		earn(&"held_the_line")


func _on_raid_ended(report: Dictionary, st: Settlement) -> void:
	raid_over(st.settlement_id, report)


func _add(key: StringName, by := 1) -> void:
	stats[String(key)] = int(stats.get(String(key), 0)) + by


func _flag(key: StringName) -> void:
	stats[String(key)] = true


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------------------------------------------------------------- new games and saves

## A new game in `new_mode`. Story: you wake in the barracks, and the Field
## Manual waits in Sgt. Vance's footlocker. Free Play: every chapter of the
## manual is open, and it's on your quick bar.
func begin(new_mode: Mode) -> void:
	mode = new_mode
	done.clear()
	earned.clear()
	stats.clear()
	tracked = &""
	var zone := _zone()
	if mode == Mode.FREE_PLAY:
		if player.field_manual != null:
			player.field_manual.open_all()
		return
	if zone == null:
		return
	var bed := zone.get_node_or_null("Outpost17/Settlement/Shelter") as Node3D
	if bed != null:
		player.global_position = bed.global_position + Vector3(0, 0.05, 0)
		player.rotation.y = 0.0
	var locker := zone.get_node_or_null("Outpost17/SalvageContainers/VanceFootlocker") as SalvageContainer
	if locker != null:
		var manual := ItemDatabase.get_item(&"field_manual")
		var moved := false
		for inv: InventoryComponent in [player.quick_bar, player.inventory]:
			if moved or inv == null:
				continue
			for i in inv.slot_count:
				var it := inv.get_slot_item(i)
				if it != null and it.id == &"field_manual":
					inv.take_from_slot(i, 1)
					moved = true
					break
		locker.search()
		locker.inventory.add_item(manual, 1)


func save_state() -> Dictionary:
	var e := {}
	for k: StringName in earned:
		e[String(k)] = earned[k]
	return {"mode": "free_play" if mode == Mode.FREE_PLAY else "story", "done": done.keys().map(func(k: StringName) -> String: return String(k)),
		"tracked": String(tracked), "earned": e, "stats": stats.duplicate(true)}


func load_state(data: Variant) -> void:
	done.clear()
	earned.clear()
	stats.clear()
	tracked = &""
	if not data is Dictionary:
		# A game from before orders: it carries on in Story, with Act 1 done
		# as far as it's got (the chapters before the furthest it shows any
		# sign of are counted done), and achievements it shows caught up
		# quietly.
		mode = Mode.STORY
		_catch_up = true
		return
	var d: Dictionary = data
	mode = Mode.FREE_PLAY if str(d.get("mode", "story")) == "free_play" else Mode.STORY
	for k in (d.get("done", []) as Array if d.get("done") is Array else []):
		if Orders.all_ids().has(StringName(str(k))):
			done[StringName(str(k))] = true
	tracked = StringName(str(d.get("tracked", "")))
	if d.get("earned") is Dictionary:
		for k in d["earned"]:
			if not Achievements.find(StringName(str(k))).is_empty():
				earned[StringName(str(k))] = int(d["earned"][k])
	if d.get("stats") is Dictionary:
		stats = (d["stats"] as Dictionary).duplicate(true)


func _catch_up_orders() -> void:
	# You woke long ago
	done[&"wake"] = true
	var furthest := -1
	for i in Orders.CHAPTERS.size():
		for o: Dictionary in Orders.CHAPTERS[i]["orders"]:
			if _shows(o):
				furthest = i
	for i in Orders.CHAPTERS.size():
		for o: Dictionary in Orders.CHAPTERS[i]["orders"]:
			if i < furthest or (i == furthest and _shows(o)):
				done[o["id"]] = true


## Does the world show `o` done (for a game from before orders)? Only what
## can be seen: places held, pumps, jobs, what you carry.
func _shows(o: Dictionary) -> bool:
	match o["check"]:
		&"claimed_ash", &"cleared_ash", &"pump_fixed", &"has_farmer", &"armed_guard", &"claimed_mine", &"has_miner", \
				&"mine_palisade", &"claimed_northwatch", &"cleared_northwatch", &"has_armorer", &"held_three":
			return check(o)
	return false
