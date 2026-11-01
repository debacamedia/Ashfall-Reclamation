class_name PlayerHunger
extends Node
## The player's hunger (Increment 21). `food` runs from `max_food` (full)
## down to 0 over `full_to_empty_seconds` of play, three times as fast while
## sprinting. Eating (J, or Eat in the inventory) puts it back.
##
##   Fed       above half         nothing
##   Peckish   half to a quarter  a notice: time to eat
##   Hungry    under a quarter    no sprinting
##   Starving  empty              slower, and health drains, never below
##                                `starving_health_floor`: hunger can't kill
##
## A child of the PlayerController (made in its _ready); saved with it.

signal stage_changed(stage: Stage)
signal food_changed(food: float, max_food: float)

enum Stage { FED, PECKISH, HUNGRY, STARVING }

@export var max_food := 100.0
## Full to empty, walking or standing (s of play): about 20 min between meals.
@export var full_to_empty_seconds := 2400.0
@export var sprint_multiplier := 3.0
## Starving: walking speed is multiplied by this.
@export var starving_speed_multiplier := 0.75
## Starving: health lost per second, down to the floor.
@export var starving_health_per_second := 0.25
@export var starving_health_floor := 25.0

var food := 100.0
var stage: Stage = Stage.FED
var _starve_debt := 0.0


func fraction() -> float:
	return clampf(food / maxf(max_food, 0.001), 0.0, 1.0)


static func stage_for(fraction_full: float) -> Stage:
	if fraction_full <= 0.0:
		return Stage.STARVING
	if fraction_full < 0.25:
		return Stage.HUNGRY
	if fraction_full < 0.5:
		return Stage.PECKISH
	return Stage.FED


static func stage_name(s: Stage) -> String:
	return ["Fed", "Peckish", "Hungry", "Starving"][s]


## Can the player sprint? Not when hungry or starving.
func can_sprint() -> bool:
	return stage < Stage.HUNGRY


func speed_multiplier() -> float:
	return starving_speed_multiplier if stage == Stage.STARVING else 1.0


## How much eating would top up now.
func missing() -> float:
	return maxf(max_food - food, 0.0)


## Advances hunger by `delta` seconds of play. `health` loses a little while
## starving (never below the floor).
func tick(delta: float, sprinting: bool, health: HealthComponent) -> void:
	var rate := max_food / maxf(full_to_empty_seconds, 1.0) * (sprint_multiplier if sprinting else 1.0)
	set_food(food - rate * delta)
	if stage == Stage.STARVING and health != null and not health.is_dead() and health.current_health > starving_health_floor:
		_starve_debt += starving_health_per_second * delta
		if _starve_debt >= 1.0:
			var take := minf(floorf(_starve_debt), health.current_health - starving_health_floor)
			_starve_debt -= floorf(_starve_debt)
			if take > 0.0:
				# Quietly: no hurt sound or red flash, just the bar going down
				health.current_health -= take
				health.health_changed.emit(health.current_health, health.max_health)
	else:
		_starve_debt = 0.0


func eat(amount: float) -> void:
	set_food(food + amount)


func set_food(value: float) -> void:
	var before := food
	food = clampf(value, 0.0, max_food)
	if not is_equal_approx(before, food):
		food_changed.emit(food, max_food)
	var s := stage_for(fraction())
	if s != stage:
		stage = s
		stage_changed.emit(stage)


func save_state() -> float:
	return food


func load_state(value: Variant) -> void:
	if (value is float or value is int) and is_finite(float(value)):
		set_food(float(value))
	else:
		set_food(max_food)
