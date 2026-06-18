extends SceneTree
# Guards the tutorial's survival-critical DEFENCE hint (iter112): the tutorial taught
# build/food/market/edict but never defence, so a new player reached the endgame siege
# undefended. As the King's Peace nears its end it must warn (once) an UNDEFENDED realm to
# raise walls + a garrison — and stay quiet for a realm that's already siege-ready.
# Run: godot --headless --script tests/TestTutorial.gd

const BuildingState = preload("res://simulation/buildings/BuildingState.gd")

var _ts: Node = null
var _gs: Node = null
var _hints: Array = []
var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	_ts = root.get_node_or_null("TutorialSystem")
	_gs = root.get_node_or_null("GameState")
	if _ts == null or _gs == null:
		print("FATAL: autoloads not found"); quit(1); return
	_ts.tutorial_hint.connect(func(msg): _hints.append(msg))
	_run_steps()
	_run()
	print("\n=== Tutorial Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _last_is_defense_hint() -> bool:
	if _hints.is_empty(): return false
	var m: String = String(_hints[-1])
	return ("walls" in m) and ("guard" in m)

func _bare_player() -> Dictionary:
	return {"id": 0, "is_alive": true, "buildings": [], "units": []}

# Append a fully-built building to the tutorial player so completion-gated steps advance.
func _place_built(btype: String, bid: int) -> void:
	var b: Dictionary = BuildingState.create(btype, 0, 5 + bid, 5, bid)
	b["built"] = true
	_gs.players[0]["buildings"].append(b)

# The fleshed-out, data-driven curriculum: start → guided steps → completion, plus the
# enemy-AI pause flag that holds the world still while the player learns.
func _run_steps() -> void:
	print("\n[Data-driven tutorial: start, step progression, AI pause]")
	_gs.world = {}
	_gs.players = [_bare_player()]
	_ts._skipped = false
	_ts.index = -1
	_hints.clear()
	_ts.start()
	ok("start() begins at step 0", _ts.index == 0)
	ok("start() pauses enemy AI (tutorial_active)", bool(_gs.world.get("tutorial_active", false)))
	ok("start() emits the first hint", _hints.size() >= 1 and "Village Hall" in String(_hints[-1]))
	ok("GameState._ai_paused() true during tutorial", _gs._ai_paused())
	var tgt: Dictionary = _ts.current_target()
	ok("first target is to build the village_hall", tgt.get("kind") == "build" and tgt.get("build") == "village_hall")

	# Placing the Village Hall does NOT advance — the next step waits until it is BUILT.
	_ts._on_building_placed(0, "village_hall", 0, 0, 1)
	ok("placing the hall does not advance yet", _ts.index == 0)
	_ts._on_tick(240)
	ok("an unbuilt hall still does not advance", _ts.index == 0)
	# Once the hall is fully raised, the woodcutter step unlocks (wood is needed for all).
	_place_built("village_hall", 1)
	_ts._on_tick(480)
	ok("a BUILT hall advances to step 1", _ts.index == 1)
	ok("step 1 target is the woodcutter", _ts.current_target().get("build") == "woodcutter_camp")
	# Then a built woodcutter advances to the food step.
	_place_built("woodcutter_camp", 2)
	_ts._on_tick(720)
	ok("a built woodcutter advances to the farm step", _ts.current_target().get("build") == "apple_orchard")

	# A wrong (built) building does NOT advance.
	var before: int = _ts.index
	_place_built("well", 3)
	_ts._on_tick(960)
	ok("a non-target building does not advance", _ts.index == before)

	# Skipping ends the tutorial and resumes enemy AI.
	_ts.skip_tutorial()
	ok("skip ends the tutorial", _ts.index == _ts.STEP_DONE and not _ts.is_active())
	ok("skip resumes enemy AI", not bool(_gs.world.get("tutorial_active", true)))

func _run() -> void:
	print("\n[Defence hint fires for an undefended realm near the grace cutoff]")
	# Undefended player, tutorial done, defence hint not yet given.
	_gs.players = [_bare_player()]
	_ts._skipped = false
	_ts.index = _ts.STEP_DONE
	_ts._defense_hint_given = false
	_hints.clear()
	# Defence warning now fires on CALENDAR day 3 (3 × TICKS_PER_CALENDAR_DAY).
	var cd: int = SimulationClock.TICKS_PER_CALENDAR_DAY
	_ts._on_tick(2 * cd)   # calendar day 2 — too early
	ok("no defence hint before calendar day 3", not _last_is_defense_hint())
	_ts._on_tick(3 * cd)   # calendar day 3 — undefended → warn
	ok("undefended realm IS warned at calendar day 3", _last_is_defense_hint())
	# Fires only once.
	var n_after: int = _hints.size()
	_ts._on_tick(4 * cd)
	ok("defence hint fires only once", _hints.size() == n_after)

	print("\n[A siege-ready realm is NOT nagged]")
	var p := _bare_player()
	for d in [["stone_wall", 10, 10, 1], ["lookout_tower", 12, 10, 2], ["gatehouse", 14, 10, 3]]:
		var b: Dictionary = BuildingState.create(d[0], 0, d[1], d[2], d[3])
		b["built"] = true
		p["buildings"].append(b)
	_gs.players = [p]
	_ts._defense_hint_given = false
	_hints.clear()
	ok("the prepared realm reads as siege-ready", _gs.is_siege_ready(p))
	_ts._on_tick(25 * 240)
	ok("a siege-ready realm gets NO defence hint", not _last_is_defense_hint())
