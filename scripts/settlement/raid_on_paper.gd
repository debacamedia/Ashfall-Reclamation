class_name RaidOnPaper
extends RefCounted
## A raid you weren't there for, settled on paper (Increment 20.5).
##
## When raiders reach a settlement and no player is within its
## `away_range`, the Settlement doesn't spawn them: it asks this to play the
## fight out in quarter-second steps, with the same numbers the real fight
## uses, and applies the result (rounds spent, who's down, what was taken).
##
## How it goes, raider by raider:
##   APPROACH  running in under the guards' fire (`under_fire_seconds`)
##   BREACH    (28.1) hacking at the shut gate in the walls, together, under
##             fire from the towers (and from the ground through a fence
##             gate's gaps), until it gives (`breach_health`)
##   CLIMB     (28.1) up a tower's stair to a guard on it, under fire
##   FIGHT     at a guard who's still standing: machete swings
##   LOOT      no guard left standing (or none at all): at the stores
##   HUNT      still nobody standing in its way: after the settlers sheltering
##             in the farmhouse, beating them down (`HUNT_SECONDS` at most)
##   FLEE      running back out with what it took, under fire again
## Guards with a gun and rounds shoot raiders they can see (coming in,
## fighting, running off); a guard without one fights with a machete when
## raiders close in. Settlers who aren't guards shelter, which only helps
## while a guard's still standing: real raiders find them in the farmhouse.
##
## Odds were tuned against real raids played out headless (see
## docs/increments/20_5_away.md). Seeded, so a test can repeat one.

enum Phase { APPROACH, FIGHT, LOOT, HUNT, FLEE, GONE, DEAD, BREACH, CLIMB }

const STEP := 0.25
const MAX_SECONDS := 400.0
## Seconds a raider spends in the guards' sight coming in (and again going out).
const UNDER_FIRE_SECONDS := 9.0
## How far off the guards are shooting from, on average (m).
const SHOT_DISTANCE := 14.0
## Half the width of a raider, for the chance a shot lands (m).
const TARGET_RADIUS := 0.4
## Shots lost to cover, posts in the way and moving targets.
const AIM := 1.0
## Raider swings: one every windup + recovery; how often one lands.
const RAIDER_HIT_CHANCE := 0.75
const GUARD_MELEE_EVERY := 1.0
const GUARD_MELEE_HIT_CHANCE := 0.7
## Seconds at the stores.
const LOOT_SECONDS := 4.0
## How long a raider with nobody standing in its way spends after the
## settlers sheltering in the farmhouse before running off.
const HUNT_SECONDS := 25.0
## Seconds up a tower's stair to the guard on it (28.1).
const CLIMB_SECONDS := 4.0


class Fighter:
	var name := ""
	var node: Node = null
	var health := 100.0
	var max_health := 100.0
	# Raiders
	var phase := Phase.APPROACH
	var timer := 0.0
	var target: Fighter = null
	var swing_every := 1.25
	var swing_damage := 20.0
	var carrying := {}
	var looted := false
	# Guards
	var weapon: WeaponDefinition = null
	var magazine := 0
	var ammo := 0
	var reloading := 0.0
	var cooldown := 0.0
	var shots := 0
	var down := false
	## Armour (22): the share of a hit it takes off, and what it stopped.
	var protection := 0.0
	var stopped := 0.0
	## Up a tower (28.1): sees over the walls, aims steadier, and is reached
	## only up its stair.
	var raised := false

	func standing() -> bool:
		return not down and health > 0.0


## The fight's result:
##   killed, escaped        raiders
##   stolen {id: n}         what got away with them
##   recovered {id: n}      taken, then dropped by a raider who was killed
##   wounded [names]        settlers who went down
##   rounds                 rounds the guards fired
##   seconds                how long it lasted
var result := {}
var raiders: Array[Fighter] = []
var guards: Array[Fighter] = []
var sheltering: Array[Fighter] = []
## What's in the stores to take: {item id: n}, taken from as raiders loot.
var stores := {}
var carry := {}
## The shut gate in the walls the raiders must break first: its health (0:
## no walls in their way) (28.1).
var breach_health := 0.0
## Guards on the ground can see raiders at that gate (a fence gate's gaps;
## not a palisade's).
var gate_seen_from_ground := true
var _walled := false
var _rng := RandomNumberGenerator.new()


func _init(seed_value := 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func add_raider(name: String, health: float, swing_damage: float, swing_every: float) -> Fighter:
	var f := Fighter.new()
	f.name = name
	f.health = health
	f.max_health = health
	f.swing_damage = swing_damage
	f.swing_every = swing_every
	f.timer = UNDER_FIRE_SECONDS * _rng.randf_range(0.8, 1.2)
	raiders.append(f)
	return f


func add_guard(name: String, health: float, weapon: WeaponDefinition, magazine: int, ammo: int, node: Node = null) -> Fighter:
	var f := Fighter.new()
	f.name = name
	f.node = node
	f.health = health
	f.weapon = weapon
	f.magazine = magazine
	f.ammo = ammo
	guards.append(f)
	return f


func add_sheltering(name: String, health: float, node: Node = null) -> Fighter:
	var f := Fighter.new()
	f.name = name
	f.node = node
	f.health = health
	sheltering.append(f)
	return f


## Expected chance one shot (or pellet) from `w` lands at SHOT_DISTANCE,
## and its damage there.
static func shot_odds(w: WeaponDefinition, raised := false) -> Array:
	var spread := (1.5 + w.base_spread * 2.0) * (Settler.TOWER_SPREAD if raised else 1.0)  # degrees, as Settler._shoot
	var size := rad_to_deg(atan(TARGET_RADIUS / SHOT_DISTANCE))
	var chance := clampf(size / spread, 0.02, 0.95) * AIM
	var d := SHOT_DISTANCE
	var fall := 1.0 if d <= w.falloff_start else lerpf(1.0, w.falloff_min_multiplier, clampf((d - w.falloff_start) / maxf(w.falloff_end - w.falloff_start, 1.0), 0.0, 1.0))
	return [chance, w.damage * fall]


func run() -> Dictionary:
	result = {"killed": 0, "escaped": 0, "stolen": {}, "recovered": {}, "wounded": [], "rounds": 0, "seconds": 0.0, "breached": false}
	_walled = breach_health > 0.0
	var t := 0.0
	while t < MAX_SECONDS and raiders.any(func(r: Fighter) -> bool: return r.phase != Phase.GONE and r.phase != Phase.DEAD):
		t += STEP
		for g in guards:
			if g.standing():
				_guard_step(g)
		for r in raiders:
			_raider_step(r)
	for g in guards:
		result["rounds"] = int(result["rounds"]) + g.shots
	result["seconds"] = t
	return result


func _raider_step(r: Fighter) -> void:
	if r.phase == Phase.GONE or r.phase == Phase.DEAD:
		return
	if r.health <= 0.0:
		_kill(r)
		return
	r.timer -= STEP
	match r.phase:
		Phase.APPROACH:
			if r.timer <= 0.0:
				if breach_health > 0.0:
					r.phase = Phase.BREACH
					r.timer = r.swing_every * _rng.randf_range(0.3, 1.0)
				else:
					_pick_fight(r)
		Phase.BREACH:
			if breach_health <= 0.0:
				_pick_fight(r)
				return
			if r.timer <= 0.0:
				r.timer = r.swing_every
				breach_health -= r.swing_damage
				if breach_health <= 0.0:
					result["breached"] = true
		Phase.CLIMB:
			if r.target == null or not r.target.standing():
				_pick_fight(r)
				return
			if r.timer <= 0.0:
				r.phase = Phase.FIGHT
				r.timer = r.swing_every * _rng.randf_range(0.3, 1.0)
		Phase.FIGHT:
			if r.target == null or not r.target.standing():
				_pick_fight(r)
				return
			if r.timer <= 0.0:
				r.timer = r.swing_every
				if _rng.randf() < RAIDER_HIT_CHANCE:
					_hurt(r.target, r.swing_damage)
		Phase.LOOT:
			if r.timer <= 0.0:
				_take(r)
				r.phase = Phase.HUNT
				r.timer = HUNT_SECONDS
				r.target = null
		Phase.HUNT:
			# A guard back on their feet (or never down) is fought first
			if guards.any(func(g: Fighter) -> bool: return g.standing()):
				_pick_fight(r)
				if r.phase == Phase.FIGHT:
					return
			if r.target == null or not r.target.standing():
				var hiding := sheltering.filter(func(f: Fighter) -> bool: return f.standing())
				r.target = hiding[_rng.randi() % hiding.size()] if not hiding.is_empty() else null
			if r.target == null or r.timer <= 0.0:
				r.phase = Phase.FLEE
				r.target = null
				r.timer = UNDER_FIRE_SECONDS * _rng.randf_range(0.8, 1.2)
				return
			r.cooldown -= STEP
			if r.cooldown <= 0.0:
				r.cooldown = r.swing_every
				if _rng.randf() < RAIDER_HIT_CHANCE:
					_hurt(r.target, r.swing_damage)
		Phase.FLEE:
			if r.timer <= 0.0:
				r.phase = Phase.GONE
				result["escaped"] = int(result["escaped"]) + 1
				var stolen: Dictionary = result["stolen"]
				for id in r.carrying:
					stolen[id] = int(stolen.get(id, 0)) + int(r.carrying[id])


## Go for the standing guard with the fewest raiders on them, those on the
## ground before those up towers (28.1: up its stair first); nobody
## standing: the stores.
func _pick_fight(r: Fighter) -> void:
	var best: Fighter = null
	var best_n := 1 << 20
	for g in guards:
		if not g.standing():
			continue
		var n := raiders.filter(func(o: Fighter) -> bool: return (o.phase == Phase.FIGHT or o.phase == Phase.CLIMB) and o.target == g).size()
		if g.raised:
			n += 1000
		if n < best_n:
			best = g
			best_n = n
	if best != null:
		r.target = best
		if best.raised:
			r.phase = Phase.CLIMB
			r.timer = CLIMB_SECONDS * _rng.randf_range(0.8, 1.2)
		else:
			r.phase = Phase.FIGHT
			r.timer = r.swing_every * _rng.randf_range(0.3, 1.0)
	elif r.looted:
		r.phase = Phase.HUNT
		r.target = null
		r.timer = HUNT_SECONDS * 0.5
	else:
		r.phase = Phase.LOOT
		r.target = null
		r.timer = LOOT_SECONDS


func _take(r: Fighter) -> void:
	r.looted = true
	for id in carry:
		var n := mini(int(stores.get(id, 0)), int(carry[id]))
		if n > 0:
			stores[id] = int(stores[id]) - n
			r.carrying[id] = n


func _kill(r: Fighter) -> void:
	r.phase = Phase.DEAD
	result["killed"] = int(result["killed"]) + 1
	var back: Dictionary = result["recovered"]
	for id in r.carrying:
		back[id] = int(back.get(id, 0)) + int(r.carrying[id])
		stores[id] = int(stores.get(id, 0)) + int(r.carrying[id])
	r.carrying = {}


func _hurt(f: Fighter, amount: float) -> void:
	if f.protection > 0.0 and amount < 9000.0:
		f.stopped += amount * f.protection
		amount *= 1.0 - f.protection
	f.health -= amount
	if f.health <= 0.0 and not f.down:
		f.health = 0.0
		f.down = true
		(result["wounded"] as Array).append(f.name)


func _guard_step(g: Fighter) -> void:
	g.cooldown -= STEP
	if g.weapon != null and not g.weapon.melee and (g.magazine > 0 or g.ammo > 0 or g.reloading > 0.0):
		if g.reloading > 0.0:
			g.reloading -= STEP
			if g.reloading <= 0.0:
				var take := mini(g.weapon.magazine_size, g.ammo)
				g.magazine += take
				g.ammo -= take
			return
		var target := _shoot_target(g)
		if target == null:
			return
		if g.magazine <= 0:
			g.reloading = g.weapon.reload_time
			return
		if g.cooldown > 0.0:
			return
		g.magazine -= 1
		g.shots += 1
		g.cooldown = Settler.shot_interval(g.weapon)
		var odds := shot_odds(g.weapon, g.raised)
		for p in maxi(g.weapon.pellets, 1):
			if _rng.randf() < float(odds[0]):
				target.health -= float(odds[1])
		return
	# The machete, at raiders who've closed in
	if g.cooldown > 0.0:
		return
	var near := raiders.filter(func(r: Fighter) -> bool: return r.phase == Phase.FIGHT and r.health > 0.0 and (not g.raised or r.target == g))
	if near.is_empty():
		return
	var mine := near.filter(func(r: Fighter) -> bool: return r.target == g)
	var r: Fighter = (mine if not mine.is_empty() else near)[0]
	g.cooldown = GUARD_MELEE_EVERY
	if _rng.randf() < GUARD_MELEE_HIT_CHANCE:
		r.health -= 18.0


## Who a guard with a gun shoots: a raider on them, else one fighting, else
## one climbing a tower, else one at the gate, else one coming in or running
## off (in the barn, looting, they can't be seen). Behind solid walls (28.1)
## only the towers see raiders outside: coming in and at the gate.
func _shoot_target(g: Fighter) -> Fighter:
	var live := raiders.filter(func(r: Fighter) -> bool: return r.health > 0.0)
	var outside_seen := g.raised or not _walled or gate_seen_from_ground
	for want in [func(r: Fighter) -> bool: return r.phase == Phase.FIGHT and r.target == g,
			func(r: Fighter) -> bool: return r.phase == Phase.FIGHT,
			func(r: Fighter) -> bool: return r.phase == Phase.CLIMB,
			func(r: Fighter) -> bool: return r.phase == Phase.BREACH and outside_seen,
			func(r: Fighter) -> bool: return (r.phase == Phase.APPROACH and outside_seen) or r.phase == Phase.FLEE]:
		var some := live.filter(want)
		if not some.is_empty():
			return some[0]
	return null
