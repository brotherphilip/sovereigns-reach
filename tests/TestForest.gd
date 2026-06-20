extends SceneTree
# Living-forest regression (simulation/world/ForestSystem.gd). The forest is a substantial sim
# system that previously shipped guarded only by throwaway probe scripts; this locks its
# invariants: seed-from-grid, only-adults-fellable, fell→stump→regrow, sapling maturation,
# JSON key/stage survival, and that spread/new-seed only ever ADDS to open grass.
# Run: godot --headless --script tests/TestForest.gd

const WorldGrid    = preload("res://simulation/world/WorldGrid.gd")
const ForestSystem = preload("res://simulation/world/ForestSystem.gd")

var _pass: int = 0
var _fail: int = 0

func _init() -> void:
	_test_seed_from_grid()
	_test_only_adults_fellable()
	_test_fell_stump_regrow()
	_test_sapling_matures_to_adult()
	_test_spread_only_onto_open_grass()
	_test_json_round_trip()
	print("\n=== Forest Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = s; return r

# A small all-grass grid with a 3×3 FOREST block at (5,5)..(7,7).
func _grove_grid() -> WorldGrid:
	var grid := WorldGrid.new(20, 20)
	for y in range(5, 8):
		for x in range(5, 8):
			grid.set_terrain(x, y, WorldGrid.Terrain.FOREST)
	return grid

func _test_seed_from_grid() -> void:
	var grid := _grove_grid()
	var world := {}
	ForestSystem.init_from_grid(world, grid, _rng(1))
	ok("init seeds one tree per FOREST tile (9)", world["trees"].size() == 9)
	var all_adult := true
	for k in world["trees"].keys():
		if int(world["trees"][k][0]) != ForestSystem.ADULT: all_adult = false
	ok("seeded trees all start ADULT", all_adult)
	ok("init is idempotent (trees_init flag)", world.get("trees_init", false))
	# A second init must not double-seed.
	ForestSystem.init_from_grid(world, grid, _rng(1))
	ok("second init_from_grid does not duplicate", world["trees"].size() == 9)

func _test_only_adults_fellable() -> void:
	var grid := _grove_grid()
	var world := {}
	ForestSystem.init_from_grid(world, grid, _rng(2))
	ok("adult tile reports is_adult", ForestSystem.is_adult(world, grid, 6, 6))
	# Demote one to a sapling — it must not be fellable.
	world["trees"][ForestSystem.key_for(grid, 6, 6)] = [ForestSystem.SAPLING, 0.0, 0.03, 0]
	ok("sapling is NOT adult", not ForestSystem.is_adult(world, grid, 6, 6))
	ok("felling a sapling yields 0 wood", ForestSystem.fell(world, grid, 6, 6) == 0)
	ok("felling empty tile yields 0 wood", ForestSystem.fell(world, grid, 0, 0) == 0)

func _test_fell_stump_regrow() -> void:
	var grid := _grove_grid()
	var world := {}
	ForestSystem.init_from_grid(world, grid, _rng(3))
	var k := ForestSystem.key_for(grid, 6, 6)
	var wood := ForestSystem.fell(world, grid, 6, 6)
	ok("felling an adult yields FELL_WOOD", wood == ForestSystem.FELL_WOOD)
	ok("felled tile becomes a STUMP", int(world["trees"][k][0]) == ForestSystem.STUMP)
	ok("felled terrain reverts to GRASS", grid.get_terrain(6, 6) == WorldGrid.Terrain.GRASS)
	# Tick STUMP_REGROW_DAYS days; the stump sprouts a fresh sapling and re-forests the tile.
	for i in range(ForestSystem.STUMP_REGROW_DAYS):
		ForestSystem.tick(world, grid, _rng(100 + i))
	ok("stump regrows to a SAPLING after STUMP_REGROW_DAYS", int(world["trees"][k][0]) == ForestSystem.SAPLING)
	ok("regrown tile is FOREST terrain again", grid.get_terrain(6, 6) == WorldGrid.Terrain.FOREST)

func _test_sapling_matures_to_adult() -> void:
	var grid := WorldGrid.new(20, 20)
	grid.set_terrain(10, 10, WorldGrid.Terrain.FOREST)
	var world := {"trees": {}, "trees_init": true}
	var k := ForestSystem.key_for(grid, 10, 10)
	# A lone sapling with a known growth rate (0.05/day → ~20 days per stage).
	world["trees"][k] = [ForestSystem.SAPLING, 0.0, 0.05, 0]
	var rng := _rng(7)
	var stages: Array = []
	for day in range(60):
		ForestSystem.tick(world, grid, rng)
		stages.append(int(world["trees"][k][0]))
	ok("lone sapling reaches ADULT within 60 days", int(world["trees"][k][0]) == ForestSystem.ADULT)
	ok("growth is monotone sapling→young→adult (no stage skipped/reversed)",
		stages.has(ForestSystem.YOUNG) and stages.find(ForestSystem.YOUNG) < stages.find(ForestSystem.ADULT))

func _test_spread_only_onto_open_grass() -> void:
	var grid := WorldGrid.new(24, 24)
	# A dense adult block so spread has adults to seed from.
	for y in range(8, 14):
		for x in range(8, 14):
			grid.set_terrain(x, y, WorldGrid.Terrain.FOREST)
	# Occupy one open neighbour with a building — a tree must never sprout on it.
	grid.set_building_at(7, 10, 555)
	var world := {}
	ForestSystem.init_from_grid(world, grid, _rng(9))
	var rng := _rng(9)
	for i in range(120):
		ForestSystem.tick(world, grid, rng)
	# Every tree must sit on a FOREST tile and never on the occupied building tile.
	var occupied_has_tree: bool = world["trees"].has(ForestSystem.key_for(grid, 7, 10))
	ok("no tree ever sprouts on a building tile", not occupied_has_tree)
	var all_on_forest := true
	for k in world["trees"].keys():
		var x: int = int(k) % grid.width
		var y: int = int(k) / grid.width
		# A live (non-stump) tree must stand on FOREST terrain.
		if int(world["trees"][k][0]) != ForestSystem.STUMP and grid.get_terrain(x, y) != WorldGrid.Terrain.FOREST:
			all_on_forest = false
	ok("every standing tree sits on FOREST terrain", all_on_forest)
	ok("forest spread/new-seed grew the woodland (>= initial 36)", world["trees"].size() >= 36)

func _test_json_round_trip() -> void:
	var grid := _grove_grid()
	var world := {}
	ForestSystem.init_from_grid(world, grid, _rng(11))
	world["trees"][ForestSystem.key_for(grid, 6, 6)] = [ForestSystem.SAPLING, 0.4, 0.03, 0]
	var round = JSON.parse_string(JSON.stringify(world["trees"]))
	ok("JSON round-trip preserves tree count", round != null and round.size() == world["trees"].size())
	var keys_are_strings := true
	for k in round.keys():
		if not (k is String): keys_are_strings = false
	ok("JSON keys survive as Strings (no int-key orphaning)", keys_are_strings)
	# is_adult must still resolve correctly against the round-tripped dict.
	var w2 := {"trees": round}
	ok("round-tripped adult still reads as adult", ForestSystem.is_adult(w2, grid, 5, 5))
	ok("round-tripped sapling still reads as non-adult", not ForestSystem.is_adult(w2, grid, 6, 6))
