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
## The seven places are BLOCKOUTS here: rough shapes where each place
## stands, with its name on the compass. Increment 26 builds them out.
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


# ================================================================ the places (blockouts)

## Each place: [material, size, position (local x, z, from the place's
## centre), yaw] boxes standing on the ground; "cyl" entries are
## [radius, height] cylinders. Roads through a place are kept clear.
const BLOCKOUTS := {
	# A ruined town at the foot of the mesa, its street running north from
	# the end of the road
	"RedMesa": [
		["plaster", Vector3(12, 7, 10), Vector2(-14, 40), 0.0], ["brick", Vector3(10, 9, 12), Vector2(-16, 14), 0.0],
		["plaster", Vector3(14, 6, 9), Vector2(-15, -14), 0.0], ["concrete_stained", Vector3(11, 12, 11), Vector2(-17, -40), 0.0],
		["brick", Vector3(12, 8, 10), Vector2(30, 38), 0.0], ["plaster", Vector3(10, 6, 14), Vector2(32, 10), 0.0],
		["concrete_stained", Vector3(13, 10, 10), Vector2(30, -18), 0.0], ["plaster", Vector3(9, 5, 9), Vector2(28, -44), 0.0],
		["brick", Vector3(18, 7, 10), Vector2(8, -64), 0.0], ["corrugated", Vector3(8, 4, 6), Vector2(-40, 0), 12.0],
		["cyl", 3.2, 14.0, Vector2(-38, 30), "rust"],  # water tower
	],
	# A reservoir behind a concrete wall, the pump house and its pipes
	"DryRiverPumpStation": [
		["concrete", Vector3(56, 3, 2), Vector2(10, -20), 0.0],
		["concrete", Vector3(24, 3, 2), Vector2(-6, 20), 0.0], ["concrete", Vector3(24, 3, 2), Vector2(26, 20), 0.0],  # a gate in the middle
		["concrete", Vector3(2, 3, 40), Vector2(-18, 0), 0.0], ["concrete", Vector3(2, 3, 40), Vector2(38, 0), 0.0],
		["concrete_stained", Vector3(16, 9, 12), Vector2(-4, 36), 0.0], ["metal_dark", Vector3(6, 6, 6), Vector2(14, 36), 0.0],
		["cyl", 1.0, 30.0, Vector2(-30, 36), "rust"], ["corrugated", Vector3(10, 4, 8), Vector2(30, 38), 0.0],
	],
	# Spoil heaps round the pit's edge, the crusher tower and its conveyor
	"CinderQuarry": [
		["gravel", Vector3(22, 8, 16), Vector2(-30, -40), 25.0], ["gravel", Vector3(26, 10, 18), Vector2(20, -50), -15.0],
		["gravel", Vector3(20, 7, 22), Vector2(45, 0), 10.0], ["gravel", Vector3(24, 9, 16), Vector2(18, 45), 30.0],
		["metal_dark", Vector3(10, 18, 10), Vector2(-40, 20), 0.0], ["rust", Vector3(28, 2, 3), Vector2(-20, 26), -20.0],
		["corrugated", Vector3(14, 6, 10), Vector2(-58, -10), 0.0], ["concrete_stained", Vector3(9, 4, 7), Vector2(-62, 14), 0.0],
	],
	# Engine sheds south of the tracks, the yard office north of them, wagons
	# on a siding
	"IronVeinRailYard": [
		["corrugated", Vector3(44, 10, 16), Vector2(-20, 30), -15.0], ["corrugated", Vector3(40, 9, 14), Vector2(36, 34), -15.0],
		["brick", Vector3(14, 7, 9), Vector2(-30, -26), -15.0], ["container_red", Vector3(14, 3.6, 3), Vector2(10, 12), -15.0],
		["container_olive", Vector3(14, 3.6, 3), Vector2(26, 8), -15.0], ["container_blue", Vector3(14, 3.6, 3), Vector2(42, 4), -15.0],
		["metal_dark", Vector3(6, 14, 6), Vector2(60, -14), 0.0], ["rust", Vector3(10, 5, 8), Vector2(-60, 18), -15.0],
	],
	# Two rows of buildings along the main street (the road), a few of them tall
	"Dusthaven": [
		["concrete_stained", Vector3(14, 22, 14), Vector2(-26, -50), 0.0], ["plaster", Vector3(12, 8, 18), Vector2(-24, -18), 0.0],
		["brick", Vector3(12, 12, 14), Vector2(-24, 12), 0.0], ["concrete", Vector3(14, 26, 14), Vector2(-28, 46), 0.0],
		["plaster", Vector3(12, 7, 16), Vector2(24, -46), 0.0], ["concrete_stained", Vector3(12, 16, 12), Vector2(26, -14), 0.0],
		["brick", Vector3(14, 9, 18), Vector2(26, 20), 0.0], ["plaster", Vector3(12, 6, 12), Vector2(20, 56), 0.0],
		["corrugated", Vector3(10, 5, 8), Vector2(-52, 0), 0.0], ["concrete", Vector3(10, 18, 10), Vector2(52, 4), 0.0],
	],
	# Fuel canopy, the diner and the garage
	"BrokenSpurTruckStop": [
		["paint_white", Vector3(18, 0.6, 12), Vector2(0, 0), 0.0, 5.0],  # the canopy, raised
		["metal_dark", Vector3(0.5, 5, 0.5), Vector2(-8, -5), 0.0], ["metal_dark", Vector3(0.5, 5, 0.5), Vector2(8, -5), 0.0],
		["metal_dark", Vector3(0.5, 5, 0.5), Vector2(-8, 5), 0.0], ["metal_dark", Vector3(0.5, 5, 0.5), Vector2(8, 5), 0.0],
		["plaster", Vector3(18, 5, 10), Vector2(-14, 26), 0.0], ["corrugated", Vector3(14, 6, 12), Vector2(18, 26), 0.0],
		["container_red", Vector3(12, 3.6, 3), Vector2(-30, -6), 80.0],
	],
	# Shacks and scrap walls in a ring, with a lookout
	"RaiderCampScorch": [
		["rust", Vector3(30, 3.5, 1), Vector2(0, -38), 0.0], ["rust", Vector3(1, 3.5, 30), Vector2(-38, -10), 0.0],
		["rust", Vector3(1, 3.5, 26), Vector2(38, -6), 0.0], ["corrugated", Vector3(8, 4, 6), Vector2(-20, -12), 15.0],
		["corrugated", Vector3(7, 3.5, 6), Vector2(18, -18), -10.0], ["wood", Vector3(9, 4, 7), Vector2(-14, 16), 5.0],
		["corrugated", Vector3(10, 4.5, 7), Vector2(20, 14), -20.0], ["wood", Vector3(3, 9, 3), Vector2(0, 30), 0.0],
		["container_olive", Vector3(12, 3.6, 3), Vector2(-30, 26), 40.0],
	],
}


func _add_places(zone: Node3D) -> void:
	var blockouts := Node3D.new()
	blockouts.name = "Blockouts"
	zone.add_child(blockouts)
	for key: String in PLACES:
		var c: Vector2 = PLACES[key][1]
		var body := _solid_body(key)
		body.position = Vector3(c.x, 0, c.y)
		body.set_meta("blockout", true)
		var n := 0
		for b: Array in BLOCKOUTS.get(key, []):
			n += 1
			var at: Vector2 = b[3] if str(b[0]) == "cyl" else b[2]
			if str(b[0]) == "cyl":
				_cylinder(body, "Part%d" % n, float(b[1]), float(b[2]), Vector3(at.x, float(b[2]) * 0.5, at.y), str(b[4]))
				continue
			var size: Vector3 = b[1]
			var lift := float(b[4]) if b.size() > 4 else 0.0
			_box(body, "Part%d" % n, size, Vector3(at.x, lift + size.y * 0.5, at.y), str(b[0]), float(b[3]))
		blockouts.add_child(body)
