extends SceneTree
# Locks the FIRE ALERT (iter304). Fire is the ONLY thing that drains a building's HP with no attacker
# on the field — so a burning building used to read as an "invisible attack" (player report: a watched
# town's buildings lost HP with no enemies anywhere). GameState now fires a one-shot realm_notice when
# a building first catches fire. This verifies: a flammable building under fire-risk weather ignites,
# and exactly that ignition raises a player-facing "fire" notice (and not one per tile/tick).
# Run: godot --headless --script tests/TestFireAlert.gd

const BuildingState = preload("res://simulation/buildings/BuildingState.gd")
const DROUGHT := 2

var _fire_notices := 0
var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	var clock = root.get_node_or_null("SimulationClock")
	var eb = root.get_node_or_null("EventBus")
	if gs == null or clock == null or eb == null:
		print("FATAL: autoloads missing"); quit(1); return
	eb.realm_notice.connect(_on_notice)
	_run(gs, clock)
	print("\n=== Fire-Alert Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _on_notice(text, _tone) -> void:
	var s := String(text)
	if s.findn("fire") >= 0 or s.find("🔥") >= 0:
		_fire_notices += 1

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _run(gs, clock) -> void:
	gs.players.clear(); gs.ai_factions.clear(); gs.citizens.clear()
	gs._grid = null
	gs.setup_world(123, 8)
	gs.initialize_player(0, "Tinderbox", 100, 100)
	var p: Dictionary = gs.players[0]
	# TWO flammable buildings (hovel baseline fire_risk 0.04) — both ignite on the SAME day boundary,
	# which also exercises the one-shot guard (2 ignitions → 1 alert, not per-tile).
	var b1: Dictionary = BuildingState.create("hovel", 0, 100, 100, 1); b1["built"] = true
	var b2: Dictionary = BuildingState.create("hovel", 0, 102, 100, 2); b2["built"] = true
	p["buildings"] = [b1, b2]
	# Force a persistent drought with guaranteed ignition (fire_risk 1.0 → randf() < 1.0 always).
	gs.weather = {"current": DROUGHT, "ticks_remaining": 9999999, "duration_ticks": 9999999,
		"effects": {"fire_risk": 1.0}}
	_fire_notices = 0

	# Fire ignition is checked on the day boundary — tick across one (240).
	for t in range(1, 241):
		clock.current_tick = t
		gs.simulate_tick(t)
	var on_fire := false
	for bb in p.get("buildings", []):
		if bb is Dictionary and bb.get("is_on_fire", false):
			on_fire = true
	ok("a flammable building ignited under fire-risk weather", on_fire)
	ok("ignition raised a player-facing FIRE notice", _fire_notices >= 1)
	ok("the alert is ONE-SHOT (two buildings igniting → a single notice)", _fire_notices == 1)
