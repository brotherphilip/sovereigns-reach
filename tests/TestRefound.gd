extends SceneTree
# Guards the depopulation REFOUNDING safety net (iter293). A seat that loses ALL its villagers
# (population 0) was a permanent LIMBO: births need a fertile pair so 0 can't recover, and there's
# no loss condition for it (food isn't consumed at pop 0 and popularity doesn't read population, so
# the empty seat just persists, silent). GameState now spawns a few wandering settlers to refound a
# depopulated seat on a day boundary, throttled by a cooldown. This locks: refounds when empty,
# respects the cooldown, and does NOT fire while the seat has people.
# Run: godot --headless --script tests/TestRefound.gd

const TPD: int = 240

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	var clock = root.get_node_or_null("SimulationClock")
	if gs == null or clock == null:
		print("FATAL: no GameState/SimulationClock"); quit(1); return
	_run(gs, clock)
	print("\n=== Refound Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

# Run one game-day of ticks ending exactly on a day boundary.
func _run_a_day(gs, clock) -> void:
	# Advance to just before the next day boundary, then step across it.
	var start: int = clock.current_tick
	var next_boundary: int = ((start / TPD) + 1) * TPD
	while clock.current_tick < next_boundary:
		clock.current_tick += 1
		gs.simulate_tick(clock.current_tick)

func _run(gs, clock) -> void:
	gs.players.clear(); gs.ai_factions.clear(); gs.citizens.clear()
	gs._grid = null
	gs.setup_world(123, 8)
	gs.initialize_player(0, "Refound", 100, 100)
	gs.spectator_mode = false
	var p: Dictionary = gs.players[0]
	p["food"] = {"apples": 500}

	print("\n[a fully-depopulated seat refounds via wandering settlers]")
	gs.citizens.clear(); p["population"] = 0
	gs.world["seat_refound_until"] = 0
	clock.current_tick = 0
	_run_a_day(gs, clock)
	ok("depopulated seat refounds (population > 0)", int(p.get("population", 0)) > 0)
	ok("refounds exactly REFOUND_SETTLERS (%d)" % gs.REFOUND_SETTLERS, gs.citizens.size() == gs.REFOUND_SETTLERS)
	var cd: int = int(gs.world.get("seat_refound_until", 0))
	ok("a refound cooldown is set", cd > clock.current_tick)

	print("\n[the cooldown prevents immediate re-refounding]")
	gs.citizens.clear(); p["population"] = 0   # depopulate again, still within the cooldown
	_run_a_day(gs, clock)
	ok("does NOT refound again within the cooldown", gs.citizens.size() == 0 and int(p.get("population", 0)) == 0)

	print("\n[once the cooldown elapses, a depopulated seat refounds again]")
	clock.current_tick = cd   # jump to the cooldown's end (a day boundary)
	gs.citizens.clear(); p["population"] = 0
	_run_a_day(gs, clock)
	ok("refounds again past the cooldown (persistent safety net)", gs.citizens.size() == gs.REFOUND_SETTLERS)

	print("\n[a seat WITH people never spuriously refounds]")
	gs.world["seat_refound_until"] = 0   # clear the cooldown so only the living==0 gate matters
	# citizens currently > 0 from the refound above; run a day and confirm no refound was triggered.
	_run_a_day(gs, clock)
	ok("no refound fired while the seat has people (cooldown untouched)",
		int(gs.world.get("seat_refound_until", 0)) == 0)
