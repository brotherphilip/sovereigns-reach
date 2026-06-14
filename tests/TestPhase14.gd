extends SceneTree
# Phase 14 test suite — Citizens (villager pawns, builders, construction).
# Run: godot --headless --script tests/TestPhase14.gd

const CitizenSystem = preload("res://simulation/world/CitizenSystem.gd")

var _pass: int = 0
var _fail: int = 0

func _init() -> void:
	await process_frame
	_run()
	print("Phase 14 Results: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: " + label)
	else: _fail += 1; print("  FAIL: " + label)

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = s; return r

func _run() -> void:
	print("\n--- Spawn ---")
	var cz: Array = []
	var nxt := CitizenSystem.spawn(cz, 8, 50.0, 50.0, _rng(1), 1)
	ok("spawns 8 citizens", cz.size() == 8)
	ok("ids sequential", cz[0]["id"] == 1 and nxt == 9)
	ok("spawn near home", cz.all(func(c): return abs(c["x"] - 50.0) <= 4.0))
	ok("start as peasants", cz.all(func(c): return c["role"] == "peasant"))

	print("\n--- Idle ↔ wander cycle ---")
	var c0: Dictionary = cz[0]
	c0["state"] = CitizenSystem.STATE_IDLE
	c0["state_ticks"] = 1
	var saw_wander := false
	for t in range(600):
		CitizenSystem.tick(cz, [], _rng(t + 1), t)
		if c0["state"] == CitizenSystem.STATE_WANDER:
			saw_wander = true
	ok("citizens idle→wander", saw_wander)

	print("\n--- Builder-driven construction ---")
	var cz2: Array = []
	CitizenSystem.spawn(cz2, 6, 50.0, 50.0, _rng(2), 1)
	var bld := [{"id": 1, "grid_x": 56, "grid_y": 50, "built": false, "build_progress": 0.0, "build_required": 200.0}]
	var saw_builder := false
	var reached_build := false
	var built_at := -1
	for t in range(1000):
		CitizenSystem.tick(cz2, bld, _rng(t + 1), t)
		for c in cz2:
			if c["role"] == "builder": saw_builder = true
			if c["state"] == CitizenSystem.STATE_BUILD: reached_build = true
		if bld[0]["built"] and built_at < 0:
			built_at = t
	ok("citizens become builders", saw_builder)
	ok("builders reach the site and build", reached_build)
	ok("progress is builder-driven and completes the building", bld[0]["built"])
	ok("builders revert to peasants once built", cz2.all(func(c): return c["role"] == "peasant"))

	# More builders → faster: same work with 6 vs 1 villager.
	print("\n--- More builders build faster ---")
	var one: Array = []; CitizenSystem.spawn(one, 1, 50.0, 50.0, _rng(4), 1)
	var many: Array = []; CitizenSystem.spawn(many, 6, 50.0, 50.0, _rng(4), 1)
	var b1 := [{"id": 1, "grid_x": 51, "grid_y": 50, "built": false, "build_progress": 0.0, "build_required": 300.0}]
	var bM := [{"id": 1, "grid_x": 51, "grid_y": 50, "built": false, "build_progress": 0.0, "build_required": 300.0}]
	var t1 := -1; var tM := -1
	for t in range(1500):
		if t1 < 0:
			CitizenSystem.tick(one, b1, _rng(t + 100), t)
			if b1[0]["built"]: t1 = t
		if tM < 0:
			CitizenSystem.tick(many, bM, _rng(t + 100), t)
			if bM[0]["built"]: tM = t
		if t1 >= 0 and tM >= 0: break
	ok("six builders finish faster than one", tM >= 0 and t1 >= 0 and tM < t1)

	print("\n--- Walk movement ---")
	var w: Array = []
	CitizenSystem.spawn(w, 1, 50.0, 50.0, _rng(3), 1)
	var wc: Dictionary = w[0]
	wc["x"] = 50.0; wc["y"] = 50.0
	wc["state"] = CitizenSystem.STATE_WALK
	wc["tx"] = 58.0; wc["ty"] = 50.0
	var d0: float = abs(58.0 - wc["x"])
	for t in range(40):
		wc["state"] = CitizenSystem.STATE_WALK
		wc["tx"] = 58.0; wc["ty"] = 50.0
		CitizenSystem.tick(w, [], _rng(t + 1), t)
	ok("citizen walks toward target", abs(58.0 - wc["x"]) < d0 - 0.5)
