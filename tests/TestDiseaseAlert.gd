extends SceneTree
# Guards the plague-outbreak ALERT (iter267): when a plague first breaks out it used to give the
# player no clear signal — only a passive "Plague! X%" HUD label while it silently killed villagers
# and sank popularity. GameState now fires a one-shot realm_notice (toast) + plague_outbreak (herald
# VO) on the not-active → active transition. This drives the live GameState through real day
# boundaries with a crowded, unsanitary seat until the outbreak fires.
# Run: godot --headless --script tests/TestDiseaseAlert.gd

const BuildingState = preload("res://simulation/buildings/BuildingState.gd")

const TPD: int = 240

var _gs: Node = null
var _sc: Node = null
var _eb: Node = null
var _notices: Array = []
var _outbreaks: int = 0

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
	_eb.plague_outbreak.connect(func(_pid): _outbreaks += 1)
	_run_all()
	print("\n=== Disease Alert Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _add(p: Dictionary, t: String, x: int, y: int, id: int) -> void:
	var b: Dictionary = BuildingState.create(t, 0, x, y, id)
	if not b.is_empty():
		b["built"] = true
		p["buildings"].append(b)

func _plague_notice_seen() -> bool:
	for m in _notices:
		if "plague" in String(m).to_lower():
			return true
	return false

func _run_all() -> void:
	print("\n[Plague outbreak fires a one-shot alert]")
	_gs.players.clear()
	_gs.ai_factions.clear()
	_gs._grid = null
	_gs._next_building_id = 1
	_sc.current_tick = 0
	_gs.setup_world(12345, 8)
	_gs.initialize_player(0, "Tester", 50, 50)
	var p: Dictionary = _gs.players[0]
	# A hall + a crowded, UNSANITARY cluster of hovels (>= CROWDING_THRESHOLD, no wells/apothecary)
	# → is_crowding_risk → a plague can break out. Minimal food variety keeps health low (raises the
	# per-day outbreak chance). No citizens/wildlife — the outbreak depends on buildings, not pawns —
	# so the day-boundary run stays fast.
	var id := 1
	_add(p, "village_hall", 50, 50, id); id += 1
	for i in range(7):
		_add(p, "hovel", 46 + i, 52, id); id += 1
	p["food"] = {"apples": 9999}   # well-fed: proves the alert isn't a starvation artifact
	_gs.citizens.clear()
	_gs.wildlife.clear()
	# Deterministic outbreak: a fixed disease RNG so the (chance-gated) outbreak fires on a set day.
	var rng := RandomNumberGenerator.new(); rng.seed = 42
	_gs._disease_rng = rng

	var fired_day := -1
	for d in range(1, 161):
		_sc.current_tick = d * TPD
		_gs.simulate_tick(d * TPD)
		if fired_day < 0 and _outbreaks > 0:
			fired_day = d
	ok("a plague broke out within the run window", _outbreaks >= 1)
	ok("the outbreak emitted a player-facing 'plague' notice (toast)", _plague_notice_seen())
	ok("the alert is ONE-SHOT (fired once, not every day while active)", _outbreaks == 1)
	ok("the realm registers the plague as active (disease_active)", bool(p.get("disease_active", false)))
	print("    (plague broke out on day %d)" % fired_day)
