extends SceneTree
# Proof harness for building min-spacing + paths (ROAD tiles): placement spacing rule,
# path validation/exemptions, citizen road speed-up, and pathfinder road preference.
# Run: godot --headless --script tests/TestPaths.gd

const PlacementValidator = preload("res://simulation/buildings/PlacementValidator.gd")
const BuildingRegistry   = preload("res://simulation/buildings/BuildingRegistry.gd")
const WorldGrid          = preload("res://simulation/world/WorldGrid.gd")
const CitizenSystem      = preload("res://simulation/world/CitizenSystem.gd")
const Pathfinder         = preload("res://simulation/pathfinding/Pathfinder.gd")

var _pass := 0
var _fail := 0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_test_min_spacing()
	_test_path_validation()
	_test_citizen_road_speed()
	_test_pathfinder_prefers_road()
	_test_path_built_over_time()
	print("\n=== Path/Spacing Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _player_with(building: Dictionary) -> Dictionary:
	return {
		"buildings": [building] if not building.is_empty() else [],
		"gold": 9999, "resources": {"wood": 999, "stone": 999}, "tech_unlocks": [],
		"food": {}, "armory": {},
	}

func _bld(btype: String, gx: int, gy: int) -> Dictionary:
	return {"id": 1, "type": btype, "grid_x": gx, "grid_y": gy, "built": true}

func _code(btype: String, gx: int, gy: int, grid, player) -> int:
	return PlacementValidator.validate(btype, gx, gy, grid, player, {}).get("code", -1)

func _test_min_spacing() -> void:
	print("\n[Min spacing between buildings]")
	var grid := WorldGrid.new(40, 40)
	# Register an existing hovel (2x2) at (20,20)..(21,21) on the grid.
	var player := _player_with(_bld("hovel", 20, 20))
	for dy in range(2):
		for dx in range(2):
			grid.set_building_at(20 + dx, 20 + dy, 1)
	ok("edge-adjacent placement is rejected (too close)",
		_code("hovel", 22, 20, grid, player) == PlacementValidator.ValidationResult.TOO_CLOSE)
	ok("a 1-tile gap is still too close (gap rule is 2)",
		_code("hovel", 23, 20, grid, player) == PlacementValidator.ValidationResult.TOO_CLOSE)
	ok("placement with the full gap is allowed",
		_code("hovel", 24, 20, grid, player) == PlacementValidator.ValidationResult.OK)
	ok("a defensive wall may sit flush against a building (exempt)",
		_code("wooden_palisade", 22, 20, grid, player) == PlacementValidator.ValidationResult.OK)
	ok("a path may sit flush against a building (exempt)",
		_code("path", 22, 20, grid, player) == PlacementValidator.ValidationResult.OK)

func _test_path_validation() -> void:
	print("\n[Path placement validation]")
	var grid := WorldGrid.new(20, 20)
	var player := _player_with({})
	ok("path allowed on grass", _code("path", 5, 5, grid, player) == PlacementValidator.ValidationResult.OK)
	grid.set_terrain(7, 7, WorldGrid.Terrain.MOUNTAIN)
	ok("path rejected on mountain",
		_code("path", 7, 7, grid, player) == PlacementValidator.ValidationResult.WRONG_TERRAIN)
	grid.set_terrain(8, 8, WorldGrid.Terrain.RIVER)
	ok("path rejected on river",
		_code("path", 8, 8, grid, player) == PlacementValidator.ValidationResult.WRONG_TERRAIN)
	ok("is_path flag set on the path type", BuildingRegistry.is_path("path"))
	ok("path is exempt from spacing", not BuildingRegistry.needs_spacing("path"))

func _test_citizen_road_speed() -> void:
	print("\n[Citizen road speed-up]")
	var grid := WorldGrid.new(10, 10)
	grid.set_terrain(5, 5, WorldGrid.Terrain.ROAD)
	grid.set_terrain(6, 6, WorldGrid.Terrain.FOREST)
	var on_grass: float = CitizenSystem._walk_speed(grid, Vector2(1, 1))
	var on_road: float  = CitizenSystem._walk_speed(grid, Vector2(5, 5))
	var on_forest: float = CitizenSystem._walk_speed(grid, Vector2(6, 6))
	ok("road is ~2× grass speed", is_equal_approx(on_road, on_grass * 2.0))
	ok("forest is slower than grass", on_forest < on_grass)

func _test_pathfinder_prefers_road() -> void:
	print("\n[Pathfinder prefers a faster road, even if longer]")
	# 9×3 grass; top row (y=0) is a ROAD. Straight line y=1 is 8 grass steps (cost 8);
	# detouring via the road is more tiles but cheaper, so A* should take it.
	var tiles: Array = []
	for y in range(3):
		var row: Array = []
		for x in range(9):
			row.append(WorldGrid.Terrain.ROAD if y == 0 else WorldGrid.Terrain.GRASS)
		tiles.append(row)
	var g := {"width": 9, "height": 3, "tiles": tiles}
	var path := Pathfinder.find_path_dict(g, 0, 1, 8, 1, Pathfinder.PASS_FOOT)
	var used_road := false
	var all_straight := true
	for step in path:
		if step[1] == 0:
			used_road = true
		if step[1] != 1:
			all_straight = false
	ok("route detours onto the road row", used_road)
	ok("route does NOT just walk the straight grass line", not all_straight)

func _test_path_built_over_time() -> void:
	print("\n[Path is paved by a builder over time]")
	var grid := WorldGrid.new(30, 30)
	# A path is placed as a small build-site (not instant terrain).
	var path_site := {"id": 50, "type": "path", "grid_x": 15, "grid_y": 15,
		"built": false, "build_required": 15.0, "build_progress": 0.0}
	grid.set_building_at(15, 15, 50)
	var buildings := [path_site]
	var citizens := [CitizenSystem.make_citizen(1, 12.0, 15.0, _rng)]
	citizens[0]["x"] = 12.0; citizens[0]["y"] = 15.0
	citizens[0]["hx"] = 12.0; citizens[0]["hy"] = 15.0
	ok("path starts unbuilt (not instant)", not path_site.get("built", false))
	for i in range(800):
		CitizenSystem.tick(citizens, buildings, _rng, i, grid)
		if path_site.get("built", false):
			break
	ok("a builder paved the path over time", path_site.get("built", false))
