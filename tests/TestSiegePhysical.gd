extends SceneTree
# Locks the PHYSICAL siege (iter295): while the player is present at the live seat, a building only
# loses HP when an enemy unit is physically beside it striking — there is NO abstract "siege strike".
# Besieging units that reach the seat batter the nearest structure (SIEGE_HIT_DAMAGE per strike on the
# combat cadence); kill them and the battering stops. This is the user-requested model: "the strike
# should only land if a unit actually strikes the building."
#
# Drives the LIVE GameState autoload with the player PRESENT (no catch_up — that fast-forward keeps
# the abstract strike, covered by TestSiege). Citizens/wildlife are cleared so the per-tick sim is
# cheap; the besieger units are placed adjacent to the hall so they batter immediately.
# Run: godot --headless --script tests/TestSiegePhysical.gd

const BuildingState = preload("res://simulation/buildings/BuildingState.gd")
const AIFaction     = preload("res://simulation/ai/AIFaction.gd")
const UnitState     = preload("res://simulation/units/UnitState.gd")

const TPD: int = 240

var _gs: Node = null
var _sc: Node = null
var _eb: Node = null
var _hall_destroyed_cause: String = ""

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_sc = root.get_node_or_null("SimulationClock")
	_eb = root.get_node_or_null("EventBus")
	if _gs == null or _sc == null or _eb == null:
		print("FATAL: autoloads not found"); quit(1); return
	_eb.building_destroyed.connect(_on_destroyed)
	_run_all()
	print("\n=== Siege-Physical Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _on_destroyed(_pid, _bid, cause) -> void:
	if String(cause) == "siege":
		_hall_destroyed_cause = "siege"

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _add(p: Dictionary, t: String, x: int, y: int, id: int) -> void:
	var b: Dictionary = BuildingState.create(t, 0, x, y, id)
	if not b.is_empty():
		b["built"] = true
		p["buildings"].append(b)

# Fresh live world; player 0 at (50,50) with a village_hall; one bandit faction past grace.
# `attackers` units (if any) are placed ringing the hall so they batter it at once.
func _setup(attackers: int) -> Dictionary:
	_gs.players.clear()
	_gs.ai_factions.clear()
	_gs._grid = null
	_gs._next_building_id = 1
	_gs._next_unit_id = 1
	_sc.current_tick = 0
	_hall_destroyed_cause = ""
	_gs.setup_world(7777, 8)
	_gs.initialize_player(0, "Defender", 50, 50)
	_gs.citizens.clear()
	_gs.wildlife.clear()
	_gs._catch_up_mode = false   # player PRESENT → physical besiegers, no abstract strike
	var p: Dictionary = _gs.players[0]
	_add(p, "village_hall", 50, 50, 1)
	_gs.add_ai_faction(AIFaction.ARCHETYPE_BANDIT, 70, 70)
	var fac: Dictionary = _gs.ai_factions[0]
	# Keep the faction WITHIN the King's Peace so it never launches a NATURAL siege (which would
	# spawn its own warband and confound the control case). The battering we test is driven purely by
	# the units we place — the physical assault doesn't require an assembled siege, only a unit at the wall.
	fac["days_alive"] = 0
	var ring := [Vector2i(49, 49), Vector2i(50, 49), Vector2i(51, 49), Vector2i(49, 51),
		Vector2i(50, 51), Vector2i(51, 51), Vector2i(49, 50), Vector2i(51, 50)]
	var units: Array = []
	for i in range(mini(attackers, ring.size())):
		units.append(UnitState.create("armed_peasant", int(fac.get("id", -1)), ring[i].x, ring[i].y, 5000 + i))
	fac["units"] = units
	return p

func _hall_hp() -> int:
	for b in _gs.players[0].get("buildings", []):
		if b is Dictionary and String(b.get("type", "")) == "village_hall":
			return int(b.get("hp", -1))
	return -1

func _tick_days(days: int) -> void:
	var start: int = _sc.current_tick
	for tk in range(start + 1, start + days * TPD + 1):
		_sc.current_tick = tk
		_gs.simulate_tick(tk)

func _run_all() -> void:
	# Case A — besiegers at the wall physically batter the hall down.
	print("\n[Besiegers at the wall batter the hall — HP falls per strike, then it's razed]")
	var p := _setup(6)
	var hp0 := _hall_hp()
	_tick_days(2)
	var hp2 := _hall_hp()
	ok("the hall loses HP while enemies strike it (no abstract strike)", hp2 < hp0)
	ok("the HP loss is physical/visible, not an instant chunk", hp2 > 0 and (hp0 - hp2) < hp0)
	_tick_days(12)
	ok("a sustained, undefended assault razes the seat (cause=siege)", _hall_destroyed_cause == "siege" and _hall_hp() <= 0)

	# Case B — control: no besiegers present → the hall takes NO damage at all.
	print("\n[No besiegers present — the hall is never touched]")
	var p2 := _setup(0)
	var hp0b := _hall_hp()
	_tick_days(14)
	ok("an unbesieged hall keeps full HP (no phantom siege damage)", _hall_hp() == hp0b)
	ok("no siege destruction fired without attackers", _hall_destroyed_cause == "")
