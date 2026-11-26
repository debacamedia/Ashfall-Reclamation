class_name Achievements
extends RefCounted
## The 33 achievements approved with story mode (Increment 33.1 lists them;
## Increment 34 tracks them). Story ones follow Act 1's chapters; hidden ones
## show as "Hidden" until earned.

const CATEGORIES := {&"story": "Story", &"survival": "Survival", &"combat": "Combat", &"crafting": "Crafting",
	&"settlements": "Settlements", &"exploring": "Exploring"}

const LIST := [
	{"id": &"first_light", "category": &"story", "name": "First Light", "text": "Craft your first gun at Outpost 17", "hidden": false},
	{"id": &"crossing_over", "category": &"story", "name": "Crossing Over", "text": "Reach Halden's Crossing", "hidden": false},
	{"id": &"roots", "category": &"story", "name": "Roots", "text": "Claim Ash Creek Farms", "hidden": false},
	{"id": &"deep_work", "category": &"story", "name": "Deep Work", "text": "Claim Black Ridge Mine", "hidden": false},
	{"id": &"northwatch_stands", "category": &"story", "name": "Northwatch Stands", "text": "Claim Northwatch Outpost", "hidden": false},
	{"id": &"beyond_the_storm", "category": &"story", "name": "Beyond the Storm", "text": "Cross into the mid zone", "hidden": false},
	{"id": &"patched_up", "category": &"survival", "name": "Patched Up", "text": "Heal with a medkit in the middle of a fight", "hidden": false},
	{"id": &"back_for_it", "category": &"survival", "name": "Back for It", "text": "Recover your gear chest after dying", "hidden": false},
	{"id": &"square_meal", "category": &"survival", "name": "Square Meal", "text": "Eat a stew you cooked yourself", "hidden": false},
	{"id": &"storm_chaser", "category": &"survival", "name": "Storm Chaser", "text": "Walk out of the ash storm with less than 10 health", "hidden": true},
	{"id": &"first_blood", "category": &"combat", "name": "First Blood", "text": "Kill a raider", "hidden": false},
	{"id": &"old_hands", "category": &"combat", "name": "Old Hands", "text": "Kill a Raider Veteran", "hidden": false},
	{"id": &"plate_breaker", "category": &"combat", "name": "Plate Breaker", "text": "Kill a Scorch Marauder", "hidden": false},
	{"id": &"long_shot", "category": &"combat", "name": "Long Shot", "text": "Kill a raider more than 150 m away", "hidden": false},
	{"id": &"two_of_a_kind", "category": &"combat", "name": "Two of a Kind", "text": "Kill raiders with two different pistols in under 10 s", "hidden": false},
	{"id": &"roadkill", "category": &"combat", "name": "Roadkill", "text": "Run down a raider with the truck", "hidden": true},
	{"id": &"pipe_dream", "category": &"crafting", "name": "Pipe Dream", "text": "Make a pipe pistol by hand", "hidden": false},
	{"id": &"gunsmith", "category": &"crafting", "name": "Gunsmith", "text": "Assemble a gun from parts at a weapons bench", "hidden": false},
	{"id": &"kitted_out", "category": &"crafting", "name": "Kitted Out", "text": "Fit three attachments to one gun", "hidden": false},
	{"id": &"dressed_for_trouble", "category": &"crafting", "name": "Dressed for Trouble", "text": "Wear head, body and legs armour at once", "hidden": false},
	{"id": &"running_water", "category": &"settlements", "name": "Running Water", "text": "Fix Ash Creek's pump", "hidden": false},
	{"id": &"first_harvest", "category": &"settlements", "name": "First Harvest", "text": "Farmers fill the Farm Store with 50 vegetables", "hidden": false},
	{"id": &"armed_and_ready", "category": &"settlements", "name": "Armed and Ready", "text": "Arm a guard with a gun", "hidden": false},
	{"id": &"held_the_line", "category": &"settlements", "name": "Held the Line", "text": "Beat a raid with nobody wounded", "hidden": false},
	{"id": &"full_house", "category": &"settlements", "name": "Full House", "text": "Twelve settlers in one place", "hidden": false},
	{"id": &"barnyard", "category": &"settlements", "name": "Barnyard", "text": "Chickens, pigs, cows and sheep at one farm", "hidden": false},
	{"id": &"walls_of_scrap", "category": &"settlements", "name": "Walls of Scrap", "text": "Finish a reinforced palisade", "hidden": false},
	{"id": &"supply_line", "category": &"settlements", "name": "Supply Line", "text": "Hold three places at once", "hidden": false},
	{"id": &"all_seven", "category": &"exploring", "name": "All Seven", "text": "Visit all seven early-zone places", "hidden": false},
	{"id": &"cartographer", "category": &"exploring", "name": "Cartographer", "text": "Uncover three quarters of the early zone's map", "hidden": false},
	{"id": &"high_ground", "category": &"exploring", "name": "High Ground", "text": "Climb Halden's water tower", "hidden": false},
	{"id": &"road_trip", "category": &"exploring", "name": "Road Trip", "text": "Drive 10 km in the truck", "hidden": false},
	{"id": &"running_on_fumes", "category": &"exploring", "name": "Running on Fumes", "text": "Run the truck dry more than 1 km from fuel", "hidden": true},
]


static func count() -> int:
	return LIST.size()


## Two letters for a medal: "First Light" -> "FL".
static func initials(a: Dictionary) -> String:
	var parts := String(a["name"]).split(" ", false)
	var out := ""
	for p in parts:
		if out.length() < 2 and p[0] == p[0].to_upper():
			out += p[0]
	return out if out != "" else String(a["name"]).left(2)


## The achievement called `id`, or {}.
static func find(id: StringName) -> Dictionary:
	for a: Dictionary in LIST:
		if a["id"] == id:
			return a
	return {}
