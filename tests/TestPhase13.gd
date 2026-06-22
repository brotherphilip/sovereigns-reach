extends SceneTree
# Phase 13 test suite — Wildlife (deer herds, state machine, herding, flight).
# Run: godot --headless --script tests/TestPhase13.gd

const WildlifeSystem = preload("res://simulation/world/WildlifeSystem.gd")
const WorldGrid      = preload("res://simulation/world/WorldGrid.gd")

var _pass: int = 0
var _fail: int = 0

func _init() -> void:
	await process_frame
	_run()
	print("Phase 13 Results: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: " + label)
	else: _fail += 1; print("  FAIL: " + label)

func _rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r

func _run() -> void:
	print("\n--- Spawning ---")
	var wl: Array = []
	var rng := _rng(7)
	var nxt := WildlifeSystem.spawn_herd(wl, 0, 50.0, 50.0, 5, rng, 1)
	ok("herd spawns 5 deer", wl.size() == 5)
	ok("ids are sequential", wl[0]["id"] == 1 and wl[4]["id"] == 5 and nxt == 6)
	ok("all in herd 0", wl.all(func(a): return a["herd_id"] == 0))
	ok("deer spawn near centre", wl.all(func(a): return abs(a["x"] - 50.0) <= 3.0))
	ok("herd has at least one fawn", wl.any(func(a): return a["age"] == 0))

	print("\n--- Threat flight ---")
	var d := WildlifeSystem.make_animal(1, 0, 50.0, 50.0, true)
	var herd := [d]
	# Threat just to the west (x=48) → deer should flee east (x increases).
	WildlifeSystem.tick(herd, [{"x": 48.0, "y": 50.0}], null, _rng(1), 10, 2)
	ok("deer flees → state run", d["state"] == WildlifeSystem.STATE_RUN)
	ok("deer flees away from threat (east)", d["x"] > 50.0)
	var x_after_one: float = d["x"]
	WildlifeSystem.tick(herd, [{"x": 48.0, "y": 50.0}], null, _rng(2), 11, 2)
	ok("deer keeps fleeing", d["x"] > x_after_one)

	print("\n--- Roaming + idle states ---")
	var d2 := WildlifeSystem.make_animal(1, 0, 50.0, 50.0, true)
	d2["state"] = WildlifeSystem.STATE_ROAM
	d2["state_ticks"] = 1   # forces a state change next tick
	var herd2 := [d2]
	var rng2 := _rng(99)
	var saw_non_roam := false
	var path_len: float = 0.0
	var prev := Vector2(d2["x"], d2["y"])
	for t in range(400):
		WildlifeSystem.tick(herd2, [], null, rng2, t + 1, 2)
		if d2["state"] != WildlifeSystem.STATE_ROAM:
			saw_non_roam = true
		var cur := Vector2(d2["x"], d2["y"])
		path_len += prev.distance_to(cur)
		prev = cur
	ok("deer wanders while roaming (path length)", path_len > 1.0)
	ok("deer cycles into feed/brood states", saw_non_roam)

	print("\n--- Herding (cohesion) ---")
	var a := WildlifeSystem.make_animal(1, 0, 50.0, 50.0, true)
	var b := WildlifeSystem.make_animal(2, 0, 62.0, 50.0, true)
	a["state_ticks"] = 100000; b["state_ticks"] = 100000  # stay roaming
	var grp := [a, b]
	var rng3 := _rng(123)
	var d_start: float = Vector2(a["x"], a["y"]).distance_to(Vector2(b["x"], b["y"]))
	for t in range(400):
		a["state"] = WildlifeSystem.STATE_ROAM; b["state"] = WildlifeSystem.STATE_ROAM
		a["state_ticks"] = 100000; b["state_ticks"] = 100000
		WildlifeSystem.tick(grp, [], null, rng3, t + 1, 3)
	var d_end: float = Vector2(a["x"], a["y"]).distance_to(Vector2(b["x"], b["y"]))
	ok("herd-mates converge (cohesion)", d_end < d_start - 4.0)

	print("\n--- Terrain blocking ---")
	var g := WorldGrid.new(20, 20)  # all grass by default
	g.set_terrain(11, 10, WorldGrid.Terrain.RIVER)  # impassable tile east of the deer
	var dw := WildlifeSystem.make_animal(1, 0, 10.0, 10.0, true)
	dw["state"] = WildlifeSystem.STATE_RUN
	dw["state_ticks"] = 100
	var herdw := [dw]
	# Drive it east into the river repeatedly; it must not stand on the river tile.
	for t in range(60):
		WildlifeSystem.tick(herdw, [{"x": 5.0, "y": 10.0}], g, _rng(t + 1), t + 1, 2)
	ok("deer does not enter impassable water", int(round(dw["x"])) != 11 or int(round(dw["y"])) != 10)

	print("\n--- Breeding ---")
	var bw: Array = []
	WildlifeSystem.spawn_herd(bw, 0, 50.0, 50.0, 3, _rng(5), 1)
	for x in bw:
		x["age"] = WildlifeSystem.ADULT_AGE + 100   # all adults
	var before: int = bw.size()
	# Before the cooldown elapses, no births.
	var nid := 4
	for t in range(100):
		nid = WildlifeSystem.tick(bw, [], null, _rng(t + 1), t + 1, nid)
	ok("no births before breed cooldown", bw.size() == before)
	# Over several breed intervals, the herd grows (up to the cap).
	for t in range(2000, 2000 + WildlifeSystem.BREED_INTERVAL * 5):
		nid = WildlifeSystem.tick(bw, [], null, _rng(t), t, nid)
	ok("herd grows via breeding", bw.size() > before)
	ok("herd respects population cap", bw.size() <= WildlifeSystem.HERD_CAP)

	print("\n--- Species (deer / boar / fox / rabbit) ---")
	for type in ["deer", "boar", "fox", "rabbit"]:
		var sl: Array = []
		WildlifeSystem.spawn_herd(sl, 0, 40.0, 40.0, 4, _rng(11), 1, type)
		ok("%s group all tagged '%s'" % [type, type], sl.all(func(x): return x["type"] == type))
		var c: Dictionary = WildlifeSystem.cfg(type)
		ok("%s adult hp = cfg.adult_hp" % type, sl[0]["max_hp"] == c["adult_hp"])
	# Default type stays deer (back-compat with the 7-arg call used above).
	var dl: Array = []
	WildlifeSystem.spawn_herd(dl, 0, 40.0, 40.0, 2, _rng(12), 1)
	ok("spawn_herd default type is deer", dl[0]["type"] == "deer")
	# Newborns inherit the herd's species, and each species honours its own cap.
	var fl: Array = []
	WildlifeSystem.spawn_herd(fl, 0, 30.0, 30.0, 3, _rng(3), 1, "fox")
	for x in fl:
		x["age"] = WildlifeSystem.ADULT_AGE + 100
	var fnid := 5
	for t in range(3000, 3000 + WildlifeSystem.BREED_INTERVAL * 6):
		fnid = WildlifeSystem.tick(fl, [], null, _rng(t), t, fnid)
	ok("fox skulk grows via breeding", fl.size() > 3)
	ok("fox newborns are foxes", fl.all(func(x): return x["type"] == "fox"))
	ok("fox honours its own (smaller) cap", fl.size() <= int(WildlifeSystem.cfg("fox")["cap"]))
