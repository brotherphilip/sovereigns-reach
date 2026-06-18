extends SceneTree
# REAL state-over-time probe on the SAME building plan the on-screen SR_AUTOPLAY uses
# (hall + granary + 3 orchards + wheat farm + woodcutter, NO stockpile → wood routes to
# the hall, food to the granary). Drives CitizenSystem with day_night=true across multiple
# sun cycles and samples credited food & wood — proving (a) chain goods accumulate ONLY via
# physical delivery on the realistic layout, and (b) the night sleep fix does NOT stall the
# workforce (production must keep climbing through night windows).
# Run: godot --headless --script tools/ProbeHaulEconomy.gd

const CitizenSystem    = preload("res://simulation/world/CitizenSystem.gd")
const SeasonSystem     = preload("res://simulation/world/SeasonSystem.gd")
const WorldGrid        = preload("res://simulation/world/WorldGrid.gd")
const BuildingState    = preload("res://simulation/buildings/BuildingState.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const FoodSystem       = preload("res://simulation/economy/FoodSystem.gd")

var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 2026
	var grid := WorldGrid.new(200, 200)
	var kx := 100
	var ky := 100
	# Same plan as CityViewScene._dev_autoplay (offsets from the keep).
	var plan := [
		["village_hall", 0, 0], ["granary", -3, 0],
		["apple_orchard", 3, 0], ["apple_orchard", 3, 2], ["apple_orchard", 3, -2],
		["wheat_farm", -3, 3], ["woodcutter_camp", 0, 4],
	]
	var buildings: Array = []
	var bid := 1
	for item in plan:
		var defn: Dictionary = BuildingRegistry.lookup(item[0])
		var gx: int = kx + int(item[1])
		var gy: int = ky + int(item[2])
		var b: Dictionary = BuildingState.create(item[0], 0, gx, gy, bid)
		bid += 1
		b["built"] = true
		b["workers"] = defn.get("max_workers", 1)
		buildings.append(b)
		var w: int = defn.get("width", 1); var h: int = defn.get("height", 1)
		var field: bool = defn.get("field", false)
		for dy in range(h):
			for dx in range(w):
				grid.set_building_at(gx + dx, gy + dy, b["id"])
				grid.set_field_at(gx + dx, gy + dy, field)
	# A wood within reach of the camp (camp at +0,+4 from keep).
	for d in [Vector2i(kx, ky + 7), Vector2i(kx + 1, ky + 7), Vector2i(kx - 1, ky + 7),
			Vector2i(kx, ky + 8), Vector2i(kx + 1, ky + 8)]:
		grid.set_terrain(d.x, d.y, WorldGrid.Terrain.FOREST)
		grid.set_resource_density(d.x, d.y, 400)

	var player := {"buildings": buildings, "resources": {}, "food": {}, "armory": {},
		"tech_unlocks": [], "active_edicts": [], "population": 12}
	var citizens: Array = []
	CitizenSystem.spawn(citizens, 12, float(kx), float(ky), _rng, 1)

	# Force the harvest season so the orchard/wheat actually yield (autumn = both in window).
	# season_at_tick is derived from the tick we pass, so run within an autumn window.
	print("real_tick, phase, day_food, wood, inside, working")
	var total_ticks := 54000   # 3 sun cycles
	var sample_every := 4500
	for t in range(total_ticks + 1):
		CitizenSystem.tick(citizens, player, _rng, t, grid, 1.0, true)
		if t % sample_every == 0:
			var food: int = FoodSystem.get_total_food(player)
			var wood: int = int(player.get("resources", {}).get("wood", 0))
			var inside := 0
			var working := 0
			for c in citizens:
				if c is Dictionary:
					var st: String = c.get("state", "")
					if st == "inside": inside += 1
					elif st == "work": working += 1
			var phase := "NIGHT" if SeasonSystem.is_night(t) else "day"
			print("%6d, %5s, %8d, %5d, %6d, %7d" % [t, phase, food, wood, inside, working])
	quit(0)
