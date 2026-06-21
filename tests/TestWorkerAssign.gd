extends SceneTree
# Guards the worker-assignment clamp (iter282). WorkerSystem.assign_workers clamped only the UPPER
# bound (min of capacity & available pool) — a crafted/replayed set-workers command with a NEGATIVE
# count stored negative workers on a building, which inflated the free-worker pool (since
# _available_workers subtracts total_assigned) and let the realm over-staff OTHER buildings: a
# phantom-worker production exploit. assign_workers now clamps count to [0, capacity]. The UI only
# ever sends 0..max, so this purely hardens the authoritative command path.
# Run: godot --headless --script tests/TestWorkerAssign.gd

const WorkerSystem = preload("res://simulation/player/WorkerSystem.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	_run()
	print("\n=== Worker Assign Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _run() -> void:
	print("\n[a NEGATIVE worker count cannot create phantom workers]")
	# pop 20; building A fully staffed (5), building B empty (cap 5).
	var player := {
		"population": 20, "military_strength": 0,
		"buildings": [
			{"id": 1, "max_workers": 5, "workers": 5},
			{"id": 2, "max_workers": 5, "workers": 0},
		],
	}
	var bld_a: Dictionary = player["buildings"][0]
	var bld_b: Dictionary = player["buildings"][1]

	WorkerSystem.assign_workers(bld_a, -100, player)
	ok("negative count clamps to 0 (not stored negative)", int(bld_a["workers"]) == 0)
	ok("total_assigned never goes negative", WorkerSystem.total_assigned(player) >= 0)

	# The exploit was: A at -100 frees 100 phantom workers, so B could be over-staffed beyond pop.
	WorkerSystem.assign_workers(bld_b, 1000, player)
	ok("upper clamp still holds: B gets at most its capacity (5)", int(bld_b["workers"]) == 5)
	ok("no phantom workers: total assigned ≤ population", WorkerSystem.total_assigned(player) <= 20)

	print("\n[normal positive assignment is unaffected]")
	var p2 := {
		"population": 10, "military_strength": 0,
		"buildings": [{"id": 1, "max_workers": 5, "workers": 0}],
	}
	var net: int = WorkerSystem.assign_workers(p2["buildings"][0], 3, p2)
	ok("assigning 3 to a cap-5 building works", int(p2["buildings"][0]["workers"]) == 3)
	ok("net change reported correctly (+3)", net == 3)

	# Reducing workers (a legitimate smaller positive count) still works.
	WorkerSystem.assign_workers(p2["buildings"][0], 1, p2)
	ok("reducing 3→1 works (legit lower positive count)", int(p2["buildings"][0]["workers"]) == 1)

	# Assigning more than the available pool is capped by the pool, not the request.
	var p3 := {
		"population": 2, "military_strength": 0,
		"buildings": [{"id": 1, "max_workers": 8, "workers": 0}],
	}
	WorkerSystem.assign_workers(p3["buildings"][0], 8, p3)
	ok("capped by available pool (only 2 free for a cap-8 building)", int(p3["buildings"][0]["workers"]) == 2)
