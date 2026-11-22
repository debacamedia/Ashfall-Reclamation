extends "res://tools/build_sites.gd"
## Builds the mid zone's seven places as real sites (Increment 26), the way
## build_sites.gd built the early zone's: buildings to go into, furniture,
## searchable containers, salvage, pickups, ladders to high ground and
## raiders. The mid zone is tougher than the early one: Raider Veterans in
## most places, and the Scorch Marauders (scrap-plated, tools/build_marauder.gd)
## at Red Mesa, Cinder Quarry and their camp, Scorch. Its loot is richer.
##
##   levels/red_mesa/red_mesa.tscn
##   levels/dry_river_pump_station/dry_river_pump_station.tscn
##   levels/cinder_quarry/cinder_quarry.tscn
##   levels/iron_vein_rail_yard/iron_vein_rail_yard.tscn
##   levels/dusthaven/dusthaven.tscn
##   levels/broken_spur_truck_stop/broken_spur_truck_stop.tscn
##   levels/raider_camp_scorch/raider_camp_scorch.tscn
## and their loot tables (resources/loot/*.tres).
##
## Run from the project root, then rebuild the mid zone (it places them, and
## bakes its navmesh round them) and its map picture:
##
##     godot --headless --path . -s res://tools/build_mid_sites.gd [-- <folder> …]
##     godot --headless --path . -s res://tools/build_mid_zone.gd -- zone-only bake
##     godot --path . -s res://tools/render_map.gd -- mid_zone
##
## Each site is drawn in its own coordinates, centred on its spot in
## PLACES (build_mid_zone.gd); x is east, -z north. The zone's roads run
## through some of them: the notes say where, and nothing solid stands on them.

## The mid zone's loot tables, as LOOT in build_sites.gd.
const MID_LOOT := {
	"mesa_sheriff": [1, 2, [["pistol_ammo", 1, 8, 16]], [["shotgun_shells", 2, 6, 12], ["rifle_ammo", 2, 10, 20], ["gun_magazine", 1, 1, 1], ["scrap_helmet", 0.6, 1, 1]],
		[["weapons/pistol_item", 3, 1, 1], ["weapons/shotgun_item", 2, 1, 1]]],
	"pump_parts": [2, 4, [], [["metal_pipe", 3, 1, 3], ["spring", 2, 1, 2], ["electronics", 2, 1, 1], ["metal_plate", 2, 1, 2], ["scrap_metal", 2, 2, 5], ["chemicals", 1, 1, 2], ["fuel", 1, 1, 1]]],
	"water_treatment": [1, 3, [["chemicals", 1, 1, 2]], [["chemicals", 2, 1, 3], ["cloth", 2, 2, 4], ["bandage", 2, 1, 2], ["electronics", 1, 1, 1], ["medkit", 0.6, 1, 1]]],
	"quarry_office": [1, 3, [], [["electronics", 2, 1, 2], ["pistol_ammo", 2, 8, 14], ["canned_beans", 2, 1, 2], ["fuel", 1, 1, 1], ["gunpowder", 1, 1, 3], ["leather", 1, 1, 2]]],
	"rail_freight": [2, 4, [], [["metal_plate", 3, 1, 3], ["metal_pipe", 2, 1, 3], ["scrap_metal", 3, 3, 6], ["spring", 2, 1, 2], ["fuel", 2, 1, 2], ["electronics", 1, 1, 1], ["cloth", 2, 2, 5], ["canned_peaches", 1, 1, 2], ["leather", 1, 1, 3]]],
	"rail_office": [1, 3, [["electronics", 1, 1, 1]], [["pistol_ammo", 2, 8, 16], ["rifle_308", 1, 6, 12], ["medkit", 1, 1, 1], ["chemicals", 1, 1, 2], ["gun_receiver", 1, 1, 1], ["red_dot", 0.5, 1, 1]]],
	"dusthaven_police": [1, 2, [["pistol_ammo", 1, 10, 20]], [["rifle_ammo", 2, 15, 30], ["shotgun_shells", 2, 8, 16], ["extended_mag", 1, 1, 1], ["red_dot", 1, 1, 1], ["scrap_helmet", 1, 1, 1], ["plated_vest", 0.5, 1, 1]],
		[["weapons/shotgun_item", 3, 1, 1], ["weapons/service_rifle_item", 2, 1, 1], ["weapons/pistol_item", 2, 1, 1]]],
	"diner_kitchen": [1, 3, [["canned_beans", 1, 1, 2]], [["canned_peaches", 2, 1, 2], ["canned_beans", 2, 1, 2], ["cloth", 1, 1, 2], ["fuel", 1, 1, 1], ["wood", 1, 2, 4]]],
	"motel_room": [1, 2, [], [["cloth", 3, 1, 3], ["bandage", 2, 1, 2], ["pistol_ammo", 2, 6, 12], ["canned_peaches", 1, 1, 1], ["electronics", 1, 1, 1], ["leather_cap", 0.4, 1, 1], ["rucksack", 0.2, 1, 1]]],
	"scorch_cache": [2, 4, [["gunpowder", 1, 2, 4]], [["rifle_ammo", 3, 15, 30], ["shotgun_shells", 2, 8, 16], ["pistol_ammo", 2, 10, 20], ["metal_plate", 2, 1, 2], ["gun_barrel", 1, 1, 1], ["gun_receiver", 1, 1, 1], ["trigger_group", 1, 1, 1], ["leather", 2, 1, 3], ["scrap_helmet", 0.6, 1, 1], ["plated_trousers", 0.4, 1, 1], ["medkit", 1, 1, 1]]],
	"scorch_warlord": [2, 3, [["rifle_ammo", 1, 30, 60]], [["scope_4x", 1, 1, 1], ["suppressor", 1, 1, 1], ["extended_mag", 1, 1, 1], ["plated_vest", 1, 1, 1], ["medkit", 1, 1, 2], ["military_pack", 0.5, 1, 1]],
		[["weapons/service_rifle_item", 3, 1, 1], ["weapons/scoped_rifle_item", 2, 1, 1]]],
}

const SITES := {
	"red_mesa": "_red_mesa",
	"dry_river_pump_station": "_dry_river",
	"cinder_quarry": "_cinder_quarry",
	"iron_vein_rail_yard": "_iron_vein",
	"dusthaven": "_dusthaven",
	"broken_spur_truck_stop": "_broken_spur",
	"raider_camp_scorch": "_scorch",
}


func _run() -> void:
	var only := Array(OS.get_cmdline_user_args())
	_mid_loot_tables()
	for folder: String in SITES:
		if only.is_empty() or only.has(folder):
			var k: Kit = call(SITES[folder])
			k.save("res://levels/%s/%s.tscn" % [folder, folder])
			print("  %s: %s" % [folder, k.counts])
	print("mid sites built")
	quit()


func _mid_loot_tables() -> void:
	for name in MID_LOOT:
		var spec: Array = MID_LOOT[name]
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
	print("  %d loot tables" % MID_LOOT.size())


# ================================================================ shared parts

## A tower on four legs: a deck at `height` with rails (open on the ladder
## side, +z), and a ladder up. Returns the body; things on the deck go at
## Vector3(x, height, z) in its frame.
func _tower(k: Kit, name: String, pos: Vector3, yaw: float, height: float, deck := 3.6, mat_key := "wood") -> StaticBody3D:
	var t := k.solid_body(k.groups["Buildings"], name, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos))
	var h := deck / 2.0 - 0.2
	for leg in [Vector3(-h, height / 2.0, -h), Vector3(h, height / 2.0, -h), Vector3(-h, height / 2.0, h), Vector3(h, height / 2.0, h)]:
		k.box(t, "Leg", Vector3(0.25, height, 0.25), leg, mat_key)
	k.box(t, "Deck", Vector3(deck, 0.2, deck), Vector3(0, height - 0.1, 0), mat_key)
	k.box(t, "RailN", Vector3(deck, 1.0, 0.1), Vector3(0, height + 0.5, -deck / 2.0), mat_key)
	k.box(t, "RailW", Vector3(0.1, 1.0, deck), Vector3(-deck / 2.0, height + 0.5, 0), mat_key)
	k.box(t, "RailE", Vector3(0.1, 1.0, deck), Vector3(deck / 2.0, height + 0.5, 0), mat_key)
	k.ladder(name + "Ladder", t, Vector3(0, 0, deck / 2.0), 0, height)
	t.set_meta("doors", [])
	t.set_meta("size", Vector2(deck, deck))
	return t


## A water tank on a tower (Red Mesa, the rail yard).
func _water_tower(k: Kit, name: String, pos: Vector3, height: float) -> StaticBody3D:
	var t := _tower(k, name, pos, 0, height, 4.4, "rust")
	k.box(t, "Tank", Vector3(3.4, 3.2, 2.2), Vector3(0, height + 1.6, -0.9), "rust")
	return t


## A shack: a one-room wooden hut with a door on `door_side`.
func _shack(k: Kit, name: String, at: Vector2, yaw: float, size := Vector2(5, 4), door_side := "S", wall := "wood") -> StaticBody3D:
	var other := {"S": "N", "N": "S", "E": "W", "W": "E"}
	return k.building(name, at, yaw, size, {
		"wall": wall, "floor": "wood", "roof": "flat", "roof_mat": "corrugated",
		"openings": [[door_side, 0, "door"], [other[door_side], 0, "window"]],
	})


## A wall of scrap: rusted sheets on posts (solid), `from` to `to`.
func _scrap_wall(k: Kit, name: String, from: Vector2, to: Vector2, height := 3.4) -> void:
	var d := to - from
	var body := k.solid_body(k.groups["Buildings"], name, Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x)), Vector3((from.x + to.x) / 2.0, 0, (from.y + to.y) / 2.0)))
	var n := maxi(int(d.length() / 3.0), 1)
	var w := d.length() / n
	for i in n:
		var x := -d.length() / 2.0 + w * (i + 0.5)
		k.box(body, "Sheet%d" % i, Vector3(w + 0.05, height + k.rng.randf_range(-0.4, 0.3), 0.12), Vector3(x, height / 2.0, k.rng.randf_range(-0.08, 0.08)),
			"rust" if i % 3 != 1 else "corrugated", k.rng.randf_range(-3.0, 3.0))
	body.set_meta("doors", [])
	body.set_meta("size", Vector2(d.length(), 0.2))


# ================================================================ Red Mesa

## A ruined town at the foot of the mesas. The road from the south ends at
## (12, 83) and carries on as the main street (x 4…20) north to the church.
func _red_mesa() -> Kit:
	var k := Kit.new("RedMesa", "Red Mesa", 601)
	# West side of the street, south to north
	var hA := k.building("HouseSouth", Vector2(-12, 60), 0, Vector2(8, 7), {
		"wall": "wood", "floor": "wood", "roof": "pitched", "ruin": {"W": 1.4},
		"openings": [["E", 0, "door"], ["S", 0, "window"], ["N", 0, "window"]],
	})
	k.container_at_wall("footlocker", "HouseSouthChest", hA, "N", -2.0, "town_household", "Chest")
	k.pile("furniture", "HouseSouthJunk", hA, Vector3(-2.0, 0, 1.6), 30)
	var saloon := k.building("Saloon", Vector2(-10, 32), 0, Vector2(12, 10), {
		"wall": "wood", "floor": "wood", "storeys": 2, "roof": "flat", "roof_mat": "corrugated",
		"openings": [["E", -2, "door"], ["E", 3, "window"], ["N", 0, "window"], ["S", 0, "window"],
			["E", -3, "window", 1], ["E", 3, "window", 1], ["N", 0, "window", 1]],
		"inner": [[Vector2(-5.85, 1.0), Vector2(5.85, 1.0), [4.0]]],
		"hole": Rect2(Vector2(-5.6, -4.6), Vector2(2.4, 1.6)),
	})
	k.fixture("Bar", saloon, Vector3(-2.5, 0, -2.6), Vector3(5.0, 1.1, 0.7), "wood")
	k.ladder("SaloonLadder", saloon, Vector3(-4.4, 0, -4.6), 0, 3.3)
	k.container_at_wall("crate", "SaloonStores", saloon, "W", 3.0, "town_supplies", "Saloon Stores")
	k.container_at_wall("footlocker", "SaloonRoomChest", saloon, "S", 3.0, "town_household", "Chest", 3.3)
	k.pile("furniture", "SaloonTables", saloon, Vector3(2.4, 0, -1.5), 15)
	k.pickup("canned_beans", 2, "SaloonBeans", saloon, Vector3(-3.5, 1.1, -2.6))
	k.pickup("pistol_ammo", 10, "SaloonRoomAmmo", saloon, Vector3(-2.0, 3.3, 3.4))
	var store := k.building("GeneralStore", Vector2(-10, 4), 0, Vector2(12, 9), {
		"wall": "brick", "floor": "concrete_plain", "roof": "flat",
		"openings": [["E", 0, "door"], ["E", -3, "window"], ["E", 3, "window"], ["W", 2, "door"]],
	})
	k.fixture("ShelvesA", store, Vector3(-1.5, 0, -2.6), Vector3(6.0, 1.8, 0.6), "wood")
	k.fixture("ShelvesB", store, Vector3(-1.5, 0, 1.0), Vector3(6.0, 1.8, 0.6), "wood")
	k.container_at_wall("crate", "StoreRoomA", store, "N", 3.5, "town_supplies", "Supplies")
	k.container_at_wall("crate", "StoreRoomB", store, "S", -3.5, "town_supplies", "Supplies")
	k.pickup("cloth", 3, "StoreCloth", store, Vector3(2.5, 0, 3.2))
	k.sign("StoreSign", P3 + "sign_sign_general_store.tres", store, Vector3(6.03, 3.4, 0), 90, Vector2(3.0, 0.75), BOARD)
	# The church at the north end, its tower a lookout over the street
	var church := k.building("Church", Vector2(-10, -36), 0, Vector2(10, 16), {
		"wall": "plaster", "floor": "wood", "roof": "none", "height": 5.0,
		"ruin": {"W": 2.6, "N": 3.5},
		"openings": [["E", 4, "door"], ["E", -3, "window"], ["W", 0, "window"]],
	})
	k.fixture("Altar", church, Vector3(0, 0, -6.6), Vector3(2.4, 1.0, 1.0), "wood")
	k.pile("furniture", "Pews", church, Vector3(-1.5, 0, 0), 0)
	k.container_at_wall("footlocker", "VestryChest", church, "W", -5.5, "scavenger_stash", "Vestry Chest")
	var bell := _tower(k, "BellTower", Vector3(-10, 0, -50), 0, 9.0, 3.6, "brick")
	k.box(bell, "Roof", Vector3(4.2, 0.3, 4.2), Vector3(0, 12.4, 0), "roofing", 0.0, false)
	for c in [Vector3(-1.7, 10.7, -1.7), Vector3(1.7, 10.7, -1.7), Vector3(-1.7, 10.7, 1.7), Vector3(1.7, 10.7, 1.7)]:
		k.box(bell, "Pillar", Vector3(0.25, 3.2, 0.25), c, "brick", 0.0, false)
	k.container("crate", "BellTowerCache", bell, Vector3(0.6, 9.0, -0.9), 0, "sniper_stash", "Lookout's Cache")
	# East side
	var hB := k.building("HouseNorthEast", Vector2(32, 54), 0, Vector2(8, 7), {
		"wall": "wood", "floor": "wood", "roof": "pitched",
		"openings": [["W", 0, "door"], ["E", 0, "window"], ["N", 0, "window"]],
	})
	_bed(k, "HouseNorthEastBed", hB, Vector3(2.0, 0, -1.8))
	k.container_at_wall("footlocker", "HouseNorthEastChest", hB, "E", 2.0, "town_household", "Chest")
	var sheriff := k.building("SheriffsOffice", Vector2(32, 24), 0, Vector2(10, 8), {
		"wall": "brick", "floor": "concrete_plain", "roof": "flat",
		"openings": [["W", 1.5, "door"], ["W", -2.5, "window"], ["N", 0, "window"]],
		"inner": [[Vector2(2.0, -3.85), Vector2(2.0, 3.85), [3.85]]],  # door offsets run from the wall's start
	})
	k.fixture("SheriffsDesk", sheriff, Vector3(-1.5, 0, -2.4), Vector3(1.6, 0.8, 0.8), "wood")
	k.container_at_wall("locker", "GunRack", sheriff, "N", -3.2, "mesa_sheriff", "Gun Rack")
	k.container_at_wall("footlocker", "EvidenceLocker", sheriff, "E", 2.4, "footlocker", "Evidence Locker")
	k.pickup("shotgun_shells", 8, "DeskShells", sheriff, Vector3(-1.5, 0.8, -2.4))
	var garage := k.building("MesaGarage", Vector2(34, -10), 0, Vector2(12, 10), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "flat", "roof_mat": "rust",
		"openings": [["W", 0, "wide"], ["N", 3, "window"], ["E", 2, "door"]],
	})
	var bench := k.prop("workbench", "MesaWorkbench", k.at(garage, Vector3(3.6, 0, -3.6)), 0, "CraftingStations")
	bench.name = "MesaWorkbench"
	k.container_at_wall("crate", "GarageParts", garage, "S", 2.5, "garage_parts", "Parts Bin")
	k.pile("scrap", "GarageScrap", garage, Vector3(3.0, 0, 2.6), 20)
	k.pile("appliance", "GarageCompressor", garage, Vector3(-3.0, 0, -3.6), 60)
	k.pickup("fuel", 1, "GarageFuel", garage, Vector3(-3.6, 0, 3.4))
	var hC := k.building("HouseNorthWest", Vector2(32, -40), 0, Vector2(8, 7), {
		"wall": "plaster", "floor": "wood", "roof": "pitched", "ruin": {"E": 1.2, "N": 2.0},
		"openings": [["W", 0, "door"], ["S", 0, "window"]],
	})
	k.pile("furniture", "HouseNorthWestJunk", hC, Vector3(1.5, 0, 1.0), 70)
	k.pickup("bandage", 1, "HouseNorthWestBandage", hC, Vector3(-1.8, 0, -1.6))
	# The water tower behind the store
	var wt := _water_tower(k, "WaterTower", Vector3(-34, 0, 12), 8.0)
	k.container("crate", "TowerStash", wt, Vector3(1.2, 8.0, 1.2), -90, "scavenger_stash", "Stash")
	# The street: wrecks, barrels, sandbags, salvage
	k.prop("truck", "StreetWreck", Vector3(19, 0, 44), 170)
	k.prop("burning_barrel", "StreetFireA", Vector3(18, 0, 10), 0)
	k.prop("burning_barrel", "StreetFireB", Vector3(6, 0, -24), 0)
	for i in 3:
		k.prop("sandbags", "Barricade%d" % i, Vector3(6 + i * 2.7, 0, -58), 0)
	k.prop("fuel_drums", "MesaDrums", Vector3(44, 0, -2), 30)
	k.pile("scrap", "ScrapA", null, Vector3(-26, 0, 46), 15)
	k.pile("scrap", "ScrapB", null, Vector3(46, 0, 36), -30)
	k.pile("pallet", "PalletA", null, Vector3(-26, 0, -12), 40)
	k.pile("appliance", "StreetFridge", null, Vector3(22, 0, -26), 80)
	k.pickup("rifle_ammo", 15, "StreetAmmo", null, Vector3(14, 0, 30))
	k.pickup("metal_pipe", 2, "StreetPipes", null, Vector3(-24, 0, 22))
	k.sign("MesaGraffiti", P3 + "graffiti_graffiti_raider_2.tres", store, Vector3(-6.03, 1.8, -1.0), -90, Vector2(2.2, 2.2))
	k.spawner("VeteranSpawner", "veteran", 3, 120.0, [Vector2(12, 20), Vector2(14, -20), Vector2(-24, 30)])
	k.spawner("MarauderSpawner", "marauder", 2, 180.0, [Vector2(4, -50), Vector2(24, -50)])
	return k


# ================================================================ Dry River Pump Station

## A raised reservoir behind concrete walls, the pump house and the
## workers' quarters. The road north passes the west side (x -58…-50) and
## the quarry road the north (z < -68); the yard opens to the west.
func _dry_river() -> Kit:
	var k := Kit.new("DryRiverPumpStation", "Dry River Pump Station", 602)
	# The reservoir: a raised concrete tank, full; a walkway on its south wall
	var res := k.solid_body(k.groups["Buildings"], "Reservoir", Transform3D(Basis.IDENTITY, Vector3(28, 0, -26)))
	k.box(res, "WallS", Vector3(40, 4.0, 1.2), Vector3(0, 2.0, 14.4), "concrete")
	k.box(res, "WallN", Vector3(40, 4.0, 1.2), Vector3(0, 2.0, -14.4), "concrete")
	k.box(res, "WallW", Vector3(1.2, 4.0, 28), Vector3(-19.4, 2.0, 0), "concrete")
	k.box(res, "WallE", Vector3(1.2, 4.0, 28), Vector3(19.4, 2.0, 0), "concrete")
	k.box(res, "Fill", Vector3(37.6, 3.2, 27.6), Vector3(0, 1.6, 0), "concrete_stained")
	k.box(res, "Water", Vector3(37.6, 0.1, 27.6), Vector3(0, 3.45, 0), "water", 0.0, false)
	k.box(res, "Walkway", Vector3(40, 0.15, 1.6), Vector3(0, 4.07, 15.6), "metal_dark")
	k.ladder("ReservoirLadder", res, Vector3(-12, 0, 16.4), 0, 4.1)
	k.container("crate", "SluiceCabinet", res, Vector3(-4, 4.15, 15.6), 180, "pump_parts", "Sluice Cabinet")
	res.set_meta("doors", [])
	res.set_meta("size", Vector2(40, 30))
	# The pump house: pumps below, the control room above
	var ph := k.building("PumpHouse", Vector2(-18, -14), 0, Vector2(16, 10), {
		"wall": "concrete", "floor": "concrete_plain", "storeys": 2, "roof": "flat",
		"openings": [["W", 0, "door"], ["S", -4, "door"], ["S", 3, "window"], ["N", -4, "window"],
			["S", -4, "window", 1], ["S", 3, "window", 1], ["W", 0, "window", 1], ["E", 0, "window", 1]],
		"hole": Rect2(Vector2(5.0, 2.8), Vector2(2.6, 1.6)),
	})
	k.fixture("PumpA", ph, Vector3(-3.5, 0, -2.0), Vector3(2.0, 1.6, 1.4), "metal_dark")
	k.fixture("PumpB", ph, Vector3(0.5, 0, -2.0), Vector3(2.0, 1.6, 1.4), "metal_dark")
	k.fixture("Manifold", ph, Vector3(-1.5, 0, -4.1), Vector3(8.0, 0.8, 0.5), "rust")
	k.ladder("PumpHouseLadder", ph, Vector3(6.3, 0, 4.4), 180, 3.3)
	k.container_at_wall("crate", "PumpSpares", ph, "S", 3.5, "pump_parts", "Pump Spares")
	k.container_at_wall("footlocker", "PumpToolChest", ph, "N", 4.5, "tool_chest", "Tool Chest")
	k.fixture("ControlDesk", ph, Vector3(-2.0, 3.3, 2.6), Vector3(3.0, 0.9, 0.8), "metal_dark")
	k.container_at_wall("crate", "ControlRoomCabinet", ph, "N", 0.0, "comms_gear", "Control Cabinet", 3.3)
	k.pickup("electronics", 1, "ControlBoard", ph, Vector3(-2.0, 4.2, 2.6))
	var bench := k.prop("workbench", "PumpWorkbench", k.at(ph, Vector3(-5.6, 0, 3.6)), 180, "CraftingStations")
	bench.name = "PumpWorkbench"
	# Pipes from the pump house over to the reservoir, overhead
	var pipes := k.solid_body(k.groups["Props"], "Pipes")
	for z in [-16.5, -12.5]:
		var p := k.box(pipes, "Pipe", Vector3(24, 0.8, 0.8), Vector3(0, 5.0, z), "rust", 0.0, false)
		p.position.x = -0.5
		k.box(pipes, "Stand", Vector3(0.4, 5.0, 0.4), Vector3(-0.5, 2.5, z), "rust")
	# Workers' quarters and the chemical store
	var q := k.building("Quarters", Vector2(-14, 22), 0, Vector2(12, 7), {
		"wall": "wood", "floor": "wood", "roof": "pitched",
		"openings": [["W", 0, "door"], ["N", -3, "window"], ["N", 3, "window"], ["S", 3, "window"]],
	})
	for i in 3:
		_bed(k, "Bunk%d" % i, q, Vector3(-3.0 + i * 2.6, 0, 1.8), 90)
	k.container_at_wall("footlocker", "QuartersLockerA", q, "E", -1.5, "footlocker", "Footlocker")
	k.container_at_wall("footlocker", "QuartersLockerB", q, "N", 1.0, "footlocker", "Footlocker")
	k.pickup("canned_peaches", 1, "QuartersPeaches", q, Vector3(-4.0, 0, -2.2))
	var chem := k.building("ChemicalStore", Vector2(16, 24), 0, Vector2(7, 5), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "flat", "roof_mat": "rust",
		"openings": [["W", 0, "door"]],
	})
	k.container_at_wall("crate", "TreatmentChemicals", chem, "E", 0.0, "water_treatment", "Treatment Chemicals")
	k.pickup("chemicals", 2, "ChemDrums", chem, Vector3(-1.6, 0, -1.4))
	k.sign("ChemKeepOut", P3 + "sign_sign_keep_out.tres", chem, Vector3(-3.53, 1.9, 1.6), -90, Vector2(1.2, 0.5), BOARD)
	# Yard
	k.prop("water_tank", "YardTank", Vector3(-40, 0, 2), 0)
	k.prop("generator", "YardGenerator", Vector3(-8, 0, 6), 90)
	k.prop("fuel_drums", "YardDrums", Vector3(4, 0, 8), 20)
	k.prop("burning_barrel", "YardFire", Vector3(-30, 0, 12), 0)
	k.pile("scrap", "ScrapA", null, Vector3(-34, 0, -30), 0)
	k.pile("scrap", "ScrapB", null, Vector3(38, 0, 20), 40)
	k.pile("pallet", "PalletA", null, Vector3(2, 0, 34), 15)
	k.pile("appliance", "OldPump", null, Vector3(-36, 0, 20), 70)
	k.pickup("metal_pipe", 3, "YardPipes", null, Vector3(-4, 0, -2))
	k.pickup("fuel", 1, "YardFuel", null, Vector3(6.5, 0, 8.5))
	k.spawner("RaiderSpawner", "raider", 3, 45.0, [Vector2(-30, 0), Vector2(0, 14), Vector2(30, 6)])
	k.spawner("VeteranSpawner", "veteran", 2, 120.0, [Vector2(-6, -2), Vector2(-26, 30)])
	return k


# ================================================================ Cinder Quarry

## The quarry face to the east in benches you climb by ladder, spoil heaps,
## the crusher tower, sheds, the site office and the explosives magazine.
## The road comes in from the west at (-84, 4).
func _cinder_quarry() -> Kit:
	var k := Kit.new("CinderQuarry", "Cinder Quarry", 603)
	# The face: three benches rising east, 4, 8 and 12 m
	var face := k.solid_body(k.groups["Buildings"], "QuarryFace", Transform3D(Basis.IDENTITY, Vector3(48, 0, 0)))
	k.box(face, "Bench1", Vector3(14, 4.0, 70), Vector3(0, 2.0, 0), "rock_tan")
	k.box(face, "Bench2", Vector3(12, 8.0, 64), Vector3(13, 4.0, 0), "rock_tan")
	k.box(face, "Bench3", Vector3(12, 12.0, 58), Vector3(25, 6.0, 0), "rock_tan")
	k.ladder("Bench1Ladder", face, Vector3(-7.05, 0, 10), -90, 4.0)
	k.ladder("Bench2Ladder", face, Vector3(6.95, 4.0, -6), -90, 4.0)
	k.ladder("Bench3Ladder", face, Vector3(18.95, 8.0, 12), -90, 4.0)
	k.container("crate", "BlastersCache", face, Vector3(26, 12.0, 0), -90, "mine_explosives", "Blaster's Cache")
	k.pickup("gunpowder", 2, "BenchPowder", face, Vector3(2, 4.0, -12))
	face.set_meta("doors", [])
	face.set_meta("size", Vector2(37, 70))
	# Spoil heaps
	for r: Array in [[Vector3(-10, -0.4, -48), Vector3(8, 6, 7)], [Vector3(18, -0.4, -52), Vector3(9, 7, 6)],
			[Vector3(12, -0.4, 50), Vector3(8, 5, 7)], [Vector3(-24, -0.4, 46), Vector3(7, 5, 6)]]:
		k.rock(k.groups["Props"], "SpoilHeap", r[0], k.rng.randf_range(0, 360), r[1], "rock_dark", k.rng.randi() % 8, 0.85)
	# The crusher: a steel frame with a deck at 8 m, a hopper and a conveyor
	var cr := k.solid_body(k.groups["Buildings"], "Crusher", Transform3D(Basis.IDENTITY, Vector3(-6, 0, -22)))
	for leg in [Vector3(-3, 8, -3), Vector3(3, 8, -3), Vector3(-3, 8, 3), Vector3(3, 8, 3)]:
		k.box(cr, "Leg", Vector3(0.5, 16, 0.5), leg, "rust")
	k.box(cr, "Deck", Vector3(7, 0.25, 7), Vector3(0, 7.875, 0), "metal_dark")
	k.box(cr, "Hopper", Vector3(5, 4, 5), Vector3(0, 12, 0), "rust")
	k.box(cr, "Jaw", Vector3(3, 3, 3), Vector3(0, 1.5, -1.2), "metal_dark")
	var conv := k.box(cr, "Conveyor", Vector3(1.6, 0.6, 22), Vector3(9, 4.5, 8), "metal_dark", 50.0, false)
	conv.rotation.x = deg_to_rad(-12)
	k.ladder("CrusherLadder", cr, Vector3(0, 0, 3.6), 0, 7.9)
	k.container("crate", "CrusherToolbox", cr, Vector3(-2.0, 8.0, -2.0), 0, "tool_chest", "Tool Box")
	cr.set_meta("doors", [])
	cr.set_meta("size", Vector2(7, 7))
	# Equipment shed with a workbench, the site office, the magazine
	var shed := k.building("EquipmentShed", Vector2(-34, -30), 0, Vector2(14, 10), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "flat", "roof_mat": "rust",
		"openings": [["S", 0, "wide"], ["E", 2, "door"], ["N", -4, "window"]],
	})
	var bench := k.prop("workbench", "QuarryWorkbench", k.at(shed, Vector3(-4.6, 0, -3.6)), 0, "CraftingStations")
	bench.name = "QuarryWorkbench"
	k.container_at_wall("crate", "ShedParts", shed, "N", 3.5, "garage_parts", "Parts Bin")
	k.container_at_wall("crate", "ShedSupplies", shed, "W", 2.0, "mine_supplies", "Quarry Supplies")
	k.pile("scrap", "ShedScrap", shed, Vector3(4.0, 0, -2.6), 10)
	k.pickup("spring", 2, "ShedSprings", shed, Vector3(0, 0, -3.6))
	var office := k.building("SiteOffice", Vector2(-44, 18), 90, Vector2(9, 4), {
		"wall": "corrugated", "floor": "wood", "roof": "flat", "roof_mat": "corrugated",
		"openings": [["S", 2.5, "door"], ["S", -2.5, "window"], ["N", 0, "window"]],
	})
	k.fixture("PlanTable", office, Vector3(-2.5, 0, -0.8), Vector3(2.0, 0.9, 1.0), "wood")
	k.container_at_wall("footlocker", "OfficeLocker", office, "W", 0.0, "quarry_office", "Office Locker")
	k.container_at_wall("crate", "OfficeFiles", office, "N", 2.6, "quarry_office", "Office Crate")
	k.pickup("electronics", 1, "OfficeRadio", office, Vector3(-2.5, 0.9, -0.8))
	var mag := k.building("Magazine", Vector2(18, 34), 0, Vector2(5, 4), {
		"wall": "concrete", "floor": "concrete_plain", "roof": "flat", "roof_mat": "concrete_plain",
		"openings": [["W", 0, "door"]],
	})
	k.container_at_wall("crate", "MagazineA", mag, "E", -0.9, "mine_explosives", "Explosives")
	k.container_at_wall("crate", "MagazineB", mag, "N", 0.6, "mine_explosives", "Explosives")
	k.sign("MagazineSign", P3 + "sign_sign_keep_out.tres", mag, Vector3(-2.53, 1.9, 1.2), -90, Vector2(1.2, 0.5), BOARD)
	# Haul trucks, drums, salvage
	k.prop("truck", "HaulTruck", Vector3(-20, 0, 12), 200)
	k.prop("truck", "DeadHaulTruck", Vector3(26, 0, 46), 30)
	k.prop("fuel_drums", "QuarryDrums", Vector3(-52, 0, -14), 0)
	k.prop("burning_barrel", "QuarryFire", Vector3(-26, 0, 4), 0)
	k.pile("scrap", "ScrapA", null, Vector3(-14, 0, 30), 30)
	k.pile("scrap", "ScrapB", null, Vector3(-60, 0, -32), -40)
	k.pile("pallet", "PalletA", null, Vector3(-56, 0, 28), 10)
	k.pickup("metal_plate", 2, "YardPlate", null, Vector3(-12, 0, -8))
	k.pickup("fuel", 1, "YardFuel", null, Vector3(-50.5, 0, -12))
	k.spawner("VeteranSpawner", "veteran", 3, 120.0, [Vector2(-20, -6), Vector2(-40, 0), Vector2(6, 20)])
	k.spawner("MarauderSpawner", "marauder", 1, 200.0, [Vector2(-16, -40)])
	return k


# ================================================================ Iron Vein Rail Yard

## The main line runs through on a slant (`_rail_at`), with a siding to its
## south; the east road runs along the north side (v ≈ -44). Sheds and the
## warehouse are south of the tracks, the yard office and signal box north.
const RAIL_DIR := Vector2(0.966, -0.259)   ## along the tracks (east-north-east)
const RAIL_ACROSS := Vector2(0.259, 0.966) ## across them, to the south
const RAIL_YAW := 15.0                     ## a building's yaw to line up


## A point `u` along the tracks and `v` across them (south +), in the site.
func _rail_at(u: float, v: float) -> Vector2:
	return Vector2(0, 0.33) + RAIL_DIR * u + RAIL_ACROSS * v


func _iron_vein() -> Kit:
	var k := Kit.new("IronVeinRailYard", "Iron Vein Rail Yard", 604)
	# The engine shed, with a locomotive inside
	var es := k.building("EngineShed", _rail_at(-22, 24), RAIL_YAW, Vector2(40, 16), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "flat", "roof_mat": "rust", "height": 6.0,
		"openings": [["W", 0, "wide"], ["E", 0, "wide"], ["N", -10, "door"], ["N", 10, "window"], ["S", 0, "window"]],
	})
	var loco := k.solid_body(es, "Locomotive", Transform3D(Basis.IDENTITY, Vector3(-2, 0, 0)))
	k.box(loco, "Body", Vector3(14, 3.2, 3.0), Vector3(0, 2.1, 0), "metal_dark")
	k.box(loco, "Cab", Vector3(3.5, 1.4, 3.0), Vector3(-5.2, 4.4, 0), "metal_dark")
	k.box(loco, "Wheels", Vector3(13, 0.6, 2.6), Vector3(0, 0.3, 0), "rust")
	k.container_at_wall("crate", "ShedSpares", es, "S", -12.0, "rail_freight", "Engine Spares")
	k.container_at_wall("footlocker", "ShedToolChest", es, "N", 4.0, "tool_chest", "Tool Chest")
	var bench := k.prop("workbench", "YardWorkbench", k.at(es, Vector3(12.0, 0, 5.8)), 180, "CraftingStations")
	bench.name = "YardWorkbench"
	k.pile("scrap", "ShedScrap", es, Vector3(14.0, 0, -4.6), 20)
	k.pickup("metal_plate", 2, "ShedPlate", es, Vector3(-12.0, 0, 5.0))
	# The freight warehouse
	var wh := k.building("Warehouse", _rail_at(32, 26), RAIL_YAW, Vector2(28, 14), {
		"wall": "brick", "floor": "concrete_plain", "roof": "flat", "height": 5.0,
		"openings": [["N", -6, "wide"], ["N", 7, "door"], ["E", 0, "window"], ["S", 6, "window"]],
	})
	for i in 3:
		k.container_at_wall("crate", "FreightCrate%d" % i, wh, "S", -9.0 + i * 5.0, "rail_freight", "Freight Crate")
	k.pile("pallet", "WarehousePalletA", wh, Vector3(4, 0, -2), 20)
	k.pile("pallet", "WarehousePalletB", wh, Vector3(-4, 0, 1), -10)
	k.prop("wood_crate", "WarehouseCrateA", k.at(wh, Vector3(10, 0, 3)), 15)
	k.prop("wood_crate", "WarehouseCrateB", k.at(wh, Vector3(11.4, 0, 2.6)), -20)
	k.pickup("leather", 2, "WarehouseLeather", wh, Vector3(-10.0, 0, -4.0))
	# The yard office (two storeys) between the tracks and the road
	var off := k.building("YardOffice", _rail_at(-8, -22), RAIL_YAW, Vector2(10, 8), {
		"wall": "brick", "floor": "wood", "storeys": 2, "roof": "pitched",
		"openings": [["S", -2, "door"], ["N", 2, "door"], ["E", 0, "window"], ["W", 0, "window"],
			["S", 2, "window", 1], ["N", -2, "window", 1], ["E", 0, "window", 1]],
		"hole": Rect2(Vector2(-4.6, -3.6), Vector2(2.4, 1.6)),
	})
	k.ladder("OfficeLadder", off, Vector3(-3.4, 0, -3.6), 0, 3.3)
	k.fixture("TicketCounter", off, Vector3(1.6, 0, 0), Vector3(3.0, 1.1, 0.7), "wood")
	k.container_at_wall("footlocker", "StationSafe", off, "E", 2.4, "rail_office", "Station Safe")
	k.container_at_wall("crate", "DispatchCabinet", off, "W", 2.0, "rail_office", "Dispatch Cabinet", 3.3)
	k.pickup("rifle_308", 8, "DispatchRounds", off, Vector3(2.0, 3.3, 1.0))
	# The signal box on stilts, and a water tower for the engines
	var sb := _tower(k, "SignalBox", Vector3(_rail_at(50, -12).x, 0, _rail_at(50, -12).y), RAIL_YAW, 4.5, 4.0)
	k.box(sb, "Hut", Vector3(4.0, 2.4, 0.1), Vector3(0, 5.7, -1.95), "wood", 0.0, false)
	k.box(sb, "Roof", Vector3(4.4, 0.2, 4.4), Vector3(0, 7.0, 0), "roofing", 0.0, false)
	k.fixture("Levers", sb, Vector3(0, 4.5, -1.2), Vector3(3.0, 1.0, 0.5), "rust")
	k.container("crate", "SignalCabinet", sb, Vector3(1.2, 4.5, 0.4), -90, "comms_gear", "Signal Cabinet")
	var wt := _water_tower(k, "EngineWaterTower", Vector3(_rail_at(-56, -14).x, 0, _rail_at(-56, -14).y), 7.0)
	k.pickup("canned_beans", 1, "TowerBeans", wt, Vector3(1.4, 7.0, 1.2))
	# The siding: rails and a rake of wagons (containers on bogies)
	var siding := k.solid_body(k.groups["Props"], "Siding", Transform3D(Basis(Vector3.UP, deg_to_rad(RAIL_YAW)), Vector3(_rail_at(5, 9).x, 0, _rail_at(5, 9).y)))
	k.box(siding, "RailN", Vector3(70, 0.12, 0.1), Vector3(0, 0.06, -0.72), "rust", 0.0, false)
	k.box(siding, "RailS", Vector3(70, 0.12, 0.1), Vector3(0, 0.06, 0.72), "rust", 0.0, false)
	var wagons := ["container_red", "container_olive", "container_blue", "rust"]
	for i in wagons.size():
		k.box(siding, "Wagon%d" % i, Vector3(12.5, 3.0, 2.8), Vector3(-24 + i * 14.0, 2.1, 0), wagons[i])
		k.box(siding, "Bogie%d" % i, Vector3(11, 0.6, 2.2), Vector3(-24 + i * 14.0, 0.3, 0), "metal_dark")
	k.container("crate", "WagonLoad", null, Vector3(_rail_at(-2, 12).x, 0, _rail_at(-2, 12).y), 180 + RAIL_YAW, "rail_freight", "Wagon Load")
	# Yard clutter
	k.prop("fuel_drums", "YardDrums", Vector3(_rail_at(60, 20).x, 0, _rail_at(60, 20).y), 10)
	k.prop("burning_barrel", "YardFire", Vector3(_rail_at(0, -10).x, 0, _rail_at(0, -10).y), 0)
	k.prop("shipping_container", "StackA", Vector3(_rail_at(64, 18).x, 0, _rail_at(64, 18).y), RAIL_YAW)
	k.pile("scrap", "ScrapA", null, Vector3(_rail_at(-40, 14).x, 0, _rail_at(-40, 14).y), 0)
	k.pile("scrap", "ScrapB", null, Vector3(_rail_at(20, -14).x, 0, _rail_at(20, -14).y), 50)
	k.pile("scrap", "ScrapC", null, Vector3(_rail_at(56, 32).x, 0, _rail_at(56, 32).y), -20)
	k.pile("pallet", "PalletA", null, Vector3(_rail_at(14, 40).x, 0, _rail_at(14, 40).y), 15)
	k.pickup("metal_pipe", 2, "TrackPipes", null, Vector3(_rail_at(-30, -8).x, 0, _rail_at(-30, -8).y))
	k.pickup("spring", 2, "TrackSprings", null, Vector3(_rail_at(38, -8).x, 0, _rail_at(38, -8).y))
	k.spawner("RaiderSpawner", "raider", 4, 45.0, [Vector2(_rail_at(-20, 4).x, _rail_at(-20, 4).y), Vector2(_rail_at(30, 4).x, _rail_at(30, 4).y),
		Vector2(_rail_at(10, -16).x, _rail_at(10, -16).y), Vector2(_rail_at(-50, 14).x, _rail_at(-50, 14).y)])
	k.spawner("VeteranSpawner", "veteran", 2, 120.0, [Vector2(_rail_at(0, 16).x, _rail_at(0, 16).y), Vector2(_rail_at(45, 12).x, _rail_at(45, 12).y)])
	return k


# ================================================================ Dusthaven

## A town either side of its main street (the road south: x -10…4 from
## z -60 to 60), a few tall ruined blocks behind. Two-storey apartments and
## a hotel, the clinic, the bar, the bank, the market hall, the police
## station and the garage.
func _dusthaven() -> Kit:
	var k := Kit.new("Dusthaven", "Dusthaven", 605)
	# West side, north to south
	var apt := k.building("Apartments", Vector2(-24, -36), 0, Vector2(12, 20), {
		"wall": "concrete", "floor": "concrete_plain", "storeys": 2, "roof": "flat", "parapet": true,
		"roof_ladder": Vector3(-6, 0, -6),
		"openings": [["E", -6, "door"], ["E", 0, "window"], ["E", 6, "window"], ["W", 4, "window"],
			["E", -6, "window", 1], ["E", 0, "window", 1], ["E", 6, "window", 1], ["W", -4, "window", 1], ["W", 4, "window", 1]],
		"inner": [[Vector2(-5.85, 0), Vector2(5.85, 0), [3.5]]],
		"hole": Rect2(Vector2(-5.6, -9.6), Vector2(2.6, 1.6)),
	})
	k.ladder("ApartmentsLadder", apt, Vector3(-4.3, 0, -9.6), 0, 3.3)
	k.ladder("ApartmentsRoofLadder", apt, Vector3(-6.05, 0, -6), -90, 6.9)
	_bed(k, "FlatBedA", apt, Vector3(2.5, 0, 6.0))
	_bed(k, "FlatBedB", apt, Vector3(2.5, 3.3, -6.0))
	k.container_at_wall("footlocker", "FlatChestA", apt, "W", 7.0, "town_household", "Chest")
	k.container_at_wall("footlocker", "FlatChestB", apt, "N", 2.5, "town_household", "Chest", 3.3)
	k.container_at_wall("crate", "RoofStash", apt, "N", 2.0, "sniper_stash", "Rooftop Stash", 6.9)
	k.pile("furniture", "FlatJunk", apt, Vector3(-2.0, 0, 4.0), 20)
	k.pickup("pistol_ammo", 12, "FlatAmmo", apt, Vector3(1.0, 3.3, 5.0))
	var clinic := k.building("Clinic", Vector2(-24, -6), 0, Vector2(12, 12), {
		"wall": "paint_white", "floor": "concrete_plain", "roof": "flat",
		"openings": [["E", 0, "door"], ["E", -4, "window"], ["E", 4, "window"], ["N", 0, "window"]],
		"inner": [[Vector2(-5.85, 1.5), Vector2(1.5, 1.5), [4.0]]],
	})
	_bed(k, "ClinicBed", clinic, Vector3(-3.5, 0, -3.0), 90)
	k.container_at_wall("locker", "ClinicCabinet", clinic, "W", -3.0, "clinic_cabinet", "Medicine Cabinet")
	k.container_at_wall("crate", "ClinicSupplies", clinic, "S", -3.0, "hospital_supplies", "Medical Supplies")
	k.pickup("bandage", 2, "ClinicBandages", clinic, Vector3(2.5, 0, -3.5))
	k.sign("ClinicSign", P3 + "sign_sign_clinic.tres", clinic, Vector3(6.03, 3.4, 0), 90, Vector2(2.6, 0.65), BOARD)
	var bar := k.building("Bar", Vector2(-22, 20), 0, Vector2(10, 10), {
		"wall": "wood", "floor": "wood", "roof": "flat", "roof_mat": "corrugated",
		"openings": [["E", 0, "door"], ["E", 3, "window"], ["S", 0, "window"]],
	})
	k.fixture("BarCounter", bar, Vector3(-2.5, 0, -1.0), Vector3(0.7, 1.1, 5.0), "wood")
	k.container_at_wall("crate", "BarStores", bar, "N", -2.0, "diner_kitchen", "Bar Stores")
	k.pile("furniture", "BarTables", bar, Vector3(1.8, 0, 2.6), 30)
	k.pickup("canned_peaches", 1, "BarPeaches", bar, Vector3(-2.5, 1.1, 0.5))
	var bank := k.building("Bank", Vector2(-22, 45), 0, Vector2(10, 10), {
		"wall": "brick", "floor": "concrete_plain", "roof": "flat",
		"openings": [["E", 0, "door"], ["E", -3, "window"], ["E", 3, "window"]],
		"inner": [[Vector2(-1.5, -4.85), Vector2(-1.5, 4.85), [2.5]]],
	})
	k.container_at_wall("locker", "Vault", bank, "W", -2.5, "bank_safe", "Vault")
	k.fixture("BankCounter", bank, Vector3(0.5, 0, -1.0), Vector3(0.7, 1.1, 4.0), "wood")
	k.sign("BankSign", P3 + "sign_sign_bank.tres", bank, Vector3(5.03, 3.4, 0), 90, Vector2(2.4, 0.6), BOARD)
	# East side, north to south
	var market := k.building("MarketHall", Vector2(19, -36), 0, Vector2(14, 20), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "flat", "roof_mat": "rust", "height": 5.0,
		"openings": [["W", -4, "wide"], ["W", 6, "door"], ["S", 0, "window"], ["E", 0, "door"]],
	})
	for i in 3:
		k.fixture("Stall%d" % i, market, Vector3(2.0, 0, -6.0 + i * 5.0), Vector3(3.0, 1.0, 1.4), "wood")
	k.container_at_wall("crate", "MarketCrateA", market, "E", -7.0, "town_supplies", "Market Crate")
	k.container_at_wall("crate", "MarketCrateB", market, "N", 3.0, "scavenger_stash", "Trader's Crate")
	k.pile("pallet", "MarketPallets", market, Vector3(-3.0, 0, 6.0), 10)
	k.pile("appliance", "MarketJunk", market, Vector3(4.5, 0, 7.5), 60)
	k.pickup("cloth", 4, "MarketCloth", market, Vector3(2.0, 1.0, -1.0))
	var hotel := k.building("Hotel", Vector2(18, -4), 0, Vector2(12, 14), {
		"wall": "brick", "floor": "wood", "storeys": 2, "roof": "flat",
		"openings": [["W", 0, "door"], ["W", -4, "window"], ["W", 4, "window"], ["E", 0, "window"],
			["W", -4, "window", 1], ["W", 0, "window", 1], ["W", 4, "window", 1], ["E", -3, "window", 1], ["E", 3, "window", 1]],
		"inner": [[Vector2(-5.85, 2.0), Vector2(5.85, 2.0), [3.0]]],
		"hole": Rect2(Vector2(3.0, -6.6), Vector2(2.6, 1.6)),
	})
	k.ladder("HotelLadder", hotel, Vector3(4.3, 0, -6.6), 0, 3.3)
	k.fixture("Reception", hotel, Vector3(-2.0, 0, -2.0), Vector3(3.0, 1.1, 0.7), "wood")
	_bed(k, "HotelBedA", hotel, Vector3(-3.0, 3.3, 4.5))
	_bed(k, "HotelBedB", hotel, Vector3(2.5, 3.3, 4.5))
	k.container_at_wall("footlocker", "HotelRoomChestA", hotel, "S", -3.5, "motel_room", "Suitcase", 3.3)
	k.container_at_wall("footlocker", "HotelRoomChestB", hotel, "E", -4.0, "motel_room", "Suitcase", 3.3)
	k.container_at_wall("crate", "HotelStores", hotel, "S", 3.5, "town_supplies", "Hotel Stores")
	k.sign("HotelSign", P3 + "sign_sign_hotel.tres", hotel, Vector3(-6.03, 4.2, 0), -90, Vector2(2.6, 0.65), BOARD)
	var police := k.building("PoliceStation", Vector2(17, 24), 0, Vector2(10, 10), {
		"wall": "concrete", "floor": "concrete_plain", "roof": "flat",
		"openings": [["W", 0, "door"], ["W", 3, "window"], ["N", 0, "window"]],
		"inner": [[Vector2(1.5, -4.85), Vector2(1.5, 4.85), [2.5]]],
	})
	k.container_at_wall("locker", "PoliceArmory", police, "E", 2.0, "dusthaven_police", "Police Armory")
	k.container_at_wall("crate", "PoliceAmmo", police, "E", -2.5, "ammo_crate", "Ammo Crate")
	k.fixture("PoliceDesk", police, Vector3(-2.5, 0, -2.5), Vector3(1.6, 0.8, 0.8), "wood")
	k.pickup("shotgun_shells", 8, "DeskShells", police, Vector3(-2.5, 0.8, -2.5))
	var garage := k.building("TownGarage", Vector2(18, 50), 0, Vector2(12, 10), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "flat", "roof_mat": "rust",
		"openings": [["W", 0, "wide"], ["S", 3, "window"]],
	})
	var bench := k.prop("workbench", "TownWorkbench", k.at(garage, Vector3(3.6, 0, -3.6)), 0, "CraftingStations")
	bench.name = "TownWorkbench"
	k.container_at_wall("crate", "GarageParts", garage, "E", 2.5, "garage_parts", "Parts Bin")
	k.pile("scrap", "GarageScrap", garage, Vector3(2.8, 0, 2.8), 20)
	k.pickup("fuel", 1, "GarageFuel", garage, Vector3(-4.0, 0, 3.6))
	# The tall ruined blocks behind (shells you can't get into)
	var blocks := k.group("TallBlocks", true)
	for t: Array in [[Vector2(-54, -58), Vector3(14, 22, 14), "concrete_stained"], [Vector2(48, -66), Vector3(12, 18, 12), "concrete"],
			[Vector2(-52, 36), Vector3(12, 26, 12), "concrete_stained"], [Vector2(50, 14), Vector3(10, 16, 12), "concrete"]]:
		var b := k.solid_body(blocks, "Block", Transform3D(Basis.IDENTITY, Vector3(t[0].x, 0, t[0].y)))
		var size: Vector3 = t[1]
		k.box(b, "Shell", size, Vector3(0, size.y / 2.0, 0), t[2])
		k.box(b, "Broken", Vector3(size.x * 0.6, 3.0, size.z * 0.5), Vector3(size.x * 0.2, size.y + 1.5, -size.z * 0.2), t[2], 8.0)
	# The street
	k.prop("truck", "StreetWreckA", Vector3(-14, 0, -48), 10)
	k.prop("truck", "StreetWreckB", Vector3(2, 0, 34), 195)
	k.prop("burning_barrel", "StreetFireA", Vector3(-12, 0, 8), 0)
	k.prop("burning_barrel", "StreetFireB", Vector3(8, 0, -20), 0)
	k.prop("jersey", "BarrierA", Vector3(-4, 0, -64), 80)
	k.prop("jersey", "BarrierB", Vector3(6, 0, 62), 100)
	k.prop("fuel_drums", "TownDrums", Vector3(30, 0, 60), 0)
	k.pile("scrap", "ScrapA", null, Vector3(-36, 0, -20), 15)
	k.pile("scrap", "ScrapB", null, Vector3(32, 0, -16), -30)
	k.pile("appliance", "StreetFridge", null, Vector3(-36, 0, 32), 40)
	k.pile("pallet", "PalletA", null, Vector3(32, 0, 38), 70)
	k.pickup("rifle_ammo", 20, "StreetAmmo", null, Vector3(-12, 0, -28))
	k.pickup("medkit", 1, "StreetMedkit", null, Vector3(10, 0, 14))
	k.sign("TownGraffiti", P3 + "graffiti_graffiti_raider_3.tres", market, Vector3(-7.03, 2.4, 2.0), -90, Vector2(2.2, 2.2))
	k.spawner("RaiderSpawner", "raider", 4, 45.0, [Vector2(-4, -40), Vector2(-4, 0), Vector2(-2, 40), Vector2(30, 0)])
	k.spawner("VeteranSpawner", "veteran", 3, 120.0, [Vector2(-34, 4), Vector2(34, -50), Vector2(-4, 56)])
	return k


# ================================================================ Broken Spur Truck Stop

## The fuel canopy on the forecourt, the diner, the garage and a motel row.
## The road comes in from the north-east to (26, -47).
func _broken_spur() -> Kit:
	var k := Kit.new("BrokenSpurTruckStop", "Broken Spur Truck Stop", 606)
	# The canopy over the pumps
	var can := k.solid_body(k.groups["Buildings"], "Canopy", Transform3D(Basis.IDENTITY, Vector3(4, 0, -16)))
	k.box(can, "Roof", Vector3(20, 0.6, 12), Vector3(0, 5.3, 0), "paint_white")
	for p in [Vector3(-8, 2.5, -4), Vector3(8, 2.5, -4), Vector3(-8, 2.5, 4), Vector3(8, 2.5, 4)]:
		k.box(can, "Pillar", Vector3(0.5, 5.0, 0.5), p, "metal_dark")
	for x in [-5.0, 0.0, 5.0]:
		k.box(can, "Pump", Vector3(0.9, 1.7, 0.6), Vector3(x, 0.85, 0), "container_red")
	can.set_meta("doors", [])
	can.set_meta("size", Vector2(20, 12))
	k.sign("GasSign", P3 + "sign_sign_gas.tres", can, Vector3(0, 5.3, 6.03), 0, Vector2(3.0, 0.6), BOARD)
	# The diner, with its kitchen stove
	var diner := k.building("Diner", Vector2(-24, 8), 0, Vector2(16, 10), {
		"wall": "plaster", "floor": "concrete_plain", "roof": "flat",
		"openings": [["N", 2, "door"], ["N", -3, "window"], ["N", 6, "window"], ["E", 0, "window"], ["S", -5, "door"]],
		"inner": [[Vector2(-3.0, -4.85), Vector2(-3.0, 4.85), [2.5]]],
	})
	k.fixture("DinerCounter", diner, Vector3(-1.6, 0, -1.0), Vector3(0.7, 1.1, 5.0), "paint_white")
	k.pile("furniture", "Booths", diner, Vector3(3.5, 0, 1.0), 0)
	var stove := k.prop("cooking_stove", "DinerStove", k.at(diner, Vector3(-6.8, 0, -3.8)), 0, "CraftingStations")
	stove.name = "DinerStove"
	k.container_at_wall("crate", "DinerPantry", diner, "W", 2.0, "diner_kitchen", "Pantry")
	k.container_at_wall("footlocker", "DinerTill", diner, "E", 3.5, "town_household", "Till")
	k.pickup("canned_beans", 2, "CounterBeans", diner, Vector3(-1.6, 1.1, 1.0))
	k.sign("DinerSign", P3 + "sign_sign_diner.tres", diner, Vector3(0, 3.4, -5.03), 180, Vector2(3.0, 0.75), BOARD)
	# The garage
	var garage := k.building("Garage", Vector2(22, 16), 0, Vector2(14, 12), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "flat", "roof_mat": "rust",
		"openings": [["N", -2, "wide"], ["E", 3, "door"], ["S", 0, "window"]],
	})
	var bench := k.prop("workbench", "SpurWorkbench", k.at(garage, Vector3(-4.6, 0, 4.6)), 180, "CraftingStations")
	bench.name = "SpurWorkbench"
	k.container_at_wall("crate", "GaragePartsA", garage, "W", -3.0, "garage_parts", "Parts Bin")
	k.container_at_wall("crate", "GaragePartsB", garage, "S", 4.0, "garage_parts", "Parts Bin")
	k.box(k.solid_body(garage, "Lift"), "LiftDeck", Vector3(2.6, 0.3, 5.0), Vector3(3.5, 1.2, 0.5), "hazard")
	k.pile("scrap", "GarageScrap", garage, Vector3(-4.0, 0, 0), 30)
	k.pickup("fuel", 2, "GarageFuel", garage, Vector3(5.0, 0, -4.5))
	# The motel: four rooms in a row, doors to the north
	var motel := k.building("Motel", Vector2(-12, 40), 0, Vector2(28, 7), {
		"wall": "plaster", "floor": "wood", "roof": "flat", "roof_mat": "corrugated",
		"openings": [["N", -10.5, "door"], ["N", -3.5, "door"], ["N", 3.5, "door"], ["N", 10.5, "door"],
			["S", -10.5, "window"], ["S", -3.5, "window"], ["S", 3.5, "window"], ["S", 10.5, "window"]],
		"inner": [[Vector2(-7.0, -3.35), Vector2(-7.0, 3.35)], [Vector2(0, -3.35), Vector2(0, 3.35)], [Vector2(7.0, -3.35), Vector2(7.0, 3.35)]],
	})
	for i in 4:
		var x := -10.5 + i * 7.0
		_bed(k, "MotelBed%d" % i, motel, Vector3(x + 1.6, 0, 1.6), 90)
		k.container("footlocker", "MotelRoom%d" % i, motel, Vector3(x - 2.2, 0, 2.6), 180, "motel_room", "Room %d" % (i + 1))
	k.pickup("bandage", 1, "MotelBandage", motel, Vector3(-3.5, 0, -1.6))
	# Wrecks, drums, the billboard
	k.prop("truck", "WreckA", Vector3(-6, 0, -36), 120)
	k.prop("truck", "WreckB", Vector3(36, 0, -6), 20)
	k.prop("shipping_container", "TrailerBox", Vector3(-40, 0, -22), 100)
	k.prop("fuel_drums", "SpurDrums", Vector3(32, 0, 30), 0)
	k.prop("burning_barrel", "ForecourtFire", Vector3(14, 0, -4), 0)
	var bb := k.solid_body(k.groups["Props"], "Billboard", Transform3D(Basis(Vector3.UP, deg_to_rad(-30)), Vector3(40, 0, -30)))
	k.box(bb, "PostL", Vector3(0.4, 8, 0.4), Vector3(-3, 4, 0), "metal_dark")
	k.box(bb, "PostR", Vector3(0.4, 8, 0.4), Vector3(3, 4, 0), "metal_dark")
	k.box(bb, "Board", Vector3(9, 4, 0.3), Vector3(0, 8.5, 0), "rust")
	k.pile("scrap", "ScrapA", null, Vector3(-40, 0, 10), 10)
	k.pile("scrap", "ScrapB", null, Vector3(40, 0, 44), -40)
	k.pile("pallet", "PalletA", null, Vector3(-30, 0, 26), 20)
	k.pile("appliance", "OldFreezer", null, Vector3(-36, 0, 28), 80)
	k.pickup("fuel", 1, "PumpFuel", null, Vector3(10, 0, -14))
	k.pickup("pistol_ammo", 10, "ForecourtAmmo", null, Vector3(-14, 0, -12))
	k.spawner("RaiderSpawner", "raider", 3, 45.0, [Vector2(4, -6), Vector2(-26, 24), Vector2(28, 2)])
	k.spawner("VeteranSpawner", "veteran", 1, 150.0, [Vector2(-10, 26)])
	return k


# ================================================================ Raider Camp Scorch

## The Scorch Marauders' camp in the red rocks: a ring of scrap walls with
## a gate to the north (the trail from Dusthaven comes in at (6, -66)), gate
## towers, the warlord's hall, shacks, cages and caches.
func _scorch() -> Kit:
	var k := Kit.new("RaiderCampScorch", "Raider Camp Scorch", 607)
	# The ring of scrap walls (an octagon, radius ~40), the gate at the north
	var ring: Array[Vector2] = []
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0 - PI / 2.0
		ring.append(Vector2(cos(a), sin(a)) * 40.0)
	for i in 8:
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % 8]
		if i == 7:  # the north side: a gate gap between two stubs
			var mid := (a + b) / 2.0
			var along := (b - a).normalized()
			_scrap_wall(k, "WallGateW", a, mid - along * 5.0)
			_scrap_wall(k, "WallGateE", mid + along * 5.0, b)
			continue
		_scrap_wall(k, "Wall%d" % i, a, b)
	var gate := (ring[7] + ring[0]) / 2.0
	for side in [-1, 1]:
		var t := _tower(k, "GateTower%s" % ("W" if side < 0 else "E"), Vector3(gate.x + side * 8.0, 0, gate.y + 3.0), 0, 5.0, 3.2, "rust")
		k.container("crate", "GateCache%s" % ("W" if side < 0 else "E"), t, Vector3(0.5 * side, 5.0, -0.8), 0, "scorch_cache", "Raider Cache")
	# The warlord's hall
	var hall := k.building("WarlordsHall", Vector2(0, 14), 0, Vector2(18, 12), {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "flat", "roof_mat": "rust", "height": 4.5,
		"openings": [["N", 0, "wide"], ["E", 3, "door"], ["W", -3, "window"]],
		"inner": [[Vector2(-8.85, 2.0), Vector2(3.0, 2.0), [3.0]]],
	})
	k.fixture("Throne", hall, Vector3(6.5, 0, -2.0), Vector3(1.6, 1.6, 1.2), "rust")
	k.container_at_wall("locker", "WarlordsLocker", hall, "S", 6.5, "scorch_warlord", "Warlord's Locker")
	k.container_at_wall("crate", "HallCacheA", hall, "W", 4.0, "scorch_cache", "Raider Cache")
	k.container_at_wall("crate", "HallCacheB", hall, "S", -6.0, "scorch_cache", "Raider Cache")
	var wb := k.prop("weapons_bench", "ScorchWeaponsBench", k.at(hall, Vector3(-6.0, 0, -4.0)), 0, "CraftingStations")
	wb.name = "ScorchWeaponsBench"
	k.pickup("rifle_ammo", 20, "HallAmmo", hall, Vector3(2.0, 0, -4.0))
	k.sign("HallGraffiti", P3 + "graffiti_graffiti_raider_1.tres", hall, Vector3(-4.0, 2.4, -6.03), 180, Vector2(2.4, 2.4))
	# Shacks round the yard
	var sa := _shack(k, "ShackA", Vector2(-22, -14), 0, Vector2(5, 4), "E", "corrugated")
	_bed(k, "ShackABed", sa, Vector3(-0.8, 0, 1.0))
	k.container_at_wall("footlocker", "ShackAChest", sa, "W", -0.8, "scorch_cache", "Raider's Chest")
	var sb := _shack(k, "ShackB", Vector2(22, -14), 0, Vector2(5, 4), "W", "wood")
	_bed(k, "ShackBBed", sb, Vector3(0.8, 0, 1.0))
	k.pickup("gunpowder", 2, "ShackBPowder", sb, Vector3(-0.6, 0, -1.2))
	var sc := _shack(k, "ShackC", Vector2(-24, 14), 0, Vector2(5, 4), "E", "corrugated")
	k.container_at_wall("crate", "ShackCCache", sc, "W", 0.0, "scorch_cache", "Raider Cache")
	var sd := _shack(k, "ShackD", Vector2(24, 18), 0, Vector2(5, 4), "W", "wood")
	_bed(k, "ShackDBed", sd, Vector3(0.8, 0, 1.0))
	k.pile("furniture", "ShackDJunk", sd, Vector3(-1.2, 0, -1.0), 30)
	# Cages, a scrap pile mountain, fires, tents, containers
	var cages := k.solid_body(k.groups["Props"], "Cages", Transform3D(Basis.IDENTITY, Vector3(-14, 0, 30)))
	for i in 2:
		var x := i * 4.0
		for bar in 5:
			k.box(cages, "Bar", Vector3(0.08, 2.4, 0.08), Vector3(x - 1.4 + bar * 0.7, 1.2, -1.4), "metal_dark")
		k.box(cages, "Top", Vector3(3.0, 0.1, 3.0), Vector3(x, 2.45, 0), "metal_dark", 0.0, false)
	k.prop("shipping_container", "BunkA", Vector3(12, 0, 28), 90)
	k.prop("shipping_container", "BunkB", Vector3(30, 0, 2), 20)
	for t: Array in [[Vector3(-8, 0, -10), 30.0], [Vector3(8, 0, -24), -20.0], [Vector3(-30, 0, 0), 90.0]]:
		k.tent("Tent", t[0], t[1])
	k.prop("burning_barrel", "FireA", Vector3(0, 0, -6), 0)
	k.prop("burning_barrel", "FireB", Vector3(-12, 0, 4), 0)
	k.prop("burning_barrel", "FireC", Vector3(12, 0, 6), 0)
	k.prop("fuel_drums", "CampDrums", Vector3(-26, 0, 20), 0)
	k.prop("truck", "RaiderTruck", Vector3(20, 0, -22), 150)
	k.pile("scrap", "ScrapA", null, Vector3(-4, 0, 32), 0)
	k.pile("scrap", "ScrapB", null, Vector3(28, 0, -12), 40)
	k.pile("scrap", "ScrapC", null, Vector3(-28, 0, -18), -30)
	k.pile("pallet", "PalletA", null, Vector3(6, 0, -14), 15)
	k.pickup("shotgun_shells", 10, "FireShells", null, Vector3(1.5, 0, -8))
	k.pickup("metal_plate", 1, "CampPlate", null, Vector3(-18, 0, 6))
	k.pickup("leather", 2, "CampLeather", null, Vector3(18, 0, 10))
	k.container("crate", "CampCache", null, Vector3(-8, 0, 22), 0, "scorch_cache", "Raider Cache")
	_sign_board(k, "TurnBack", P3 + "sign_sign_turn_back.tres", Vector3(gate.x + 12, 0, gate.y - 14), 180, Vector2(1.8, 0.7))
	k.spawner("MarauderSpawner", "marauder", 3, 150.0, [Vector2(0, 0), Vector2(-14, 18), Vector2(14, 22)])
	k.spawner("VeteranSpawner", "veteran", 3, 120.0, [Vector2(-20, -24), Vector2(20, -26), Vector2(0, -32)])
	k.spawner("RaiderSpawner", "raider", 2, 60.0, [Vector2(-20, 34), Vector2(26, -2)])
	return k
