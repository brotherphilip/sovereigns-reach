extends SceneTree
# Guards the stores-full warning (iter204): the raw pool (wood/stone/ore/intermediates) is
# shared, so when it fills, gatherers can't deposit and freeze carrying their load — the
# woodcutter keeps cutting but the realm gets no more wood. The realm now warns the player
# ONCE (realm_notice, "stores are full") while a raw producer is throttled, and re-arms only
# after room opens. Drives the live GameState autoload through real day-boundary ticks.
# Run: godot --headless --script tests/TestStoresWarning.gd

const BuildingState = preload("res://simulation/buildings/BuildingState.gd")

const TPD: int = 240

var _gs: Node = null
var _sc: Node = null
var _eb: Node = null
var _notices: Array = []

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_sc = root.get_node_or_null("SimulationClock")
	_eb = root.get_node_or_null("EventBus")
	if _gs == null or _sc == null or _eb == null:
		print("FATAL: autoloads not found"); quit(1); return
	_eb.realm_notice.connect(func(msg, _tone): _notices.append(String(msg)))
	_run_all()
	print("\n=== Stores Warning Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _setup(with_producer: bool) -> Dictionary:
	_gs.players.clear()
	_gs.ai_factions.clear()
	_gs._grid = null
	_gs._next_building_id = 1
	_sc.current_tick = 0
	_gs.setup_world(12345, 8)
	_gs.initialize_player(0, "Tester", 50, 50)
	var p: Dictionary = _gs.players[0]
	var hall: Dictionary = BuildingState.create("village_hall", 0, 50, 50, 1)
	hall["built"] = true; p["buildings"].append(hall)
	if with_producer:
		var wc: Dictionary = BuildingState.create("woodcutter_camp", 0, 52, 52, 2)
		wc["built"] = true; p["buildings"].append(wc)
	return p

func _saw_stores_notice() -> bool:
	for m in _notices:
		if "stores are full" in m:
			return true
	return false

func _fill_raw_pool(p: Dictionary) -> void:
	# Drive the shared raw pool to its capacity with wood so room() == 0.
	var cap: int = _gs.StorageSystem.get_capacity(p)
	p["resources"] = {"wood": cap}

func _tick_one_day(at_day: int) -> void:
	var tk: int = at_day * TPD
	_sc.current_tick = tk
	_gs.simulate_tick(tk)

func _run_all() -> void:
	print("\n[Stores-full warning fires + re-arms (with a raw producer)]")
	var p := _setup(true)
	_fill_raw_pool(p)
	_notices.clear()
	_tick_one_day(1)
	ok("warns when the raw pool is full + a producer is throttled", _saw_stores_notice())
	ok("the warning latched (stores_full_warned set)", bool(_gs.world.get("stores_full_warned", false)))

	# Still full → no spam.
	_notices.clear()
	_tick_one_day(2)
	ok("does NOT re-warn while still full (no spam)", not _saw_stores_notice())

	# Room opens back up (player spent/built) → re-arm.
	p["resources"] = {"wood": 0}
	_tick_one_day(3)
	ok("re-arms once room opens (flag cleared)", not bool(_gs.world.get("stores_full_warned", false)))

	# Fills again → warns again.
	_fill_raw_pool(p)
	_notices.clear()
	_tick_one_day(4)
	ok("warns again after recovery + new fill", _saw_stores_notice())

	print("\n[No warning without a raw producer — full stores alone don't nag]")
	var p2 := _setup(false)
	_fill_raw_pool(p2)
	_notices.clear()
	_tick_one_day(1)
	ok("silent when no raw producer exists (nothing is throttled)", not _saw_stores_notice())
