extends SceneTree
# Phase 10 test suite — Simulation audit fixes (S1–S4 and related).
# Run: godot --headless --script tests/TestPhase10.gd
# Pattern: integer constants for CommandType to avoid compile-time autoload resolution.

const UnitState     = preload("res://simulation/units/UnitState.gd")
const UnitRegistry  = preload("res://simulation/units/UnitRegistry.gd")
const WorldGrid     = preload("res://simulation/world/WorldGrid.gd")
const AIFaction     = preload("res://simulation/ai/AIFaction.gd")
const BuildingState = preload("res://simulation/buildings/BuildingState.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

const CT_RECRUIT_UNIT       = 11
const CT_ISSUE_ATTACK_ORDER = 13

var _gs: Node = null
var _cq: Node = null
var _sc: Node = null
var _pass: int = 0
var _fail: int = 0

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_cq = root.get_node_or_null("CommandQueue")
	_sc = root.get_node_or_null("SimulationClock")
	if _gs == null or _cq == null or _sc == null:
		print("FATAL: Autoloads not found")
		quit(1)
		return
	_run_all()
	print("Phase 10 Results: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _run_all() -> void:
	_test_attack_orders()
	_test_training_queue()

func ok(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  PASS: " + label)
	else:
		_fail += 1
		print("  FAIL: " + label)

func _fresh_player(grid_size: int = 60) -> Dictionary:
	_gs.players.clear()
	_gs.ai_factions.clear()
	_gs._grid = WorldGrid.new(grid_size, grid_size)
	_gs._next_building_id = 1
	_gs._next_unit_id = 1
	_sc.current_tick = 0
	_cq.clear()
	_gs.initialize_player(0, "TestLord", 50, 50)
	return _gs.players[0]

# ─── S1: Attack orders ────────────────────────────────────────────────────────

func _test_attack_orders() -> void:
	print("\n--- S1: Attack Orders ---")

	# Adjacent strike: a swordsman next to a weak enemy kills it via attack order.
	var p: Dictionary = _fresh_player(60)
	var fid: int = _gs.add_ai_faction(AIFaction.ARCHETYPE_BANDIT, 55, 50)
	var faction: Dictionary = _gs.ai_factions[fid]
	var target: Dictionary = UnitState.create("armed_peasant", fid, 51, 50, 9001)
	faction["units"] = [target]
	var atk: Dictionary = UnitState.create("swordsman", 0, 50, 50, 1)
	p["units"] = [atk]
	p["total_kills"] = 0

	_cq.enqueue(CT_ISSUE_ATTACK_ORDER,
		{"unit_id": 1, "target_x": 51, "target_y": 50, "target_id": 9001}, 0)
	_sc._advance_tick()
	ok("attack order sets ORDER_ATTACK", p["units"][0].get("order") == UnitState.ORDER_ATTACK)

	for _i in range(120):
		_sc._advance_tick()
	ok("attack order kills adjacent target", not faction["units"][0].get("is_alive", true))
	ok("attack order increments total_kills", int(p.get("total_kills", 0)) >= 1)
	ok("attacker reverts to IDLE after kill", p["units"][0].get("order") == UnitState.ORDER_IDLE)

	# Chase: an out-of-range attacker steps toward its target.
	var p2: Dictionary = _fresh_player(60)
	var fid2: int = _gs.add_ai_faction(AIFaction.ARCHETYPE_BANDIT, 55, 50)
	var faction2: Dictionary = _gs.ai_factions[fid2]
	faction2["units"] = [UnitState.create("armed_peasant", fid2, 53, 50, 9002)]
	var chaser: Dictionary = UnitState.create("swordsman", 0, 50, 50, 1)
	chaser["order"] = UnitState.ORDER_ATTACK
	chaser["target_id"] = 9002
	chaser["target_x"] = 53
	chaser["target_y"] = 50
	p2["units"] = [chaser]
	var start_x: int = chaser["pos_x"]
	# swordsman speed 3 → one step every 80 ticks; tick 80 triggers a step.
	_gs._tick_player_unit_movement(p2, 80)
	ok("out-of-range attacker steps toward target", int(p2["units"][0]["pos_x"]) > start_x)

# ─── S2: Training queue ───────────────────────────────────────────────────────

func _give_barracks(p: Dictionary) -> void:
	p["buildings"] = [BuildingState.create("barracks", 0, 40, 40, 1)]
	p["gold"] = 500

func _test_training_queue() -> void:
	print("\n--- S2: Training Queue ---")

	# Recruited unit with train_ticks > 0 enters ORDER_TRAINING, not deployable.
	var p: Dictionary = _fresh_player(60)
	_give_barracks(p)
	_cq.enqueue(CT_RECRUIT_UNIT, {"unit_type": "armed_peasant"}, 0)
	_sc._advance_tick()
	ok("recruited unit added to army", p.get("units", []).size() == 1)
	ok("recruited unit is in training", p["units"][0].get("order") == UnitState.ORDER_TRAINING)
	ok("training unit is not deployable", not UnitState.is_deployable(p["units"][0]))

	# After train_ticks (60) the unit graduates to IDLE and becomes deployable.
	for _i in range(60):
		_sc._advance_tick()
	ok("unit graduates after train_ticks", p["units"][0].get("order") == UnitState.ORDER_IDLE)
	ok("graduated unit is deployable", UnitState.is_deployable(p["units"][0]))

	# training_rate_bonus (training_speed tech) shortens the required time.
	var p2: Dictionary = _fresh_player(60)
	_give_barracks(p2)
	p2["tech_unlocks"] = ["unit_unlocks", "training_speed"]  # grants training_rate_bonus 0.3
	_cq.enqueue(CT_RECRUIT_UNIT, {"unit_type": "armed_peasant"}, 0)
	_sc._advance_tick()
	# required = round(60 / 1.3) = 46 ticks; advance 46 more (47 total) → graduated.
	for _i in range(46):
		_sc._advance_tick()
	ok("training_rate_bonus speeds training", p2["units"][0].get("order") == UnitState.ORDER_IDLE)

	# Peasants (train_ticks 0) are available immediately (no training queue).
	var p3: Dictionary = _fresh_player(60)
	p3["buildings"] = [BuildingState.create("village_hall", 0, 40, 40, 1)]
	p3["gold"] = 500
	_cq.enqueue(CT_RECRUIT_UNIT, {"unit_type": "peasant"}, 0)
	_sc._advance_tick()
	ok("peasant deploys instantly", p3["units"].size() == 1 and UnitState.is_deployable(p3["units"][0]))
