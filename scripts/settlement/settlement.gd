class_name Settlement
extends Node3D
## A place you've claimed and people live in (Increment 19). Ash Creek Farms
## is the first.
##
## Clear its raiders, then claim it at the notice board (ClaimPoint). Once
## it's yours:
##   - the pump (WaterPump, repaired with parts) fills the water tank,
##   - farmers turn water into Fresh Vegetables in the Farm Store,
##   - everyone eats and drinks from those stocks (a meal every few hours;
##     with nothing to eat they stop working, and in time they leave),
##   - newcomers walk in when there's a free bed and spare food, and the
##     survivors you meet elsewhere can be sent here,
##   - guards patrol and shoot raiders; arm them from your backpack or by
##     stocking the Armory Locker, which they take from themselves.
##
## Time: a settlement hour is `hour_seconds` of play (a minute), a day 24.
##
## AUTHORITY: everything here runs where the game state lives (the host).
## Players change it only through the request_* methods, which validate.
##
## Built into the farm by tools/build_sites.gd. Children it uses:
##   ClaimPoint, WaterPump, FarmStore (container), Armory (container),
##   FarmSpots/*, GuardPosts/*, ArrivalPoint, Hangout, Settlers (runtime).

signal claimed
signal settler_arrived(settler: Settler)
## A settler left or died: their name and why.
signal settler_lost(settler_name: String, reason: String)
signal pump_repaired
## Something a player tried was refused: the reason.
signal refused(reason: String)
## Something worth a notice ("Maya is on the way to Ash Creek Farms").
signal notice(text: String)

const SETTLER_SCENE := "res://scenes/npcs/settler.tscn"
const FOOD := &"vegetables"
## Your settlements on the compass and the map.
const CLAIMED_COLOR := Color(0.45, 0.9, 0.45)
## Repairing the pump takes these from your backpack.
const PUMP_PARTS := {&"scrap_metal": 3, &"metal_pipe": 2, &"spring": 1}
const NAMES := ["Ada", "Ben", "Cora", "Dale", "Edie", "Finn", "Greta", "Hank", "Iris", "Joel", "Kit", "Lena",
	"Milo", "Nora", "Otis", "Pearl", "Quinn", "Rosa", "Sam", "Tess", "Vic", "Wade", "Yara", "Zeke"]

@export var settlement_name := "Ash Creek Farms"
## The Landmark (place) this settlement is.
@export var place_name := "Ash Creek Farms"
@export var settlement_id: StringName = &"ash_creek"
## Raiders within this far of the board stop you claiming it (m).
@export var claim_radius := 75.0
## Guards defend within this far of the board (m).
@export var defend_radius := 90.0

@export_group("Time")
## Seconds of play in one settlement hour.
@export var hour_seconds := 60.0

@export_group("Housing")
@export var beds := 4
## A newcomer may turn up this often (hours), if there's room and food.
@export var arrival_every_hours := 3.0
## …and the first one this soon after you claim it.
@export var first_arrival_hours := 1.0
## Vegetables in the store before a newcomer will come.
@export var arrival_food_needed := 4

@export_group("Water and food")
@export var water_capacity := 200.0
## Litres an hour from the repaired pump, and from the rain barrel before.
@export var pump_water_per_hour := 12.0
@export var barrel_water_per_hour := 1.0
## A working farmer, each hour: water used, vegetables grown.
@export var farmer_water_per_hour := 2.0
@export var farmer_food_per_hour := 1.5
## Everyone eats a meal this often (hours): vegetables and water per meal.
@export var meal_every_hours := 4.0
@export var food_per_meal := 1
@export var water_per_meal := 2.0
## Unfed this long (hours), a settler stops working…
@export var hungry_after_hours := 1.0
## …and this long, they leave.
@export var leave_after_hours := 8.0
## What the farm has when you claim it.
@export var starting_food := 6
@export var starting_water := 20.0

var is_claimed := false
var water := 0.0
var pump_working := false
## Hours until the next newcomer may arrive.
var arrival_in := 0.0
var _food_progress := 0.0
var _next_id := 1
var _armory_check := 0.0
## Raider spawners stopped when it was claimed (restarted if a load unclaims it).
var _stopped_spawners: Array[EnemySpawner] = []

@onready var claim_point: Interactable = get_node_or_null("ClaimPoint")
@onready var pump: Interactable = get_node_or_null("WaterPump")
@onready var store: SalvageContainer = get_node_or_null("FarmStore")
@onready var armory: SalvageContainer = get_node_or_null("Armory")
@onready var settlers_root: Node3D = get_node_or_null("Settlers")


func _ready() -> void:
	add_to_group("settlements")
	add_to_group("persist")
	for c in [store, armory]:
		if c != null:
			c.is_searched = true  # nothing hidden in them: just open
			c.call("_update_prompt")
	_apply_claimed_look()


## The settlement with this id in `tree`, or null.
static func find(tree: SceneTree, id: StringName) -> Settlement:
	for n in tree.get_nodes_in_group("settlements"):
		if (n as Settlement).settlement_id == id:
			return n
	return null


# ---------------------------------------------------------------- people

## Everyone who lives here (or is on their way), alive.
func members() -> Array[Settler]:
	var out: Array[Settler] = []
	for n in get_tree().get_nodes_in_group("settlers"):
		var s := n as Settler
		if s != null and s.settlement == self and not s.is_dead():
			out.append(s)
	return out


func free_beds() -> int:
	return beds - members().size()


func count_role(role: Settler.Role) -> int:
	return members().filter(func(s: Settler) -> bool: return s.role == role).size()


## Raiders alive within claim_radius of the board.
func raiders_here() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		var r := e as Node3D
		if r != null and r.has_method("is_dead") and not r.call("is_dead") \
				and Vector2(r.global_position.x - global_position.x, r.global_position.z - global_position.z).length() <= claim_radius:
			n += 1
	return n


# ---------------------------------------------------------------- stocks

func food() -> int:
	return store.inventory.count_of(FOOD) if store != null else 0


## How many vegetables the store holds when full (its free space, plus what's
## in it already).
func food_capacity() -> int:
	if store == null:
		return 0
	return food() + store.inventory.can_add(ItemDatabase.get_item(FOOD), 1 << 20)


## Water and food gained (or lost) per hour at the moment.
func rates() -> Dictionary:
	var pop := members().filter(func(s: Settler) -> bool: return s.has_arrived())
	var farmers := pop.filter(func(s: Settler) -> bool: return s.is_working() and s.role == Settler.Role.FARMER).size()
	var meals := pop.size() / meal_every_hours
	return {
		"water": (pump_water_per_hour if pump_working else barrel_water_per_hour) - farmers * farmer_water_per_hour - meals * water_per_meal,
		"food": farmers * farmer_food_per_hour - meals * food_per_meal,
		"farmers": farmers,
	}


# ---------------------------------------------------------------- claiming

func claim_refusal_reason(player: Node3D) -> String:
	if is_claimed:
		return "%s is already yours" % settlement_name
	if player is PlayerController and (player as PlayerController).is_dead():
		return "Can't do that now"
	var n := raiders_here()
	if n > 0:
		return "Raiders are still here (%d left): clear the farm first" % n
	return ""


## Claims it for the players (validated). The farm's raiders stop coming.
func request_claim(player: Node3D) -> bool:
	var reason := claim_refusal_reason(player)
	if reason != "":
		refused.emit(reason)
		return false
	is_claimed = true
	water = starting_water
	arrival_in = first_arrival_hours
	if store != null and store.inventory.count_of(FOOD) < starting_food:
		store.inventory.add_item(ItemDatabase.get_item(FOOD), starting_food - store.inventory.count_of(FOOD))
	_apply_claimed_look()
	claimed.emit()
	notice.emit("%s is yours. Settlers will come when there's food and a bed (L: settlement)" % settlement_name)
	return true


## Raiders stop spawning here; the place shows as yours on the compass.
## (A save from before you claimed it puts it back as it was.)
func _apply_claimed_look() -> void:
	if not is_inside_tree():
		return
	var site := get_parent()
	for n in site.find_children("*", "Node", true, false):
		if n is EnemySpawner:
			var sp := n as EnemySpawner
			if is_claimed and sp.enabled:
				sp.enabled = false
				_stopped_spawners.append(sp)
				for e in sp.get_alive():
					e.queue_free()
			elif not is_claimed and _stopped_spawners.has(sp):
				sp.enabled = true
				_stopped_spawners.erase(sp)
	for n in get_tree().get_nodes_in_group("landmarks"):
		var l := n as Landmark
		if l != null and l.display_name == place_name:
			l.marker_color = CLAIMED_COLOR if is_claimed else Color(0.95, 0.75, 0.35)


# ---------------------------------------------------------------- the pump

func pump_refusal_reason(player: Node3D) -> String:
	var pc := player as PlayerController
	if pc == null or pc.is_dead():
		return "Can't do that now"
	if not is_claimed:
		return "Claim the farm first"
	if pump_working:
		return "The pump's working"
	for id: StringName in PUMP_PARTS:
		if pc.inventory == null or pc.inventory.count_of(id) < PUMP_PARTS[id]:
			return "Needs %s" % pump_parts_text()
	return ""


static func pump_parts_text() -> String:
	var parts := []
	for id: StringName in PUMP_PARTS:
		var item := ItemDatabase.get_item(id)
		parts.append("%d %s" % [PUMP_PARTS[id], item.display_name if item != null else String(id)])
	return ", ".join(parts)


func request_repair_pump(player: Node3D) -> bool:
	var reason := pump_refusal_reason(player)
	if reason != "":
		refused.emit(reason)
		return false
	var pc := player as PlayerController
	for id: StringName in PUMP_PARTS:
		pc.inventory.remove_item(id, PUMP_PARTS[id])
	pump_working = true
	pump_repaired.emit()
	notice.emit("The pump's running: %s has water" % settlement_name)
	return true


# ---------------------------------------------------------------- jobs and guns

func _member_reason(player: Node3D, s: Settler) -> String:
	if player is PlayerController and (player as PlayerController).is_dead():
		return "Can't do that now"
	if s == null or not is_instance_valid(s) or s.is_dead() or s.settlement != self:
		return "They don't live here"
	return ""


func request_set_role(player: Node3D, s: Settler, role: Settler.Role) -> bool:
	var reason := _member_reason(player, s)
	if reason != "":
		refused.emit(reason)
		return false
	s.set_role(role)
	return true


## Gives `s` the spare gun in `player`'s backpack slot `index`. Their old gun
## (and its rounds) come back to you, or go in the armory if you're full.
func request_give_gun(player: PlayerController, s: Settler, index: int) -> bool:
	var reason := _member_reason(player, s)
	var item := player.inventory.get_slot_item(index) if reason == "" and player.inventory != null else null
	if reason == "" and (item == null or item.weapon == null or item.weapon.melee):
		reason = "That's not a gun"
	if reason != "":
		refused.emit(reason)
		return false
	player.inventory.take_from_slot(index, 1)
	_return_gun(s, player)
	s.arm(item, 0)
	# Rounds for it from your backpack, if you have them
	give_ammo_from(player.inventory, s, Settler.AMMO_TARGET)
	notice.emit("%s has your %s (%d rounds)" % [s.settler_name, item.display_name, s.ammo])
	return true


func request_give_ammo(player: PlayerController, s: Settler) -> bool:
	var reason := _member_reason(player, s)
	if reason == "" and s.gun == null:
		reason = "%s has no gun" % s.settler_name
	if reason == "" and give_ammo_from(player.inventory, s, Settler.AMMO_TARGET) <= 0:
		reason = "No %s to give" % _ammo_name(s)
	if reason != "":
		refused.emit(reason)
		return false
	notice.emit("%s has %d rounds" % [s.settler_name, s.ammo])
	return true


func request_take_gun(player: PlayerController, s: Settler) -> bool:
	var reason := _member_reason(player, s)
	if reason == "" and s.gun == null:
		reason = "%s has no gun" % s.settler_name
	if reason != "":
		refused.emit(reason)
		return false
	_return_gun(s, player)
	return true


## Moves up to `target` - (what they have) rounds of `s`'s ammo from `from`.
func give_ammo_from(from: InventoryComponent, s: Settler, target: int) -> int:
	if from == null or s.gun == null:
		return 0
	var ammo_item := ItemDatabase.find_ammo_item(s.gun.weapon.ammo_type)
	if ammo_item == null:
		return 0
	var n := mini(maxi(target - s.ammo, 0), from.count_of(ammo_item.id))
	if n > 0:
		from.remove_item(ammo_item.id, n)
		s.ammo += n
	return n


func _ammo_name(s: Settler) -> String:
	var a := ItemDatabase.find_ammo_item(s.gun.weapon.ammo_type) if s.gun != null else null
	return a.display_name if a != null else "ammo"


## Takes `s`'s gun and rounds back: to `player` if they have room, else
## into the armory.
func _return_gun(s: Settler, player: PlayerController) -> void:
	if s.gun == null:
		return
	var item := s.gun
	var rounds := s.ammo
	s.disarm()
	var ammo_item := ItemDatabase.find_ammo_item(item.weapon.ammo_type)
	for inv in [player.inventory if player != null else null, armory.inventory if armory != null else null]:
		if inv != null and item != null and inv.can_add(item, 1) >= 1:
			inv.add_item(item, 1)
			item = null
	if item != null and armory != null:
		armory.inventory.max_weight = 0.0
		armory.inventory.add_item(item, 1)
	if ammo_item != null and rounds > 0:
		var left := rounds
		if player != null and player.inventory != null:
			left -= player.inventory.add_item(ammo_item, left)
		if left > 0 and armory != null:
			armory.inventory.add_item(ammo_item, left)


## Unarmed guards, or ones low on rounds, help themselves from the armory.
func _supply_guards() -> void:
	if armory == null:
		return
	var inv := armory.inventory
	for s in members():
		if s.role != Settler.Role.GUARD or not s.has_arrived():
			continue
		if s.gun == null:
			var best: ItemDefinition = null
			var best_index := -1
			for i in inv.slot_count:
				var it := inv.get_slot_item(i)
				if it != null and it.weapon != null and not it.weapon.melee and (best == null or it.weapon.tier > best.weapon.tier):
					best = it
					best_index = i
			if best != null:
				inv.take_from_slot(best_index, 1)
				s.arm(best, 0)
				notice.emit("%s took a %s from the armory" % [s.settler_name, best.display_name])
		if s.gun != null and s.ammo < Settler.AMMO_TARGET / 2:
			give_ammo_from(inv, s, Settler.AMMO_TARGET)


# ---------------------------------------------------------------- recruiting

## Why survivor `s` can't come and live here ("" = they can).
func recruit_refusal_reason(s: Settler) -> String:
	if not is_claimed:
		var line := s.greeting if s.greeting != "" else "Find somewhere safe for us to live, and I'll come."
		return "%s: \"%s\"  (Claim a settlement first)" % [s.settler_name, line]
	if free_beds() <= 0:
		return "%s: \"%s has no bed for me yet.\"" % [s.settler_name, settlement_name]
	return ""


func request_recruit(player: Node3D, s: Settler) -> bool:
	var reason := "Can't do that now" if player is PlayerController and (player as PlayerController).is_dead() else ""
	if reason == "" and (s == null or s.settlement != null or s.is_dead()):
		reason = "They're already settled"
	if reason == "":
		reason = recruit_refusal_reason(s)
	if reason != "":
		refused.emit(reason)
		return false
	s.join(self)
	notice.emit("%s is on the way to %s" % [s.settler_name, settlement_name])
	return true


## A newcomer walks in at the arrival point.
func spawn_newcomer() -> Settler:
	var scene := load(SETTLER_SCENE) as PackedScene
	var s := scene.instantiate() as Settler
	s.name = "Settler%d" % _next_id
	_next_id += 1
	s.settler_name = _free_name()
	s.look_seed = randi()
	s.spawned = true
	var at := get_node_or_null("ArrivalPoint") as Node3D
	settlers_root.add_child(s)
	s.global_position = (at.global_position if at != null else global_position) + Vector3.UP * 0.1
	s.join(self)
	return s


func _free_name() -> String:
	var used := {}
	for n in get_tree().get_nodes_in_group("settlers"):
		used[(n as Settler).settler_name] = true
	var free := NAMES.filter(func(n: String) -> bool: return not used.has(n))
	return free[randi() % free.size()] if not free.is_empty() else "Drifter %d" % _next_id


## Called by a settler when they reach the farm.
func on_arrived(s: Settler) -> void:
	settler_arrived.emit(s)
	notice.emit("%s has arrived at %s. Give them a job (L)" % [s.settler_name, settlement_name])


# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	if not is_claimed:
		return
	simulate(delta / hour_seconds)
	_armory_check -= delta
	if _armory_check <= 0.0:
		_armory_check = 2.0
		_supply_guards()


## Advances the settlement by `hours` (water, crops, meals, arrivals).
func simulate(hours: float) -> void:
	var here := members().filter(func(s: Settler) -> bool: return s.has_arrived())
	# Water
	water = minf(water + (pump_water_per_hour if pump_working else barrel_water_per_hour) * hours, water_capacity)
	# Crops: each working farmer turns water into vegetables
	for s: Settler in here:
		if s.role != Settler.Role.FARMER or not s.is_working():
			continue
		var need := farmer_water_per_hour * hours
		if water < need:
			s.short_of_water = true
			continue
		s.short_of_water = false
		water -= need
		_food_progress += farmer_food_per_hour * hours
	while _food_progress >= 1.0 and store != null:
		if store.inventory.add_item(ItemDatabase.get_item(FOOD), 1) < 1:
			_food_progress = 1.0  # the store's full
			break
		_food_progress -= 1.0
	# Meals
	for s: Settler in here:
		s.next_meal -= hours
		if s.next_meal > 0.0:
			continue
		if food() >= food_per_meal and water >= water_per_meal:
			store.inventory.remove_item(FOOD, food_per_meal)
			water -= water_per_meal
			s.next_meal += meal_every_hours
			s.unfed_hours = 0.0
		else:
			s.next_meal = 0.0
			s.unfed_hours += hours
			if s.unfed_hours >= leave_after_hours:
				var why := "nothing to eat" if food() < food_per_meal else "no water"
				settler_lost.emit(s.settler_name, why)
				notice.emit("%s has left %s: %s" % [s.settler_name, settlement_name, why])
				s.leave()
	# Newcomers
	arrival_in -= hours
	if arrival_in <= 0.0:
		arrival_in = arrival_every_hours
		if free_beds() > 0 and food() >= arrival_food_needed:
			spawn_newcomer()


## Called by a settler that died here.
func on_settler_died(s: Settler) -> void:
	settler_lost.emit(s.settler_name, "killed")
	notice.emit("%s was killed" % s.settler_name)


# ---------------------------------------------------------------- saving

## Which layout of the place a save was made with. Ash Creek was laid out
## again in 19.5 (layout 2): settlers saved standing round the old layout are
## brought to the new one when it loads.
const LAYOUT := 2


func save_state() -> Dictionary:
	return {"claimed": is_claimed, "water": water, "pump": pump_working, "arrival_in": arrival_in,
		"food_progress": _food_progress, "next_id": _next_id, "layout": LAYOUT}


func load_state(data: Dictionary) -> void:
	is_claimed = data.get("claimed") is bool and data["claimed"]
	water = clampf(_num(data.get("water"), 0.0), 0.0, water_capacity)
	pump_working = data.get("pump") is bool and data["pump"]
	arrival_in = _num(data.get("arrival_in"), arrival_every_hours)
	_food_progress = clampf(_num(data.get("food_progress"), 0.0), 0.0, 1.0)
	_next_id = maxi(int(_num(data.get("next_id"), 1.0)), _next_id)
	_apply_claimed_look()
	if int(_num(data.get("layout"), 1.0)) < LAYOUT:
		_resettle.call_deferred()


## After loading a save made with an older layout: everyone who'd arrived
## gathers at the Hangout (they were standing where the old buildings were).
func _resettle() -> void:
	var h := get_node_or_null("Hangout") as Node3D
	if h == null or not is_inside_tree():
		return
	var i := 0
	for s in members():
		if s.has_arrived():
			s.global_position = h.global_position + Vector3((i % 3 - 1) * 1.2, 0.1, (i / 3) * 1.2)
			s.velocity = Vector3.ZERO
			i += 1


static func _num(v: Variant, fallback: float) -> float:
	return float(v) if (v is float or v is int) and is_finite(float(v)) else fallback
