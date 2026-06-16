extends SceneTree
# Headless 100-day survival regression — the loop's core goal made into a test.
# Drives the LIVE GameState autoload (via root.get_node_or_null, like TestPhase6) through
# a full 24000-tick session and asserts the simulation stays sane the whole way: no crash,
# state stays within valid bounds, and a realm with a basic food economy doesn't revolt
# during the fragile establishment window. (Player loss = popularity < 10 / keep destroyed,
# evaluated in the view layer; GameState.is_alive is AI-only. ~7s headless.)
# Run: godot --headless --script tests/TestSurvival.gd

const BuildingState = preload("res://simulation/buildings/BuildingState.gd")

const DAYS: int = 100
const TICKS_PER_DAY: int = 240
const REVOLT_FLOOR: float = 10.0          # popularity below this = revolt (game over)
const ESTABLISH_WINDOW: int = 20          # must not revolt during the opening establishment

var _pass: int = 0
var _fail: int = 0

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	var sc = root.get_node_or_null("SimulationClock")
	if gs == null or sc == null:
		print("FATAL: autoloads not found"); quit(1); return
	_run(gs, sc)
	print("\n=== Survival Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _add(p: Dictionary, t: String, x: int, y: int, id: int) -> void:
	var b: Dictionary = BuildingState.create(t, 0, x, y, id)
	if b.is_empty():
		return
	b["built"] = true
	p["buildings"].append(b)

func _run(gs, sc) -> void:
	print("\n[Headless 100-day survival sim]")
	gs.setup_world(12345, 8)
	gs.initialize_player(0, "Survivor", 50, 50)
	var p: Dictionary = gs.players[0]
	# A basic food economy so the realm can feed its people (orchards + a granary).
	_add(p, "apple_orchard", 52, 50, 1)
	_add(p, "apple_orchard", 54, 50, 2)
	_add(p, "apple_orchard", 48, 50, 3)
	_add(p, "granary", 46, 50, 4)
	ok("game initialised (world + player + food buildings)", gs.players.size() > 0 and p["buildings"].size() == 4)

	var min_pop: int = 1 << 30
	var min_prity: float = INF
	var max_prity: float = -INF
	var min_food: int = 1 << 30
	var revolt_day: int = -1
	var t0: int = Time.get_ticks_msec()

	for day in range(1, DAYS + 1):
		for s in range(TICKS_PER_DAY):
			var tk: int = (day - 1) * TICKS_PER_DAY + s + 1
			sc.current_tick = tk
			gs.simulate_tick(tk)
		var pp: Dictionary = gs.players[0]
		min_pop = mini(min_pop, int(pp.get("population", 0)))
		var prity: float = float(pp.get("popularity", 50.0))
		min_prity = minf(min_prity, prity)
		max_prity = maxf(max_prity, prity)
		var food: Dictionary = pp.get("food", {})
		for ft in ["apples", "bread", "cheese", "meat"]:
			min_food = mini(min_food, int(food.get(ft, 0)))
		if revolt_day < 0 and prity < REVOLT_FLOOR:
			revolt_day = day

	var elapsed: int = Time.get_ticks_msec() - t0
	print("  ran %d days (%d ticks) in %d ms; min_pop=%d popularity[min=%.0f max=%.0f] min_food=%d first_revolt_day=%d"
		% [DAYS, DAYS * TICKS_PER_DAY, elapsed, min_pop, min_prity, max_prity, min_food, revolt_day])

	# Invariants — the sim stays sane across a full session (regression net for the tick loop).
	ok("100-day sim runs to completion (no crash/hang)", true)
	ok("population never goes negative (realm persists)", min_pop >= 0)
	ok("popularity stays within valid [0,100] bounds", min_prity >= 0.0 and max_prity <= 100.0)
	ok("food stores never go negative", min_food >= 0)
	# The 20-minute goal's opening: a fed realm must not revolt during establishment.
	ok("a fed realm holds off revolt through the establishment window (day %d)" % ESTABLISH_WINDOW,
		revolt_day < 0 or revolt_day > ESTABLISH_WINDOW)
