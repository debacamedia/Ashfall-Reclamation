extends "res://tools/build_early_zone.gd"
## Builds the mid zone (Increment 25): the band of country east of the early
## zone on the Regional Buildout Map (docs/art/regional_buildout_map.png),
## from Red Mesa in the north round to Raider Camp Scorch in the south.
##
## Same builder as the early zone, with its own data; the two zones share
## one map frame (1 px of the map = 1.1 m, Outpost 17 at the origin), so
## the road east out of Halden's Crossing crosses the early zone's edge and
## the mid zone's at the same spot (656.6, -288), where ZoneExits take you
## between them.
##
## Run from the project root (re-running rebuilds everything it makes):
##
##     godot --headless --path . -s res://tools/build_mid_zone.gd
##     … -- zone-only       (just mid_zone.tscn)
##     … -- zone-only bake  (that, and a fresh navmesh)
##
## Then render its map picture (needs a window):
##     godot --path . -s res://tools/render_map.gd -- mid_zone
##
## Writes levels/mid_zone/ (mid_zone.tscn, terrain.scn, roads.scn,
## rocks.scn, navigation.scn, mid_zone_environment.tres, materials/).
##
## The seven places are site scenes from tools/build_mid_sites.gd (Increment
## 26); in 25 they were blockouts. Build the sites first.
##
## Where the map put two of them inside the early zone's edge as built
## (Dry River Pump Station and Broken Spur Truck Stop) they've moved east
## and south into the mid zone, keeping their places relative to the rest.


func _init() -> void:
	OUT = "res://levels/mid_zone/"
	ZONE_NODE = "MidZone"
	REGION_NAME = "Mid Zone"
	SCENE_FILE = "mid_zone.tscn"
	ENV_FILE = "mid_zone_environment.tres"
	SPAWN = Vector3(682, 0.05, -291)  # where the road from the early zone comes in
	RAIL_BUFFER_STOP = false

	## Places: node name -> [display name, centre (x, z), radius, compass name]
	PLACES = {
		"RedMesa": ["Red Mesa", Vector2(700, -735), 85.0, "Red Mesa"],
		"DryRiverPumpStation": ["Dry River Pump Station", Vector2(752, -455), 70.0, "Dry River"],
		"CinderQuarry": ["Cinder Quarry", Vector2(890, -545), 85.0, "Cinder Quarry"],
		"IronVeinRailYard": ["Iron Vein Rail Yard", Vector2(830, -300), 90.0, "Iron Vein"],
		"Dusthaven": ["Dusthaven", Vector2(770, -105), 100.0, "Dusthaven"],
		"BrokenSpurTruckStop": ["Broken Spur Truck Stop", Vector2(600, 95), 60.0, "Broken Spur"],
		"RaiderCampScorch": ["Raider Camp Scorch", Vector2(740, 160), 70.0, "Scorch"],
	}

	## The playable area. Its west side is the early zone's east edge, point
	## for point, so the two zones meet without a gap or an overlap.
	EDGE = [
		Vector2(300, 115), Vector2(480, 50), Vector2(610, -70), Vector2(660, -230),
		Vector2(650, -400), Vector2(610, -580), Vector2(540, -745), Vector2(420, -800),
		Vector2(430, -880), Vector2(620, -920), Vector2(820, -915), Vector2(990, -860),
		Vector2(1060, -720), Vector2(1050, -560), Vector2(1000, -420), Vector2(960, -290),
		Vector2(935, -150), Vector2(910, -20), Vector2(890, 120), Vector2(840, 240),
		Vector2(680, 275), Vector2(520, 250), Vector2(380, 200), Vector2(300, 160),
	]
	SEA_EDGES = []

	ROADS = [
		# From the early zone (it starts in the storm, past the edge) to the
		# junction west of the rail yard, then along the yard's north side and
		# on east toward the late zone
		["EastRoad", "main", 7.0, [Vector2(626, -286), Vector2(656.6, -288), Vector2(690, -297),
			Vector2(712, -305), Vector2(745, -330), Vector2(790, -346), Vector2(850, -350),
			Vector2(910, -342), Vector2(990, -332)]],
		# North: past Dry River Pump Station to the foot of Red Mesa
		["RoadNorth", "gravel", 5.5, [Vector2(712, -305), Vector2(705, -360), Vector2(694, -420),
			Vector2(694, -480), Vector2(702, -528), Vector2(710, -600), Vector2(712, -652)]],
		["RoadToQuarry", "gravel", 5.0, [Vector2(702, -528), Vector2(760, -531), Vector2(806, -541)]],
		# South: down Dusthaven's main street to Broken Spur
		["RoadSouth", "gravel", 6.0, [Vector2(712, -305), Vector2(722, -250), Vector2(742, -198),
			Vector2(762, -160), Vector2(770, -105), Vector2(766, -42), Vector2(722, 2),
			Vector2(662, 30), Vector2(626, 48)]],
		["TrailToScorch", "trail", 4.0, [Vector2(768, -30), Vector2(772, 20), Vector2(756, 72),
			Vector2(746, 94)]],
	]
	## The railway from the early zone, through the rail yard and on east
	RAIL = [Vector2(600, -213), Vector2(620, -228), Vector2(700, -258), Vector2(760, -279),
		Vector2(820, -297), Vector2(880, -313), Vector2(960, -333), Vector2(1040, -352)]

	VEHICLES = []
	SURVIVORS = []
	TIMBER = [
		[Vector2(640, -160), 26.0, 6, 2], [Vector2(850, -440), 28.0, 6, 2], [Vector2(640, -640), 26.0, 5, 2],
		[Vector2(860, 40), 26.0, 5, 2], [Vector2(470, 175), 28.0, 6, 2], [Vector2(900, -200), 24.0, 4, 2],
	]
	SIGNPOSTS = [
		[Vector2(702, -318), ["IronVeinRailYard", "DryRiverPumpStation", "Dusthaven"]],
		[Vector2(690, -535), ["RedMesa", "CinderQuarry", "DryRiverPumpStation"]],
		[Vector2(780, -32), ["RaiderCampScorch", "BrokenSpurTruckStop", "Dusthaven"]],
	]
	TINTS = [
		[Vector2(710, -820), 260.0, Color(1.1, 0.78, 0.64)],   # Red Mesa: red earth
		[Vector2(740, 190), 190.0, Color(1.08, 0.8, 0.66)],    # Scorch: red earth
		[Vector2(430, 200), 120.0, Color(1.05, 0.84, 0.72)],
		[Vector2(900, -545), 160.0, Color(0.72, 0.71, 0.72)],  # Cinder Quarry: grey dust
		[Vector2(770, -105), 150.0, Color(0.84, 0.8, 0.74)],   # Dusthaven: trodden
		[Vector2(830, -300), 120.0, Color(0.8, 0.76, 0.7)],    # the rail yard: cinders
		[Vector2(752, -455), 90.0, Color(0.9, 0.9, 0.82)],     # Dry River: damp
	]
	## [style, material, centre, radius, count, width min, width max, height / width]
	ROCK_CLUSTERS = [
		["mesa", "rock_red", Vector2(720, -850), 95.0, 9, 30.0, 62.0, Vector2(0.34, 0.5)],  # the mesa itself
		["mesa", "rock_red", Vector2(590, -820), 70.0, 5, 16.0, 30.0, Vector2(0.4, 0.7)],
		["mesa", "rock_red", Vector2(830, -800), 70.0, 5, 14.0, 28.0, Vector2(0.45, 0.75)],
		["mesa", "rock_red", Vector2(770, 225), 70.0, 7, 14.0, 30.0, Vector2(0.45, 0.8)],   # round Scorch
		["mesa", "rock_red", Vector2(640, 215), 50.0, 4, 10.0, 22.0, Vector2(0.45, 0.8)],
		["mesa", "rock_red", Vector2(420, 185), 55.0, 5, 10.0, 22.0, Vector2(0.45, 0.8)],
		["hill", "rock_dark", Vector2(985, -650), 80.0, 5, 22.0, 40.0, Vector2(0.3, 0.5)],  # behind the quarry
		["boulder", "rock_dark", Vector2(900, -545), 140.0, 14, 3.0, 9.0, Vector2(0.5, 0.8)],
		["mesa", "rock_red", Vector2(880, -60), 45.0, 4, 10.0, 20.0, Vector2(0.45, 0.8)],
		["boulder", "rock_red", Vector2(620, -460), 50.0, 5, 5.0, 12.0, Vector2(0.5, 0.8)],
		["boulder", "rock_tan", Vector2(760, -330), 520.0, 70, 2.0, 6.0, Vector2(0.45, 0.8)],
	]

	EXITS = [
		["ToEarlyZone", Vector2(656.6, -288.0), 14.0, "res://levels/early_zone/early_zone.tscn", &"FromMidZone", "the Early Zone",
			Vector2(684, -279), 90.0],
	]
	ARRIVALS = [
		["FromEarlyZone", Vector2(682, -291), 90.0],
	]


# ================================================================ the places

## Each place is a site scene built by tools/build_mid_sites.gd (Increment
## 26; they were blockouts in 25), placed at its spot in PLACES.
const SITE_FOLDERS := {
	"RedMesa": "red_mesa", "DryRiverPumpStation": "dry_river_pump_station", "CinderQuarry": "cinder_quarry",
	"IronVeinRailYard": "iron_vein_rail_yard", "Dusthaven": "dusthaven",
	"BrokenSpurTruckStop": "broken_spur_truck_stop", "RaiderCampScorch": "raider_camp_scorch",
}


func _add_places(zone: Node3D) -> void:
	for key: String in PLACES:
		var folder: String = SITE_FOLDERS[key]
		var site := (load("res://levels/%s/%s.tscn" % [folder, folder]) as PackedScene).instantiate() as Node3D
		site.name = key
		var c: Vector2 = PLACES[key][1]
		site.position = Vector3(c.x, 0, c.y)
		zone.add_child(site)
