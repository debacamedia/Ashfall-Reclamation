extends SceneTree
## Builds the early zone's five newer places as real sites, like Halden's
## Crossing: buildings you can walk into, furniture, searchable containers,
## salvage, pickups, ladders to high ground and raiders (Increment 16).
##
##   levels/saint_mercy_clinic/saint_mercy_clinic.tscn
##   levels/ash_creek_farms/ash_creek_farms.tscn
##   levels/smugglers_gulch/smugglers_gulch.tscn
##   levels/black_ridge_mine/black_ridge_mine.tscn
##   levels/northwatch_outpost/northwatch_outpost.tscn
## and the loot tables they use (resources/loot/*.tres).
##
## Run from the project root, then rebuild the zone (its navmesh):
##
##     godot --headless --path . -s res://tools/build_sites.gd
##     godot --headless --path . -s res://tools/build_early_zone.gd
##
## Each site is drawn in its own coordinates, centred on the place's spot in
## the zone (see PLACES in build_early_zone.gd). x is east, -z is north.

const Kit := preload("res://tools/site_kit.gd")

## New loot tables: name -> [min_rolls, max_rolls, [guaranteed…], [entries…]]
## where each entry is [item, weight, min, max].
const LOOT := {
	"hospital_supplies": [2, 3, [], [["bandage", 3, 1, 3], ["chemicals", 3, 1, 2], ["cloth", 2, 2, 4], ["medkit", 1, 1, 1], ["electronics", 1, 1, 1]]],
	"pharmacy": [1, 2, [["bandage", 1, 2, 2]], [["chemicals", 3, 2, 4], ["medkit", 2, 1, 1], ["cloth", 1, 1, 3]]],
	"farm_shed": [2, 4, [], [["scrap_metal", 3, 2, 4], ["wood_plank", 3, 2, 4], ["spring", 2, 1, 2], ["metal_pipe", 2, 1, 2], ["fuel", 2, 1, 1], ["cloth", 1, 1, 3], ["shotgun_shells", 1, 3, 6]]],
	"barn_loft": [1, 3, [["shotgun_shells", 1, 6, 12]], [["gun_stock", 1, 1, 1], ["cloth", 2, 2, 4], ["medkit", 1, 1, 1], ["fuel", 1, 1, 2]]],
	"mine_supplies": [2, 4, [], [["gunpowder", 3, 2, 4], ["fuel", 2, 1, 2], ["metal_plate", 2, 1, 2], ["scrap_metal", 2, 2, 5], ["spring", 1, 1, 2], ["metal_pipe", 2, 1, 2], ["frame_pack", 0.3, 1, 1]]],
	"mine_explosives": [1, 2, [["gunpowder", 1, 3, 5]], [["fuel", 2, 1, 2], ["chemicals", 2, 1, 2], ["spring", 1, 1, 1]]],
	"mine_office": [1, 3, [], [["electronics", 2, 1, 2], ["pistol_ammo", 2, 6, 12], ["chemicals", 1, 1, 2], ["cloth", 1, 1, 2], ["gun_magazine", 1, 1, 1]]],
	"smuggler_stash": [3, 5, [["electronics", 1, 1, 2]], [["suppressor", 1, 1, 1], ["extended_mag", 1, 1, 1], ["red_dot", 1, 1, 1], ["scope_4x", 0.5, 1, 1], ["foregrip", 1, 1, 1], ["rifle_ammo", 2, 15, 30], ["pistol_ammo", 2, 10, 20], ["shotgun_shells", 1, 6, 12], ["chemicals", 2, 1, 2], ["gunpowder", 2, 1, 3], ["gun_receiver", 1, 1, 1], ["gun_barrel", 1, 1, 1], ["trigger_group", 1, 1, 1], ["medkit", 1, 1, 1], ["military_pack", 0.4, 1, 1]]],
	# Increment 16.6: guns you can find. Each list's 5th part is "exactly one of"
	"smuggler_guns": [1, 2, [["pistol_ammo", 1, 8, 15]], [["shotgun_shells", 2, 6, 12], ["rifle_ammo", 2, 15, 30], ["gun_magazine", 1, 1, 1], ["suppressor", 1, 1, 1]],
		[["weapons/pistol_item", 4, 1, 1], ["weapons/shotgun_item", 3, 1, 1], ["weapons/service_rifle_item", 1, 1, 1]]],
	"smuggler_lookout": [1, 3, [["rifle_308", 1, 6, 12]], [["weapons/scoped_rifle_item", 1, 1, 1], ["weapons/pistol_item", 1, 1, 1], ["scope_4x", 1, 1, 1], ["red_dot", 1, 1, 1], ["medkit", 1, 1, 1], ["rifle_ammo", 2, 10, 20]]],
	"garrison_armory": [2, 3, [], [["rifle_ammo", 3, 20, 40], ["shotgun_shells", 2, 8, 16], ["pistol_ammo", 2, 10, 20], ["gun_magazine", 1, 1, 1], ["gun_barrel", 1, 1, 1], ["red_dot", 1, 1, 1], ["foregrip", 1, 1, 1], ["extended_mag", 1, 1, 1]],
		[["weapons/service_rifle_item", 3, 1, 1], ["weapons/shotgun_item", 3, 1, 1], ["weapons/pistol_item", 2, 1, 1], ["weapons/scoped_rifle_item", 1, 1, 1]]],
	"garrison_ammo": [2, 3, [["rifle_ammo", 1, 30, 60]], [["pistol_ammo", 2, 15, 30], ["shotgun_shells", 2, 10, 20], ["rifle_308", 1, 10, 20], ["gunpowder", 1, 2, 4]]],
	"garrison_crate": [2, 4, [["medkit", 1, 1, 1]], [["bandage", 2, 2, 4], ["rifle_ammo", 3, 15, 30], ["gun_receiver", 1, 1, 1], ["trigger_group", 1, 1, 1], ["gun_stock", 1, 1, 1], ["metal_plate", 2, 1, 2], ["electronics", 1, 1, 2], ["red_dot", 1, 1, 1], ["military_pack", 0.6, 1, 1]]],
	# Increment 16.8: Northwatch's stores always have a military pack
	"quartermaster": [1, 3, [["military_pack", 1, 1, 1]], [["bandage", 2, 2, 4], ["cloth", 2, 2, 5], ["rifle_ammo", 2, 15, 30], ["medkit", 1, 1, 1], ["metal_plate", 1, 1, 2]]],
	"officer_locker": [1, 3, [["pistol_ammo", 1, 8, 16]], [["electronics", 2, 1, 2], ["medkit", 1, 1, 1], ["weapons/pistol_item", 1, 1, 1], ["red_dot", 1, 1, 1], ["extended_mag", 1, 1, 1]]],
	"comms_gear": [1, 2, [["electronics", 1, 2, 3]], [["scope_4x", 1, 1, 1], ["spring", 1, 1, 2], ["metal_plate", 1, 1, 1], ["rifle_308", 1, 5, 10]]],
}

const BOARD := Rect2(0.045, 0.145, 0.911, 0.713)  ## the board in a Pack 3 sign image
const P3 := "res://assets/ashfall_pack_v3/materials/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# -- ash_creek_farms … builds just the named places (folder names)
	var only := Array(OS.get_cmdline_user_args())
	var want := func(folder: String) -> bool: return only.is_empty() or only.has(folder)
	_loot_tables()
	if want.call("saint_mercy_clinic"):
		_saint_mercy().save("res://levels/saint_mercy_clinic/saint_mercy_clinic.tscn")
	if want.call("ash_creek_farms"):
		_ash_creek().save("res://levels/ash_creek_farms/ash_creek_farms.tscn")
	if want.call("smugglers_gulch"):
		_smugglers_gulch().save("res://levels/smugglers_gulch/smugglers_gulch.tscn")
	if want.call("black_ridge_mine"):
		_black_ridge().save("res://levels/black_ridge_mine/black_ridge_mine.tscn")
	if want.call("northwatch_outpost"):
		_northwatch().save("res://levels/northwatch_outpost/northwatch_outpost.tscn")
	print("sites built")
	quit()


func _loot_tables() -> void:
	for name in LOOT:
		var spec: Array = LOOT[name]
		var t := LootTable.new()
		t.min_rolls = spec[0]
		t.max_rolls = spec[1]
		var g: Array[LootEntry] = []
		for e: Array in spec[2]:
			g.append(_entry(e))
		var en: Array[LootEntry] = []
		for e: Array in spec[3]:
			en.append(_entry(e))
		t.guaranteed = g
		t.entries = en
		var one: Array[LootEntry] = []
		if spec.size() > 4:
			for e: Array in spec[4]:
				one.append(_entry(e))
		t.one_of = one
		ResourceSaver.save(t, "res://resources/loot/%s.tres" % name)
	print("  %d loot tables" % LOOT.size())


func _entry(e: Array) -> LootEntry:
	var le := LootEntry.new()
	var path := "res://resources/items/%s.tres" % e[0]
	if not ResourceLoader.exists(path):
		path = "res://resources/items/attachments/%s.tres" % e[0]
	le.item = load(path)
	assert(le.item != null, "item " + e[0])
	le.weight = e[1]
	le.min_quantity = e[2]
	le.max_quantity = e[3]
	return le


## A free-standing sign board on two posts, with a Pack 3 sign on its face.
func _sign_board(k: Kit, name: String, sign_mat: String, pos: Vector3, yaw: float, size: Vector2) -> void:
	var body := k.solid_body(k.groups["Props"], name, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos))
	k.box(body, "Board", Vector3(size.x + 0.2, size.y + 0.2, 0.08), Vector3(0, 1.9, 0), "wood")
	k.box(body, "PostL", Vector3(0.12, 2.0, 0.12), Vector3(-size.x / 2.0, 1.0, -0.08), "wood")
	k.box(body, "PostR", Vector3(0.12, 2.0, 0.12), Vector3(size.x / 2.0, 1.0, -0.08), "wood")
	k.sign(name + "Face", sign_mat, null, pos + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 1.9, 0.05), yaw, size, BOARD)


func _bed(k: Kit, name: String, b: Node3D, local: Vector3, yaw := 0.0) -> void:
	k.fixture(name, b, local, Vector3(2.0, 0.55, 0.95), "wood", yaw)


# ================================================================ Saint Mercy Clinic

func _saint_mercy() -> Kit:
	var k := Kit.new("SaintMercyClinic", "Saint Mercy Clinic", 101)
	# The hospital: two storeys, the front facing the road from the east
	var h := k.building("Hospital", Vector2(0, 0), 0, Vector2(14, 30), {
		"wall": "paint_white", "floor": "concrete_plain", "storeys": 2, "roof": "flat", "parapet": true,
		"roof_ladder": Vector3(-7, 0, 7),
		"openings": [["E", 0, "door"], ["E", -10, "window"], ["E", -5, "window"], ["E", 5, "window"], ["E", 10, "window"],
			["E", -10, "window", 1], ["E", -5, "window", 1], ["E", 0, "window", 1], ["E", 5, "window", 1], ["E", 10, "window", 1],
			["W", -10, "door"], ["W", 4, "window"], ["W", 10, "window"],
			["W", -10, "window", 1], ["W", -4, "window", 1], ["W", 4, "window", 1], ["W", 10, "window", 1],
			["N", -3, "window"], ["N", 3, "window"], ["N", -3, "window", 1], ["N", 3, "window", 1],
			["S", -3, "window"], ["S", 3, "window"], ["S", -3, "window", 1], ["S", 3, "window", 1]],
		"inner": [[Vector2(-6.85, -5), Vector2(6.85, -5), [6.85]], [Vector2(-6.85, 5), Vector2(6.85, 5), [6.85]]],
		"hole": Rect2(Vector2(-6.4, -1.6), Vector2(2.6, 1.6)),
	})
	k.ladder("InnerLadder", h, Vector3(-5.1, 0, -1.6), 0, 3.3)
	k.ladder("RoofLadder", h, Vector3(-7.05, 0, 7), -90, 6.9)
	# Hall: reception counter and benches
	k.fixture("ReceptionCounter", h, Vector3(3.0, 0, -2.6), Vector3(0.6, 1.0, 2.4), "wood")
	k.fixture("WaitingBench", h, Vector3(-1.5, 0, 3.6), Vector3(3.0, 0.45, 0.5), "wood")
	k.container("footlocker", "ReceptionDrawer", h, Vector3(4.5, 0, -4.55), 0, "town_household", "Reception Drawer")
	k.pickup("bandage", 2, "HallBandages", h, Vector3(3.0, 1.0, -2.2))
	k.pile("appliance", "HallVending", h, Vector3(5.6, 0, 3.4), -90)
	# The wards behind the inner walls (y 0 is the hall floor)
	for i in 3:
		_bed(k, "NorthWardBed%d" % i, h, Vector3(-5.4, 0, -13.2 + i * 2.6))
		_bed(k, "SouthWardBed%d" % i, h, Vector3(-5.4, 0, 8.0 + i * 2.6))
	k.container_at_wall("locker", "MedicineCabinet", h, "N", 0.0, "clinic_cabinet", "Medicine Cabinet")
	k.container_at_wall("crate", "MedicalSupplies", h, "E", -12.5, "hospital_supplies", "Medical Supplies")
	k.container_at_wall("locker", "PharmacyCabinet", h, "S", 5.0, "pharmacy", "Pharmacy Cabinet")
	k.container_at_wall("footlocker", "PatientBelongings", h, "E", 12.5, "town_household", "Patient Belongings")
	k.pile("furniture", "NorthWardWreck", h, Vector3(2.0, 0, -9.0), 30)
	k.pile("furniture", "SouthWardWreck", h, Vector3(2.5, 0, 10.0), -20)
	k.pickup("chemicals", 1, "WardChemicals", h, Vector3(-3.8, 0, -9.0))
	# Upstairs (y 3.3): offices and an operating room
	k.fixture("OperatingTable", h, Vector3(1.0, 3.3, -9.5), Vector3(2.0, 0.9, 0.8), "metal_dark")
	k.fixture("DoctorsDesk", h, Vector3(2.0, 3.3, 9.0), Vector3(1.6, 0.8, 0.8), "wood")
	k.container_at_wall("crate", "SurgicalSupplies", h, "E", 2.5, "hospital_supplies", "Surgical Supplies", 3.3)
	k.container_at_wall("footlocker", "DoctorsLocker", h, "W", -12.5, "clinic_cabinet", "Doctor's Locker", 3.3)
	k.pickup("medkit", 1, "UpstairsMedkit", h, Vector3(2.0, 4.1, 9.0))
	k.pile("appliance", "OldXRay", h, Vector3(-3.0, 3.3, -11.5), 90)
	# The roof
	k.container("crate", "RooftopStash", h, Vector3(-4.0, 6.9, 3.0), 90, "sniper_stash", "Rooftop Stash")
	# Signs: the clinic's name over the door, red crosses
	k.sign("ClinicSign", P3 + "sign_sign_clinic.tres", h, Vector3(7.03, 3.0, 0), 90, Vector2(2.4, 0.94), BOARD)
	k.box(h, "CrossV", Vector3(0.6, 2.0, 0.06), Vector3(0, 4.9, 15.03), "red_cross", 0.0, false)
	k.box(h, "CrossH", Vector3(2.0, 0.6, 0.06), Vector3(0, 4.9, 15.03), "red_cross", 0.0, false)
	# Emergency annex
	var a := k.building("Annex", Vector2(-15, 4), 0, Vector2(9, 10), {
		"wall": "concrete_stained", "floor": "concrete_plain",
		"openings": [["S", 0, "door"], ["E", -2, "door"], ["W", -2, "window"], ["W", 2, "window"], ["N", 2, "window"]],
	})
	_bed(k, "AnnexBedA", a, Vector3(-2.7, 0, -3.4))
	_bed(k, "AnnexBedB", a, Vector3(-2.7, 0, 0.4))
	k.container_at_wall("crate", "TriageSupplies", a, "N", 2.0, "hospital_supplies", "Triage Supplies")
	k.pile("appliance", "AnnexMachine", a, Vector3(2.6, 0, 2.6), -90)
	k.pickup("pistol_ammo", 8, "AnnexAmmo", a, Vector3(1.2, 0, -3.0))
	# Staff house
	var s := k.building("StaffHouse", Vector2(-2, -30), 0, Vector2(9, 7), {
		"wall": "plaster", "floor": "wood", "roof": "pitched",
		"openings": [["S", 0, "door"], ["E", 0, "window"], ["W", 0, "window"], ["N", -2, "window"]],
	})
	_bed(k, "StaffBed", s, Vector3(-2.6, 0, -1.8))
	k.fixture("StaffTable", s, Vector3(2.0, 0, -1.0), Vector3(1.2, 0.75, 0.8), "wood")
	k.container_at_wall("footlocker", "StaffLocker", s, "W", 1.9, "town_household", "Staff Locker")
	k.pile("furniture", "StaffChair", s, Vector3(2.3, 0, 1.6), 15)
	k.pickup("cloth", 3, "StaffCloth", s, Vector3(2.0, 0.75, -1.0))
	# Generator shed
	var g := k.building("GeneratorShed", Vector2(13, 20), 0, Vector2(6, 5), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "flat", "roof_mat": "rust",
		"openings": [["W", 0, "door"], ["N", 1, "window"]],
	})
	k.prop("generator", "ClinicGenerator", k.at(g, Vector3(1.4, 0, -1.2)), 0)
	k.container_at_wall("crate", "ShedToolChest", g, "S", 1.2, "tool_chest", "Tool Chest")
	k.pickup("electronics", 1, "ShedElectronics", g, Vector3(-1.4, 0, -1.4))
	k.pickup("fuel", 1, "ShedFuel", null, Vector3(9.0, 0, 23.6))
	k.pile("pallet", "ShedPalletA", null, Vector3(8.5, 0, 15.5), 20)
	k.pile("pallet", "ShedPalletB", null, Vector3(18.5, 0, 15.0), -10)
	# Ambulance bay: wrecks under a canopy east of the front door
	var bay := k.solid_body(k.groups["Props"], "AmbulanceBay")
	for p in [Vector3(12, 1.7, -4.8), Vector3(18, 1.7, -4.8), Vector3(12, 1.7, 4.8), Vector3(18, 1.7, 4.8)]:
		k.box(bay, "CanopyPost", Vector3(0.25, 3.4, 0.25), p, "metal_dark")
	k.box(bay, "Canopy", Vector3(7.5, 0.2, 10.4), Vector3(15, 3.5, 0), "corrugated")
	for w: Array in [[Vector3(14.0, 0, -2.6), 8.0], [Vector3(16.5, 0, 2.8), -12.0]]:
		var amb := k.solid_body(k.groups["Props"], "Ambulance", Transform3D(Basis(Vector3.UP, deg_to_rad(w[1])), w[0]))
		k.box(amb, "Box", Vector3(2.2, 2.3, 3.8), Vector3(0, 1.35, -0.6), "paint_white")
		k.box(amb, "Cab", Vector3(2.1, 1.6, 1.6), Vector3(0, 0.95, 2.1), "paint_white")
		k.box(amb, "Stripe", Vector3(2.22, 0.3, 3.82), Vector3(0, 1.6, -0.6), "red_cross", 0.0, false)
	k.pile("scrap", "AmbulanceScrapA", null, Vector3(19.5, 0, -2.0), 30)
	k.pile("scrap", "AmbulanceScrapB", null, Vector3(12.0, 0, 6.8), -15)
	# Morgue container and a broken boundary wall with gaps for the roads
	k.prop("shipping_container", "MorgueContainer", Vector3(-15, 0, -16), 90)
	var wall := k.solid_body(k.groups["Props"], "BoundaryWall")
	for seg: Array in [[Vector3(26, 0, 12), 22.0, 90.0], [Vector3(26, 0, -33), 8.0, 90.0], [Vector3(12, 0, -38), 26.0, 0.0],
			[Vector3(-24.5, 0, -38), 3.0, 0.0], [Vector3(-26, 0, -10), 30.0, 90.0], [Vector3(-26, 0, 20), 12.0, 90.0],
			[Vector3(-8, 0, 28), 30.0, 0.0], [Vector3(18, 0, 28), 10.0, 0.0]]:
		k.box(wall, "Wall", Vector3(seg[1], 1.1, 0.4), (seg[0] as Vector3) + Vector3(0, 0.55, 0), "concrete", seg[2])
	k.spawner("RaiderSpawner", "raider", 3, 45.0, [Vector2(24, 18), Vector2(-21, 18), Vector2(8, -34)])
	return k


# ================================================================ Ash Creek Farms

func _ash_creek() -> Kit:
	var k := Kit.new("AshCreekFarms", "Ash Creek Farms", 202)
	# Farmhouse: two rooms, a porch, the front door facing the lane
	var f := k.building("Farmhouse", Vector2(-8, 8), 0, Vector2(10, 8), {
		"wall": "wood", "floor": "wood", "roof": "pitched",
		"openings": [["S", -2, "door"], ["S", 2.5, "window"], ["N", -2.5, "window"], ["N", 2.5, "window"],
			["W", 0, "window"], ["E", 0, "door"]],
		"inner": [[Vector2(0, -3.85), Vector2(0, 3.85), [3.85]]],
	})
	k.box(k.groups["Buildings"].get_node("Farmhouse"), "Porch", Vector3(10, 0.1, 2.4), Vector3(0, 0.05, 5.2), "wood", 0.0, false)
	_bed(k, "FarmBed", f, Vector3(-3.5, 0, -2.6))
	k.container_at_wall("footlocker", "BedroomChest", f, "W", 2.3, "town_household", "Bedroom Chest")
	k.fixture("KitchenCounter", f, Vector3(2.6, 0, -3.25), Vector3(3.0, 0.9, 0.6), "wood")
	k.fixture("KitchenTable", f, Vector3(2.4, 0, 0.8), Vector3(1.4, 0.75, 0.9), "wood")
	k.container_at_wall("crate", "Pantry", f, "E", 2.6, "town_supplies", "Pantry")
	k.pile("furniture", "KitchenChair", f, Vector3(-1.4, 0, 2.2), 40)
	k.pickup("cloth", 2, "FarmCloth", f, Vector3(2.4, 0.75, 0.8))
	# The barn, with a hayloft up a ladder
	var b := k.building("Barn", Vector2(14, -14), 0, Vector2(12, 16), {
		"wall": "barn_red", "floor": "wood", "roof": "pitched", "height": 5.4, "pitch": 3.0,
		"openings": [["S", 0, "wide"], ["N", 3, "door"], ["E", 3, "window"], ["W", 3, "window"]],
	})
	var loft := k.solid_body(b, "Hayloft")
	k.box(loft, "Deck", Vector3(11.4, 0.25, 6.0), Vector3(0, 2.875, -4.7), "wood")
	k.ladder("LoftLadder", b, Vector3(-3.5, 0, -1.7), 0, 3.0)
	for i in 3:
		k.fixture("HayBale%d" % i, b, Vector3(-4.2 + i * 1.3, 3.0, -6.6), Vector3(1.1, 0.7, 0.9), "crop")
	k.container("crate", "HayloftStash", b, Vector3(3.5, 3.0, -6.8), 0, "barn_loft", "Hayloft Stash")
	k.pickup("shotgun_shells", 6, "LoftShells", b, Vector3(1.0, 3.0, -4.0))
	k.container_at_wall("crate", "FeedBins", b, "W", 6.0, "farm_shed", "Feed Bins")
	k.pile("pallet", "BarnPalletA", b, Vector3(3.8, 0, 3.0), 10)
	k.pile("pallet", "BarnPalletB", b, Vector3(3.6, 0, 5.4), -5)
	k.pile("scrap", "OldPlough", b, Vector3(-3.6, 0, 4.0), 60)
	k.prop("wood_crate", "BarnCrateA", k.at(b, Vector3(4.6, 0, -0.4)), 15)
	k.prop("wood_crate", "BarnCrateB", k.at(b, Vector3(-4.6, 0, 1.2)), -20)
	# Tool shed with a workbench
	var t := k.building("ToolShed", Vector2(-20, -6), 0, Vector2(6, 5), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "flat", "roof_mat": "rust",
		"openings": [["E", 0, "door"], ["N", -1, "window"]],
	})
	var bench := k.prop("workbench", "FarmWorkbench", k.at(t, Vector3(-0.6, 0, 1.6)), 180, "CraftingStations")
	bench.name = "FarmWorkbench"
	k.container_at_wall("crate", "ShedCrate", t, "N", 1.3, "farm_shed", "Shed Crate")
	k.container_at_wall("footlocker", "ToolChest", t, "W", -0.9, "tool_chest", "Tool Chest")
	k.pickup("spring", 2, "ShedSprings", t, Vector3(1.4, 0, -0.2))
	# Pump house by the water tower (the farm's future water)
	var p := k.building("PumpHouse", Vector2(10, 22), 0, Vector2(5, 4), {
		"wall": "concrete", "floor": "concrete_plain", "roof": "flat",
		"openings": [["W", 0, "door"], ["S", 1, "window"]],
	})
	k.prop("water_tank", "PumpTank", k.at(p, Vector3(1.2, 0, -0.6)), 0)
	k.container_at_wall("footlocker", "PumpParts", p, "N", -1.0, "garage_parts", "Pump Parts")
	# Water tower: a deck at 8 m with a ladder, a lookout over the fields
	var tower := k.solid_body(k.groups["Buildings"], "WaterTower", Transform3D(Basis.IDENTITY, Vector3(-16, 0, 24)))
	for leg in [Vector3(-1.8, 4, -1.8), Vector3(1.8, 4, -1.8), Vector3(-1.8, 4, 1.8), Vector3(1.8, 4, 1.8)]:
		k.box(tower, "Leg", Vector3(0.3, 8.0, 0.3), leg, "wood")
	k.box(tower, "Deck", Vector3(5.0, 0.2, 5.0), Vector3(0, 7.9, 0), "wood")
	for r: Array in [[Vector3(0, 8.5, -2.45), Vector3(5, 1.0, 0.1)], [Vector3(-2.45, 8.5, 0), Vector3(0.1, 1.0, 5)], [Vector3(2.45, 8.5, 0), Vector3(0.1, 1.0, 5)],
			[Vector3(-1.6, 8.5, 2.45), Vector3(1.8, 1.0, 0.1)], [Vector3(1.6, 8.5, 2.45), Vector3(1.8, 1.0, 0.1)]]:
		k.box(tower, "Rail", r[1], r[0], "wood")
	var tank := MeshInstance3D.new()
	tank.name = "Tank"
	var cm := CylinderMesh.new()
	cm.top_radius = 1.5
	cm.bottom_radius = 1.5
	cm.height = 2.8
	tank.mesh = cm
	tank.material_override = k.mat("wood")
	tank.position = Vector3(0, 9.4, -0.6)
	tower.add_child(tank)
	var tcs := CollisionShape3D.new()
	tcs.name = "TankCol"
	var tsh := CylinderShape3D.new()
	tsh.radius = 1.5
	tsh.height = 2.8
	tcs.shape = tsh
	tcs.position = tank.position
	tower.add_child(tcs)
	k.ladder("TowerLadder", tower, Vector3(0, 0, 2.5), 0, 8.0)
	k.container("crate", "LookoutStash", tower, Vector3(-1.3, 8.0, 1.5), 90, "sniper_stash", "Lookout Stash")
	# Silo, chicken coop, tractor wreck, fuel
	var silo := k.solid_body(k.groups["Buildings"], "Silo", Transform3D(Basis.IDENTITY, Vector3(26, 0, -24)))
	var sm := MeshInstance3D.new()
	sm.name = "Body"
	var scm := CylinderMesh.new()
	scm.top_radius = 3.0
	scm.bottom_radius = 3.0
	scm.height = 12.0
	sm.mesh = scm
	sm.material_override = k.mat("corrugated")
	sm.position.y = 6.0
	silo.add_child(sm)
	var scs := CollisionShape3D.new()
	scs.name = "BodyCol"
	var ssh := CylinderShape3D.new()
	ssh.radius = 3.0
	ssh.height = 12.0
	scs.shape = ssh
	scs.position.y = 6.0
	silo.add_child(scs)
	var c := k.building("ChickenCoop", Vector2(-24, 14), 0, Vector2(4, 3), {
		"wall": "wood", "floor": "", "roof": "flat", "roof_mat": "rust", "height": 2.6,
		"openings": [["E", 0, "door"]],
	})
	k.pile("furniture", "CoopNests", c, Vector3(-0.6, 0, 0), 90)
	var tractor := k.solid_body(k.groups["Props"], "TractorWreck", Transform3D(Basis(Vector3.UP, deg_to_rad(35)), Vector3(-2, 0, -8)))
	k.box(tractor, "Body", Vector3(1.8, 1.4, 3.2), Vector3(0, 1.0, 0), "rust")
	k.box(tractor, "Cab", Vector3(1.4, 1.2, 1.4), Vector3(0, 2.2, -0.6), "rust")
	k.pile("scrap", "TractorScrap", null, Vector3(1.5, 0, -10.5), 20)
	k.pile("scrap", "RustyMachinery", null, Vector3(30, 0, -12), -30)
	k.pile("appliance", "OldStove", null, Vector3(-15, 0, 14), 90)
	k.pile("pallet", "YardPallet", null, Vector3(4, 0, 6), 45)
	k.prop("fuel_drums", "FarmDrums", Vector3(22, 0, -2), 0)
	k.pickup("fuel", 1, "YardFuel", null, Vector3(23.6, 0, 0.2))
	k.pickup("metal_pipe", 1, "YardPipe", null, Vector3(-4, 0, -5))
	k.pickup("wood_plank", 3, "YardPlanks", null, Vector3(6.5, 0, 4.5))
	# Fields of crops, and a fence along the lane
	_fields(k)
	var fence := k.solid_body(k.groups["Props"], "LaneFence")
	for side in [-1.0, 1.0]:
		k.box(fence, "Rail", Vector3(0.1, 0.12, 20), Vector3(side * 4.0 - 6, 0.95, 32), "wood")
		k.box(fence, "RailLow", Vector3(0.1, 0.12, 20), Vector3(side * 4.0 - 6, 0.5, 32), "wood")
	k.spawner("RaiderSpawner", "raider", 2, 60.0, [Vector2(-32, -2), Vector2(40, -30)])
	_ash_creek_settlement(k, f, b)
	return k


## Ash Creek Farms as a settlement (Increment 19): the notice board where you
## claim it, the pump, the Farm Store (barn) and the Armory Locker
## (farmhouse), beds for four, and the spots settlers work and stand guard.
## The Settlement sits at the farm's centre (its defended area is round it).
func _ash_creek_settlement(k: Kit, house: StaticBody3D, barn: StaticBody3D) -> void:
	var st := Settlement.new()
	st.name = "Settlement"
	k.root.add_child(st)
	# Notice board in front of the porch, facing the lane
	var board_at := Vector3(-4.2, 0, 15.4)
	var board := k.solid_body(st, "NoticeBoard", Transform3D(Basis.IDENTITY, board_at))
	for x in [-0.55, 0.55]:
		k.box(board, "Post", Vector3(0.1, 1.9, 0.1), Vector3(x, 0.95, 0), "wood")
	k.box(board, "Board", Vector3(1.3, 0.8, 0.06), Vector3(0, 1.4, 0.03), "wood")
	k.box(board, "Notice", Vector3(0.9, 0.55, 0.01), Vector3(0, 1.42, 0.065), "paint_white")
	k.box(board, "Roof", Vector3(1.5, 0.06, 0.36), Vector3(0, 1.92, 0.05), "rust")
	var claim := ClaimPoint.new()
	claim.name = "ClaimPoint"
	claim.position = board_at + Vector3(0, 1.4, 0.1)
	st.add_child(claim)
	_area(claim, Vector3(1.4, 1.0, 0.4))
	# The pump, in the pump house in front of the water tank (the door's west)
	var pump_at := Vector3(9.6, 0, 23.1)  # clear of the parts footlocker on the north wall
	var pump_body := k.solid_body(st, "PumpHead", Transform3D(Basis.IDENTITY, pump_at))
	k.box(pump_body, "Base", Vector3(0.5, 0.2, 0.5), Vector3(0, 0.1, 0), "metal_dark")
	k.box(pump_body, "Column", Vector3(0.22, 0.9, 0.22), Vector3(0, 0.65, 0), "rust")
	k.box(pump_body, "Head", Vector3(0.34, 0.24, 0.3), Vector3(0, 1.2, 0), "rust")
	k.box(pump_body, "Handle", Vector3(0.06, 0.06, 0.7), Vector3(0, 1.32, 0.3), "metal_dark", 0.0, false)
	k.box(pump_body, "Spout", Vector3(0.1, 0.1, 0.3), Vector3(-0.2, 1.05, 0), "rust", 90.0, false)
	var pump := WaterPump.new()
	pump.name = "WaterPump"
	pump.position = pump_at + Vector3(0, 0.9, 0)
	st.add_child(pump)
	_area(pump, Vector3(0.8, 1.6, 1.0))
	# Farm Store in the barn; Armory Locker in the farmhouse kitchen
	var store := k.scene("crate").instantiate() as Node3D
	store.name = "FarmStore"
	store.position = k.at(barn, k.against(barn, "W", -2.0, 0.44))
	store.rotation.y = k.yaw_in(barn, Kit.facing_from("W"))
	store.set("container_name", "Farm Store")
	store.set("object_name", "Farm Store")
	st.add_child(store)
	var armory := k.scene("locker").instantiate() as Node3D
	armory.name = "Armory"
	armory.position = k.at(house, k.against(house, "E", -1.8, 0.39))
	armory.rotation.y = k.yaw_in(house, Kit.facing_from("E"))
	armory.set("container_name", "Armory Locker")
	armory.set("object_name", "Armory Locker")
	st.add_child(armory)
	# Beds for four in the farmhouse's west room (clear of the bedroom chest)
	for i in 3:
		_bed(k, "SettlerBed%d" % i, house, [Vector3(-3.5, 0, -0.9), Vector3(-3.5, 0, 0.8), Vector3(-1.2, 0, -2.6)][i])
	# Where farmers work, guards stand, newcomers walk in and everyone gathers
	_markers(st, "FarmSpots", [Vector3(-38, 0, -20), Vector3(-34, 0, -30), Vector3(-42, 0, -14), Vector3(-38, 0, 34),
		Vector3(40, 0, -6), Vector3(40, 0, 12), Vector3(2, 0, -48), Vector3(16, 0, -48)])
	_markers(st, "GuardPosts", [Vector3(-6, 0, 17.5), Vector3(-6, 0, 30), Vector3(14, 0, -3.5), Vector3(-16, 0, 28),
		Vector3(21, 0, 5)])
	_markers(st, "", [["ArrivalPoint", Vector3(-6, 0, 44)], ["Hangout", Vector3(-8, 0, 16.5)]])
	var people := Node3D.new()
	people.name = "Settlers"
	st.add_child(people)


func _area(area: Area3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	area.add_child(cs)


## A group of Marker3Ds under `parent` (or loose ones, named, if `group` is "").
func _markers(parent: Node3D, group: String, points: Array) -> void:
	var holder := parent
	if group != "":
		holder = Node3D.new()
		holder.name = group
		parent.add_child(holder)
	var i := 0
	for p in points:
		var m := Marker3D.new()
		if p is Array:
			m.name = p[0]
			m.position = p[1]
		else:
			m.name = "%s%d" % [group.trim_suffix("s"), i]
			m.position = p
		holder.add_child(m)
		i += 1


func _fields(k: Kit) -> void:
	var fields := Node3D.new()
	fields.name = "Fields"
	k.root.add_child(fields)
	var plots := [[Vector2(-38, -24), Vector2(20, 30), "crop"], [Vector2(-38, 30), Vector2(20, 18), "crop_green"],
		[Vector2(40, 4), Vector2(14, 36), "crop"], [Vector2(8, -48), Vector2(44, 14), "crop_green"]]
	var plant := CylinderMesh.new()
	plant.top_radius = 0.04
	plant.bottom_radius = 0.28
	plant.height = 0.9
	plant.radial_segments = 5
	plant.rings = 0
	plant.cap_top = false
	plant.cap_bottom = false
	var i := 0
	for pl in plots:
		var c: Vector2 = pl[0]
		var s: Vector2 = pl[1]
		var soil := MeshInstance3D.new()
		soil.name = "Soil%d" % i
		var pm := PlaneMesh.new()
		pm.size = s
		soil.mesh = pm
		soil.material_override = k.mat("field_soil")
		soil.position = Vector3(c.x, 0.012, c.y)
		fields.add_child(soil)
		var xf: Array[Transform3D] = []
		var row := -s.x * 0.5 + 1.0
		while row < s.x * 0.5 - 0.5:
			var along := -s.y * 0.5 + 1.0
			while along < s.y * 0.5 - 0.5:
				if k.rng.randf() < 0.82:
					var hh := k.rng.randf_range(0.5, 1.2)
					xf.append(Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU).scaled(Vector3(1, hh, 1)), Vector3(c.x + row + k.rng.randf_range(-0.15, 0.15), 0.45 * hh, c.y + along)))
				along += 0.7
			row += 1.3
		k.merged(fields, "Crops%d" % i, plant, xf, pl[2], 220.0)
		i += 1


# ================================================================ Smuggler's Gulch

func _smugglers_gulch() -> Kit:
	var k := Kit.new("SmugglersGulch", "Smuggler's Gulch", 303)
	# Red rock walls in a ring, open to the south-south-east where the trail comes in
	var walls := k.group("RockWalls", true)
	var gap := atan2(23.0, 10.0)
	var n := 0
	var ang := 0.0
	while ang < TAU:
		if absf(wrapf(ang - gap, -PI, PI)) > 0.42:
			var r := k.rng.randf_range(50.0, 60.0)
			var w := k.rng.randf_range(16.0, 24.0)
			var hh := k.rng.randf_range(12.0, 19.0)
			k.rock(walls, "Wall%d" % n, Vector3(cos(ang) * r, 0, sin(ang) * r), rad_to_deg(-ang), Vector3(w * 0.35, hh / 0.42, w * 0.5), "rock_red", n % 8)
			n += 1
		ang += 0.33
	# The smugglers' den: a corrugated warehouse at the back of the hollow
	var d := k.building("Den", Vector2(0, -18), 0, Vector2(14, 8), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "flat", "roof_mat": "rust",
		"openings": [["S", -3, "wide"], ["E", 0, "door"], ["N", 3, "window"], ["W", 0, "window"]],
	})
	k.container_at_wall("crate", "ContrabandA", d, "N", -4.5, "smuggler_stash", "Contraband")
	k.container_at_wall("crate", "ContrabandB", d, "N", -2.8, "smuggler_stash", "Contraband")
	k.container_at_wall("locker", "GunCabinet", d, "W", -2.4, "smuggler_guns", "Gun Cabinet")
	var wb := k.prop("weapons_bench", "DenWeaponsBench", k.at(d, Vector3(4.2, 0, -3.0)), 0, "CraftingStations")
	wb.name = "DenWeaponsBench"
	k.prop("wood_crate", "DenCrateA", k.at(d, Vector3(5.6, 0, 2.6)), 10)
	k.prop("wood_crate", "DenCrateB", k.at(d, Vector3(4.4, 0, 2.8)), -15)
	k.pile("pallet", "DenPallet", d, Vector3(-5.4, 0, 2.4), 30)
	k.pickup("rifle_ammo", 20, "DenRifleAmmo", d, Vector3(1.0, 0, -2.6))
	k.sign("DenGraffiti", P3 + "graffiti_graffiti_raider_1.tres", d, Vector3(2.5, 2.0, 4.03), 0, Vector2(2.2, 2.2))
	# Shacks
	var a := k.building("ShackA", Vector2(-20, -4), 0, Vector2(5, 4), {
		"wall": "wood", "floor": "wood", "roof": "flat", "roof_mat": "corrugated", "openings": [["E", 0, "door"], ["N", 0, "window"]],
	})
	_bed(k, "ShackABed", a, Vector3(-0.8, 0, 1.0))
	k.container_at_wall("footlocker", "ShackAChest", a, "W", -0.8, "town_household", "Chest")
	var bs := k.building("ShackB", Vector2(20, -10), 0, Vector2(5, 4), {
		"wall": "wood", "floor": "wood", "roof": "flat", "roof_mat": "corrugated", "openings": [["W", 0, "door"], ["S", 0, "window"]],
	})
	k.container_at_wall("crate", "AmmoCrate", bs, "E", 0.0, "ammo_crate", "Ammo Crate")
	k.pickup("gunpowder", 2, "ShackBPowder", bs, Vector3(-0.6, 0, -1.2))
	var cs := k.building("ShackC", Vector2(-14, 18), 0, Vector2(5, 4), {
		"wall": "wood", "floor": "wood", "roof": "flat", "roof_mat": "corrugated", "openings": [["N", 0, "door"], ["E", 0, "window"]],
	})
	_bed(k, "ShackCBed", cs, Vector3(-0.8, 0, 1.0))
	k.container_at_wall("footlocker", "ShackCLocker", cs, "S", 1.4, "footlocker", "Footlocker")
	k.pile("furniture", "ShackCJunk", cs, Vector3(-1.4, 0, -0.9), 60)
	# Lookout tower over the entrance
	var lt := k.solid_body(k.groups["Buildings"], "Lookout", Transform3D(Basis.IDENTITY, Vector3(22, 0, 18)))
	for leg in [Vector3(-1.5, 2.5, -1.5), Vector3(1.5, 2.5, -1.5), Vector3(-1.5, 2.5, 1.5), Vector3(1.5, 2.5, 1.5)]:
		k.box(lt, "Leg", Vector3(0.25, 5.0, 0.25), leg, "wood")
	k.box(lt, "Deck", Vector3(3.6, 0.2, 3.6), Vector3(0, 4.9, 0), "wood")
	for r: Array in [[Vector3(0, 5.5, -1.75), Vector3(3.6, 1.0, 0.1)], [Vector3(-1.75, 5.5, 0), Vector3(0.1, 1.0, 3.6)], [Vector3(1.75, 5.5, 0), Vector3(0.1, 1.0, 3.6)]]:
		k.box(lt, "Rail", r[1], r[0], "wood")
	k.ladder("LookoutLadder", lt, Vector3(0, 0, 1.8), 0, 5.0)
	k.container("crate", "LookoutCache", lt, Vector3(0.6, 5.0, -0.9), 0, "smuggler_lookout", "Lookout Cache")
	# Shipping containers, tents, fires, sandbags at the way in
	k.prop("shipping_container", "ContainerRed", Vector3(12, 0, 6), 80)
	k.prop("shipping_container", "ContainerBlue", Vector3(16, 0, -1), 75)
	k.prop("shipping_container", "ContainerOlive", Vector3(-6, 0, 24), 10)
	for t: Array in [[Vector3(0, 0, 4), 20.0], [Vector3(-7, 0, -2), 70.0], [Vector3(5, 0, -6), -30.0]]:
		k.tent("Tent", t[0], t[1])
	k.prop("burning_barrel", "FireA", Vector3(-1, 0, 10), 0)
	k.prop("burning_barrel", "FireB", Vector3(8, 0, 14), 0)
	for i in 3:
		k.prop("sandbags", "EntranceSandbags%d" % i, Vector3(4 + i * 2.6, 0, 30 - i * 0.4), -20)
	k.prop("jersey", "EntranceBarrier", Vector3(16, 0, 28), 60)
	_sign_board(k, "KeepOut", P3 + "sign_sign_keep_out.tres", Vector3(10, 0, 40), 200, Vector2(1.8, 0.7))
	# The raiders' own cache behind the den
	k.container("crate", "RaiderCache", null, Vector3(-9, 0, -26), 0, "raider_camp_cache", "Raider Cache")
	k.pile("scrap", "ScrapA", null, Vector3(-24, 0, 6), 10)
	k.pile("scrap", "ScrapB", null, Vector3(24, 0, -2), -40)
	k.pile("scrap", "ScrapC", null, Vector3(-10, 0, 30), 70)
	k.pile("pallet", "PalletA", null, Vector3(-28, 0, -10), 15)
	k.pile("pallet", "PalletB", null, Vector3(10, 0, -28), -25)
	k.pile("furniture", "CampChairs", null, Vector3(2, 0, 12.5), 0)
	k.pickup("pistol_ammo", 12, "FirePistolAmmo", null, Vector3(-2.5, 0, 12))
	k.pickup("chemicals", 2, "CampChemicals", null, Vector3(-18, 0, 8))
	k.pickup("electronics", 1, "CampElectronics", null, Vector3(18, 0, 10))
	k.pickup("shotgun_shells", 8, "CampShells", null, Vector3(-4, 0, -9))
	k.spawner("CampSpawner", "veteran", 3, 120.0, [Vector2(-4, 6), Vector2(10, -9), Vector2(-12, 0)])
	k.spawner("RaiderSpawner", "raider", 3, 45.0, [Vector2(14, 24), Vector2(-20, 24), Vector2(22, -14)])
	return k


# ================================================================ Black Ridge Mine

func _black_ridge() -> Kit:
	var k := Kit.new("BlackRidgeMine", "Black Ridge Mine", 404)
	# Headframe over the shaft, with a working deck at 9 m
	var hf := k.solid_body(k.groups["Buildings"], "Headframe")
	for leg in [Vector3(-2.5, 9, -2.5), Vector3(2.5, 9, -2.5), Vector3(-2.5, 9, 2.5), Vector3(2.5, 9, 2.5)]:
		k.box(hf, "Leg", Vector3(0.5, 18, 0.5), leg, "rust")
	for y in [6.0, 12.0]:
		for b: Array in [[Vector3(0, y, -2.5), Vector3(5.5, 0.35, 0.35)], [Vector3(0, y, 2.5), Vector3(5.5, 0.35, 0.35)],
				[Vector3(-2.5, y, 0), Vector3(0.35, 0.35, 5.5)], [Vector3(2.5, y, 0), Vector3(0.35, 0.35, 5.5)]]:
			k.box(hf, "Brace", b[1], b[0], "rust", 0.0, false)
	k.box(hf, "WorkDeck", Vector3(6.2, 0.25, 6.2), Vector3(0, 8.875, 0), "metal_dark")
	k.box(hf, "Top", Vector3(7, 0.5, 7), Vector3(0, 18.25, 0), "metal_dark")
	k.box(hf, "Sheave", Vector3(0.4, 4.6, 4.6), Vector3(0, 20.4, 0), "metal_dark", 0.0, false)
	var stay := k.box(hf, "BackStay", Vector3(0.5, 20, 0.5), Vector3(7.5, 9, 0), "rust", 0.0, false)
	stay.rotation.z = deg_to_rad(28)
	k.box(hf, "ShaftCollar", Vector3(4.4, 0.25, 4.4), Vector3(0, 0.125, 0), "concrete")
	k.ladder("HeadframeLadder", hf, Vector3(0, 0, 3.1), 0, 9.0)
	k.container("crate", "HeadframeCrate", hf, Vector3(-1.6, 9.0, -1.6), 0, "mine_supplies", "Winding Gear Crate")
	# Hoist house beside it
	var hh := k.building("HoistHouse", Vector2(15, 0), 0, Vector2(8, 10), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "pitched", "roof_mat": "rust",
		"openings": [["W", 2, "door"], ["E", -2, "door"], ["N", 0, "window"], ["S", 0, "window"]],
	})
	k.fixture("WinchDrum", hh, Vector3(0, 0, -1.5), Vector3(3.0, 1.6, 2.0), "rust")
	k.fixture("ControlDesk", hh, Vector3(2.6, 0, 3.2), Vector3(1.4, 1.0, 0.7), "metal_dark")
	k.container_at_wall("crate", "HoistSupplies", hh, "S", -2.2, "mine_supplies", "Mine Supplies")
	k.container_at_wall("footlocker", "HoistToolChest", hh, "W", -3.4, "tool_chest", "Tool Chest")
	k.pickup("metal_plate", 1, "HoistPlate", hh, Vector3(-1.8, 0, 2.6))
	# Mine office: two rooms
	var o := k.building("MineOffice", Vector2(16, -20), 0, Vector2(10, 7), {
		"wall": "wood", "floor": "wood", "roof": "pitched",
		"openings": [["S", 2, "door"], ["S", -2.5, "window"], ["N", 2.5, "window"], ["W", 0, "window"], ["E", 0, "window"]],
		"inner": [[Vector2(-1, -3.35), Vector2(-1, 3.35), [3.35]]],
	})
	k.fixture("ForemanDesk", o, Vector3(2.2, 0, -1.8), Vector3(1.6, 0.8, 0.8), "wood")
	k.container_at_wall("footlocker", "ForemansLocker", o, "E", 2.0, "mine_office", "Foreman's Locker")
	k.container_at_wall("locker", "MineSafe", o, "W", -2.0, "bank_safe", "Mine Safe")
	k.pile("furniture", "OfficeChair", o, Vector3(-3.0, 0, 1.6), 25)
	k.pickup("rifle_ammo", 15, "OfficeAmmo", o, Vector3(2.2, 0.8, -1.8))
	# Workshop with a workbench
	var w := k.building("Workshop", Vector2(-6, 20), 0, Vector2(12, 8), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "flat", "roof_mat": "rust",
		"openings": [["E", 0, "wide"], ["N", -3, "window"], ["S", -3, "window"]],
	})
	var bench := k.prop("workbench", "MineWorkbench", k.at(w, Vector3(-3.0, 0, -3.0)), 0, "CraftingStations")
	bench.name = "MineWorkbench"
	k.container_at_wall("crate", "PartsBin", w, "S", 1.0, "garage_parts", "Parts Bin")
	k.pile("scrap", "WorkshopScrap", w, Vector3(2.8, 0, -2.4), 30)
	k.pile("appliance", "OldCompressor", w, Vector3(-4.6, 0, 2.4), 90)
	k.pickup("spring", 2, "WorkshopSprings", w, Vector3(-1.0, 0, 1.6))
	# Bunkhouse
	var bh := k.building("Bunkhouse", Vector2(16, 22), 0, Vector2(10, 6), {
		"wall": "wood", "floor": "wood", "roof": "pitched",
		"openings": [["W", 0, "door"], ["N", -2.5, "window"], ["N", 2.5, "window"], ["S", 2.5, "window"]],
	})
	for i in 3:
		_bed(k, "Bunk%d" % i, bh, Vector3(-2.4 + i * 2.4, 0, -1.6), 90)
	k.container_at_wall("footlocker", "BunkLockerA", bh, "S", -1.8, "footlocker", "Footlocker")
	k.container_at_wall("footlocker", "BunkLockerB", bh, "E", 1.6, "footlocker", "Footlocker")
	# The mine tunnel, into the ridge to the west
	var tun := k.solid_body(k.groups["Buildings"], "Tunnel", Transform3D(Basis.IDENTITY, Vector3(-27, 0, -6)))
	k.box(tun, "WallN", Vector3(14, 3.2, 0.5), Vector3(0, 1.6, -1.85), "rock_dark")
	k.box(tun, "WallS", Vector3(14, 3.2, 0.5), Vector3(0, 1.6, 1.85), "rock_dark")
	k.box(tun, "End", Vector3(0.5, 3.2, 4.2), Vector3(-7.25, 1.6, 0), "rock_dark")
	k.box(tun, "Ceiling", Vector3(14.5, 0.4, 4.2), Vector3(0, 3.4, 0), "rock_dark")
	for x in [6.6, 2.0, -2.6]:
		k.box(tun, "TimberL", Vector3(0.25, 3.0, 0.25), Vector3(x, 1.5, -1.45), "wood", 0.0, false)
		k.box(tun, "TimberR", Vector3(0.25, 3.0, 0.25), Vector3(x, 1.5, 1.45), "wood", 0.0, false)
		k.box(tun, "TimberTop", Vector3(0.25, 0.25, 3.2), Vector3(x, 3.05, 0), "wood", 0.0, false)
	k.box(tun, "TrackL", Vector3(18, 0.08, 0.1), Vector3(4, 0.04, -0.55), "rust", 0.0, false)
	k.box(tun, "TrackR", Vector3(18, 0.08, 0.1), Vector3(4, 0.04, 0.55), "rust", 0.0, false)
	k.box(tun, "MineCart", Vector3(1.6, 1.1, 1.1), Vector3(-1.0, 0.6, 0), "rust")
	# Work lamps strung along the timbers
	k.lamp(tun, "Portal", Vector3(4.3, 2.8, 0), 0.9, 6.0, true)
	k.lamp(tun, "Deep", Vector3(-4.3, 2.8, 0), 0.9, 6.0, true)
	# The ridge over and round it: solid rocks that leave the tunnel clear
	var ridge := k.group("Ridge", true)
	for r: Array in [[Vector3(-30, -0.5, -15), Vector3(9, 8, 6)], [Vector3(-30, -0.5, 3), Vector3(9, 8, 6)],
			[Vector3(-41, -0.5, -6), Vector3(6, 8, 7)], [Vector3(-29, 4.4, -6), Vector3(8, 3, 4.5)]]:
		k.rock(ridge, "Rock", r[0], 0, r[1], "rock_dark", 2, 0.8)
	k.box(tun, "PortalLintel", Vector3(0.6, 0.6, 4.6), Vector3(7.0, 3.3, 0), "wood", 0.0, false)
	k.container("crate", "ExplosivesCrate", tun, Vector3(-6.4, 0, 0.8), 90, "mine_explosives", "Explosives Crate")
	k.pickup("gunpowder", 2, "TunnelPowder", tun, Vector3(-4.6, 0, -1.0))
	tun.set_meta("doors", [[tun.transform * Vector3(7.0, 0, 0), Vector3(1, 0, 0)]])
	tun.set_meta("size", Vector2(14, 3.2))
	# Conveyor, hopper and spoil heaps
	var plant := k.solid_body(k.groups["Props"], "OrePlant")
	var conveyor := k.box(plant, "Conveyor", Vector3(2, 0.8, 24), Vector3(-10, 5, -6), "metal_dark", 30.0, false)
	conveyor.rotation.x = deg_to_rad(-18)
	k.box(plant, "Hopper", Vector3(4, 4, 4), Vector3(-16, 2, -18), "rust", 30.0)
	k.rock(k.groups["Props"], "SpoilHeap", Vector3(-12, -0.3, 8), 30, Vector3(6, 5, 5), "rock_dark", 3, 0.85)
	k.prop("fuel_drums", "MineDrums", Vector3(26, 0, -8), 20)
	k.prop("truck", "OreTruck", Vector3(30, 0, 8), 160)
	k.prop("wood_crate", "YardCrate", Vector3(6, 0, -10), 30)
	k.pile("scrap", "ScrapA", null, Vector3(-4, 0, -14), 0)
	k.pile("scrap", "ScrapB", null, Vector3(26, 0, 12), 40)
	k.pile("scrap", "ScrapC", null, Vector3(-18, 0, 20), -20)
	k.pile("pallet", "PalletA", null, Vector3(6, 0, 12), 10)
	k.pile("pallet", "PalletB", null, Vector3(8, 0, 9.5), -30)
	k.pile("pallet", "PalletC", null, Vector3(28, 0, -14), 60)
	k.pickup("fuel", 1, "DrumFuel", null, Vector3(24.5, 0, -6.2))
	k.pickup("metal_pipe", 2, "YardPipes", null, Vector3(-1, 0, 12))
	k.pickup("gunpowder", 1, "YardPowder", null, Vector3(10, 0, -8))
	k.spawner("RaiderSpawner", "raider", 4, 45.0, [Vector2(26, 2), Vector2(-6, -24), Vector2(2, 30), Vector2(-22, 12)])
	return k


# ================================================================ Northwatch Outpost

func _northwatch() -> Kit:
	var k := Kit.new("NorthwatchOutpost", "Northwatch Outpost", 505)
	# The perimeter, its gate facing the road from the south
	var per := k.solid_body(k.groups["Buildings"], "Perimeter")
	k.box(per, "WallN", Vector3(36, 3.2, 0.6), Vector3(0, 1.6, -18), "concrete")
	k.box(per, "WallW", Vector3(0.6, 3.2, 36), Vector3(-18, 1.6, 0), "concrete")
	k.box(per, "WallE", Vector3(0.6, 3.2, 36), Vector3(18, 1.6, 0), "concrete")
	k.box(per, "WallSW", Vector3(15, 3.2, 0.6), Vector3(-10.5, 1.6, 18), "concrete")
	k.box(per, "WallSE", Vector3(15, 3.2, 0.6), Vector3(10.5, 1.6, 18), "concrete")
	k.box(per, "GatePostW", Vector3(0.8, 4, 0.8), Vector3(-3.2, 2, 18), "concrete_stained")
	k.box(per, "GatePostE", Vector3(0.8, 4, 0.8), Vector3(3.2, 2, 18), "concrete_stained")
	k.box(per, "Barrier", Vector3(6, 0.15, 0.15), Vector3(0, 1.1, 18.6), "hazard", 0.0, false)
	per.set_meta("doors", [[Vector3(0, 0, 18), Vector3(0, 0, 1)]])
	per.set_meta("size", Vector2(36, 36))
	# Command post
	var c := k.building("CommandPost", Vector2(10, -10), 0, Vector2(8, 7), {
		"wall": "concrete", "floor": "concrete_plain", "roof": "flat",
		"openings": [["S", 0, "door"], ["W", 0, "window"], ["E", 0, "window"], ["N", -2, "window"]],
	})
	k.fixture("MapTable", c, Vector3(-1.2, 0, -1.0), Vector3(1.8, 0.85, 1.0), "wood")
	k.prop("radio", "CommsRadio", k.at(c, Vector3(2.6, 0, -2.7)), 0)
	k.container_at_wall("crate", "CommsGear", c, "N", 1.6, "comms_gear", "Comms Gear")
	k.container_at_wall("footlocker", "OfficersLocker", c, "W", 2.2, "officer_locker", "Officer's Locker")
	k.pickup("electronics", 1, "TableElectronics", c, Vector3(-1.2, 0.85, -1.0))
	# Barracks
	var b := k.building("Barracks", Vector2(-9, -11), 0, Vector2(12, 6), {
		"wall": "concrete_stained", "floor": "concrete_plain", "roof": "flat",
		"openings": [["S", 2, "door"], ["S", -3.5, "window"], ["N", -3, "window"], ["N", 3, "window"]],
	})
	for i in 4:
		_bed(k, "Bunk%d" % i, b, Vector3(-4.6 + i * 2.6, 0, -1.6), 90)
	k.container_at_wall("footlocker", "BarracksLockerA", b, "W", 1.4, "footlocker", "Footlocker")
	k.container_at_wall("footlocker", "BarracksLockerB", b, "E", 1.4, "footlocker", "Footlocker")
	k.container_at_wall("crate", "BarracksCrate", b, "S", 4.6, "garrison_crate", "Military Crate")
	k.pickup("medkit", 1, "BarracksMedkit", b, Vector3(0.6, 0.55, -1.6))
	# Armory, with a gun bench (Increment 16.6)
	var a := k.building("Armory", Vector2(-12, 9), 0, Vector2(8, 6), {
		"wall": "concrete", "floor": "concrete_plain", "roof": "flat",
		"openings": [["E", 0, "door"], ["S", -1.5, "window"]],
	})
	k.container_at_wall("locker", "ArmoryLockerA", a, "W", -1.2, "garrison_armory", "Weapons Locker")
	k.container_at_wall("locker", "ArmoryLockerB", a, "W", 1.0, "garrison_armory", "Weapons Locker")
	k.container_at_wall("crate", "ArmoryAmmo", a, "N", -2.2, "garrison_ammo", "Ammo Crate")
	var gun_bench := k.prop("weapons_bench", "ArmoryWeaponsBench", k.at(a, Vector3(1.3, 0, -2.0)), 0, "CraftingStations")
	gun_bench.name = "ArmoryWeaponsBench"
	k.pickup("rifle_ammo", 30, "ArmoryRifleAmmo", a, Vector3(2.4, 0, 1.9))
	# Stores hut
	var s := k.building("Stores", Vector2(11, 9), 0, Vector2(6, 5), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "flat", "roof_mat": "rust",
		"openings": [["W", 0, "door"], ["N", 1, "window"]],
	})
	k.container_at_wall("crate", "StoresCrate", s, "E", -1.0, "quartermaster", "Quartermaster's Crate")
	k.pile("appliance", "BrokenRadio", s, Vector3(1.6, 0, 1.4), -90)
	# Guard towers in two corners (their ladders face the yard)
	k.prop("guard_tower", "TowerNE", Vector3(13.5, 0, -2.0), 180, "Towers")
	k.prop("guard_tower", "TowerSW", Vector3(-13.5, 0, 0.5), 0, "Towers")
	k.pickup("rifle_308", 8, "TowerRounds", null, Vector3(-13.5, 4.6, 0.0))
	# Radio mast and dish
	var mast := k.solid_body(k.groups["Buildings"], "Mast", Transform3D(Basis.IDENTITY, Vector3(1, 0, -14.5)))
	k.box(mast, "Pole", Vector3(0.5, 30, 0.5), Vector3(0, 15, 0), "metal_dark")
	var dish := k.box(mast, "Dish", Vector3(3.2, 3.2, 0.25), Vector3(0, 24, 0.6), "metal_dark", 0.0, false)
	dish.rotation.x = deg_to_rad(-30)
	k.box(mast, "Shack", Vector3(2.4, 2.2, 2.0), Vector3(2.6, 1.1, 0.4), "olive")
	# The yard and the way in
	k.prop("truck", "PatrolTruck", Vector3(0, 0, 3), 90)
	k.prop("fuel_drums", "YardDrums", Vector3(-6, 0, 14), 0)
	k.prop("sandbags", "GateSandbagsW", Vector3(-5.5, 0, 21), 0)
	k.prop("sandbags", "GateSandbagsE", Vector3(5.5, 0, 21), 0)
	k.prop("jersey", "RoadBlock", Vector3(-1.5, 0, 28), 15)
	k.pile("scrap", "ScrapA", null, Vector3(-15, 0, 15.5), 0)
	k.pile("scrap", "ScrapB", null, Vector3(24, 0, 6), 40)
	k.pile("pallet", "PalletA", null, Vector3(4.5, 0, 14), 10)
	k.pile("pallet", "PalletB", null, Vector3(-3.5, 0, -6), -20)
	k.pile("appliance", "DeadGenerator", null, Vector3(6, 0, -15.6), 0)
	k.pickup("metal_plate", 1, "YardPlate", null, Vector3(-2, 0, 9))
	k.spawner("GarrisonSpawner", "veteran", 2, 120.0, [Vector2(-2, -4), Vector2(6, 12)])
	k.spawner("RaiderSpawner", "raider", 2, 45.0, [Vector2(-10, 30), Vector2(14, 32)])
	return k
