extends SceneTree
# Phase 2 headless test suite.
# Run: godot --headless --script tests/TestPhase2.gd
#
# Uses preload() for all simulation classes — class_name declarations are not
# resolved at parse time in --script mode (same constraint as Phase 1 autoloads).

const WorldGrid       = preload("res://simulation/world/WorldGrid.gd")
const ShireMap        = preload("res://simulation/world/ShireMap.gd")
const PopularityEngine= preload("res://simulation/economy/PopularityEngine.gd")
const ResourceTick    = preload("res://simulation/economy/ResourceTick.gd")
const WeatherSystem   = preload("res://simulation/world/WeatherSystem.gd")

var _gs    # GameState autoload
var _sc    # SimulationClock autoload

var _pass: int = 0
var _fail: int = 0

func _init() -> void:
	print("\n╔══════════════════════════════════════════════╗")
	print("║  SOVEREIGN'S REACH — PHASE 2 TEST SUITE     ║")
	print("╚══════════════════════════════════════════════╝\n")
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_sc = root.get_node_or_null("SimulationClock")
	if not (_gs and _sc):
		print("FATAL: Autoloads not found")
		quit(1)
		return
	_sc.pause()

	_test_world_grid()
	_test_shire_map()
	_test_popularity_engine()
	_test_resource_tick()
	_test_weather_system()
	_test_gamestate_integration()

	print("")
	if _fail == 0:
		print("✓ ALL %d TESTS PASSED" % _pass)
	else:
		print("✗ %d PASSED  %d FAILED" % [_pass, _fail])
	# Uniform, greppable summary line so a full-suite sweep can't silently miss this suite.
	print("=== Phase 2 Results: %d passed, %d failed ===" % [_pass, _fail])
	print("")
	quit(0 if _fail == 0 else 1)

# ─── WorldGrid ───────────────────────────────────────────────────────────

func _test_world_grid() -> void:
	print("── WorldGrid ────────────────────────────────")
	var grid = WorldGrid.new(50, 50)

	_ok(grid.width == 50,  "width set to 50")
	_ok(grid.height == 50, "height set to 50")
	_ok(grid.get_terrain(0, 0) == WorldGrid.Terrain.GRASS, "default terrain is GRASS")

	_ok(grid.in_bounds(0, 0),       "in_bounds(0,0) true")
	_ok(grid.in_bounds(49, 49),     "in_bounds(49,49) true")
	_ok(not grid.in_bounds(50, 0),  "in_bounds(50,0) false")
	_ok(not grid.in_bounds(-1, 0),  "in_bounds(-1,0) false")

	grid.set_terrain(10, 10, WorldGrid.Terrain.FOREST)
	_ok(grid.get_terrain(10, 10) == WorldGrid.Terrain.FOREST, "set/get terrain FOREST")

	grid.set_terrain(20, 20, WorldGrid.Terrain.RIVER)
	# Deep water now fully BLOCKS all movement — you cross only via a BRIDGE (BridgePlanner).
	_ok(not grid.is_passable(20, 20, WorldGrid.PASSABLE_FOOT),    "river blocks foot (no fording)")
	_ok(not grid.is_passable(20, 20, WorldGrid.PASSABLE_CAVALRY), "river blocks cavalry")
	_ok(grid.get_move_cost(20, 20) > 3.0,                         "river is impassable terrain (high move cost)")
	# A bridge laid over the water is the crossing — passable to foot and cavalry.
	grid.set_terrain(20, 20, WorldGrid.Terrain.BRIDGE)
	_ok(grid.is_passable(20, 20, WorldGrid.PASSABLE_FOOT),        "bridge carries foot across the water")
	_ok(grid.is_passable(20, 20, WorldGrid.PASSABLE_CAVALRY),     "bridge carries cavalry across the water")
	grid.set_terrain(21, 21, WorldGrid.Terrain.MOUNTAIN)
	_ok(not grid.is_passable(21, 21, WorldGrid.PASSABLE_FOOT),    "mountain fully blocks foot")

	grid.set_terrain(5, 5, WorldGrid.Terrain.ROAD)
	_ok(grid.get_move_cost(5, 5) < 1.0, "road move cost < 1.0 (faster than grass)")

	_ok(grid.is_buildable(0, 0),  "grass tile is buildable")
	grid.set_terrain(1, 1, WorldGrid.Terrain.RIVER)
	_ok(not grid.is_buildable(1, 1), "river tile not buildable")
	grid.set_building_at(2, 2, 99)
	_ok(not grid.is_buildable(2, 2), "occupied tile not buildable")

	var tiles = grid.get_tiles_in_radius(25, 25, 3)
	_ok(tiles.size() > 0,   "get_tiles_in_radius returns tiles")
	_ok(tiles.size() <= 32, "radius 3 circle has reasonable tile count")

	grid.set_terrain(30, 30, WorldGrid.Terrain.VALLEY)
	_ok(grid.get_farm_yield(30, 30) > grid.get_farm_yield(0, 0), "valley has higher farm yield than grass")
	grid.set_terrain(31, 31, WorldGrid.Terrain.MOUNTAIN)
	_ok(grid.get_farm_yield(31, 31) == 0.0, "mountain has zero farm yield")

	var big_grid = WorldGrid.new(100, 100)
	big_grid.generate(42, 4)
	var forest_count = big_grid.get_tiles_of_type(WorldGrid.Terrain.FOREST).size()
	var river_count  = big_grid.get_tiles_of_type(WorldGrid.Terrain.RIVER).size()
	_ok(forest_count > 0, "procedural gen creates forests")
	_ok(river_count > 0,  "procedural gen creates rivers")

	grid.set_terrain(3, 3, WorldGrid.Terrain.MARSH)
	var snap = grid.serialize()
	var grid2 = WorldGrid.new(50, 50)
	grid2.deserialize(snap)
	_ok(grid2.get_terrain(3, 3) == WorldGrid.Terrain.MARSH, "terrain survives serialize/deserialize")
	_ok(grid2.width == 50 and grid2.height == 50,           "dimensions survive serialize/deserialize")

# ─── ShireMap ────────────────────────────────────────────────────────────

func _test_shire_map() -> void:
	print("── ShireMap ─────────────────────────────────")
	var sm = ShireMap.new()
	sm.generate_default(200, 200, 4)

	_ok(sm.shires.size() == 4, "4 shires generated")

	var s0 = sm.get_shire(0)
	_ok(s0.has("name"),          "shire has name")
	_ok(s0.has("capital_x"),     "shire has capital_x")
	_ok(s0.has("biome"),         "shire has biome")
	_ok(s0["owner_id"] == -1,    "shire starts unclaimed")
	_ok(s0["capital_level"] == 0,"capital starts at level 0")

	sm.set_owner(0, 1)
	_ok(sm.get_owner(0) == 1, "set/get owner works")
	_ok(sm.get_shires_owned_by(1).size() == 1, "get_shires_owned_by returns 1 shire")

	var upgraded = sm.upgrade_capital(0)
	_ok(upgraded, "capital upgrade succeeds at level 0")
	_ok(sm.get_shire(0)["capital_level"] == 1, "capital level incremented to 1")
	_ok(sm.get_shire(0)["active_buffs"].size() > 0, "capital upgrade adds buff")

	for _i in range(10):
		sm.upgrade_capital(0)
	_ok(sm.get_shire(0)["capital_level"] == 5, "capital capped at level 5")

	sm.donate_to_capital(0, 0, 500, "stone")
	var key = "0_stone"
	_ok(sm.get_shire(0)["capital_resources_donated"].has(key), "donation tracked")
	_ok(sm.get_shire(0)["capital_resources_donated"][key] == 500, "donation amount correct")

	var snap = sm.serialize()
	var sm2 = ShireMap.new()
	sm2.deserialize(snap)
	_ok(sm2.shires.size() == 4, "shires survive serialize/deserialize")
	_ok(sm2.get_owner(0) == 1,  "owner survives serialize/deserialize")

# ─── PopularityEngine ────────────────────────────────────────────────────

func _test_popularity_engine() -> void:
	print("── PopularityEngine ─────────────────────────")
	var player := {
		"id": 0, "popularity": 50.0,
		"tax_rate": 0, "food_ration": 2, "ale_ration": 1,
		"inn_coverage": 0.5, "religion_coverage": 0.0,
		"food": {"apples": 100, "cheese": 0, "meat": 0, "bread": 0, "ale": 0},
	}

	var normal_delta = PopularityEngine.calculate_delta(player, [])
	_ok(normal_delta > -30.0 and normal_delta < 30.0, "neutral settings: reasonable delta")

	player["tax_rate"] = 3
	var taxed_delta = PopularityEngine.calculate_delta(player, [])
	player["tax_rate"] = 0
	_ok(taxed_delta < normal_delta, "heavy tax reduces popularity delta")

	player["tax_rate"] = -3
	var bribe_delta = PopularityEngine.calculate_delta(player, [])
	player["tax_rate"] = 0
	_ok(bribe_delta > normal_delta, "bribe increases popularity delta")

	player["food"] = {"apples": 0, "cheese": 0, "meat": 0, "bread": 0, "ale": 0}
	var starve_delta = PopularityEngine.calculate_delta(player, [])
	_ok(starve_delta < -15.0, "starvation gives large negative delta")

	player["food"] = {"apples": 10, "cheese": 0, "meat": 0, "bread": 0, "ale": 0}
	var one_type_delta = PopularityEngine.calculate_delta(player, [])
	player["food"] = {"apples": 10, "cheese": 10, "meat": 10, "bread": 10, "ale": 0}
	var four_type_delta = PopularityEngine.calculate_delta(player, [])
	_ok(four_type_delta > one_type_delta, "food variety increases popularity delta")

	player["food"] = {"apples": 50, "cheese": 0, "meat": 0, "bread": 0, "ale": 0}
	var siege_delta = PopularityEngine.calculate_delta(player, ["active_siege"])
	_ok(siege_delta < normal_delta, "active_siege event reduces popularity")
	# A defended realm keeps its nerve: the siege morale hit is lighter (but still negative).
	var siege_defended_delta = PopularityEngine.calculate_delta(player, ["active_siege_defended"])
	_ok(siege_defended_delta < normal_delta, "defended siege still reduces popularity")
	_ok(siege_defended_delta > siege_delta, "readying defences softens the siege morale hit")

	player["popularity"] = 50.0
	player["tax_rate"] = 0
	PopularityEngine.apply_tick(player, [])
	_ok(player["popularity"] >= 0.0 and player["popularity"] <= 100.0, "apply_tick clamps to [0,100]")

	player["popularity"] = 15.0
	_ok(PopularityEngine.is_desertion_risk(player), "popularity 15 is desertion risk")
	player["popularity"] = 25.0
	_ok(not PopularityEngine.is_desertion_risk(player), "popularity 25 is not desertion risk")

	player["popularity"] = 85.0
	_ok(PopularityEngine.get_prestige_multiplier(player) > 1.0, "high pop gives prestige mult >1")
	player["popularity"] = 10.0
	_ok(PopularityEngine.get_prestige_multiplier(player) == 0.0, "very low pop gives 0 prestige mult")

# ─── ResourceTick ────────────────────────────────────────────────────────

func _test_resource_tick() -> void:
	print("── ResourceTick ─────────────────────────────")
	var player := {
		"id": 0, "population": 10, "food_ration": 2,
		"resources": {"wood": 0, "stone": 0, "iron": 0, "pitch": 0, "hops": 0,
		              "wheat": 10, "flour": 0, "leather": 0},
		"food":    {"apples": 20, "cheese": 0, "meat": 0, "bread": 0, "ale": 0},
		"armory":  {"bows": 0, "crossbows": 0, "pikes": 0, "swords": 0, "leather_armor": 0, "plate_armor": 0},
	}

	var wc = {"type": "woodcutter_camp", "workers": 1}
	_ok(ResourceTick.tick_building(wc, player, 0).is_empty(),  "tick 0: no production")
	_ok(ResourceTick.tick_building(wc, player, 30).get("wood", 0) == 1, "tick 30: 1 wood produced")
	_ok(ResourceTick.tick_building(wc, player, 31).is_empty(), "tick 31: no production (between intervals)")

	var wc3 = {"type": "woodcutter_camp", "workers": 3}
	_ok(ResourceTick.tick_building(wc3, player, 30).get("wood", 0) == 3, "3 workers produce 3 wood")

	var wc0 = {"type": "woodcutter_camp", "workers": 0}
	_ok(ResourceTick.tick_building(wc0, player, 30).is_empty(), "0 workers produce nothing")

	var mill = {"type": "mill", "workers": 1}
	var no_wheat = player.duplicate(true)
	no_wheat["resources"]["wheat"] = 0
	_ok(ResourceTick.tick_building(mill, no_wheat, 120).is_empty(), "mill produces nothing without wheat")

	var mill_result = ResourceTick.tick_building(mill, player, 120)
	_ok(mill_result.get("flour", 0) == 1,  "mill produces 1 flour")
	_ok(mill_result.get("wheat", 0) == -1, "mill consumes 1 wheat")

	var tp = player.duplicate(true)
	tp["resources"]["wood"] = 10
	ResourceTick.apply_changes(tp, {"wood": 5})
	_ok(tp["resources"]["wood"] == 15, "apply_changes adds resources")
	ResourceTick.apply_changes(tp, {"wood": -20})
	_ok(tp["resources"]["wood"] == 0, "apply_changes clamps at 0 (no negatives)")

	var dp = player.duplicate(true)
	dp["population"] = 10
	dp["food_ration"] = 2
	dp["food"]["apples"] = 100
	var food_delta = ResourceTick.tick_food_consumption(dp, 240)
	_ok(not food_delta.is_empty(), "food consumed on day boundary (tick 240)")
	_ok(food_delta.values().any(func(v): return v < 0), "food consumption has negative values")
	_ok(ResourceTick.tick_food_consumption(dp, 241).is_empty(), "no consumption on non-day-boundary tick")

# ─── WeatherSystem ───────────────────────────────────────────────────────

func _test_weather_system() -> void:
	print("── WeatherSystem ────────────────────────────")

	var weather = WeatherSystem.make_state()
	_ok(weather.has("current"),          "weather has 'current'")
	_ok(weather.has("ticks_remaining"),  "weather has 'ticks_remaining'")
	_ok(weather.has("effects"),          "weather has 'effects'")
	_ok(weather["current"] == WeatherSystem.WeatherType.CLEAR, "starts CLEAR")

	_ok(WeatherSystem.get_movement_penalty(weather) == 1.0, "clear: full movement")
	_ok(WeatherSystem.get_farm_yield_mult(weather) == 1.0,  "clear: full farm yield")
	_ok(WeatherSystem.get_popularity_delta(weather) == 0,   "clear: 0 popularity delta")
	_ok(WeatherSystem.get_food_drain(weather) == 0.0,       "clear: no food drain")

	var snow_eff = WeatherSystem.WEATHER_EFFECTS[WeatherSystem.WeatherType.SNOW]
	_ok(snow_eff["movement_penalty"] < 1.0, "snow reduces movement")
	_ok(snow_eff["food_drain"] > 0.0,       "snow drains food (GDD §1.1.3)")
	_ok(snow_eff["popularity_delta"] < 0,   "snow hurts popularity")

	_ok(WeatherSystem.WEATHER_EFFECTS[WeatherSystem.WeatherType.FOG]["fog_army_ui"] == true,
		"fog hides army UI (GDD §1.1.3)")

	_ok(WeatherSystem.WEATHER_EFFECTS[WeatherSystem.WeatherType.DROUGHT]["farm_yield_mult"] == 0.0,
		"drought kills farm yield (GDD §1.1.3)")

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var w = WeatherSystem.make_state()
	w["ticks_remaining"] = 1
	var ev = WeatherSystem.tick(w, rng)
	_ok(not ev.is_empty(),           "weather transitions at ticks_remaining=0")
	_ok(ev.has("new_weather"),        "transition event has new_weather")
	_ok(ev.has("duration_ticks"),     "transition event has duration_ticks")
	_ok(ev["duration_ticks"] > 0,     "new weather duration > 0")

	var seen: Dictionary = {}
	for _i in range(50):
		w["ticks_remaining"] = 1
		var event = WeatherSystem.tick(w, rng)
		if not event.is_empty():
			seen[event["new_weather"]] = true
	_ok(seen.size() >= 2, "weather varies over time (>=2 types in 50 transitions)")

	_ok(WeatherSystem.weather_name(WeatherSystem.WeatherType.RAIN)    == "Rain",    "weather_name RAIN")
	_ok(WeatherSystem.weather_name(WeatherSystem.WeatherType.SNOW)    == "Snow",    "weather_name SNOW")
	_ok(WeatherSystem.weather_name(WeatherSystem.WeatherType.DROUGHT) == "Drought", "weather_name DROUGHT")

# ─── GameState integration ───────────────────────────────────────────────

func _test_gamestate_integration() -> void:
	print("── GameState integration ─────────────────────")

	_ok(_gs.weather.has("current"),           "GameState.weather initialized")
	_ok(_gs.weather.has("ticks_remaining"),   "GameState.weather has ticks_remaining")
	_ok(_gs.weather["current"] == WeatherSystem.WeatherType.CLEAR, "weather starts CLEAR")

	_gs.players = []
	_gs.simulate_tick(240)
	_ok(true, "simulate_tick with no players doesn't crash")

	_gs.initialize_player(0, "SimTest", 50, 50)
	_gs.players[0]["population"] = 5
	_gs.players[0]["food"]["apples"] = 200
	_gs.simulate_tick(240)
	_ok(true, "simulate_tick on day boundary doesn't crash with player")

	var pop_before = _gs.players[0]["popularity"]
	_gs.players[0]["tax_rate"] = 3
	for _i in range(5):
		_gs.simulate_tick(240 * (_i + 1))
	_ok(true, "5 day-boundary ticks with heavy tax don't crash")

	_gs.weather["ticks_remaining"] = 1
	_gs.simulate_tick(1999)
	_ok(true, "weather transition via simulate_tick doesn't crash")

# ─── Helper ──────────────────────────────────────────────────────────────

func _ok(condition: bool, label: String) -> void:
	if condition:
		print("  ✓ " + label)
		_pass += 1
	else:
		print("  ✗ FAIL: " + label)
		_fail += 1
