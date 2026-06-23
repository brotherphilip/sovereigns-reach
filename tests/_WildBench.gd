extends SceneTree
# Measures WildlifeSystem.tick ms/tick on the finding's scenario.
const WildlifeSystem = preload("res://simulation/world/WildlifeSystem.gd")

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345 ^ 0x0DEE12
	var wildlife: Array = []
	var next_id: int = 1
	var hid: int = 0
	# Spawn herds to reach ~74 animals across the 4 species, like setup_world.
	var types := ["deer", "boar", "fox", "rabbit"]
	while wildlife.size() < 74:
		var type: String = types[hid % types.size()]
		var band: Vector2i = WildlifeSystem.cfg(type)["herd"]
		var count: int = rng.randi_range(band.x, band.y)
		var cx: float = rng.randf_range(20, 180)
		var cy: float = rng.randf_range(20, 180)
		next_id = WildlifeSystem.spawn_herd(wildlife, hid, cx, cy, count, rng, next_id, type)
		hid += 1
	# trim to ~74
	while wildlife.size() > 74:
		wildlife.pop_back()
	print("animals=", wildlife.size())

	var threats: Array = []   # normal case: no threats
	var grid = null            # finding measured grid present; test both

	# Warm
	for w in range(500):
		next_id = WildlifeSystem.tick(wildlife, threats, grid, rng, w, next_id)

	# state mix
	var mix := {}
	for a in wildlife:
		mix[a["state"]] = mix.get(a["state"], 0) + 1
	print("state mix (grid=null): ", mix)

	var N: int = 5000
	var t0: int = Time.get_ticks_usec()
	for w in range(N):
		next_id = WildlifeSystem.tick(wildlife, threats, grid, rng, 500 + w, next_id)
	var dt: float = float(Time.get_ticks_usec() - t0) / 1000.0 / float(N)
	print(">>> WildlifeSystem.tick = %.4f ms/tick  (animals=%d, grid=null, no threats)" % [dt, wildlife.size()])

	# Re-measure with a real grid to capture _passable cost.
	var WorldGrid = load("res://simulation/world/WorldGrid.gd")
	if WorldGrid != null:
		var g = WorldGrid.new(200, 200)
		var t1: int = Time.get_ticks_usec()
		for w in range(N):
			next_id = WildlifeSystem.tick(wildlife, threats, g, rng, 5500 + w, next_id)
		var dt1: float = float(Time.get_ticks_usec() - t1) / 1000.0 / float(N)
		print(">>> WildlifeSystem.tick = %.4f ms/tick  (animals=%d, grid=present, no threats)" % [dt1, wildlife.size()])
	quit(0)
