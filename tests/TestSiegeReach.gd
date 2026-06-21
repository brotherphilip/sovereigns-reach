extends SceneTree
# Locks the SIEGE-REACH gate (iter294): a siege "strike" only damages the seat when the besieging
# warband actually reached it — a living attacker within SIEGE_REACH_TILES of the keep. If the
# defenders broke the warband (or it never closed the distance), the assault is LIFTED: no shire
# lost, no seat damage. This is the root-cause fix for the reported bug where a town's buildings
# get an empty HP bar and fall "unusable" with NO troops anywhere in sight — the strike used to
# fire on a bare assembly timer, fully decoupled from the physical warband.
#
# Drives the LIVE GameState autoload. The siege chain is day-boundary gated, so we prime a faction's
# siege_assembly to assemble on the next boundary and tick exactly one day — fast and deterministic,
# no 200-day run needed. The reach gate is only enforced when the player is PRESENT at the live seat
# (NOT catch_up_mode — that fast-forward keeps the abstract strike, see GameState), so this test runs
# with the player present and places attackers manually to test one precise reach condition each.
# Run: godot --headless --script tests/TestSiegeReach.gd

const BuildingState = preload("res://simulation/buildings/BuildingState.gd")
const AIFaction     = preload("res://simulation/ai/AIFaction.gd")
const UnitState     = preload("res://simulation/units/UnitState.gd")

const TPD: int = 240

var _gs: Node = null
var _sc: Node = null
var _eb: Node = null
var _struck: int = 0
var _lifted: int = 0

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_sc = root.get_node_or_null("SimulationClock")
	_eb = root.get_node_or_null("EventBus")
	if _gs == null or _sc == null or _eb == null:
		print("FATAL: autoloads not found"); quit(1); return
	_eb.ai_siege_struck.connect(_on_struck)
	_eb.realm_notice.connect(_on_notice)
	_run_all()
	print("\n=== Siege-Reach Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _on_struck(_f, _t, _d, _dmg) -> void:
	_struck += 1

func _on_notice(text, _tone) -> void:
	if String(text).findn("siege is lifted") >= 0:
		_lifted += 1

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _add(p: Dictionary, t: String, x: int, y: int, id: int) -> void:
	var b: Dictionary = BuildingState.create(t, 0, x, y, id)
	if not b.is_empty():
		b["built"] = true
		p["buildings"].append(b)

# Fresh world; player 0 at (50,50) with a village_hall; one bandit faction primed to assemble its
# siege on the NEXT day boundary. Returns the faction dict so each case can set its attackers.
func _setup() -> Dictionary:
	_gs.players.clear()
	_gs.ai_factions.clear()
	_gs._grid = null
	_gs._next_building_id = 1
	_gs._next_unit_id = 1
	_sc.current_tick = 0
	_struck = 0
	_lifted = 0
	_gs.setup_world(2468, 8)
	_gs.initialize_player(0, "Defender", 50, 50)
	_gs.citizens.clear()
	_gs.wildlife.clear()
	_gs._catch_up_mode = false   # player PRESENT at the seat → the reach gate is enforced
	var p: Dictionary = _gs.players[0]
	_add(p, "village_hall", 50, 50, 1)
	_gs.add_ai_faction(AIFaction.ARCHETYPE_BANDIT, 70, 70)
	var fac: Dictionary = _gs.ai_factions[0]
	fac["days_alive"] = AIFaction.PLAYER_GRACE_DAYS + 10
	# Prime the siege so the very next day boundary tips it over SIEGE_ASSEMBLY_TICKS → assembled.
	fac["siege_assembly"] = {
		"target_player_id": 0, "target_x": 50, "target_y": 50,
		"ticks_elapsed": AIFaction.SIEGE_ASSEMBLY_TICKS - TPD,
	}
	return fac

func _hall_hp() -> int:
	for b in _gs.players[0].get("buildings", []):
		if b is Dictionary and String(b.get("type", "")) == "village_hall":
			return int(b.get("hp", -1))
	return -1

func _tick_one_day(day: int) -> void:
	var tk: int = day * TPD
	_sc.current_tick = tk
	_gs.simulate_tick(tk)

func _run_all() -> void:
	# Case A — the warband is AT the walls: the strike lands and the hall takes damage.
	print("\n[Warband reached the seat — the strike lands]")
	var fac := _setup()
	var hp0 := _hall_hp()
	fac["units"] = [
		UnitState.create("armed_peasant", int(fac.get("id", -1)), 50, 50, 9001),
		UnitState.create("armed_peasant", int(fac.get("id", -1)), 51, 50, 9002),
	]
	_tick_one_day(1)
	ok("a present warband makes the strike land", _struck > 0)
	ok("the seat takes damage when troops are at the walls", _hall_hp() < hp0)
	ok("no false 'siege lifted' while troops are present", _lifted == 0)

	# Case B — the warband was broken (no attacker in reach): the siege is lifted, no damage.
	print("\n[Warband broken before the walls — the siege is lifted, seat unharmed]")
	var fac2 := _setup()
	var hp0b := _hall_hp()
	fac2["units"] = []   # the defenders slaughtered them — none in reach of the keep
	_tick_one_day(1)
	ok("no strike lands when no besieger is in reach", _struck == 0)
	ok("the seat takes NO damage with no troops in sight", _hall_hp() == hp0b)
	ok("the player is told the siege was lifted", _lifted > 0)

	# Case C — a living attacker exists but is far from the seat (never closed): still lifted.
	print("\n[Attacker alive but far from the seat — still no invisible damage]")
	var fac3 := _setup()
	var hp0c := _hall_hp()
	fac3["units"] = [UnitState.create("armed_peasant", int(fac3.get("id", -1)), 150, 150, 9003)]
	_tick_one_day(1)
	ok("a distant attacker does not damage the seat", _hall_hp() == hp0c)
	ok("a distant attacker counts as not-arrived (siege lifted)", _lifted > 0)
