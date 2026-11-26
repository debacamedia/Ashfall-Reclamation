class_name Orders
extends RefCounted
## Increment 34: the story's orders, The Last Order's Act 1 (from the
## approved proofs). Short tasks in chapters, one chapter at a time; each
## ticks itself off when the game sees it done, and anything already done
## counts (so you can't get stuck). No item rewards; a compass marker for
## the order you track.
##
## Each order: id, text, check (what StoryProgress looks for), count (for
## "three of"), where (what the marker points at: a node path under the
## zone, or "survivor:<name>").

const ACT_TITLE := "Act 1 · The Last Order"

const CHAPTERS := [
	{"id": &"prologue", "label": "Prologue", "title": "Hold and wait",
	"note": "Command says hold. So we hold. — A.V.",
	"orders": [
		{"id": &"wake", "text": "Wake in Outpost 17's barracks", "check": &"in_barracks", "where": "Outpost17/Buildings/Barracks"},
		{"id": &"take_manual", "text": "Take the Field Manual from Sgt. Vance's footlocker", "check": &"has_manual", "where": "Outpost17/SalvageContainers/VanceFootlocker"},
		{"id": &"armed", "text": "Find something to fight with", "check": &"has_weapon"},
		{"id": &"search", "text": "Search three containers", "check": &"searched", "count": 3},
	]},
	{"id": &"first_light", "label": "Chapter 1", "title": "First Light",
	"note": "Pipe and a spring. Ugly, but it shoots. — A.V.",
	"orders": [
		{"id": &"pipe_pistol", "text": "Craft a pipe pistol by hand (K)", "check": &"crafted_pipe_pistol"},
		{"id": &"rounds", "text": "Make rounds at the workbench", "check": &"crafted_rounds", "where": "Outpost17/CraftingStations/Workbench"},
		{"id": &"first_kill", "text": "Kill a raider", "check": &"kills", "count": 1},
		{"id": &"bandage", "text": "Heal with a bandage", "check": &"used_bandage"},
	]},
	{"id": &"crossing_over", "label": "Chapter 2", "title": "Crossing Over",
	"note": "Follow the road north-east. Halden's had a diner. — A.V.",
	"orders": [
		{"id": &"reach_haldens", "text": "Follow the road to Halden's Crossing", "check": &"visited_haldens", "where": "HaldensCrossing"},
		{"id": &"water_tower", "text": "Climb the water tower and look around", "check": &"climbed_tower", "where": "HaldensCrossing/WaterTower"},
		{"id": &"tomas", "text": "Find Tomas in the diner", "check": &"met_tomas", "where": "survivor:Tomas"},
		{"id": &"clear_haldens", "text": "Clear the raiders at Halden's", "check": &"cleared_haldens", "where": "HaldensCrossing"},
	]},
	{"id": &"roots", "label": "Chapter 3", "title": "Roots",
	"note": "Water first. Then people. Then walls. — A.V.",
	"orders": [
		{"id": &"clear_ash", "text": "Clear Ash Creek's raiders", "check": &"cleared_ash", "where": "AshCreekFarms"},
		{"id": &"claim_ash", "text": "Claim the farm at its notice board", "check": &"claimed_ash", "where": "AshCreekFarms/Settlement/ClaimPoint"},
		{"id": &"pump", "text": "Fix the pump", "check": &"pump_fixed", "where": "AshCreekFarms/Settlement/WaterPump"},
		{"id": &"farmer", "text": "Give someone the Farmer job", "check": &"has_farmer"},
		{"id": &"guard", "text": "Arm a guard", "check": &"armed_guard"},
		{"id": &"first_raid", "text": "See the farm through its first raid", "check": &"farm_raided", "where": "AshCreekFarms"},
	]},
	{"id": &"deep_work", "label": "Chapter 4", "title": "Deep Work",
	"note": "Black Ridge sent its ore east. Ask why. — A.V.",
	"orders": [
		{"id": &"drive_mine", "text": "Drive the truck to Black Ridge Mine", "check": &"drove_to_mine", "where": "BlackRidgeMine"},
		{"id": &"jeb", "text": "Find Old Jeb in the bunkhouse", "check": &"met_jeb", "where": "survivor:Old Jeb"},
		{"id": &"claim_mine", "text": "Clear and claim the mine", "check": &"claimed_mine", "where": "BlackRidgeMine/Settlement/ClaimPoint"},
		{"id": &"miner", "text": "Put a Miner to work", "check": &"has_miner"},
		{"id": &"palisade", "text": "Build the mine's palisade", "check": &"mine_palisade", "where": "BlackRidgeMine"},
	]},
	{"id": &"northwatch", "label": "Chapter 5", "title": "Northwatch Stands",
	"note": "If the radio's still up at Northwatch, answer it. — A.V.",
	"orders": [
		{"id": &"take_northwatch", "text": "Take Northwatch from its garrison", "check": &"cleared_northwatch", "where": "NorthwatchOutpost"},
		{"id": &"claim_northwatch", "text": "Claim it", "check": &"claimed_northwatch", "where": "NorthwatchOutpost/Settlement/ClaimPoint"},
		{"id": &"armorer", "text": "Get an Armorer making guns", "check": &"has_armorer"},
		{"id": &"hold_three", "text": "Hold all three places", "check": &"held_three"},
		{"id": &"radio", "text": "Answer the radio in the command post", "check": &"answered_radio", "where": "NorthwatchOutpost/StoryRadio"},
	]},
]


static func chapter(id: StringName) -> Dictionary:
	for c: Dictionary in CHAPTERS:
		if c["id"] == id:
			return c
	return {}


static func order(id: StringName) -> Dictionary:
	for c: Dictionary in CHAPTERS:
		for o: Dictionary in c["orders"]:
			if o["id"] == id:
				return o
	return {}


## The chapter an order is in.
static func chapter_of(order_id: StringName) -> Dictionary:
	for c: Dictionary in CHAPTERS:
		for o: Dictionary in c["orders"]:
			if o["id"] == order_id:
				return c
	return {}


static func all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for c: Dictionary in CHAPTERS:
		for o: Dictionary in c["orders"]:
			out.append(o["id"])
	return out


static func count() -> int:
	return all_ids().size()
