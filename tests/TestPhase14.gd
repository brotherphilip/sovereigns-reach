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

	print("\n--- Builder dispatch + construction ---")
	var cz2: Array = []
	CitizenSystem.spawn(cz2, 6, 50.0, 50.0, _rng(2), 1)
	var bld := [{"id": 1, "grid_x": 60, "grid_y": 50, "construction_until": 100000}]
	var saw_builder := false
	var reached_build := false
	for t in range(500):
		CitizenSystem.tick(cz2, bld, _rng(t + 1), t)
		for c in cz2:
			if c["role"] == "builder":
				saw_builder = true
			if c["state"] == CitizenSystem.STATE_BUILD:
				reached_build = true
	ok("a citizen becomes a builder", saw_builder)
	ok("builder walks to site and builds", reached_build)
	# Only one builder per site.
	var builders: int = 0
	for c in cz2:
		if c["role"] == "builder":
			builders += 1
	ok("only one builder per site", builders <= 1)

	print("\n--- Construction completes → builder goes home ---")
	# Construction finished (tick_count past construction_until).
	CitizenSystem.tick(cz2, bld, _rng(9), 100001)
	var still_building := false
	for c in cz2:
		if c["state"] == CitizenSystem.STATE_BUILD:
			still_building = true
	ok("no one keeps building a finished site", not still_building)
	ok("builders revert to peasants when done", cz2.all(func(c): return c["role"] == "peasant"))

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
