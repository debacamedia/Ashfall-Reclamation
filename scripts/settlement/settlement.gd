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
##     stocking the Armory Locker, which they take from themselves,
##   - raids (Increment 20): every couple of days raiders come for the
##     stores, with a warning a couple of hours ahead (a notice, a red marker
##     on the compass and map). Guards fight from their posts; everyone else
##     shelters in the farmhouse. Settlers beaten by raiders go down wounded
##     (help them up with a bandage). Raiders who get away take food and
##     planks with them; killed, they drop it.
##   - Builders put up what's planned (Increment 19.6): the settlement's own
##     fences and guard posts, laid out when you claim it, and the buildings
##     you place in build mode (B): ConstructionSites under "Sites". You
##     bring the materials (or leave them in the stores); what they build
##     (SettlementBuildings) adds beds, shelves, guard spots and fields.
##
## Time: a settlement hour is `hour_seconds` of play (a minute), a day 24.
##
## AUTHORITY: everything here runs where the game state lives (the host).
## Players change it only through the request_* methods, which validate.
##
## Built into the farm by tools/build_sites.gd. Children it uses:
##   ClaimPoint, WaterPump, FarmStore (container), Armory (container),
##   FarmSpots/*, GuardPosts/*, ArrivalPoint, Hangout, Settlers (runtime),
##   Plans/* (what's laid out when it's claimed: markers with a "plan" meta
##   and, for fences, a "to" end point), Sites (runtime ConstructionSites).

signal claimed
signal settler_arrived(settler: Settler)
## A settler left or died: their name and why.
signal settler_lost(settler_name: String, reason: String)
signal pump_repaired
## Something a player tried was refused: the reason.
signal refused(reason: String)
## Something worth a notice ("Maya is on the way to Ash Creek Farms").
signal notice(text: String)
## A building went up.
signal built(site_name: String)
## Raiders are on their way (Increment 20): from where, how many.
signal raid_warned(from_name: String, size: int)
signal raid_started
## The raid's over: {"size", "killed", "escaped", "stolen": {id: n}, "wounded": [names]}
signal raid_ended(report: Dictionary)

const SETTLER_SCENE := "res://scenes/npcs/settler.tscn"
const FOOD := &"vegetables"
const PLANK := &"wood_plank"
## Your settlements on the compass and the map.
const CLAIMED_COLOR := Color(0.45, 0.9, 0.45)
## Repairing the pump takes these from your backpack.
const PUMP_PARTS := {&"scrap_metal": 3, &"metal_pipe": 2, &"spring": 1}
## Pump upgrades (Increment 20.1), by level: 1 is the repaired pump.
## [name, parts, litres an hour, tank size]
const PUMP_LEVELS := [
	["Broken", {}, 0.0, 200.0],
	["Hand Pump", {}, 12.0, 200.0],
	["Bigger Pump", {&"metal_pipe": 4, &"spring": 2, &"scrap_metal": 6}, 24.0, 300.0],
	["Motor Pump", {&"electronics": 2, &"metal_plate": 2, &"metal_pipe": 2, &"fuel": 2}, 40.0, 400.0],
]
const RAIDER_SCENE := "res://scenes/enemies/raider.tscn"
const VETERAN_SCENE := "res://scenes/enemies/raider_veteran.tscn"
## Raids on the compass and the map.
const RAID_COLOR := Color(1.0, 0.3, 0.25)
const SITE_SCENE := "res://scenes/settlement/construction_site.tscn"
## How far from you a building can be planned (m).
const PLAN_REACH := 14.0
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

@export_group("Wood")
## Wood Planks a working Woodcutter adds to the stores each hour (19.7).
@export var woodcutter_planks_per_hour := 3.0
## Health a Builder puts back into something damaged, an hour (20.1).
@export var builder_repair_per_hour := 400.0

@export_group("Raids")
## A raid comes about this often (settlement hours), give or take a quarter.
@export var raid_every_hours := 48.0
## Warning before raiders arrive (hours).
@export var raid_warning_hours := 2.0
## What one raider can carry off: vegetables and Wood Planks.
@export var raid_carry_food := 15
@export var raid_carry_planks := 8
## A settler left down this long (hours) dies.
@export var bleed_out_hours := 12.0

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
## 0 broken, 1 repaired, 2 and 3 upgraded (PUMP_LEVELS).
var pump_level := 0
## Hours until the next newcomer may arrive.
var arrival_in := 0.0
var _food_progress := 0.0
var _plank_progress := 0.0
var _next_id := 1
var _armory_check := 0.0
## The settlement's own plan has been laid out as sites (on claiming).
var plans_laid := false

enum RaidPhase { NONE, WARNED, ACTIVE }
var raid_phase: RaidPhase = RaidPhase.NONE
## Hours until the next raid arrives (counts down; the warning comes
## `raid_warning_hours` before).
var next_raid_in := -1.0
var raid_size := 0
## Where they're coming from (global), and its name ("the east").
var raid_from := Vector3.ZERO
var raid_from_name := ""
var raiders: Array[Raider] = []
var raid_report := {}
var _raid_marker: Landmark
## Raider spawners stopped when it was claimed (restarted if a load unclaims it).
var _stopped_spawners: Array[EnemySpawner] = []

@onready var claim_point: Interactable = get_node_or_null("ClaimPoint")
@onready var pump: Interactable = get_node_or_null("WaterPump")
@onready var store: SalvageContainer = get_node_or_null("FarmStore")
@onready var armory: SalvageContainer = get_node_or_null("Armory")
@onready var settlers_root: Node3D = get_node_or_null("Settlers")
@onready var sites_root: Node3D = get_node_or_null("Sites")


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
	return total_beds() - members().size()


## Beds in the farmhouse plus every bunkhouse built here.
func total_beds() -> int:
	var n := beds
	for b in buildings():
		n += b.beds
	return n


# ---------------------------------------------------------------- buildings

## What's been built here (SettlementBuildings within the claim radius).
func buildings() -> Array[SettlementBuilding]:
	var out: Array[SettlementBuilding] = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group("settlement_buildings"):
		var b := n as SettlementBuilding
		if b != null and not b.is_queued_for_deletion() and _within(b.global_position):
			out.append(b)
	return out


func _within(p: Vector3) -> bool:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() <= claim_radius


## Where guards stand: the spots in the guard posts and towers built here,
## or, until there are any, the settlement's own patrol points.
func guard_posts() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for b in buildings():
		out.append_array(b.guard_spots())
	return out


func patrol_points() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var g := get_node_or_null("GuardPosts")
	if g != null:
		for c in g.get_children():
			if c is Node3D:
				out.append(c)
	return out


## Where Woodcutters work: the woodlot's spots (19.7).
func wood_spots() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var g := get_node_or_null("WoodSpots")
	if g != null:
		for c in g.get_children():
			if c is Node3D:
				out.append(c)
	return out


## Wood Planks in the stores.
func planks() -> int:
	var n := 0
	for st in stores():
		n += st.inventory.count_of(PLANK)
	return n


## Where farmers work: two to a field (the farm's own, then farm plots).
func farm_spots() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var g := get_node_or_null("FarmSpots")
	if g != null:
		for c in g.get_children():
			if c is Node3D:
				out.append(c)
	for b in buildings():
		out.append_array(b.farm_spots())
	return out


## The things being built here, in the order they'll be built.
func sites() -> Array[ConstructionSite]:
	var out: Array[ConstructionSite] = []
	if sites_root != null:
		for c in sites_root.get_children():
			var site := c as ConstructionSite
			if site != null and not site.is_queued_for_deletion():
				out.append(site)
	return out


## What a Builder should do now: mend something damaged (if the stores can
## pay for it, or it's already paid for), else the current site. Null for
## nothing.
func builder_job() -> Node3D:
	for s in damaged_structures():
		if s.has_meta("repair_paid") or _stores_have(s.definition.repair_cost):
			return s
	return current_site()


## Built things here that raiders have hurt, worst first (20.1).
func damaged_structures() -> Array[Structure]:
	var out: Array[Structure] = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group("structures"):
		var s := n as Structure
		if s == null or s is LevelProp or s.is_queued_for_deletion() or not s.is_damaged() or not _within(s.global_position):
			continue
		if s.definition == null or s.definition.repair_cost.is_empty():
			continue
		out.append(s)
	out.sort_custom(func(a: Structure, b: Structure) -> bool: return a.get_health_fraction() < b.get_health_fraction())
	return out


func _stores_have(cost: Dictionary) -> bool:
	for item: ItemDefinition in cost:
		var have := 0
		for st in stores():
			have += st.inventory.count_of(item.id)
		if have < int(cost[item]):
			return false
	return true


func _take_from_stores(cost: Dictionary) -> void:
	for item: ItemDefinition in cost:
		var left := int(cost[item])
		for st in stores():
			var n := mini(st.inventory.count_of(item.id), left)
			if n > 0:
				st.inventory.remove_item(item.id, n)
				left -= n


## A Builder mends `s` for `hours` (paying its repair cost from the stores
## once, when they start on it).
func repair_with_stores(s: Structure, hours: float) -> bool:
	if not s.has_meta("repair_paid"):
		if not _stores_have(s.definition.repair_cost):
			return false
		_take_from_stores(s.definition.repair_cost)
		s.set_meta("repair_paid", true)
	s.health = minf(s.health + builder_repair_per_hour * hours, s.get_max_health())
	if not s.is_damaged():
		s.remove_meta("repair_paid")
		s.repaired.emit()
	return true


## Raiders broke something settlers built: it goes back on the list (20.1).
func on_building_destroyed(b: SettlementBuilding) -> void:
	if b.definition == null or sites_root == null:
		return
	var plan := &"fence" if b.definition.id == &"farm_fence" else b.definition.id
	if not SettlementPlans.has(plan):
		return
	var pieces: Array[Transform3D] = [Transform3D.IDENTITY]
	var site := _new_site(plan, pieces, "Rebuild%d" % _next_id)
	_next_id += 1
	site.rebuild = true
	site.transform = sites_root.global_transform.affine_inverse() * b.global_transform
	sites_root.add_child.call_deferred(site)
	notice.emit("Raiders broke a %s: it's on the building list to put back" % SettlementPlans.display_name(plan).to_lower())


## The site Builders work on now: the first with all its materials.
func current_site() -> ConstructionSite:
	for site in sites():
		if site.is_supplied() and not site.is_done():
			return site
	return null


## Lays out the settlement's own plan (fences, guard posts) as sites.
func lay_out_plans() -> void:
	if plans_laid or sites_root == null:
		return
	plans_laid = true
	var plans := get_node_or_null("Plans")
	if plans == null:
		return
	var have := {}
	for site in sites():
		have[site.key] = true
	for m in plans.get_children():
		var mark := m as Node3D
		if mark == null or have.has(String(mark.name)):
			continue
		var plan := StringName(str(mark.get_meta("plan", "")))
		if not SettlementPlans.has(plan):
			continue
		var pieces: Array[Transform3D] = []
		var site_xf := mark.transform
		if mark.has_meta("to"):
			# A run of fence from the marker to "to", in 4 m lengths
			var a := mark.position
			var b: Vector3 = mark.get_meta("to")
			var along := b - a
			var n := maxi(roundi(along.length() / 4.0), 1)
			var dir := along.normalized()
			# The run's own +X points along it; each length faces +Z (out)
			site_xf = Transform3D(Basis(Vector3.UP, atan2(-dir.z, dir.x)), a)
			for i in n:
				pieces.append(Transform3D(Basis.IDENTITY, Vector3((i + 0.5) * along.length() / n, 0, 0)))
		else:
			pieces.append(Transform3D.IDENTITY)
		var site := _new_site(plan, pieces, String(mark.name))
		site.transform = sites_root.transform.affine_inverse() * site_xf
		sites_root.add_child(site)


func _new_site(plan: StringName, pieces: Array[Transform3D], key := "") -> ConstructionSite:
	var site := (load(SITE_SCENE) as PackedScene).instantiate() as ConstructionSite
	site.name = key if key != "" else "Site%d" % _next_id
	if key == "":
		_next_id += 1
	site.configure(plan, pieces, key)
	return site


func _on_site_finished(site: ConstructionSite) -> void:
	built.emit(site.display_name())
	notice.emit("The %s is built" % site.display_name().to_lower() if site.plan_id == &"fence" else "The %s at %s is built" % [site.display_name(), settlement_name])


## "" if `player` can plan a `plan` at `xform` here, otherwise why not.
func site_refusal_reason(player: PlayerController, plan: StringName, xform: Transform3D) -> String:
	if player == null or player.is_dead():
		return "Can't build now"
	if not is_claimed:
		return "Claim %s first" % settlement_name
	if not SettlementPlans.has(plan) or not SettlementPlans.PLANS[plan]["placeable"]:
		return "That can't be planned"
	var def := SettlementPlans.structure(plan)
	if def == null:
		return "That can't be planned"
	# Every corner inside the settlement
	for c in _corners(def, xform):
		if not _within(c):
			return "Too far out: build inside %s" % settlement_name
	if player.head.global_position.distance_to(xform.origin) > PLAN_REACH:
		return "Too far away"
	# Nothing in the way (buildings, props, people, other sites), on flat ground
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(def.footprint.x, minf(def.footprint.y, 2.2), def.footprint.z) - Vector3(0.06, 0.06, 0.06)
	q.shape = box
	q.transform = Transform3D(xform.basis, xform.origin + Vector3.UP * (box.size.y * 0.5 + 0.08))
	q.collision_mask = PhysicsLayers.WORLD_SOLID | PhysicsLayers.PLAYER | PhysicsLayers.NPCS | PhysicsLayers.INTERACTABLES
	q.collide_with_areas = true
	for hit in space.intersect_shape(q, 16):
		var obj := hit["collider"] as CollisionObject3D
		if obj == null or obj.collision_layer == PhysicsLayers.TERRAIN:
			continue
		if obj is ConstructionSite:
			return "Something's already planned there"
		return "Something's in the way"
	for c in _corners(def, xform) + [xform.origin]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 1.0, c + Vector3.DOWN * 1.0, PhysicsLayers.WORLD_SOLID))
		if hit.is_empty():
			return "Needs solid ground"
		if absf((hit["position"] as Vector3).y - xform.origin.y) > 0.35:
			return "The ground is too uneven"
	return ""


static func _corners(def: StructureDefinition, xform: Transform3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			out.append(xform * Vector3(def.footprint.x * sx, 0, def.footprint.z * sz))
	return out


## Plans a building at `xform` (validated): a site appears for Builders.
func request_place_site(player: PlayerController, plan: StringName, xform: Transform3D) -> ConstructionSite:
	var reason := site_refusal_reason(player, plan, xform)
	if reason != "":
		refused.emit(reason)
		return null
	var pieces: Array[Transform3D] = [Transform3D.IDENTITY]
	var site := _new_site(plan, pieces)
	site.transform = sites_root.global_transform.affine_inverse() * xform
	sites_root.add_child(site)
	notice.emit("%s planned. It needs %s; then a Builder" % [site.display_name(), SettlementPlans.cost_text(site.total_cost())])
	return site


## Hands `player`'s materials to `site` (validated).
func request_deliver(player: PlayerController, site: ConstructionSite) -> int:
	var reason := _site_reason(player, site)
	if reason == "" and site.is_supplied():
		reason = "It has everything it needs"
	if reason == "" and not site.wants_any(player.inventory):
		reason = "It needs %s" % SettlementPlans.cost_text(site.missing())
	if reason != "":
		refused.emit(reason)
		return 0
	var n := site.take_from(player.inventory)
	if site.is_supplied():
		notice.emit("The %s has everything%s" % [site.display_name(), "" if count_role(Settler.Role.BUILDER) > 0 else ": make someone a Builder (L)"])
	return n


## The player works on `site` for a moment (validated).
func request_help_build(player: PlayerController, site: ConstructionSite) -> bool:
	var reason := _site_reason(player, site)
	if reason == "" and not site.is_supplied():
		reason = "It needs %s first" % SettlementPlans.cost_text(site.missing())
	if reason != "":
		refused.emit(reason)
		return false
	site.add_work(ConstructionSite.HELP_HOURS)
	return true


## Calls off `site`: what was handed over comes back to `player` (what
## doesn't fit goes into the stores).
func request_cancel_site(player: PlayerController, site: ConstructionSite) -> bool:
	var reason := _site_reason(player, site)
	if reason != "":
		refused.emit(reason)
		return false
	for id: StringName in site.delivered:
		var item := ItemDatabase.get_item(id)
		var left := int(site.delivered[id])
		if player != null and player.inventory != null:
			left -= player.inventory.add_item(item, left)
		for st in stores():
			if left <= 0:
				break
			st.inventory.max_weight = 0.0
			left -= st.inventory.add_item(item, left)
	site.delivered.clear()
	notice.emit("The %s is called off" % site.display_name().to_lower())
	site.queue_free()
	return true


func _site_reason(player: PlayerController, site: ConstructionSite) -> String:
	if player == null or player.is_dead():
		return "Can't do that now"
	if site == null or not is_instance_valid(site) or site.is_queued_for_deletion() or site.settlement() != self:
		return "That isn't being built here"
	return ""


## Sites short of materials take them from the stores.
func _supply_sites() -> void:
	for site in sites():
		if site.is_supplied():
			continue
		for st in stores():
			site.take_from(st.inventory)
			if site.is_supplied():
				notice.emit("The %s has its materials from the stores" % site.display_name().to_lower())
				break


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
	var n := 0
	for st in stores():
		n += st.inventory.count_of(FOOD)
	return n


## Every store: the Farm Store, then storehouse shelves built here.
func stores() -> Array[SalvageContainer]:
	var out: Array[SalvageContainer] = []
	if store != null:
		out.append(store)
	for b in buildings():
		if b.storage != null:
			out.append(b.storage)
	return out


func _add_food(n: int) -> int:
	var added := 0
	for st in stores():
		if added >= n:
			break
		added += st.inventory.add_item(ItemDatabase.get_item(FOOD), n - added)
	return added


func _eat(n: int) -> void:
	var left := n
	for st in stores():
		if left <= 0:
			break
		var take := mini(st.inventory.count_of(FOOD), left)
		if take > 0:
			st.inventory.remove_item(FOOD, take)
			left -= take


## How many vegetables the store holds when full (its free space, plus what's
## in it already).
func food_capacity() -> int:
	var n := food()
	for st in stores():
		n += st.inventory.can_add(ItemDatabase.get_item(FOOD), 1 << 20)
	return n


## Water and food gained (or lost) per hour at the moment.
func rates() -> Dictionary:
	var pop := members().filter(func(s: Settler) -> bool: return s.has_arrived())
	var farmers := mini(pop.filter(func(s: Settler) -> bool: return s.is_working() and s.role == Settler.Role.FARMER).size(), farm_spots().size())
	var meals := pop.size() / meal_every_hours
	var cutters := pop.filter(func(s: Settler) -> bool: return s.is_working() and s.role == Settler.Role.WOODCUTTER).size() if not wood_spots().is_empty() else 0
	return {
		"water": pump_rate() - farmers * farmer_water_per_hour - meals * water_per_meal,
		"food": farmers * farmer_food_per_hour - meals * food_per_meal,
		"farmers": farmers,
		"planks": cutters * woodcutter_planks_per_hour,
		"woodcutters": cutters,
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
	lay_out_plans()
	_schedule_raid()
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
	pump_level = 1
	_apply_pump_look()
	pump_repaired.emit()
	notice.emit("The pump's running: %s has water" % settlement_name)
	return true


## Litres an hour into the tank now.
func pump_rate() -> float:
	if not pump_working:
		return barrel_water_per_hour
	return maxf(float(PUMP_LEVELS[clampi(maxi(pump_level, 1), 1, PUMP_LEVELS.size() - 1)][2]), pump_water_per_hour if pump_level <= 1 else 0.0)


## The next upgrade: [name, parts, rate, tank], or [] when there's none.
func next_pump_upgrade() -> Array:
	if not pump_working or pump_level + 1 >= PUMP_LEVELS.size():
		return []
	return PUMP_LEVELS[maxi(pump_level, 1) + 1]


static func parts_text(parts: Dictionary) -> String:
	var out := []
	for id: StringName in parts:
		var item := ItemDatabase.get_item(id)
		out.append("%d %s" % [parts[id], item.display_name if item != null else String(id)])
	return ", ".join(out)


func upgrade_refusal_reason(player: Node3D) -> String:
	var pc := player as PlayerController
	if pc == null or pc.is_dead():
		return "Can't do that now"
	if not pump_working:
		return "Repair the pump first"
	var up := next_pump_upgrade()
	if up.is_empty():
		return "The pump's as good as it gets"
	for id: StringName in up[1]:
		if pc.inventory == null or pc.inventory.count_of(id) < up[1][id]:
			return "Needs %s" % parts_text(up[1])
	return ""


## Fits the next upgrade with parts from `player` (validated).
func request_upgrade_pump(player: Node3D) -> bool:
	var reason := upgrade_refusal_reason(player)
	if reason != "":
		refused.emit(reason)
		return false
	var up := next_pump_upgrade()
	var pc := player as PlayerController
	for id: StringName in up[1]:
		pc.inventory.remove_item(id, up[1][id])
	pump_level = maxi(pump_level, 1) + 1
	_apply_pump_look()
	notice.emit("%s fitted: %d L of water an hour, a %d L tank" % [up[0], roundi(float(up[2])), roundi(float(up[3]))])
	return true


## The tank size and the pump head's extra parts follow the level.
func _apply_pump_look() -> void:
	var level := clampi(pump_level if pump_working else 0, 0, PUMP_LEVELS.size() - 1)
	water_capacity = maxf(float(PUMP_LEVELS[level][3]), 200.0)
	water = minf(water, water_capacity)
	var head := get_node_or_null("PumpHead")
	if head != null:
		for pair in [["Upgrade2", 2], ["Motor", 3]]:
			var n := head.get_node_or_null(pair[0]) as Node3D
			if n != null:
				n.visible = level >= int(pair[1])


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
		_supply_sites()


## Advances the settlement by `hours` (water, crops, meals, arrivals, raids).
func simulate(hours: float) -> void:
	_simulate_raids(hours)
	var here := members().filter(func(s: Settler) -> bool: return s.has_arrived())
	# Water
	water = minf(water + pump_rate() * hours, water_capacity)
	# Crops: each working farmer turns water into vegetables (one to a farm
	# spot: more farmers than the fields can take stand idle)
	var fields := farm_spots().size()
	for s: Settler in here:
		if s.role != Settler.Role.FARMER or not s.is_working():
			continue
		s.no_field = fields <= 0
		if s.no_field:
			continue
		fields -= 1
		var need := farmer_water_per_hour * hours
		if water < need:
			s.short_of_water = true
			continue
		s.short_of_water = false
		water -= need
		_food_progress += farmer_food_per_hour * hours
	while _food_progress >= 1.0 and store != null:
		if _add_food(1) < 1:
			_food_progress = 1.0  # the store's full
			break
		_food_progress -= 1.0
	# Meals
	for s: Settler in here:
		s.next_meal -= hours
		if s.next_meal > 0.0:
			continue
		if food() >= food_per_meal and water >= water_per_meal:
			_eat(food_per_meal)
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
	# Wood: each working Woodcutter cuts planks into the stores
	if not wood_spots().is_empty():
		for s: Settler in here:
			if s.role == Settler.Role.WOODCUTTER and s.is_working():
				_plank_progress += woodcutter_planks_per_hour * hours
		while _plank_progress >= 1.0:
			var added := 0
			for st in stores():
				added = st.inventory.add_item(ItemDatabase.get_item(PLANK), 1)
				if added > 0:
					break
			if added < 1:
				_plank_progress = 1.0  # the stores are full
				break
			_plank_progress -= 1.0
	# Building: each working Builder mends what's damaged, else puts their
	# hours into the current site
	for s: Settler in here:
		if s.role != Settler.Role.BUILDER or not s.is_working():
			continue
		var job := builder_job()
		if job is Structure and repair_with_stores(job as Structure, hours):
			continue
		var site := current_site()
		if site != null:
			site.add_work(hours)
	# Newcomers
	arrival_in -= hours
	if arrival_in <= 0.0:
		arrival_in = arrival_every_hours
		if free_beds() > 0 and food() >= arrival_food_needed:
			spawn_newcomer()


# ---------------------------------------------------------------- raids

func raid_active() -> bool:
	return raid_phase == RaidPhase.ACTIVE


func _schedule_raid() -> void:
	next_raid_in = raid_every_hours * randf_range(0.75, 1.25)


func _simulate_raids(hours: float) -> void:
	if not is_claimed:
		return
	if next_raid_in < 0.0:
		_schedule_raid()
	match raid_phase:
		RaidPhase.NONE:
			next_raid_in -= hours
			if next_raid_in <= raid_warning_hours:
				warn_raid()
		RaidPhase.WARNED:
			next_raid_in -= hours
			if next_raid_in <= 0.0:
				start_raid()
		RaidPhase.ACTIVE:
			raiders.assign(raiders.filter(func(r: Raider) -> bool: return is_instance_valid(r) and not r.is_dead() and r.raid == self))
			if raiders.is_empty():
				end_raid()
			elif _raid_marker != null:
				var c := Vector3.ZERO
				for r in raiders:
					c += r.global_position
				_raid_marker.global_position = c / raiders.size() + Vector3.UP * 2.0
	# The wounded: down too long, they die
	for s in members():
		if s.is_down():
			s.down_hours += hours
			if s.down_hours >= bleed_out_hours:
				notice.emit("%s died of their wounds" % s.settler_name)
				s.bleed_out()


## Raiders are seen coming: a notice and a marker, `raid_warning_hours`
## before they arrive (or `in_hours` if given).
func warn_raid(in_hours := -1.0) -> void:
	if not is_claimed or raid_phase != RaidPhase.NONE:
		return
	if in_hours >= 0.0:
		next_raid_in = in_hours
	var points := get_node_or_null("RaidPoints")
	if points == null or points.get_child_count() == 0:
		return
	var p := points.get_child(randi() % points.get_child_count()) as Node3D
	raid_from = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p.global_position)
	raid_from_name = str(p.get_meta("label", "the wilds"))
	raid_size = clampi(2 + members().size() / 2, 2, 8)
	raid_phase = RaidPhase.WARNED
	raid_report = {"size": raid_size, "killed": 0, "escaped": 0, "stolen": {}, "wounded": []}
	_make_raid_marker()
	raid_warned.emit(raid_from_name, raid_size)
	notice.emit("Raiders seen coming for %s from %s: %d of them, about %d min away" % [settlement_name, raid_from_name, raid_size, maxi(ceili(next_raid_in * hour_seconds / 60.0), 1)])


## They're here: raiders appear where they were seen and come in.
func start_raid() -> void:
	if raid_phase == RaidPhase.NONE:
		warn_raid(0.0)
	if raid_phase != RaidPhase.WARNED:
		return
	raid_phase = RaidPhase.ACTIVE
	next_raid_in = 0.0
	raiders.clear()
	var parent := get_parent().get_parent() if get_parent() != null and get_parent().get_parent() != null else get_parent()
	for i in raid_size:
		var veteran := i % 4 == 3
		var r := (load(VETERAN_SCENE if veteran else RAIDER_SCENE) as PackedScene).instantiate() as Raider
		r.name = "Raider_%s_%d" % [settlement_id, i]
		parent.add_child(r)
		var off := Vector3(cos(i * 2.4) * 2.5, 0.1, sin(i * 2.4) * 2.5)
		r.global_position = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, raid_from + off) + Vector3.UP * 0.1
		r.join_raid(self, raid_from)
		r.killed.connect(_on_raider_killed)
		raiders.append(r)
	raid_started.emit()
	notice.emit("Raiders at %s!" % settlement_name)


func _on_raider_killed(r: Raider) -> void:
	if r.raid == self or raiders.has(r):
		raid_report["killed"] = int(raid_report.get("killed", 0)) + 1


## A raider at the stores grabs what it can carry. Returns {item id: n}.
func raid_steal(_r: Raider) -> Dictionary:
	var took := {}
	for pair in [[FOOD, raid_carry_food], [PLANK, raid_carry_planks]]:
		var left: int = pair[1]
		for st in stores():
			var n := mini(st.inventory.count_of(pair[0]), left)
			if n > 0:
				st.inventory.remove_item(pair[0], n)
				left -= n
		var got: int = pair[1] - left
		if got > 0:
			took[pair[0]] = got
			var stolen: Dictionary = raid_report.get("stolen", {})
			stolen[pair[0]] = int(stolen.get(pair[0], 0)) + got
			raid_report["stolen"] = stolen
	return took


## Killed with loot: it's dropped, so it isn't lost.
func raid_recovered(items: Dictionary) -> void:
	var stolen: Dictionary = raid_report.get("stolen", {})
	for id in items:
		stolen[id] = maxi(int(stolen.get(id, 0)) - int(items[id]), 0)
	raid_report["stolen"] = stolen


func raid_escaped(r: Raider) -> void:
	raid_report["escaped"] = int(raid_report.get("escaped", 0)) + 1
	raiders.erase(r)


func on_settler_down(s: Settler) -> void:
	var w: Array = raid_report.get("wounded", [])
	if not w.has(s.settler_name):
		w.append(s.settler_name)
	raid_report["wounded"] = w
	notice.emit("%s is down, wounded: help them up (E, a Bandage)" % s.settler_name)


## Every raider dead or gone: the report.
func end_raid() -> void:
	raid_phase = RaidPhase.NONE
	raiders.clear()
	_schedule_raid()
	if _raid_marker != null:
		_raid_marker.name = "OldRaidMarker"
		_raid_marker.queue_free()
		_raid_marker = null
	raid_ended.emit(raid_report)
	notice.emit(raid_summary(raid_report))


static func raid_summary(rep: Dictionary) -> String:
	var parts: PackedStringArray = ["Raid over: %d killed" % int(rep.get("killed", 0))]
	if int(rep.get("escaped", 0)) > 0:
		parts.append("%d got away" % int(rep.get("escaped", 0)))
	var stolen: Dictionary = rep.get("stolen", {})
	var lost: PackedStringArray = []
	for id in stolen:
		if int(stolen[id]) > 0:
			var item := ItemDatabase.get_item(StringName(str(id)))
			lost.append("%d %s" % [int(stolen[id]), item.display_name if item != null else str(id)])
	if not lost.is_empty():
		parts.append("they took " + " and ".join(lost))
	var w: Array = rep.get("wounded", [])
	if not w.is_empty():
		parts.append("wounded: " + ", ".join(w))
	return ", ".join(parts)


## Where raiders head: the front of the Farm Store.
func raid_goal() -> Vector3:
	if store == null:
		return global_position
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, store.global_position + store.global_basis.z * 1.3)


## Helping a downed settler up uses a Bandage (or a Medkit) from `player`.
func request_help_up(player: PlayerController, s: Settler) -> bool:
	var reason := _member_reason(player, s)
	if reason == "" and not s.is_down():
		reason = "%s isn't hurt" % s.settler_name
	var with := &""
	if reason == "":
		for id in [&"bandage", &"medkit"]:
			if player.inventory.count_of(id) > 0:
				with = id
				break
		if with == &"":
			reason = "You need a Bandage or a Medkit to help %s up" % s.settler_name
	if reason != "":
		refused.emit(reason)
		return false
	player.inventory.remove_item(with, 1)
	s.help_up(0.5 if with == &"bandage" else 1.0)
	notice.emit("%s is back on their feet" % s.settler_name)
	return true


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
	return {"claimed": is_claimed, "water": water, "pump": pump_working, "pump_level": pump_level, "arrival_in": arrival_in,
		"food_progress": _food_progress, "next_id": _next_id, "layout": LAYOUT, "plans_laid": plans_laid, "plank_progress": _plank_progress,
		"next_raid_in": 0.0 if raid_active() else next_raid_in, "raid_warned": raid_phase != RaidPhase.NONE, "raid_from": [raid_from.x, raid_from.y, raid_from.z],
		"raid_from_name": raid_from_name, "raid_size": raid_size}


func load_state(data: Dictionary) -> void:
	is_claimed = data.get("claimed") is bool and data["claimed"]
	pump_working = data.get("pump") is bool and data["pump"]
	pump_level = clampi(int(_num(data.get("pump_level"), 1.0 if pump_working else 0.0)), 1 if pump_working else 0, PUMP_LEVELS.size() - 1) if pump_working else 0
	_apply_pump_look()  # the tank's size first, then what's in it
	water = clampf(_num(data.get("water"), 0.0), 0.0, water_capacity)
	arrival_in = _num(data.get("arrival_in"), arrival_every_hours)
	_food_progress = clampf(_num(data.get("food_progress"), 0.0), 0.0, 1.0)
	_next_id = maxi(int(_num(data.get("next_id"), 1.0)), _next_id)
	_apply_claimed_look()
	plans_laid = data.get("plans_laid") is bool and data["plans_laid"]
	_plank_progress = clampf(_num(data.get("plank_progress"), 0.0), 0.0, 1.0)
	# Raids: a raid under way when saved comes back as raiders seen close by
	next_raid_in = _num(data.get("next_raid_in"), -1.0)
	if _raid_marker != null:
		_raid_marker.name = "OldRaidMarker"
		_raid_marker.queue_free()
		_raid_marker = null
	raid_phase = RaidPhase.NONE
	raiders.clear()
	if is_claimed and data.get("raid_warned") is bool and data["raid_warned"]:
		var rf: Variant = data.get("raid_from")
		next_raid_in = clampf(next_raid_in, 0.25, raid_warning_hours)
		_restore_raid(Vector3(rf[0], rf[1], rf[2]) if rf is Array and rf.size() == 3 else global_position,
			str(data.get("raid_from_name", "")), int(_num(data.get("raid_size"), 2)))
	if is_claimed and not plans_laid:
		# Claimed before settlers could build (Increment 19): lay the plan out now
		lay_out_plans.call_deferred()
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


func _restore_raid(from: Vector3, from_name: String, size: int) -> void:
	raid_phase = RaidPhase.WARNED
	raid_from = from
	raid_from_name = from_name if from_name != "" else "the wilds"
	raid_size = clampi(size, 2, 8)
	raid_report = {"size": raid_size, "killed": 0, "escaped": 0, "stolen": {}, "wounded": []}
	_make_raid_marker()


func _make_raid_marker() -> void:
	if _raid_marker != null:
		_raid_marker.name = "OldRaidMarker"
		_raid_marker.queue_free()
	_raid_marker = Landmark.new()
	_raid_marker.name = "RaidMarker"
	_raid_marker.display_name = "Raiders"
	_raid_marker.compass_name = "Raiders"
	_raid_marker.radius = 0.0
	_raid_marker.marker_color = RAID_COLOR
	add_child(_raid_marker)
	_raid_marker.position = to_local(raid_from) + Vector3.UP * 2.0 if is_inside_tree() else raid_from


static func _num(v: Variant, fallback: float) -> float:
	return float(v) if (v is float or v is int) and is_finite(float(v)) else fallback
