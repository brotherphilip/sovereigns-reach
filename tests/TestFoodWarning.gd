extends SceneTree
# Guards the low-food warning (iter198): when the granary drops toward starvation while a
# buffer remains, the realm warns the player ONCE (realm_notice) and re-arms only after food
# recovers — so a drought-driven famine is never silent until is_starving (food 0) is too late.
# Drives the live GameState autoload through real day-boundary ticks.
# Run: godot --headless --script tests/TestFoodWarning.gd

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
	print("\n=== Food Warning Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _setup() -> Dictionary:
	_gs.players.clear()
	_gs.ai_factions.clear()
	_gs._grid = null
	_gs._next_building_id = 1
	_sc.current_tick = 0
	_gs.setup_world(12345, 8)
	_gs.initialize_player(0, "Tester", 50, 50)
	var p: Dictionary = _gs.players[0]
	# A hall + granary so the seat is a real establishment (and not flagged spectator).
	var b: Dictionary = BuildingState.create("village_hall", 0, 50, 50, 1)
	b["built"] = true; p["buildings"].append(b)
	return p

func _saw_food_notice() -> bool:
	for m in _notices:
		if "stores run low" in m:
			return true
	return false

func _tick_one_day(at_day: int) -> void:
	var tk: int = at_day * TPD
	_sc.current_tick = tk
	_gs.simulate_tick(tk)

func _run_all() -> void:
	print("\n[Low-food warning fires + re-arms]")
	var p := _setup()
	# Low but surviving a day's consumption (pop 20 → ~10/day; 25 → ~15 left, under the
	# 3-day threshold of 30) → the warning should fire.
	p["population"] = 20
	p["food"] = {"apples": 25}
	_notices.clear()
	_tick_one_day(1)
	ok("warns when stores run low (food ~15 < 3 days)", _saw_food_notice())
	ok("the warning latched (food_low_warned set)", bool(_gs.world.get("food_low_warned", false)))

	# Fires only ONCE while still low (no spam).
	p["food"] = {"apples": 20}
	_notices.clear()
	_tick_one_day(2)
	ok("does NOT re-warn while still low (no spam)", not _saw_food_notice())

	# Recovers well above the buffer → re-arm (flag clears).
	p["food"] = {"apples": 400}
	_tick_one_day(3)
	ok("re-arms once food recovers (flag cleared)", not bool(_gs.world.get("food_low_warned", false)))

	# Drops again → warns again.
	p["food"] = {"apples": 25}
	_notices.clear()
	_tick_one_day(4)
	ok("warns again after a recovery + new shortage", _saw_food_notice())
