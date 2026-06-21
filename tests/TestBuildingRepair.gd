extends SceneTree
# Locks general building SELF-REPAIR (iter308). A non-seat building scraped by fire or a raid used to
# stay permanently damaged — a persistent HP bar with no fix but demolish+rebuild (part of the "empty
# bar above buildings" the player flagged). The village now slowly patches up non-seat structures
# (BUILDING_REPAIR_PER_DAY/day). The SEAT is EXCLUDED (it keeps its defence-gated repair, so an
# undefended seat still falls), and burning buildings don't repair. This verifies all three.
# Run: godot --headless --script tests/TestBuildingRepair.gd

const BuildingState = preload("res://simulation/buildings/BuildingState.gd")
const TPD := 240

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	var clock = root.get_node_or_null("SimulationClock")
	if gs == null or clock == null:
		print("FATAL: autoloads missing"); quit(1); return
	_run(gs, clock)
	print("\n=== Building-Repair Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _mk(t: String, x: int, id: int, dmg: int, burning: bool = false) -> Dictionary:
	var b: Dictionary = BuildingState.create(t, 0, x, 100, id)
	b["built"] = true
	b["hp"] = maxi(1, int(b.get("max_hp", 1)) - dmg)
	b["is_on_fire"] = burning
	return b

func _find(p: Dictionary, id: int) -> Dictionary:
	for b in p.get("buildings", []):
		if b is Dictionary and int(b.get("id", -1)) == id:
			return b
	return {}

func _run(gs, clock) -> void:
	gs.players.clear(); gs.ai_factions.clear(); gs.citizens.clear()
	gs._grid = null
	clock.current_tick = 0
	gs.setup_world(321, 8)
	gs.initialize_player(0, "Mason", 100, 100)
	gs.citizens.clear(); gs.wildlife.clear()
	gs.weather = {"current": 0, "ticks_remaining": 9999999, "effects": {"fire_risk": 0.0}}  # clear (no fire)
	var p: Dictionary = gs.players[0]
	p["population"] = 5
	# Damaged non-seat building; an undamaged-by-this-path SEAT (not siege-ready); a burning building.
	p["buildings"] = [
		_mk("granary", 100, 1, 20),            # should heal
		_mk("village_hall", 103, 2, 40),       # seat — must NOT heal here (not siege-ready)
		_mk("granary", 106, 3, 20, true),      # burning — must NOT heal
	]
	var granary_hp0: int = int(_find(p, 1).get("hp", 0))
	var hall_hp0: int = int(_find(p, 2).get("hp", 0))
	var burn_hp0: int = int(_find(p, 3).get("hp", 0))

	# Tick across exactly one day boundary (repair is once/day).
	for t in range(1, TPD + 1):
		clock.current_tick = t
		gs.simulate_tick(t)

	ok("a damaged non-seat building self-repairs (hp rose)", int(_find(p, 1).get("hp", 0)) > granary_hp0)
	ok("it heals by ~BUILDING_REPAIR_PER_DAY (%d)" % gs.BUILDING_REPAIR_PER_DAY,
		int(_find(p, 1).get("hp", 0)) == granary_hp0 + gs.BUILDING_REPAIR_PER_DAY)
	ok("the SEAT does NOT self-repair via this path when undefended", int(_find(p, 2).get("hp", 0)) == hall_hp0)
	ok("a BURNING building does not repair (hp did not rise)", int(_find(p, 3).get("hp", 0)) <= burn_hp0)
