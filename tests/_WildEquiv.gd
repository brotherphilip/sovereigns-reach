extends SceneTree
# Verifies a patched WildlifeSystem produces identical state to a reference run.
# Run twice: once with the original file, once patched; compares against a dumped baseline.
const WildlifeSystem = preload("res://simulation/world/WildlifeSystem.gd")

func _hash_state(wildlife: Array) -> String:
	var s := ""
	for a in wildlife:
		s += "%.9f,%.9f,%.9f,%s,%d,%.9f|" % [a["x"], a["y"], a["facing"], a["state"], int(a["state_ticks"]), a["anim"]]
	return s

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345 ^ 0x0DEE12
	var wildlife: Array = []
	var next_id: int = 1
	var hid: int = 0
	var types := ["deer", "boar", "fox", "rabbit"]
	while wildlife.size() < 74:
		var type: String = types[hid % types.size()]
		var band: Vector2i = WildlifeSystem.cfg(type)["herd"]
		var count: int = rng.randi_range(band.x, band.y)
		var cx: float = rng.randf_range(20, 180)
		var cy: float = rng.randf_range(20, 180)
		next_id = WildlifeSystem.spawn_herd(wildlife, hid, cx, cy, count, rng, next_id, type)
		hid += 1
	while wildlife.size() > 74:
		wildlife.pop_back()
	var WorldGrid = load("res://simulation/world/WorldGrid.gd")
	var g = WorldGrid.new(200, 200)
	# Deterministic threats schedule so the RUN branch is also exercised.
	for w in range(2000):
		var threats: Array = []
		if (w / 100) % 3 == 0:
			threats.append({"x": 100.0, "y": 100.0})
		next_id = WildlifeSystem.tick(wildlife, threats, g, rng, w, next_id)
	var h := _hash_state(wildlife)
	var path := "user://wild_equiv.txt"
	var f = FileAccess.open(path, FileAccess.READ)
	if f != null:
		var prev := f.get_as_text()
		f.close()
		if prev == h:
			print("EQUIV: IDENTICAL (", wildlife.size(), " animals)")
		else:
			print("EQUIV: DIFFER")
			# show first diff index
			var pa := prev.split("|"); var ca := h.split("|")
			for i in range(min(pa.size(), ca.size())):
				if pa[i] != ca[i]:
					print("  first diff at animal ", i, ":\n    base=", pa[i], "\n    new =", ca[i])
					break
	else:
		var wf = FileAccess.open(path, FileAccess.WRITE)
		wf.store_string(h)
		wf.close()
		print("BASELINE WRITTEN (", wildlife.size(), " animals)")
	quit(0)
