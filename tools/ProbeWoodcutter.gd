extends SceneTree
# Focused diagnostic: ONE woodcutter + hall + stockpile + ample forest. Logs the worker's
# work_phase / carry, credited wood, and remaining forest density so we can see exactly
# why deliveries stall (the user: "woodcutters keep cutting but the player gets no more wood").
# Run: godot --headless --script tools/ProbeWoodcutter.gd
const CitizenSystem    = preload("res://simulation/world/CitizenSystem.gd")
const WorldGrid        = preload("res://simulation/world/WorldGrid.gd")
const BuildingState    = preload("res://simulation/buildings/BuildingState.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 7
	var grid := WorldGrid.new(200, 200)
	var kx := 100; var ky := 100
	var plan := [["village_hall", 0, 0], ["granary", -3, 0],
		["apple_orchard", 3, 0], ["wheat_farm", -3, 3], ["woodcutter_camp", 0, 4]]
	var buildings: Array = []
	var bid := 1
	for item in plan:
		var defn: Dictionary = BuildingRegistry.lookup(item[0])
		var gx: int = kx + int(item[1]); var gy: int = ky + int(item[2])
		var b: Dictionary = BuildingState.create(item[0], 0, gx, gy, bid); bid += 1
		b["built"] = true
		b["workers"] = defn.get("max_workers", 1)
		buildings.append(b)
		var w: int = defn.get("width", 1); var h: int = defn.get("height", 1)
		for dy in range(h):
			for dx in range(w):
				grid.set_building_at(gx + dx, gy + dy, b["id"])
	# A large, ample forest right next to the camp — should never run out in this run.
	var forest_tiles := 0
	for dx in range(-6, 7):
		for dy in range(5, 12):
			grid.set_terrain(kx + dx, ky + dy, WorldGrid.Terrain.FOREST)
			grid.set_resource_density(kx + dx, ky + dy, 400)
			forest_tiles += 1
	print("forest tiles=%d total density=%d" % [forest_tiles, forest_tiles * 400])

	var player := {"buildings": buildings, "resources": {}, "food": {}, "armory": {},
		"tech_unlocks": [], "active_edicts": [], "population": 16}
	var citizens: Array = []
	CitizenSystem.spawn(citizens, 16, float(kx), float(ky), _rng, 1)
	var wc_id: int = int(buildings[-1].get("id", -1))   # woodcutter is last in plan

	print("tick | wood | forest_density | worker phases (phase/carry)")
	for t in range(60001):
		CitizenSystem.tick(citizens, player, _rng, t, grid, 1.0, false)  # day_night=false → always day
		if t % 6000 == 0:
			var res: Dictionary = player.get("resources", {})
			var wc_workers := 0
			var wc_phase := "-"
			for c in citizens:
				if c is Dictionary and int(c.get("job", -1)) == wc_id and c.get("role","") == "worker":
					wc_workers += 1
					wc_phase = str(c.get("work_phase", "-")) + "/" + str(c.get("carry",""))
			print("%6d | wood=%d wheat=%d | wc_workers=%d wc_phase=%s" % [
				t, int(res.get("wood", 0)), int(res.get("wheat", 0)), wc_workers, wc_phase])
	quit(0)
