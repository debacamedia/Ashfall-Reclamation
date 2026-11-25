extends SceneTree
## Increment 33.2: Outpost 17 rebuilt, from the approved proof (the
## "Outpost 17, rebuilt as a place to hold" page):
##
##   - The walls pushed east to 95 x 50 m, in today's stone look, with the
##     firing range inside them (its old raised platform and ramp gone).
##   - The command post (Sgt. Vance's office, the radio room with a mast on
##     the roof, the armory with the weapons bench), a mess hall where the
##     stacked containers stood (its stove makes it the post's Kitchen), the
##     barracks with eight bunks, the stores and workshop, a motor pool shed,
##     a water tower with a pump, and garden plots for four Farmers.
##   - A place you can claim, at the notice board on the parade ground.
##
## Everything you can search, scrap or pick up keeps its name (saves find it
## by its name), just moved to where it now belongs; saves from before have
## their outpost pickups and props put where the new layout has them
## (SaveManager, save version 5).
##
## It rebuilds the hand-made level once (it stops if the level's already
## rebuilt), then the buildings get the city kit's walls:
##
##   godot --headless --path . -s res://tools/rebuild_outpost_17.gd
##   godot --headless --path . -s res://tools/rebuild_haldens.gd -- outpost
##   godot --headless --path . -s res://tools/build_early_zone.gd -- zone-only bake
##
## (to run it again, put the level back first:
##   git show 12722e8:levels/outpost_17/outpost_17.tscn > levels/outpost_17/outpost_17.tscn)

const Kit := preload("res://tools/site_kit.gd")
const LEVEL := "res://levels/outpost_17/outpost_17.tscn"
const MESS_KITCHEN := "res://scenes/settlement/mess_kitchen.tscn"
const WALL_SEGMENT := "res://scenes/world/props/concrete_wall_segment.tscn"
const SLAB_MAT := "res://assets/ashfall_pack_v1/materials/concrete_weathered.tres"
const BASE_MAT := "res://assets/ashfall_pack_v1/materials/concrete_cracked.tres"
const GRAVEL := "res://assets/ashfall_pack_v1/materials/gravel_mixed.tres"
const EARTH := "res://assets/materials/earth_berm.tres"

## The walls: the west wall and the north and south runs as they were (2.45 m
## segments), the east wall moved out from x 31.85 to here
const EAST_X := 61.25
const SEGMENT := 2.45
## The settlement's centre: the middle of the walls (x -31.85 to 61.25)
const ST_AT := Vector3(14.7, 0, 0)

## Buildings: [name, centre (x, z), size (x, z), openings]
const CP_AT := Vector2(-12, -15.6)
const CP_SIZE := Vector2(11, 8)
const MESS_AT := Vector2(0, -18.6)
const MESS_SIZE := Vector2(10, 7)
const BARRACKS_AT := Vector2(12, -15.6)
const BARRACKS_SIZE := Vector2(11, 8)
const STORES_AT := Vector2(-20, 8)
const STORES_SIZE := Vector2(12, 16)

## The firing line and its targets: [name, (x, z), metres]
const FIRING_Z := 19.5
const TARGETS := [
	["Target10mA", Vector2(41.5, 9.5), 10], ["Target10mB", Vector2(47.5, 9.5), 10],
	["Target20m", Vector2(44.5, -0.5), 20], ["Target30m", Vector2(51.0, -10.5), 30],
	["Target40m", Vector2(41.0, -20.5), 40],
]

## Gone: the test leftovers and what the new buildings replace. (Saves from
## before that list any of these drop them: SaveManager.O17_REMOVED.)
const REMOVE := [
	"Buildings/CommandPost", "Buildings/Barracks", "Buildings/Warehouse",
	"Props/ContainerB", "Props/ContainerC",
	"Props/YardPositionN", "Props/YardPositionW",
	"FiringRange/RangeTower", "FiringRange/FiringLineN", "FiringRange/FiringLineS", "FiringRange/LaneGravel",
	"FiringRange/Target35m", "FiringRange/Target50m",
	"FiringRange/Distance35m", "FiringRange/Distance50m",
	"Surfaces/Yard", "Surfaces/MotorPool",
]

var lvl: Node3D
var k: Kit


func _initialize() -> void:
	_make_mess_kitchen()
	lvl = (load(LEVEL) as PackedScene).instantiate() as Node3D
	if lvl.has_node("Settlement"):
		push_error("Outpost 17 is already rebuilt: put the level back first (see the top of this file)")
		lvl.free()
		quit(1)
		return
	k = Kit.new("Outpost17", "Outpost 17", 17)
	k.root.free()
	k.root = lvl
	k.groups = {}
	for g in ["Buildings", "Props", "SalvageContainers", "CraftingStations", "SalvagePiles", "Loot", "Signage", "Soundscape"]:
		var n := lvl.get_node_or_null(g) as Node3D
		assert(n != null, g)
		k.groups[g] = n
	k.group("Furniture", true)
	for path in REMOVE:
		var n := lvl.get_node_or_null(path)
		assert(n != null, "nothing at " + path)
		n.get_parent().remove_child(n)
		n.free()
	_walls()
	_ground()
	var cp := _command_post()
	var mess := _mess_hall()
	var barracks := _barracks()
	var stores := _stores()
	_motor_pool()
	_water_tower()
	_gardens()
	_range()
	_yard()
	_settlement(cp, mess, barracks, stores)
	_own(lvl, lvl)
	var ps := PackedScene.new()
	var err := ps.pack(lvl)
	assert(err == OK)
	err = ResourceSaver.save(ps, LEVEL)
	print("saved ", LEVEL, ": ", error_string(err), " ", k.counts)
	lvl.free()
	quit()


## New nodes are owned by the level (so they're saved); what's inside an
## instanced scene stays the scene's.
func _own(node: Node, root: Node) -> void:
	for c in node.get_children():
		if c.owner == null:
			c.owner = root
			if c.scene_file_path == "":
				_own(c, root)
		elif c.owner == root and c.scene_file_path == "":
			_own(c, root)


func _move(path: String, pos: Vector3, yaw_deg := INF) -> Node3D:
	var n := lvl.get_node_or_null(path) as Node3D
	assert(n != null, "nothing at " + path)
	n.position = pos
	if yaw_deg != INF:
		n.rotation = Vector3(0, deg_to_rad(yaw_deg), 0)
	return n


## Moves `path` into `b`'s frame (local position and yaw).
func _move_in(path: String, b: Node3D, local: Vector3, local_yaw := 0.0) -> Node3D:
	return _move(path, k.at(b, local), rad_to_deg(k.yaw_in(b, local_yaw)))


## A container that's already in the level, moved against `b`'s wall.
func _container_to_wall(path: String, b: StaticBody3D, side: String, offset: float, kind: String) -> Node3D:
	var depth := 0.72 if kind == "crate" else (0.62 if kind == "locker" else 0.57)
	return _move_in(path, b, k.against(b, side, offset, depth / 2.0 + 0.08), Kit.facing_from(side))


func _surface(name: String, size: Vector2, at: Vector3, mat_path: String, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = load(mat_path)
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ================================================================ the walls

func _segment(name: String, at: Vector3, yaw_deg: float) -> void:
	var s := (load(WALL_SEGMENT) as PackedScene).instantiate() as Node3D
	s.name = name
	s.position = at
	s.rotation.y = deg_to_rad(yaw_deg)
	(s.get_node("Slab") as MeshInstance3D).material_override = load(SLAB_MAT)
	(s.get_node("Base") as MeshInstance3D).material_override = load(BASE_MAT)
	lvl.get_node("Perimeter").add_child(s)
	s.owner = lvl
	# (so its materials, set above, are saved with the level)
	lvl.set_editable_instance(s, true)


func _walls() -> void:
	# The north and south runs carry on east, as they were
	var i := 0
	var x := 30.625 + SEGMENT
	while x < EAST_X:
		_segment("NorthWallEast%d" % i, Vector3(x, 0, -24.5), 0)
		_segment("SouthWallEast%d" % i, Vector3(x, 0, 24.5), 180)
		x += SEGMENT
		i += 1
	# The east wall, moved out (the same twenty segments)
	for n in lvl.get_node("Perimeter").get_children():
		if n.name.begins_with("EastWall"):
			(n as Node3D).position.x = EAST_X
	# The two eastern corner towers go to the new corners
	_move("GuardTowers/GuardTower2", Vector3(EAST_X - 3.35, 0, -21))
	_move("GuardTowers/GuardTower4", Vector3(EAST_X - 3.35, 0, 21))


# ================================================================ the ground

func _ground() -> void:
	var s := lvl.get_node("Surfaces") as Node3D
	var west := -31.85
	_surface("Yard", Vector2(EAST_X - west, 49), Vector3((EAST_X + west) / 2.0, 0.006, 0), GRAVEL, s)
	_surface("ParadeGround", Vector2(24, 15), Vector3(0, 0.03, -2.5), Kit.MATERIALS["concrete_cracked"], s)
	_surface("MotorPool", Vector2(17, 18), Vector3(21.5, 0.012, 12), Kit.MATERIALS["concrete_stained"], s)
	_surface("RangeLane", Vector2(27, 44), Vector3(47, 0.014, -1), "res://assets/materials/gravel.tres", s)
	# Paths: gate to parade ground, and across to the stores and the motor pool
	_surface("PathGate", Vector2(4, 18), Vector3(0, 0.014, 14.5), Kit.MATERIALS["concrete_plain"], s)
	_surface("PathStores", Vector2(11, 3), Vector3(-8.5, 0.014, 4.5), Kit.MATERIALS["concrete_plain"], s)


# ================================================================ the command post

func _command_post() -> StaticBody3D:
	var b := k.building("CommandPost", CP_AT, 0, CP_SIZE, {
		"wall": "concrete", "floor": "concrete_plain", "roof": "flat",
		"openings": [["S", 0.2, "door"], ["W", 0, "window"], ["E", 0, "window"], ["N", -3.4, "window"], ["N", 3.7, "window"]],
		# Vance's office (west), the radio room (middle, the way in), the armory (east)
		"inner": [[Vector2(-1.6, -4), Vector2(-1.6, 4), [5.6]], [Vector2(2.0, -4), Vector2(2.0, 4), [5.6]]],
	})
	# Vance's office: her desk, maps on the wall, her footlocker
	k.fixture("VanceDesk", b, Vector3(-3.4, 0, -2.75), Vector3(1.8, 0.78, 0.8), "wood_plain")
	k.fixture("VanceChair", b, Vector3(-3.4, 0, -1.75), Vector3(0.5, 0.46, 0.5), "metal_dark")
	k.fixture("MapBoard", b, Vector3(-3.4, 1.15, -3.67), Vector3(2.0, 1.1, 0.04), "sign_wood")
	k.fixture("Map", b, Vector3(-3.55, 1.22, -3.64), Vector3(1.3, 0.9, 0.02), "paint_white")
	k.fixture("Orders", b, Vector3(-2.45, 1.45, -3.64), Vector3(0.4, 0.55, 0.02), "paint_white")
	k.fixture("WallMap", b, Vector3(-5.18, 1.1, 0.4), Vector3(0.02, 0.9, 1.4), "paint_white")
	k.fixture("FilingCabinet", b, Vector3(-4.75, 0, -2.9), Vector3(0.5, 1.3, 0.6), "olive")
	k.container_at_wall("footlocker", "VanceFootlocker", b, "W", 2.3, "officer_locker", "Sgt. Vance's Footlocker")
	_move_in("Loot/CommandPostElectronics", b, Vector3(-2.85, 0.78, -2.7))
	_move_in("SalvagePiles/CommandPostFurniture", b, Vector3(-3.9, 0, 0.4), 20)
	# The radio room: the field radio on its table, the mast on the roof
	k.fixture("RadioTable", b, Vector3(0.2, 0, -3.15), Vector3(2.8, 0.78, 0.7), "metal_dark")
	_move_in("Pack2/Props/FieldRadio", b, Vector3(0.7, 0.78, -3.15))
	_move("Soundscape/RadioStatic", k.at(b, Vector3(0.4, 1.2, -3.0)))
	_move("Pack2/Sounds/RadioChatter", k.at(b, Vector3(0.7, 1.1, -3.15)))
	var mast := k.solid_body(k.groups["Buildings"], "RadioMast", Transform3D(Basis.IDENTITY, k.at(b, Vector3(0.6, 3.6, -3.0))))
	k.box(mast, "Pole", Vector3(0.22, 9.0, 0.22), Vector3(0, 4.5, 0), "metal_dark")
	k.box(mast, "Foot", Vector3(0.8, 0.12, 0.8), Vector3(0, 0.06, 0), "metal_dark")
	k.box(mast, "Yard", Vector3(2.2, 0.08, 0.08), Vector3(0, 7.6, 0), "metal_dark", 0.0, false)
	k.box(mast, "Whip", Vector3(0.05, 2.0, 0.05), Vector3(0, 10.0, 0), "metal_dark", 0.0, false)
	var dish := k.box(mast, "Dish", Vector3(1.2, 1.2, 0.12), Vector3(0, 5.8, 0.35), "metal_dark", 0.0, false)
	dish.rotation.x = deg_to_rad(-20)
	for sx in [-1, 1]:
		var guy := k.box(mast, "Guy%d" % sx, Vector3(0.03, 5.5, 0.03), Vector3(sx * 1.4, 2.6, 0), "metal_dark", 0.0, false)
		guy.rotation.z = deg_to_rad(sx * 30)
	# The armory: the weapons bench, the post's lockers, ammunition on a table
	_move_in("CraftingStations/WeaponsBench", b, Vector3(3.65, 0, -3.1))
	_container_to_wall("SalvageContainers/CommandPostLocker", b, "E", -0.9, "locker")
	k.fixture("AmmoTable", b, Vector3(3.5, 0, 3.0), Vector3(1.9, 0.78, 0.7), "wood_plain")
	_move_in("Loot/CommandPostAmmo", b, Vector3(2.85, 0.78, 3.0))
	_move_in("Loot/CommandPostShells", b, Vector3(3.35, 0.78, 3.05))
	_move_in("Loot/CommandPostBarrel", b, Vector3(3.85, 0.78, 2.95))
	_move_in("Loot/CommandPostTrigger", b, Vector3(4.3, 0.78, 3.05))
	# Signs and posters on the front, on the solid ends of the wall (between
	# them it's windows and the door)
	_move("Pack2/Signs/RadioRelay", k.at(b, Vector3(-4.2, 2.6, 4.01)))
	return b


# ================================================================ the mess hall

func _mess_hall() -> StaticBody3D:
	var b := k.building("MessHall", MESS_AT, 0, MESS_SIZE, {
		"wall": "concrete", "floor": "concrete_plain", "roof": "flat",
		"openings": [["S", 0, "door"], ["W", 0, "window"], ["E", 0, "window"]],
	})
	for side in [-1, 1]:
		var x: float = side * 2.6
		k.fixture("MessTable%s" % ("W" if side < 0 else "E"), b, Vector3(x, 0, 0.7), Vector3(2.8, 0.76, 0.9), "wood_plain")
		k.fixture("MessBenchN%s" % ("W" if side < 0 else "E"), b, Vector3(x, 0, -0.1), Vector3(2.8, 0.44, 0.32), "wood")
		k.fixture("MessBenchS%s" % ("W" if side < 0 else "E"), b, Vector3(x, 0, 1.5), Vector3(2.8, 0.44, 0.32), "wood")
	_move_in("Props/Crate4", b, Vector3(-4.15, 0, 2.7), 8)
	_move_in("Loot/YardScrap", b, Vector3(2.2, 0.76, 0.6))
	return b


# ================================================================ the barracks

func _barracks() -> StaticBody3D:
	var b := k.building("Barracks", BARRACKS_AT, 0, BARRACKS_SIZE, {
		"wall": "concrete", "floor": "concrete_plain", "roof": "flat",
		"openings": [["S", 0, "door"], ["N", -3.4, "window"], ["N", 3.4, "window"], ["W", 0, "window"], ["E", 0, "window"]],
	})
	# Eight bunks, four along each long wall, a footlocker at the foot of the end ones
	var i := 0
	for z in [-2.65, 2.65]:
		for x in [-4.45, -2.55, 2.55, 4.45]:
			k.fixture("Bunk%d" % i, b, Vector3(x, 0, z), Vector3(2.0, 0.5, 0.92), "olive", 90)
			k.fixture("Pillow%d" % i, b, Vector3(x, 0.5, z - signf(z) * 0.72), Vector3(0.6, 0.1, 0.35), "canvas")
			i += 1
	_move_in("SalvageContainers/BarracksFootlockerWest", b, Vector3(-4.45, 0, -1.05))
	_move_in("SalvageContainers/BarracksFootlockerEast", b, Vector3(4.45, 0, -1.05))
	_container_to_wall("SalvageContainers/BarracksLocker", b, "W", 0.0, "locker")
	k.fixture("BunkTable", b, Vector3(0, 0, -3.2), Vector3(1.3, 0.74, 0.55), "wood_plain")
	_move_in("Loot/BarracksMedkit", b, Vector3(-0.3, 0.74, -3.2))
	_move_in("Loot/BarracksPistolAmmo", b, Vector3(0.35, 0.74, -3.15))
	_move_in("Loot/BarracksCloth", b, Vector3(2.55, 0.5, 2.45))
	_move("Pack2/Signs/MedicalTriage", k.at(b, Vector3(4.4, 2.6, 4.01)))
	return b


# ================================================================ the stores and workshop

func _stores() -> StaticBody3D:
	var b := k.building("StoresWorkshop", STORES_AT, 0, STORES_SIZE, {
		"wall": "corrugated", "floor": "concrete_plain", "roof": "flat",
		"openings": [["E", -3.0, "wide"], ["W", -4, "window"], ["W", 4, "window"], ["N", 0, "window"]],
	})
	# The workbench at the north end, the crates either side of it
	_move_in("CraftingStations/Workbench", b, Vector3(-1.6, 0, -7.1))
	_container_to_wall("SalvageContainers/WarehouseCrateNorth", b, "N", 2.4, "crate")
	_container_to_wall("SalvageContainers/WarehouseCrateSouth", b, "S", -3.6, "crate")
	_container_to_wall("SalvageContainers/WarehouseAmmoCrate", b, "S", -1.6, "crate")
	# Shelving along the west wall (loot on the boards)
	_shelf(b, "ShelfA", Vector3(-5.35, 0, 3.9))
	_shelf(b, "ShelfB", Vector3(-5.35, 0, 6.4))
	_move_in("Loot/WarehouseShelfScrap", b, Vector3(-5.35, 1.34, 3.5))
	_move_in("Loot/WarehouseShelfCloth", b, Vector3(-5.35, 0.19, 4.3))
	_move_in("Loot/WarehouseShelfElectronics", b, Vector3(-5.35, 1.34, 6.7))
	_move_in("Loot/WarehouseFuel", b, Vector3(-1.4, 0, 3.6))
	_move_in("Loot/WarehouseAmmo", b, Vector3(1.2, 0, -6.6))
	_move_in("SalvagePiles/WarehousePallet", b, Vector3(3.4, 0, -5.4), 8)
	_move_in("SalvagePiles/WarehousePallet2", b, Vector3(3.4, 0, 6.2), -12)
	# The salvage sign by the bay
	_move("Signage/WarehouseSalvage", k.at(b, Vector3(6.01, 2.6, -6.2)))
	return b


## A steel shelving unit against the west wall: four boards, two uprights
## at each end.
func _shelf(b: StaticBody3D, name: String, local: Vector3) -> void:
	for y in [0.15, 0.75, 1.3, 1.85]:
		k.fixture("%sBoard%d" % [name, int(y * 100)], b, local + Vector3(0, y, 0), Vector3(0.55, 0.04, 2.4), "metal_dark")
	for dz in [-1.18, 1.18]:
		for dx in [-0.25, 0.25]:
			k.fixture("%sPost%d%d" % [name, int(dz * 10), int(dx * 10)], b, local + Vector3(dx, 0, dz), Vector3(0.04, 1.92, 0.04), "metal_dark")


# ================================================================ the motor pool

func _motor_pool() -> void:
	var shed := k.solid_body(k.groups["Buildings"], "MotorPoolShed", Transform3D(Basis.IDENTITY, Vector3(21.5, 0, 12)))
	# Steel posts, a corrugated roof over the trucks' bay, walls at the back
	# (east) and the north end, open to the yard
	for x in [-7.5, 0.0, 7.5]:
		for z in [-7.0, 7.0]:
			k.box(shed, "Post%d_%d" % [int(x), int(z)], Vector3(0.25, 4.3, 0.25), Vector3(x, 2.15, z), "rust")
	k.box(shed, "Roof", Vector3(15.8, 0.12, 14.8), Vector3(0, 4.36, 0), "corrugated")
	k.box(shed, "Beam0", Vector3(15.2, 0.3, 0.2), Vector3(0, 4.15, -7.0), "rust", 0.0, false)
	k.box(shed, "Beam1", Vector3(15.2, 0.3, 0.2), Vector3(0, 4.15, 7.0), "rust", 0.0, false)
	k.box(shed, "WallE", Vector3(0.12, 4.3, 14.2), Vector3(7.6, 2.15, 0), "corrugated")
	k.box(shed, "WallN", Vector3(15.2, 4.3, 0.12), Vector3(0, 2.15, -7.08), "corrugated")
	# The tool wall and its chest
	k.box(shed, "ToolBoard", Vector3(0.06, 1.3, 3.0), Vector3(7.5, 1.6, -1.5), "sign_wood", 0.0, false)
	for i in 5:
		k.box(shed, "Tool%d" % i, Vector3(0.04, 0.5 + 0.1 * (i % 3), 0.1), Vector3(7.45, 1.55, -2.7 + i * 0.6), "metal_dark", 0.0, false)
	_move("SalvageContainers/MotorPoolToolChest", Vector3(28.6, 0, 13.5), -90)
	# The fuel point
	var pump := k.solid_body(k.groups["Buildings"], "FuelPoint", Transform3D(Basis.IDENTITY, Vector3(28.3, 0, 18.2)))
	k.box(pump, "Pump", Vector3(0.6, 1.5, 0.45), Vector3(0, 0.75, 0), "olive")
	k.box(pump, "Hose", Vector3(0.08, 0.7, 0.08), Vector3(-0.34, 0.9, 0), "metal_dark", 0.0, false)
	k.box(pump, "Stripe", Vector3(0.62, 0.12, 0.47), Vector3(0, 1.3, 0), "hazard", 0.0, false)
	_move("Props/DrumsMotorPool", Vector3(27.6, 0, 16.2))
	_move("Props/DrumsYard", Vector3(15.2, 0, 18.6), 30)
	_move("Pack2/Overlays/MotorPoolRust", Vector3(29.03, 2.0, 10.0))
	# The WATER POINT sign on the shed's north wall, facing the water tower
	_move("Pack2/Signs/WaterPoint", Vector3(25.0, 2.2, 4.85), 180)
	_move("Soundscape/GeneratorHum", Vector3(27.6, 0.8, 7.0))
	# (the old chain-link fence round the motor pool now fences off the range)


# ================================================================ the water tower

func _water_tower() -> void:
	var at := Vector3(25, 0, -9.5)
	var t := k.solid_body(k.groups["Buildings"], "WaterTower", Transform3D(Basis.IDENTITY, at))
	for x in [-1.5, 1.5]:
		for z in [-1.5, 1.5]:
			k.box(t, "Leg%d%d" % [int(x), int(z)], Vector3(0.24, 6.2, 0.24), Vector3(x, 3.1, z), "rust")
	k.box(t, "BraceN", Vector3(3.0, 0.12, 0.1), Vector3(0, 2.6, -1.5), "rust", 0.0, false)
	k.box(t, "BraceS", Vector3(3.0, 0.12, 0.1), Vector3(0, 2.6, 1.5), "rust", 0.0, false)
	k.box(t, "BraceW", Vector3(0.1, 0.12, 3.0), Vector3(-1.5, 2.6, 0), "rust", 0.0, false)
	k.box(t, "BraceE", Vector3(0.1, 0.12, 3.0), Vector3(1.5, 2.6, 0), "rust", 0.0, false)
	k.box(t, "Deck", Vector3(4.0, 0.15, 4.0), Vector3(0, 6.25, 0), "metal_dark")
	var tank := MeshInstance3D.new()
	tank.name = "Tank"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.85
	cyl.bottom_radius = 1.85
	cyl.height = 3.2
	tank.mesh = cyl
	tank.material_override = k.mat("olive")
	tank.position = Vector3(0, 7.95, 0)
	t.add_child(tank)
	var cs := CollisionShape3D.new()
	cs.name = "TankCol"
	var sh := CylinderShape3D.new()
	sh.radius = 1.85
	sh.height = 3.2
	cs.shape = sh
	cs.position = tank.position
	t.add_child(cs)
	var lid := MeshInstance3D.new()
	lid.name = "Lid"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.2
	cone.bottom_radius = 1.95
	cone.height = 0.7
	lid.mesh = cone
	lid.material_override = k.mat("rust")
	lid.position = Vector3(0, 9.9, 0)
	t.add_child(lid)
	k.box(t, "Pipe", Vector3(0.16, 6.3, 0.16), Vector3(0.6, 3.15, 1.62), "metal_dark", 0.0, false)
	# The pump's on the yard side (the settlement's PumpHead), the generator and spare tank beside it
	_move("Pack2/Props/WaterTank", Vector3(21.6, 0, -8.0))
	_move("Pack2/Props/WaterPumpGenerator", Vector3(27.8, 0, -6.4), 180)
	_move("Pack2/Sounds/WaterPumpHum", Vector3(27.8, 0.6, -6.4))


# ================================================================ the gardens

func _gardens() -> void:
	for p: Array in [["GardenWest", Vector3(-23.3, 0, 20.0), 6.6], ["GardenEast", Vector3(-14.5, 0, 20.0), 6.6]]:
		var bed := Node3D.new()
		bed.name = p[0]
		bed.position = p[1]
		k.groups["Props"].add_child(bed)
		var w: float = p[2]
		var d := 4.2
		k.box(bed, "Soil", Vector3(w - 0.3, 0.26, d - 0.3), Vector3(0, 0.13, 0), "field_soil", 0.0, false)
		k.box(bed, "EdgeN", Vector3(w, 0.3, 0.15), Vector3(0, 0.15, -d / 2.0), "wood", 0.0, false)
		k.box(bed, "EdgeS", Vector3(w, 0.3, 0.15), Vector3(0, 0.15, d / 2.0), "wood", 0.0, false)
		k.box(bed, "EdgeW", Vector3(0.15, 0.3, d), Vector3(-w / 2.0, 0.15, 0), "wood", 0.0, false)
		k.box(bed, "EdgeE", Vector3(0.15, 0.3, d), Vector3(w / 2.0, 0.15, 0), "wood", 0.0, false)
		for r in 4:
			k.box(bed, "Row%d" % r, Vector3(w - 0.8, 0.34, 0.32), Vector3(0, 0.3, -1.35 + r * 0.9), "crop_green" if r % 2 == 0 else "crop", 0.0, false)


# ================================================================ the range

func _range() -> void:
	var fr := lvl.get_node("FiringRange") as Node3D
	var fx := k.solid_body(fr, "RangeBuilt")
	# The covered firing line: a roof on posts, sandbags along the front
	for x in [37.0, 45.5, 54.0]:
		for z in [FIRING_Z + 0.6, FIRING_Z + 4.0]:
			k.box(fx, "ShelterPost%d_%d" % [int(x), int(z)], Vector3(0.2, 2.9, 0.2), Vector3(x, 1.45, z), "wood")
	k.box(fx, "ShelterRoof", Vector3(17.8, 0.1, 4.2), Vector3(45.5, 2.95, FIRING_Z + 2.3), "corrugated")
	k.box(fx, "Sandbags", Vector3(17.0, 0.7, 0.5), Vector3(45.5, 0.35, FIRING_Z - 0.4), "sandbag")
	# The earth berm behind the targets, against the north wall
	k.box(fx, "Berm", Vector3(27.5, 3.2, 2.2), Vector3(47.2, 1.6, -22.9), "soot")
	var berm := k.box(fx, "BermFace", Vector3(27.5, 0.6, 3.6), Vector3(47.2, 1.25, -21.25), "soot", 0.0, false)
	berm.rotation.x = deg_to_rad(-40)
	(fx.get_node("Berm") as MeshInstance3D).material_override = load(EARTH)
	berm.material_override = load(EARTH)
	var backstop := lvl.get_node_or_null("FiringRange/Backstop") as Node3D
	if backstop != null:
		fr.remove_child(backstop)
		backstop.free()
	# The bench with the rounds on it, behind the sandbags
	var bench := _move("FiringRange/ShootingBench", Vector3(45.5, 0, FIRING_Z + 0.4), 90)
	assert(bench != null)
	_move("Loot/RangeAmmoA", Vector3(44.9, 0.94, FIRING_Z + 0.4))
	_move("Loot/RangeAmmoB", Vector3(46.1, 0.94, FIRING_Z + 0.4))
	_move("FiringRange/AmmoCrate", Vector3(50.0, 0, FIRING_Z + 2.6))
	_move("SalvageContainers/RangeAmmoCrate", Vector3(41.0, 0, FIRING_Z + 3.4), 180)
	_move("FiringRange/RangeSign", Vector3(35.0, 0, FIRING_Z + 1.5), -90)
	# The targets: steel targets facing the firing line, a marker beside each
	var dummy_scene := load("res://scenes/world/range/target_dummy.tscn") as PackedScene
	for t: Array in TARGETS:
		var n := fr.get_node_or_null(String(t[0])) as Node3D
		if n == null:
			n = dummy_scene.instantiate() as Node3D
			n.name = t[0]
			fr.add_child(n)
		n.position = Vector3(t[1].x, 0, t[1].y)
		# (a target's face is its -Z: toward the firing line, south)
		n.rotation = Vector3(0, PI, 0)
		var label_name := "Distance%dm" % int(t[2])
		var lab := fr.get_node_or_null(label_name) as Label3D
		if lab == null:
			lab = (fr.get_node("Distance10m") as Label3D).duplicate() as Label3D
			lab.name = label_name
			fr.add_child(lab)
		lab.text = "%d m" % int(t[2])
		lab.position = Vector3(t[1].x - 2.0, 0.5, t[1].y)
		lab.rotation = Vector3.ZERO
	# The old motor pool fence now runs along the range's west side
	var i := 0
	for n in lvl.get_node("Props").get_children():
		if n.name.begins_with("MotorPoolFence"):
			(n as Node3D).position = Vector3(32.8, 0, -22.5 + i * 3.0)
			(n as Node3D).rotation = Vector3(0, PI / 2.0, 0)
			i += 1


# ================================================================ the yard and gate

func _yard() -> void:
	# The yard's dressing, moved clear of the buildings
	_move("Props/Crate1", Vector3(-12.6, 0, 0.8), 12)
	_move("Props/Crate2", Vector3(-12.7, 0, 2.0), 4)
	_move("Props/Crate3", Vector3(-12.6, 1.0, 1.4), 30)
	_move("Props/BarracksCrate", Vector3(18.4, 0, -12.6), 20)
	# Two of the old shipping containers, on the ground now, by the water tower
	_move("Props/ContainerA", Vector3(30.9, 0, -18.5), 90)
	_move("Props/ContainerD", Vector3(30.9, 0, -8.5), 90)
	_move("Props/YardBarrier", Vector3(12.0, 0, 22.0), 90)
	_move("Props/GateSandbagsL", Vector3(-5.8, 0, 19.6))
	_move("Props/GateSandbagsR", Vector3(5.8, 0, 19.6))
	_move("SalvagePiles/BarracksFurniture", Vector3(18.6, 0, -14.6), 30)
	_move("Loot/GateMedkit", Vector3(7.4, 0, 18.2))
	# Posters on the new walls (Pack 3)
	lvl.set_editable_instance(lvl.get_node("Pack3Dressing"), true)
	var p3 := lvl.get_node("Pack3Dressing/Decals")
	(p3.get_node("PosterCommandPost") as Node3D).position = k.at(lvl.get_node("Buildings/CommandPost"), Vector3(4.4, 1.5, 4.01))
	(p3.get_node("PosterBarracks") as Node3D).position = k.at(lvl.get_node("Buildings/Barracks"), Vector3(0.0, 1.6, -3.68))


# ================================================================ the settlement

func _settlement(cp: StaticBody3D, mess: StaticBody3D, barracks: StaticBody3D, stores: StaticBody3D) -> void:
	var st := Settlement.new()
	st.name = "Settlement"
	st.position = ST_AT
	st.settlement_name = "Outpost 17"
	st.place_name = "Outpost 17"
	st.settlement_id = &"outpost_17"
	st.place_word = "the post"
	st.claim_hint = "hold E at the notice board on the parade ground"
	st.shelter_name = "the barracks"
	st.pump_where = "at the water tower"
	st.store_sign = "OUTPOST STORES"
	st.claim_radius = 56.0
	st.defend_radius = 54.0
	st.starting_food = 8
	st.beds = 8
	st.needs_gun = true
	lvl.add_child(st)
	st.add_to_group("navigation_geometry", true)
	var o := ST_AT
	# The notice board on the parade ground, by the flag
	var board_at := Vector3(4.5, 0, -6.0)
	var board := k.solid_body(st, "NoticeBoard", Transform3D(Basis.IDENTITY, board_at - o))
	for x in [-0.55, 0.55]:
		k.box(board, "Post", Vector3(0.1, 1.9, 0.1), Vector3(x, 0.95, 0), "wood")
	k.box(board, "Board", Vector3(1.3, 0.8, 0.06), Vector3(0, 1.4, 0.03), "wood")
	k.box(board, "Notice", Vector3(0.9, 0.55, 0.01), Vector3(0, 1.42, 0.065), "paint_white")
	k.box(board, "Roof", Vector3(1.5, 0.06, 0.36), Vector3(0, 1.92, 0.05), "rust")
	var claim := ClaimPoint.new()
	claim.name = "ClaimPoint"
	claim.position = board_at - o + Vector3(0, 1.4, 0.1)
	st.add_child(claim)
	_area(claim, Vector3(1.4, 1.0, 0.4))
	# The pump at the foot of the water tower
	var pump_at := Vector3(25.0, 0, -6.6)
	var head := k.solid_body(st, "PumpHead", Transform3D(Basis.IDENTITY, pump_at - o))
	k.box(head, "Base", Vector3(0.5, 0.2, 0.5), Vector3(0, 0.1, 0), "metal_dark")
	k.box(head, "Column", Vector3(0.22, 0.9, 0.22), Vector3(0, 0.65, 0), "rust")
	k.box(head, "Head", Vector3(0.34, 0.24, 0.3), Vector3(0, 1.2, 0), "rust")
	k.box(head, "Handle", Vector3(0.06, 0.06, 0.7), Vector3(0, 1.32, 0.3), "metal_dark", 0.0, false)
	k.box(head, "Spout", Vector3(0.1, 0.1, 0.3), Vector3(0.2, 1.05, 0), "rust", 90.0, false)
	var up2 := Node3D.new()
	up2.name = "Upgrade2"
	up2.visible = false
	head.add_child(up2)
	k.box(up2, "PressureTank", Vector3(0.4, 0.8, 0.4), Vector3(0.55, 0.4, -0.3), "metal_dark", 0.0, false)
	var motor := Node3D.new()
	motor.name = "Motor"
	motor.visible = false
	head.add_child(motor)
	k.box(motor, "Engine", Vector3(0.5, 0.4, 0.45), Vector3(-0.55, 0.2, 0.1), "olive", 0.0, false)
	k.box(motor, "Exhaust", Vector3(0.06, 0.6, 0.06), Vector3(-0.75, 0.7, 0.2), "rust", 0.0, false)
	var pump := WaterPump.new()
	pump.name = "WaterPump"
	pump.position = pump_at - o + Vector3(0, 0.9, 0)
	st.add_child(pump)
	_area(pump, Vector3(0.8, 1.6, 1.0))
	# The Outpost Stores: shelves along the stores' west wall, facing in
	var store := (load("res://scenes/world/containers/food_shelves.tscn") as PackedScene).instantiate() as Node3D
	store.name = "FarmStore"
	store.position = k.at(stores, Vector3(-5.25, 0, -2.5)) - o
	store.rotation.y = deg_to_rad(90)
	store.set("container_name", "Outpost Stores")
	store.set("object_name", "Outpost Stores")
	st.add_child(store)
	# The Armory Locker, in the command post's armory beside the bench
	var locker := k.scene("locker").instantiate() as Node3D
	locker.name = "Armory"
	locker.position = k.at(cp, k.against(cp, "E", 1.4, 0.39)) - o
	locker.rotation.y = k.yaw_in(cp, Kit.facing_from("E"))
	locker.set("container_name", "Armory Locker")
	locker.set("object_name", "Armory Locker")
	st.add_child(locker)
	var smiths := Node3D.new()
	smiths.name = "ArmorerSpots"
	st.add_child(smiths)
	var spot := Marker3D.new()
	spot.name = "ArmorerSpot0"
	spot.position = k.at(cp, Vector3(3.65, 0, -2.05)) - o
	smiths.add_child(spot)
	# The mess hall's stove and fridge: the post's Kitchen, there from the start
	var kitchen := (load(MESS_KITCHEN) as PackedScene).instantiate() as Node3D
	kitchen.name = "MessKitchen"
	kitchen.position = k.at(mess, Vector3(0, 0, -2.75)) - o
	st.add_child(kitchen)
	# Guards: by the gate (stood back from it), the range, the west wall, the north
	_markers(st, "GuardPosts", [Vector3(-3.5, 0, 18.4), Vector3(3.5, 0, 18.4), Vector3(57.0, 0, 0.0), Vector3(-28.5, 0, -10.0), Vector3(20.0, 0, -21.5)])
	_markers(st, "", [["ArrivalPoint", Vector3(0, 0, 34)], ["Hangout", Vector3(-5.0, 0, -1.0)], ["Shelter", k.at(barracks, Vector3(0, 0, 0))]])
	_markers(st, "RaidPoints", [Vector3(0, 0, 115), Vector3(125, 0, 5), Vector3(10, 0, -110)])
	var labels := ["the road", "the east", "the dunes to the north"]
	for j in 3:
		st.get_node("RaidPoints").get_child(j).set_meta("label", labels[j])
	# Farmers: two at each garden plot, on its north side, facing it
	_markers(st, "FarmSpots", [Vector3(-25.0, 0, 17.3), Vector3(-21.6, 0, 17.3), Vector3(-16.2, 0, 17.3), Vector3(-12.8, 0, 17.3)])
	for m in st.get_node("FarmSpots").get_children():
		(m as Node3D).rotation.y = PI
	var people := Node3D.new()
	people.name = "Settlers"
	st.add_child(people)
	# The defences: a gate in the gateway, then watchtowers either side of it
	var plans := Node3D.new()
	plans.name = "Plans"
	st.add_child(plans)
	_plan_run(plans, "Gate", "gate", Vector2(-4, 24.5) - Vector2(o.x, o.z), Vector2(4, 24.5) - Vector2(o.x, o.z))
	for t: Array in [["TowerGateW", Vector2(-9.6, 21.2)], ["TowerGateE", Vector2(9.6, 21.2)]]:
		var m := Marker3D.new()
		m.name = t[0]
		var p: Vector2 = t[1] - Vector2(o.x, o.z)
		# A tower's deck is at its back (-Z): -Z faces out, south
		m.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(p.x, 0, p.y))
		m.set_meta("plan", "watchtower")
		m.set_meta("defence", true)
		m.set_meta("stage", 2)
		plans.add_child(m)
	var sites := Node3D.new()
	sites.name = "Sites"
	st.add_child(sites)


func _area(area: Area3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	area.add_child(cs)


## Markers under `parent/group` (or straight under it, [name, position]),
## positions in the site's frame.
func _markers(parent: Node3D, group: String, points: Array) -> void:
	var under := parent
	if group != "":
		under = Node3D.new()
		under.name = group
		parent.add_child(under)
	var i := 0
	for p in points:
		var m := Marker3D.new()
		if p is Array:
			m.name = p[0]
			m.position = (p[1] as Vector3) - ST_AT
		else:
			m.name = "%s%d" % [group.trim_suffix("s"), i]
			m.position = (p as Vector3) - ST_AT
		under.add_child(m)
		i += 1


func _plan_run(plans: Node3D, mark_name: String, plan: String, a: Vector2, b: Vector2) -> void:
	var m := Marker3D.new()
	m.name = mark_name
	m.position = Vector3(a.x, 0, a.y)
	m.set_meta("plan", plan)
	m.set_meta("to", Vector3(b.x, 0, b.y))
	m.set_meta("defence", true)
	plans.add_child(m)


# ================================================================ the mess kitchen scene

## The mess hall's kitchen (a SettlementBuilding, so a Cook can work here):
## the stove, a counter and the fridge, along a wall. Built in, so it's
## always there (saves don't remove it).
func _make_mess_kitchen() -> void:
	var root := SettlementBuilding.new()
	root.name = "MessKitchen"
	root.definition = load("res://resources/structures/settlement/kitchen.tres")
	root.prebuilt = true
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = PhysicsLayers.STRUCTURES
	body.collision_mask = 0
	root.add_child(body)
	var kk := Kit.new("x", "x", 1)
	kk.box(body, "Counter", Vector3(2.4, 0.9, 0.62), Vector3(0.6, 0.45, 0), "metal_dark")
	kk.box(body, "CounterTop", Vector3(2.44, 0.04, 0.66), Vector3(0.6, 0.92, 0), "concrete_plain", 0.0, false)
	kk.box(body, "Pots", Vector3(0.5, 0.25, 0.3), Vector3(0.3, 1.06, 0), "metal_dark", 0.0, false)
	kk.box(body, "Hood", Vector3(1.3, 0.35, 0.6), Vector3(-1.9, 2.35, -0.05), "metal_dark", 0.0, false)
	kk.root.free()
	var stove := (load("res://scenes/world/stations/cooking_stove.tscn") as PackedScene).instantiate() as Node3D
	stove.name = "Stove"
	stove.position = Vector3(-1.9, 0, 0)
	root.add_child(stove)
	var fridge := (load("res://scenes/world/containers/fridge.tscn") as PackedScene).instantiate() as Node3D
	fridge.name = "Fridge"
	fridge.position = Vector3(2.55, 0, -0.02)
	fridge.set("container_name", "Fridge")
	fridge.set("search_time", 0.0)
	root.add_child(fridge)
	var spots := Node3D.new()
	spots.name = "CookSpots"
	root.add_child(spots)
	var spot := Marker3D.new()
	spot.name = "Spot0"
	spot.position = Vector3(-1.9, 0, 1.25)
	spots.add_child(spot)
	for c in root.get_children():
		c.owner = root
		if c.scene_file_path == "":
			for g in c.get_children():
				g.owner = root
				for gg in g.get_children():
					gg.owner = root
	fridge.unique_name_in_owner = true
	var ps := PackedScene.new()
	assert(ps.pack(root) == OK)
	assert(ResourceSaver.save(ps, MESS_KITCHEN) == OK)
	root.free()
	print("wrote ", MESS_KITCHEN)
