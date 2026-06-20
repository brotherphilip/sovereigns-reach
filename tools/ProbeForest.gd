extends SceneTree
const WorldGrid = preload("res://simulation/world/WorldGrid.gd")
const ForestSystem = preload("res://simulation/world/ForestSystem.gd")

func _count(world, stage):
	var n := 0
	for k in world["trees"].keys():
		if int(world["trees"][k][0]) == stage: n += 1
	return n

func _init() -> void:
	var grid := WorldGrid.new(60, 60)
	# A small grove of forest tiles.
	for x in range(20, 28):
		for y in range(20, 28):
			grid.set_terrain(x, y, WorldGrid.Terrain.FOREST)
	var world := {}
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	ForestSystem.init_from_grid(world, grid, rng)
	print("init adults=%d total=%d" % [_count(world, ForestSystem.ADULT), world["trees"].size()])
	# Fell a few adults, watch wood + stump→regrow, and spread/new-seed over time.
	var wood := 0
	wood += ForestSystem.fell(world, grid, 22, 22)
	wood += ForestSystem.fell(world, grid, 23, 23)
	print("felled 2 adults -> wood=%d, terrain(22,22)=%d (grass=%d), stumps=%d" % [
		wood, grid.get_terrain(22, 22), WorldGrid.Terrain.GRASS, _count(world, ForestSystem.STUMP)])
	for day in range(1, 41):
		ForestSystem.tick(world, grid, rng)
		if day % 10 == 0:
			print("day %2d | sapling=%d young=%d adult=%d stump=%d total=%d" % [
				day, _count(world, ForestSystem.SAPLING), _count(world, ForestSystem.YOUNG),
				_count(world, ForestSystem.ADULT), _count(world, ForestSystem.STUMP), world["trees"].size()])
	# JSON save/load round-trip: the woodcutter must still find + fell adults after a reload.
	var saved := {"trees": JSON.parse_string(JSON.stringify(world["trees"]))}
	var key_type := "String" if (saved["trees"].keys()[0] is String) else "OTHER"
	var ok_adult := ForestSystem.is_adult(saved, grid, 24, 24)   # an unfelled grove tile
	var wood2 := ForestSystem.fell(saved, grid, 24, 24)
	print("round-trip: keys are %s, is_adult(24,24)=%s, fell yielded %d" % [key_type, str(ok_adult), wood2])
	quit(0)
