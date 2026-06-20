extends SceneTree
# Reproduce the REAL game path (GameState.simulate_tick) for a player-built woodcutter +
# stockpile, WITH vs WITHOUT forest in range — to see why in-game wood doesn't move.
# Run: godot --headless --script tools/ProbeRealWood.gd
const BuildingState    = preload("res://simulation/buildings/BuildingState.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const WorldGrid        = preload("res://simulation/world/WorldGrid.gd")

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	var sc = root.get_node_or_null("SimulationClock")
	if gs == null or sc == null:
		print("FATAL: autoloads missing"); quit(1); return
	_run(gs, sc, true)
	_run(gs, sc, false)
	quit(0)

func _run(gs, sc, with_forest: bool) -> void:
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
	if with_forest:
		# Forest placed FAR from the hut (~40 tiles) to prove the woodcutter walks to it.
		for dx in range(0, 6):
			for dy in range(0, 6):
				grid.set_terrain(140 + dx, 138 + dy, WorldGrid.Terrain.FOREST)
				grid.set_resource_density(140 + dx, 138 + dy, 400)
	var w0: int = int(p.get("resources", {}).get("wood", 0))
	for i in range(1, 40001):
		sc.current_tick = i
		gs.simulate_tick(i)
	var w1: int = int(p.get("resources", {}).get("wood", 0))
	var nw: int = 0
	for c in gs.citizens:
		if c is Dictionary and int(c.get("job", -1)) == 900 and String(c.get("role", "")) == "worker":
			nw += 1
	print("forest=%s : wood %d -> %d   (woodcutter workers=%d, total citizens=%d)" % [
		str(with_forest), w0, w1, nw, gs.citizens.size()])
