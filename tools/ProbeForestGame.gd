extends SceneTree
# Real GameState: a player woodcutter + stockpile beside a living-forest grove. Confirms the
# woodcutter walks to ADULT trees, fells them (wood credited, stumps left), trees regrow, and
# tree-fall events are recorded for the view.  Run: godot --headless --script tools/ProbeForestGame.gd
const BuildingState    = preload("res://simulation/buildings/BuildingState.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const WorldGrid        = preload("res://simulation/world/WorldGrid.gd")
const ForestSystem     = preload("res://simulation/world/ForestSystem.gd")

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	var sc = root.get_node_or_null("SimulationClock")
	if gs == null or sc == null:
		print("FATAL: autoloads missing"); quit(1); return
	gs.players.clear(); gs.ai_factions.clear(); gs._grid = null; gs._next_building_id = 1
	sc.current_tick = 0
	gs.setup_world(12345, 8)
	gs.initialize_player(0, "T", 100, 100)
	var p = gs.players[0]
	var grid = gs._grid
	var maxw: int = int(BuildingRegistry.lookup("woodcutter_camp").get("max_workers", 2))
	var wc = BuildingState.create("woodcutter_camp", 0, 104, 100, 900)
	wc["built"] = true; wc["workers"] = maxw
	p["buildings"].append(wc)
	for dy in range(3): for dx in range(2): grid.set_building_at(104 + dx, 100 + dy, 900)
	var sp = BuildingState.create("stockpile", 0, 96, 100, 901)
	sp["built"] = true
	p["buildings"].append(sp)
	for dy in range(2): for dx in range(2): grid.set_building_at(96 + dx, 100 + dy, 901)
	# Plant an adult grove ~40 tiles away, registered in the living forest.
	var rng := RandomNumberGenerator.new(); rng.seed = 99
	for dx in range(0, 6):
		for dy in range(0, 6):
			var x: int = 140 + dx; var y: int = 138 + dy
			grid.set_terrain(x, y, WorldGrid.Terrain.FOREST)
			gs.world["trees"][ForestSystem.key_for(grid, x, y)] = [ForestSystem.ADULT, 1.0, 0.03, 0]

	var w0: int = int(p.get("resources", {}).get("wood", 0))
	var adults0 := _count(gs.world, grid, ForestSystem.ADULT)
	for i in range(1, 20001):
		sc.current_tick = i
		gs.simulate_tick(i)
	var w1: int = int(p.get("resources", {}).get("wood", 0))
	print("wood %d -> %d" % [w0, w1])
	print("grove adults %d -> %d, stumps now %d, total trees %d" % [
		adults0, _count(gs.world, grid, ForestSystem.ADULT),
		_count(gs.world, grid, ForestSystem.STUMP), gs.world["trees"].size()])
	print("tree_falls recorded (uncleared, no view): %d" % gs.world.get("tree_falls", []).size())
	# JSON save/load round-trip: keys must survive so the forest isn't orphaned after loading.
	var round = JSON.parse_string(JSON.stringify(gs.world["trees"]))
	var adult_after := 0
	for k in round.keys():
		if int(round[k][0]) == ForestSystem.ADULT: adult_after += 1
	print("JSON round-trip: %d keys, %d adults (was %d)" % [round.size(), adult_after, gs.world["trees"].size()])
	quit(0)

func _count(world, grid, stage) -> int:
	var n := 0
	for k in world.get("trees", {}).keys():
		if int(world["trees"][k][0]) == stage: n += 1
	return n
