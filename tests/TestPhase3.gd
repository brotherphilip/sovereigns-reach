extends SceneTree
# Phase 3 test suite — building placement, demolition, worker assignment.
# Run: godot --headless --script tests/TestPhase3.gd
#
# Pattern: autoloads via get_node_or_null(), simulation classes via preload()

const BuildingRegistry   = preload("res://simulation/buildings/BuildingRegistry.gd")
const BuildingState      = preload("res://simulation/buildings/BuildingState.gd")
const PlacementValidator = preload("res://simulation/buildings/PlacementValidator.gd")
const WorkerSystem       = preload("res://simulation/player/WorkerSystem.gd")
const ReligionSystem     = preload("res://simulation/economy/ReligionSystem.gd")
const WorldGrid          = preload("res://simulation/world/WorldGrid.gd")
const ShireMap           = preload("res://simulation/world/ShireMap.gd")

# Mirror CommandType enum values to avoid compile-time autoload resolution
const CT_PLACE_BUILDING      = 7
const CT_DEMOLISH_BUILDING   = 8
const CT_SET_BUILDING_WORKERS = 9

# Mirror ValidationResult
const VR_OK               = 0
const VR_OUT_OF_BOUNDS    = 1
const VR_OCCUPIED         = 2
const VR_WRONG_TERRAIN    = 3
const VR_MISSING_TECH     = 4
const VR_MISSING_RESOURCES = 5
const VR_OUTSIDE_BORDERS  = 6
const VR_INVALID_TYPE     = 7

# Mirror BuildingRegistry.Category
const CAT_CIVIC      = 0
const CAT_HARVESTING = 1
const CAT_FOOD       = 2
const CAT_MILITARY   = 3
const CAT_DEFENSE    = 4

var _gs = null
var _cq = null
var _sc = null

var _pass: int = 0
var _fail: int = 0
var _errors: Array = []

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_cq = root.get_node_or_null("CommandQueue")
	_sc = root.get_node_or_null("SimulationClock")
	if not (_gs and _cq and _sc):
		print("FATAL: Autoloads not found — gs=%s cq=%s sc=%s" % [str(_gs), str(_cq), str(_sc)])
		quit(1)
		return
	run_all()
	print("\n=== Phase 3 Results: %d passed, %d failed ===" % [_pass, _fail])
	for e in _errors:
		print("  FAIL: ", e)
	quit(1 if _fail > 0 else 0)

func run_all() -> void:
	print("--- BuildingRegistry ---")
	test_registry_hovel()
	test_registry_woodcutter_camp()
	test_registry_stone_quarry_needs_tech()
	test_registry_invalid_type()
	test_registry_get_by_category_food()
	test_registry_coverage_radius_church()
	test_registry_wheat_farm_size()
	test_registry_cathedral_immune_to_fire()
	test_registry_requiring_tech()

	print("--- BuildingState ---")
	test_building_state_create()
	test_building_state_take_damage_partial()
	test_building_state_take_damage_destroys()
	test_building_state_repair()
	test_building_state_ignite_flammable()
	test_building_state_ignite_immune()
	test_building_state_tick_fire_destroys()
	test_building_state_tick_fire_armory_fast()
	test_building_state_worker_efficiency_close()
	test_building_state_worker_efficiency_far()

	print("--- PlacementValidator ---")
	test_validator_ok_on_grass()
	test_validator_out_of_bounds()
	test_validator_occupied()
	test_validator_wrong_terrain_quarry_on_grass()
	test_validator_correct_terrain_quarry_on_rock()
	test_validator_missing_tech()
	test_validator_has_tech()
	test_validator_missing_gold()
	test_validator_missing_wood()
	test_validator_inside_shire_radius()
	test_validator_outside_shire_radius()
	test_validator_invalid_type()
	test_validator_farm_yield_on_valley()
	test_validator_deduct_cost_reduces_gold()
	test_validator_deduct_cost_reduces_wood()

	print("--- WorkerSystem ---")
	test_workers_assign_within_max()
	test_workers_assign_beyond_population_caps()
	test_workers_assign_to_no_worker_building()
	test_workers_unassign()
	test_workers_total_assigned()
	test_workers_available_counts_military()
	test_workers_auto_assign_fills_food_first()
	test_workers_levy_pulls_from_buildings()
	test_workers_inn_coverage_no_inn()
	test_workers_inn_coverage_with_inn()
	test_workers_religion_coverage_church()

	print("--- GameState Phase 3 commands ---")
	test_gs_place_building_no_grid()
	test_gs_place_building_deducts_cost()
	test_gs_place_building_appears_in_player()
	test_gs_demolish_building_removes_it()
	test_gs_demolish_nonexistent_fails()
	test_gs_set_workers_changes_count()
	test_gs_setup_world_creates_grid()
	test_gs_place_building_with_grid_validates_terrain()
	test_gs_place_building_with_grid_updates_occupancy()

# ============ BuildingRegistry ============

func test_registry_hovel() -> void:
	var defn = BuildingRegistry.lookup("hovel")
	expect("hovel cost has wood", defn.get("cost", {}).get("wood", 0) == 8)
	expect("hovel hp=60", defn.get("hp", 0) == 60)

func test_registry_woodcutter_camp() -> void:
	var defn = BuildingRegistry.lookup("woodcutter_camp")
	expect("woodcutter has terrain_req FOREST", defn.get("terrain_req", 0) != 0)
	expect("woodcutter max_workers=3", defn.get("max_workers", 0) == 3)

func test_registry_stone_quarry_needs_tech() -> void:
	var defn = BuildingRegistry.lookup("stone_quarry")
	var req = defn.get("requires_tech", [])
	expect("stone_quarry requires tech", req.size() > 0)

func test_registry_invalid_type() -> void:
	var defn = BuildingRegistry.lookup("nonexistent_building_xyz")
	expect("invalid type returns empty dict", defn.is_empty())

func test_registry_get_by_category_food() -> void:
	var food_buildings = BuildingRegistry.get_by_category(BuildingRegistry.Category.FOOD)
	expect("food category has buildings", food_buildings.size() > 0)
	expect("bakery in food category", "bakery" in food_buildings)

func test_registry_coverage_radius_church() -> void:
	var r = BuildingRegistry.coverage_radius("church")
	expect("church coverage_radius=12", r == 12)

func test_registry_wheat_farm_size() -> void:
	var defn = BuildingRegistry.lookup("wheat_farm")
	expect("wheat_farm width=3", defn.get("width", 1) == 3)
	expect("wheat_farm height=3", defn.get("height", 1) == 3)

func test_registry_cathedral_immune_to_fire() -> void:
	var defn = BuildingRegistry.lookup("cathedral")
	expect("cathedral immune_to_fire", defn.get("immune_to_fire", false) == true)

func test_registry_requiring_tech() -> void:
	var techs = BuildingRegistry.requiring_tech("weapon_crafting")
	expect("blacksmith requires weapon_crafting", "blacksmith" in techs)

# ============ BuildingState ============

func _make_test_building(btype: String = "hovel", pid: int = 0, gx: int = 5, gy: int = 5) -> Dictionary:
	return BuildingState.create(btype, pid, gx, gy, 100)

func test_building_state_create() -> void:
	var b = _make_test_building("hovel")
	expect("create returns dict", not b.is_empty())
	expect("create sets type", b.get("type", "") == "hovel")
	expect("create sets hp=60", b.get("hp", 0) == 60)
	expect("create workers=0", b.get("workers", -1) == 0)
	expect("create is_active=true", b.get("is_active", false) == true)

func test_building_state_take_damage_partial() -> void:
	var b = _make_test_building("hovel")
	var destroyed = BuildingState.take_damage(b, 20)
	expect("partial damage not destroyed", destroyed == false)
	expect("partial damage reduces hp", b.get("hp", 0) == 40)

func test_building_state_take_damage_destroys() -> void:
	var b = _make_test_building("hovel")
	var destroyed = BuildingState.take_damage(b, 100)
	expect("overkill destroys building", destroyed == true)
	expect("destroyed hp=0", b.get("hp", -1) == 0)
	expect("destroyed is_active=false", b.get("is_active", true) == false)

func test_building_state_repair() -> void:
	var b = _make_test_building("hovel")
	BuildingState.take_damage(b, 50)
	BuildingState.repair(b, 20)
	expect("repair raises hp", b.get("hp", 0) == 30)
	BuildingState.repair(b, 999)
	expect("repair caps at max_hp", b.get("hp", 0) == 60)

func test_building_state_ignite_flammable() -> void:
	var b = _make_test_building("wooden_palisade")
	var lit = BuildingState.ignite(b)
	expect("wooden_palisade can be ignited", lit == true)
	expect("palisade is_on_fire=true", b.get("is_on_fire", false) == true)

func test_building_state_ignite_immune() -> void:
	var b = _make_test_building("stone_wall")
	var lit = BuildingState.ignite(b)
	expect("stone_wall cannot be ignited", lit == false)
	expect("stone_wall is_on_fire=false", b.get("is_on_fire", true) == false)

func test_building_state_tick_fire_destroys() -> void:
	var b = _make_test_building("hovel")  # hp=60
	b["is_on_fire"] = true
	var destroyed = false
	# At 8 HP/tick, 60 HP hovel burns in 8 ticks
	for _i in range(8):
		destroyed = BuildingState.tick_fire(b)
		if destroyed:
			break
	expect("hovel destroyed by fire eventually", destroyed == true)

func test_building_state_tick_fire_armory_fast() -> void:
	# Armory has much higher HP but burns at 40/tick
	var b = _make_test_building("armory")
	b["is_on_fire"] = true
	var defn = BuildingRegistry.lookup("armory")
	var max_hp = defn.get("hp", 100)
	var ticks_to_destroy = int(ceil(float(max_hp) / 40.0))
	var destroyed = false
	for _i in range(ticks_to_destroy):
		destroyed = BuildingState.tick_fire(b)
		if destroyed:
			break
	expect("armory destroyed by fire", destroyed == true)

func test_building_state_worker_efficiency_close() -> void:
	var b = _make_test_building("hovel", 0, 15, 15)
	var eff = BuildingState.worker_efficiency(b, 10, 10)
	# Distance = sqrt(25+25) ≈ 7.07, within 10 tile penalty-free radius
	expect("worker near keep = full efficiency", eff == 1.0)

func test_building_state_worker_efficiency_far() -> void:
	var b = _make_test_building("hovel", 0, 50, 10)
	var eff = BuildingState.worker_efficiency(b, 10, 10)
	# Distance = 40, penalty = (40-10)*0.01 = 0.30, efficiency = 0.70
	expect("worker far from keep has reduced efficiency", eff < 1.0)
	expect("worker 40 tiles away has 0.70 efficiency", absf(eff - 0.70) < 0.01)

# ============ PlacementValidator ============

func _make_test_player(gold: int = 500, wood: int = 100, techs: Array = []) -> Dictionary:
	return {
		"gold": gold,
		"resources": {"wood": wood, "stone": 50, "iron": 20, "pitch": 0,
		              "hops": 0, "wheat": 0, "flour": 0, "leather": 0},
		"tech_unlocks": techs,
		"shire_id": -1,
	}

func _make_grass_grid(w: int = 20, h: int = 20) -> Object:
	var grid = WorldGrid.new(w, h)
	# Default is all GRASS (Terrain.GRASS = 0, which is fill default)
	return grid

func test_validator_ok_on_grass() -> void:
	var grid = _make_grass_grid()
	var player = _make_test_player()
	var result = PlacementValidator.validate("hovel", 5, 5, grid, player, {})
	expect("hovel on grass is OK", result["ok"] == true)
	expect("ok code = 0", result["code"] == VR_OK)

func test_validator_out_of_bounds() -> void:
	var grid = _make_grass_grid(10, 10)
	var player = _make_test_player()
	# (10,9) is out of bounds for a 10×10 grid (valid indices 0–9)
	var result = PlacementValidator.validate("hovel", 10, 9, grid, player, {})
	expect("hovel at edge fails bounds", result["ok"] == false)
	expect("out_of_bounds code", result["code"] == VR_OUT_OF_BOUNDS)

func test_validator_occupied() -> void:
	var grid = _make_grass_grid()
	grid.set_building_at(5, 5, 42)
	var player = _make_test_player()
	var result = PlacementValidator.validate("hovel", 5, 5, grid, player, {})
	expect("occupied tile fails", result["ok"] == false)
	expect("occupied code", result["code"] == VR_OCCUPIED)

func test_validator_wrong_terrain_quarry_on_grass() -> void:
	var grid = _make_grass_grid()
	var player = _make_test_player(500, 100, ["resource_unlocks"])
	var result = PlacementValidator.validate("stone_quarry", 5, 5, grid, player, {})
	expect("quarry on grass fails terrain", result["ok"] == false)
	expect("wrong terrain code", result["code"] == VR_WRONG_TERRAIN)

func _set_rock_2x2(grid: Object, gx: int, gy: int) -> void:
	# stone_quarry is 2×2 — all tiles must match terrain_req
	grid.set_terrain(gx,   gy,   WorldGrid.Terrain.ROCK)
	grid.set_terrain(gx+1, gy,   WorldGrid.Terrain.ROCK)
	grid.set_terrain(gx,   gy+1, WorldGrid.Terrain.ROCK)
	grid.set_terrain(gx+1, gy+1, WorldGrid.Terrain.ROCK)

func test_validator_correct_terrain_quarry_on_rock() -> void:
	var grid = _make_grass_grid()
	_set_rock_2x2(grid, 5, 5)
	var player = _make_test_player(500, 100, ["resource_unlocks"])
	var result = PlacementValidator.validate("stone_quarry", 5, 5, grid, player, {})
	expect("quarry on rock passes terrain", result["ok"] == true)

func test_validator_missing_tech() -> void:
	var grid = _make_grass_grid()
	_set_rock_2x2(grid, 5, 5)
	var player = _make_test_player()  # no techs
	var result = PlacementValidator.validate("stone_quarry", 5, 5, grid, player, {})
	expect("quarry without tech fails", result["ok"] == false)
	expect("missing tech code", result["code"] == VR_MISSING_TECH)

func test_validator_has_tech() -> void:
	var grid = _make_grass_grid()
	_set_rock_2x2(grid, 5, 5)
	var player = _make_test_player(500, 100, ["resource_unlocks"])
	var result = PlacementValidator.validate("stone_quarry", 5, 5, grid, player, {})
	expect("quarry with tech passes", result["ok"] == true)

func test_validator_missing_gold() -> void:
	var grid = _make_grass_grid()
	var player = _make_test_player(0, 100)  # no gold
	var result = PlacementValidator.validate("barracks", 5, 5, grid, player, {})
	expect("barracks without gold fails", result["ok"] == false)
	expect("missing resources code", result["code"] == VR_MISSING_RESOURCES)

func test_validator_missing_wood() -> void:
	var grid = _make_grass_grid()
	var player = _make_test_player(500, 0)  # no wood
	var result = PlacementValidator.validate("hovel", 5, 5, grid, player, {})
	expect("hovel without wood fails", result["ok"] == false)
	expect("missing resources code for wood", result["code"] == VR_MISSING_RESOURCES)

func test_validator_inside_shire_radius() -> void:
	var grid = _make_grass_grid(100, 100)
	var player = _make_test_player()
	player["shire_id"] = 0
	var world = {
		"shires": [{"id": 0, "capital_x": 50, "capital_y": 50, "influence_radius": 30}]
	}
	var result = PlacementValidator.validate("hovel", 55, 50, grid, player, world)
	expect("hovel inside influence passes", result["ok"] == true)

func test_validator_outside_shire_radius() -> void:
	# Build-area restriction removed: a valid free tile is placeable anywhere on
	# the map, regardless of shire influence radius.
	var grid = _make_grass_grid(100, 100)
	var player = _make_test_player()
	player["shire_id"] = 0
	var world = {
		"shires": [{"id": 0, "capital_x": 50, "capital_y": 50, "influence_radius": 10}]
	}
	var result = PlacementValidator.validate("hovel", 5, 5, grid, player, world)
	expect("hovel far from capital still places (no build-area restriction)", result["ok"] == true)

func test_validator_invalid_type() -> void:
	var grid = _make_grass_grid()
	var player = _make_test_player()
	var result = PlacementValidator.validate("not_a_real_building", 5, 5, grid, player, {})
	expect("invalid type returns error", result["ok"] == false)
	expect("invalid type code", result["code"] == VR_INVALID_TYPE)

func test_validator_farm_yield_on_valley() -> void:
	var grid = _make_grass_grid()
	grid.set_terrain(5, 5, WorldGrid.Terrain.VALLEY)
	var yield_val = PlacementValidator.get_terrain_yield("apple_orchard", 5, 5, grid)
	expect("apple orchard on valley has 1.5 yield", absf(yield_val - 1.5) < 0.01)

func test_validator_deduct_cost_reduces_gold() -> void:
	var player = _make_test_player(200)
	PlacementValidator.deduct_cost("barracks", player)
	# barracks costs {wood:20, stone:10, gold:10}
	expect("barracks deducts 10 gold", player["gold"] == 190)

func test_validator_deduct_cost_reduces_wood() -> void:
	var player = _make_test_player(200, 100)
	PlacementValidator.deduct_cost("barracks", player)
	expect("barracks deducts 20 wood", player["resources"]["wood"] == 80)

# ============ WorkerSystem ============

func _make_worker_player(pop: int = 100, military: int = 0) -> Dictionary:
	return {
		"population": pop,
		"military_strength": military,
		"buildings": [],
	}

func test_workers_assign_within_max() -> void:
	var player = _make_worker_player(50)
	var building = BuildingState.create("woodcutter_camp", 0, 5, 5, 1)
	player["buildings"].append(building)
	var delta = WorkerSystem.assign_workers(building, 2, player)
	expect("assign 2 workers to camp", building.get("workers", 0) == 2)
	expect("delta is +2", delta == 2)

func test_workers_assign_beyond_population_caps() -> void:
	var player = _make_worker_player(3)  # Only 3 population
	var building = BuildingState.create("woodcutter_camp", 0, 5, 5, 1)
	player["buildings"].append(building)
	WorkerSystem.assign_workers(building, 10, player)  # Request 10
	expect("workers capped by population", building.get("workers", 0) <= 3)

func test_workers_assign_to_no_worker_building() -> void:
	var player = _make_worker_player(100)
	var building = BuildingState.create("stone_wall", 0, 5, 5, 1)
	player["buildings"].append(building)
	var delta = WorkerSystem.assign_workers(building, 5, player)
	expect("stone_wall accepts no workers", delta == 0)
	expect("stone_wall workers=0", building.get("workers", 0) == 0)

func test_workers_unassign() -> void:
	var player = _make_worker_player(50)
	var building = BuildingState.create("woodcutter_camp", 0, 5, 5, 1)
	building["workers"] = 3
	player["buildings"].append(building)
	var freed = WorkerSystem.unassign_workers(building, player)
	expect("unassign frees workers", freed == 3)
	expect("building workers=0 after unassign", building.get("workers", 0) == 0)

func test_workers_total_assigned() -> void:
	var player = _make_worker_player(50)
	var b1 = BuildingState.create("woodcutter_camp", 0, 5, 5, 1)
	var b2 = BuildingState.create("wheat_farm", 0, 10, 10, 2)
	b1["workers"] = 2
	b2["workers"] = 3
	player["buildings"] = [b1, b2]
	expect("total_assigned = 5", WorkerSystem.total_assigned(player) == 5)

func test_workers_available_counts_military() -> void:
	var player = _make_worker_player(100, 20)
	var b1 = BuildingState.create("woodcutter_camp", 0, 5, 5, 1)
	b1["workers"] = 10
	player["buildings"] = [b1]
	# available = 100 - 20 (military) - 10 (assigned) = 70
	var building = BuildingState.create("wheat_farm", 0, 10, 10, 2)
	player["buildings"].append(building)
	WorkerSystem.assign_workers(building, 999, player)
	expect("workers capped with military deducted", building.get("workers", 0) <= 70)

func test_workers_auto_assign_fills_food_first() -> void:
	var player = _make_worker_player(20)
	var farm = BuildingState.create("wheat_farm", 0, 5, 5, 1)
	var camp = BuildingState.create("woodcutter_camp", 0, 10, 10, 2)
	player["buildings"] = [camp, farm]  # camp listed first
	WorkerSystem.auto_assign(player)
	# Food buildings should be prioritized
	expect("farm gets workers from auto_assign", farm.get("workers", 0) > 0)

func test_workers_levy_pulls_from_buildings() -> void:
	var player = _make_worker_player(100)
	var b1 = BuildingState.create("woodcutter_camp", 0, 5, 5, 1)
	var b2 = BuildingState.create("wheat_farm", 0, 10, 10, 2)
	b1["workers"] = 3
	b2["workers"] = 4
	player["buildings"] = [b1, b2]
	var levied = WorkerSystem.levy_peasants(5, player)
	expect("levy pulls 5 total workers", levied == 5)
	expect("buildings have fewer workers after levy", WorkerSystem.total_assigned(player) == 2)

func test_workers_inn_coverage_no_inn() -> void:
	var player = _make_worker_player(50)
	var buildings: Array = []
	var coverage = WorkerSystem.calculate_inn_coverage(player, buildings)
	expect("no inn, no hovels = 0.0 coverage", coverage == 0.0)

func test_workers_inn_coverage_with_inn() -> void:
	var player = _make_worker_player(50)
	var inn = BuildingState.create("inn", 0, 10, 10, 1)
	inn["workers"] = 1
	var hovel1 = BuildingState.create("hovel", 0, 5, 5, 2)
	var hovel2 = BuildingState.create("hovel", 0, 6, 5, 3)
	var buildings = [inn, hovel1, hovel2]
	var coverage = WorkerSystem.calculate_inn_coverage(player, buildings)
	# 1 inn covers ~4 hovels, 2 hovels present => coverage = min(4/2, 1.0) = 1.0
	expect("inn covers 2 hovels = 1.0", coverage == 1.0)

func test_workers_religion_coverage_church() -> void:
	var buildings: Array = [BuildingState.create("church", 0, 10, 10, 1)]
	buildings[0]["is_active"] = true
	var coverage = ReligionSystem.compute_religion_coverage({"buildings": buildings})
	# No hovels → no coverage denominator
	expect("church with no hovels = 0.0", coverage == 0.0)
	# Add a hovel
	buildings.append(BuildingState.create("hovel", 0, 5, 5, 2))
	coverage = ReligionSystem.compute_religion_coverage({"buildings": buildings})
	expect("church with 1 hovel has coverage > 0", coverage > 0.0)

# ============ GameState Phase 3 commands ============

func _init_player() -> void:
	_gs.players.clear()
	_gs.initialize_player(0, "TestLord", 100, 100)

func test_gs_place_building_no_grid() -> void:
	_init_player()
	_gs._grid = null
	_gs._next_building_id = 1
	# Pre-stock resources (hovel costs 8 wood)
	_gs.players[0]["resources"]["wood"] = 50
	_cq.enqueue(CT_PLACE_BUILDING, {"building_type": "hovel", "grid_x": 10, "grid_y": 10}, 0)
	_sc.set_speed(1)
	_sc._advance_tick()
	_sc.set_speed(0)
	var buildings: Array = _gs.players[0].get("buildings", [])
	expect("no-grid place adds building", buildings.size() == 1)
	expect("placed building type=hovel", buildings[0].get("type", "") == "hovel")

func test_gs_place_building_deducts_cost() -> void:
	_init_player()
	_gs._grid = null
	_gs._next_building_id = 1
	_gs.players[0]["resources"]["wood"] = 50
	var wood_before = _gs.players[0]["resources"]["wood"]
	_cq.enqueue(CT_PLACE_BUILDING, {"building_type": "hovel", "grid_x": 10, "grid_y": 10}, 0)
	_sc.set_speed(1)
	_sc._advance_tick()
	_sc.set_speed(0)
	var wood_after = _gs.players[0]["resources"]["wood"]
	expect("hovel placement deducts 8 wood", wood_before - wood_after == 8)

func test_gs_place_building_appears_in_player() -> void:
	_init_player()
	_gs._grid = null
	_gs._next_building_id = 10
	_gs.players[0]["resources"]["wood"] = 100
	_cq.enqueue(CT_PLACE_BUILDING, {"building_type": "hovel", "grid_x": 15, "grid_y": 15}, 0)
	_sc.set_speed(1)
	_sc._advance_tick()
	_sc.set_speed(0)
	var b = _gs.find_building(0, 10)
	expect("placed building found by id", not b.is_empty())
	expect("found building at correct x", b.get("grid_x", -1) == 15)

func test_gs_demolish_building_removes_it() -> void:
	_init_player()
	_gs._grid = null
	_gs._next_building_id = 1
	_gs.players[0]["resources"]["wood"] = 100
	# Place first
	_cq.enqueue(CT_PLACE_BUILDING, {"building_type": "hovel", "grid_x": 20, "grid_y": 20}, 0)
	_sc.set_speed(1)
	_sc._advance_tick()
	_sc.set_speed(0)
	var bid = _gs.players[0]["buildings"][0].get("id", -1)
	expect("building placed for demolish test", bid >= 0)
	# Demolish it
	_cq.enqueue(CT_DEMOLISH_BUILDING, {"building_id": bid}, 0)
	_sc.set_speed(1)
	_sc._advance_tick()
	_sc.set_speed(0)
	expect("building removed after demolish", _gs.players[0]["buildings"].size() == 0)

func test_gs_demolish_nonexistent_fails() -> void:
	_init_player()
	_gs._grid = null
	var before = _gs.players[0]["buildings"].size()
	_cq.enqueue(CT_DEMOLISH_BUILDING, {"building_id": 9999}, 0)
	_sc.set_speed(1)
	_sc._advance_tick()
	_sc.set_speed(0)
	expect("demolish nonexistent doesn't crash", _gs.players[0]["buildings"].size() == before)

func test_gs_set_workers_changes_count() -> void:
	_init_player()
	_gs._grid = null
	_gs._next_building_id = 1
	_gs.players[0]["resources"]["wood"] = 100
	_gs.players[0]["population"] = 50
	_cq.enqueue(CT_PLACE_BUILDING, {"building_type": "woodcutter_camp", "grid_x": 25, "grid_y": 25}, 0)
	_sc.set_speed(1)
	_sc._advance_tick()
	_sc.set_speed(0)
	var bid = _gs.players[0]["buildings"][0].get("id", -1)
	_cq.enqueue(CT_SET_BUILDING_WORKERS, {"building_id": bid, "workers": 3}, 0)
	_sc.set_speed(1)
	_sc._advance_tick()
	_sc.set_speed(0)
	var workers = _gs.players[0]["buildings"][0].get("workers", 0)
	expect("set_building_workers assigns 3 workers", workers == 3)

func test_gs_setup_world_creates_grid() -> void:
	_gs.setup_world(99999, 4)
	expect("setup_world creates _grid", _gs._grid != null)
	expect("setup_world creates _shire_map", _gs._shire_map != null)
	expect("world has shires", _gs.world.has("shires"))
	expect("world has 4 shires", _gs.world["shires"].size() == 4)

func test_gs_place_building_with_grid_validates_terrain() -> void:
	_gs.setup_world(12345, 4)
	_init_player()
	_gs._next_building_id = 1
	_gs.players[0]["resources"]["wood"] = 100
	_gs.players[0]["tech_unlocks"] = ["resource_unlocks"]
	# Place stone_quarry on GRASS should fail validation
	# First ensure tile 5,5 is GRASS (not ROCK)
	_gs._grid.set_terrain(5, 5, WorldGrid.Terrain.GRASS)
	var buildings_before = _gs.players[0]["buildings"].size()
	_cq.enqueue(CT_PLACE_BUILDING, {"building_type": "stone_quarry", "grid_x": 5, "grid_y": 5}, 0)
	_sc.set_speed(1)
	_sc._advance_tick()
	_sc.set_speed(0)
	expect("quarry on grass with grid rejected", _gs.players[0]["buildings"].size() == buildings_before)

func test_gs_place_building_with_grid_updates_occupancy() -> void:
	_gs.setup_world(12345, 4)
	_init_player()
	_gs._next_building_id = 50
	_gs.players[0]["resources"]["wood"] = 100
	# Set a grass tile far from any shire border issues
	_gs._grid.set_terrain(50, 50, WorldGrid.Terrain.GRASS)
	_gs.players[0]["shire_id"] = -1  # No shire border check
	_cq.enqueue(CT_PLACE_BUILDING, {"building_type": "hovel", "grid_x": 50, "grid_y": 50}, 0)
	_sc.set_speed(1)
	_sc._advance_tick()
	_sc.set_speed(0)
	var occupying = _gs._grid.get_building_at(50, 50)
	expect("placed building occupies grid tile", occupying == 50)

# ============ Assertion helpers ============

func expect(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  PASS: ", label)
	else:
		_fail += 1
		_errors.append(label)
		print("  FAIL: ", label)
