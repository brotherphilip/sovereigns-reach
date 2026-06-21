extends SceneTree
# Proof harness for the LIVE town roster: the AI economy, as it assigns crews to buildings each day,
# records one lightweight agent per worker (what they're doing + roughly where) so a watched town
# shows its ACTUAL people, not invented ones — without changing any economy numbers.
# Run: godot --headless --script tests/TestTownAgents.gd

const AIFaction        = preload("res://simulation/ai/AIFaction.gd")
const TownAgents       = preload("res://simulation/world/TownAgents.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	_test_helpers()
	_test_roster_covers_workforce()
	_test_activities_reflect_jobs()
	_test_positions_near_capital()
	_test_economy_unchanged()
	print("\n=== Town Agents Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _fac(pop: int, buildings: Array, res: Dictionary = {}) -> Dictionary:
	var f := AIFaction.make_faction(1, "Rivenhold", AIFaction.ARCHETYPE_BANDIT, 80, 90)
	f["population"] = pop
	f["buildings"] = buildings
	f["resources"] = res
	f["food"] = {"apples": 0, "bread": 0, "meat": 0, "ale": 0}
	return f

func _test_helpers() -> void:
	print("\n[Roster helpers]")
	ok("woodcutter is a GATHER job", TownAgents.activity_for("woodcutter_camp") == TownAgents.ACT_GATHER)
	ok("orchard is a GATHER job", TownAgents.activity_for("apple_orchard") == TownAgents.ACT_GATHER)
	ok("mill is a PROCESS job", TownAgents.activity_for("mill") == TownAgents.ACT_PROCESS)
	ok("market is a TRADE job", TownAgents.activity_for("market") == TownAgents.ACT_TRADE)
	var agents: Array = []
	TownAgents.add_workers(agents, "woodcutter_camp", 3, 0, 50.0, 50.0)
	TownAgents.add_idle(agents, 2, 50.0, 50.0)
	ok("add_workers/add_idle append the right counts", agents.size() == 5)
	var counts: Dictionary = TownAgents.activity_counts(agents)
	ok("activity_counts tallies (3 gather, 2 idle)", counts[TownAgents.ACT_GATHER] == 3 and counts[TownAgents.ACT_IDLE] == 2)

func _test_roster_covers_workforce() -> void:
	print("\n[Roster covers the whole workforce]")
	# More people than worker slots → some work, the rest are idle, but EVERY soul is on the roster.
	var f := _fac(12, ["woodcutter_camp", "apple_orchard", "hovel"], {"wood": 0})
	AIFaction._process_economy(f)
	var agents: Array = f["agents"]
	ok("one agent per villager (whole workforce tracked)", agents.size() == 12)
	var counts: Dictionary = TownAgents.activity_counts(agents)
	ok("some are working", counts[TownAgents.ACT_GATHER] > 0)
	ok("the surplus stand idle", counts[TownAgents.ACT_IDLE] > 0)

func _test_activities_reflect_jobs() -> void:
	print("\n[Activities reflect the real jobs]")
	# A staffed gatherer + a staffed processor (mill needs wheat) → both a gatherer and a processor.
	# Keep wheat modest so the raw store isn't already at cap (which would correctly BLOCK output).
	var f := _fac(8, ["woodcutter_camp", "mill"], {"wood": 0, "wheat": 50})
	AIFaction._process_economy(f)
	var counts: Dictionary = TownAgents.activity_counts(f["agents"])
	ok("a woodcutter crew is gathering", counts[TownAgents.ACT_GATHER] > 0)
	ok("a mill crew is processing", counts[TownAgents.ACT_PROCESS] > 0)
	# Each working agent carries the building it works at.
	var labelled := true
	for a in f["agents"]:
		if String(a.get("act", "")) != TownAgents.ACT_IDLE and String(a.get("btype", "")) == "":
			labelled = false
	ok("each working agent records its building", labelled)

func _test_positions_near_capital() -> void:
	print("\n[Positions — roughly where they are]")
	var f := _fac(10, ["woodcutter_camp", "apple_orchard", "wheat_farm"], {"wood": 0, "wheat": 0})
	AIFaction._process_economy(f)
	var near := true
	for a in f["agents"]:
		if absf(float(a["x"]) - 80.0) > 80.0 or absf(float(a["y"]) - 90.0) > 80.0:
			near = false
	ok("every agent stands within the town's bounds (near its capital 80,90)", near)
	# Gatherers and idlers sit at DIFFERENT places (workers at posts, idlers at the centre).
	var work_pos := Vector2.ZERO
	var idle_pos := Vector2.ZERO
	var has_w := false
	var has_i := false
	for a in f["agents"]:
		if String(a["act"]) == TownAgents.ACT_GATHER and not has_w:
			work_pos = Vector2(a["x"], a["y"]); has_w = true
		elif String(a["act"]) == TownAgents.ACT_IDLE and not has_i:
			idle_pos = Vector2(a["x"], a["y"]); has_i = true
	ok("workers stand apart from idlers (real posts vs the square)",
		not (has_w and has_i) or work_pos.distance_to(idle_pos) > 0.5)

func _test_economy_unchanged() -> void:
	print("\n[Economy numbers unchanged by the roster]")
	# The roster is pure bookkeeping: a staffed woodcutter still banks wood exactly as before.
	var f := _fac(4, ["woodcutter_camp"], {"wood": 0})
	var wood0: int = int(f["resources"].get("wood", 0))
	AIFaction._process_economy(f)
	ok("a staffed woodcutter still produced wood", int(f["resources"].get("wood", 0)) > wood0)
	# Idle-only town (no producers) banks nothing and everyone is idle.
	var g := _fac(6, ["hovel", "hovel"], {})
	AIFaction._process_economy(g)
	var c: Dictionary = TownAgents.activity_counts(g["agents"])
	ok("a town with no jobs has the whole workforce idle", c[TownAgents.ACT_IDLE] == 6)
