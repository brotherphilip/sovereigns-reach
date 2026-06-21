extends SceneTree
# Phase 1 headless test suite.
# Run from project directory: godot --headless --script tests/TestPhase1.gd
#
# Uses get_node() for all autoload access — bare autoload names are not
# resolved at GDScript compile time when running via --script.

# Autoload refs (untyped — resolved at runtime via get_node)
var _cq   # CommandQueue
var _sc   # SimulationClock
var _gs   # GameState

# CommandType enum values (must mirror CommandQueue.CommandType order exactly)
const CT_SET_TAX_RATE    = 0
const CT_SET_RATION_FOOD = 1
const CT_SET_RATION_ALE  = 2
const CT_PLACE_BUILDING  = 7
const CT_SELECT          = 17
const CT_DESELECT        = 18
const CT_SET_GAME_SPEED  = 20
const CT_TOGGLE_VIEW     = 21
const CT_SAVE            = 23

# Speed constants (must mirror SimulationClock)
const SPD_PAUSED  = 0
const SPD_NORMAL  = 1
const SPD_FAST    = 2
const SPD_FASTEST = 3

var _pass: int = 0
var _fail: int = 0

func _init() -> void:
	print("\n╔══════════════════════════════════════════════╗")
	print("║  SOVEREIGN'S REACH — PHASE 1 TEST SUITE     ║")
	print("╚══════════════════════════════════════════════╝\n")

	await process_frame

	_cq = root.get_node_or_null("CommandQueue")
	_sc = root.get_node_or_null("SimulationClock")
	_gs = root.get_node_or_null("GameState")

	if not (_cq and _sc and _gs):
		print("FATAL: Autoloads not found — run from the project directory")
		quit(1)
		return

	_sc.pause()  # Prevent ticks firing during tests

	_test_command_queue()
	_test_game_state_init()
	_test_serialization()
	_test_command_application()
	_test_sim_clock()

	print("")
	if _fail == 0:
		print("✓ ALL %d TESTS PASSED" % _pass)
	else:
		print("✗ %d PASSED  %d FAILED" % [_pass, _fail])
	# Uniform, greppable summary line so a full-suite sweep can't silently miss this suite
	# (the pretty line above isn't matched by a "Results:" grep — that hid this suite in audits).
	print("=== Phase 1 Results: %d passed, %d failed ===" % [_pass, _fail])
	print("")
	quit(0 if _fail == 0 else 1)

# ─── CommandQueue ─────────────────────────────────────────────────────────

func _test_command_queue() -> void:
	print("── CommandQueue ─────────────────────────────")
	_cq.clear()

	_ok(_cq.dequeue_all().size() == 0, "starts empty")

	_cq.enqueue(CT_SET_TAX_RATE, {"rate": 2}, 0)
	var batch = _cq.dequeue_all()
	_ok(batch.size() == 1,                        "enqueue adds one command")
	_ok(batch[0]["type"] == CT_SET_TAX_RATE,      "command type preserved")
	_ok(batch[0]["payload"]["rate"] == 2,          "payload preserved")
	_ok(batch[0]["player_id"] == 0,               "player_id preserved")
	_ok(batch[0].has("issued_at_tick"),            "issued_at_tick stamped")
	_ok(_cq.dequeue_all().size() == 0,             "queue drained after dequeue_all")

	# Multiple enqueues
	_cq.enqueue(CT_SET_TAX_RATE, {"rate": 1}, 0)
	_cq.enqueue(CT_SET_RATION_FOOD, {"level": 3}, 1)
	_ok(_cq.peek().size() == 2,    "peek sees 2 commands without draining")
	_ok(_cq.peek().size() == 2,    "peek is non-destructive")
	_cq.dequeue_all()

	# Serialization round-trip
	_cq.enqueue(CT_SET_GAME_SPEED, {"speed": SPD_FAST}, 0)
	_cq.enqueue(CT_SET_RATION_ALE, {"level": 2}, 1)
	var saved = _cq.serialize()
	_cq.clear()
	_cq.deserialize(saved)
	_ok(_cq.dequeue_all().size() == 2, "serialize/deserialize preserves 2 commands")

# ─── GameState initialization ─────────────────────────────────────────────

func _test_game_state_init() -> void:
	print("── GameState initialization ─────────────────")
	_gs.initialize_player(0, "Lord Phillip", 100, 100)
	var p = _gs.get_player(0)

	_ok(p["name"]        == "Lord Phillip", "player name set")
	_ok(p["gold"]        == 400,            "starting gold 400")
	_ok(p["popularity"]  == 80,             "starting popularity 80 (a forgiving opening buffer)")
	_ok(p["tax_rate"]    == 0,              "starting tax rate neutral (0)")
	_ok(p["food_ration"] == 2,              "starting food ration normal (2)")
	_ok(p["ale_ration"]  == 1,              "starting ale ration low (1)")
	_ok(p["is_alive"]    == true,           "player starts alive")
	_ok(p["keep_x"]      == 100,            "keep_x set")
	_ok(p["keep_y"]      == 100,            "keep_y set")

	for r in ["wood", "stone", "iron", "pitch", "hops", "wheat", "flour", "leather"]:
		_ok(p["resources"].has(r), "resource '%s' exists" % r)

	for f in ["apples", "cheese", "meat", "bread", "ale"]:
		_ok(p["food"].has(f), "food '%s' exists" % f)

	for w in ["bows", "crossbows", "pikes", "swords", "leather_armor", "plate_armor"]:
		_ok(p["armory"].has(w), "armory '%s' exists" % w)

	# get_player returns empty dict for invalid IDs
	_ok(_gs.get_player(99).is_empty(), "invalid player_id returns empty dict")

# ─── Serialization ────────────────────────────────────────────────────────

func _test_serialization() -> void:
	print("── Serialization round-trip ─────────────────")
	_gs.initialize_player(0, "SaveTest", 50, 50)
	_gs.players[0]["gold"] = 777
	_gs.players[0]["prestige"] = 42

	var snap = _gs.serialize()

	_ok(snap.has("version"),   "snapshot has version field")
	_ok(snap.has("players"),   "snapshot has players array")
	_ok(snap.has("clock"),     "snapshot embeds clock state")
	_ok(snap.has("weather"),   "snapshot has weather")
	_ok(snap["players"][0]["gold"] == 777, "gold captured in snapshot")

	_gs.players[0]["gold"]    = 9999
	_gs.players[0]["prestige"] = 0
	_gs.deserialize(snap)

	_ok(_gs.players[0]["gold"]     == 777, "gold restored after deserialize")
	_ok(_gs.players[0]["prestige"] == 42,  "prestige restored after deserialize")

	# Clock round-trip via GameState.serialize
	_sc.current_tick = 500
	var snap2 = _gs.serialize()
	_sc.current_tick = 0
	_gs.deserialize(snap2)
	_ok(_sc.current_tick == 500, "clock tick round-trips through GameState.serialize")

# ─── Command application ──────────────────────────────────────────────────

func _test_command_application() -> void:
	print("── Command application ──────────────────────")
	_gs.initialize_player(0, "CmdTest", 50, 50)
	_cq.clear()

	# Tax rate normal
	_enqueue_apply(CT_SET_TAX_RATE, {"rate": 3}, 0)
	_ok(_gs.players[0]["tax_rate"] == 3, "tax rate set to 3")

	# Clamp above max
	_enqueue_apply(CT_SET_TAX_RATE, {"rate": 99}, 0)
	_ok(_gs.players[0]["tax_rate"] == 3, "tax rate clamped to max 3")

	# Clamp below min
	_enqueue_apply(CT_SET_TAX_RATE, {"rate": -99}, 0)
	_ok(_gs.players[0]["tax_rate"] == -3, "tax rate clamped to min -3")

	# Food ration boundary
	_enqueue_apply(CT_SET_RATION_FOOD, {"level": 0}, 0)
	_ok(_gs.players[0]["food_ration"] == 0, "food ration 0 (none) applied")

	_enqueue_apply(CT_SET_RATION_FOOD, {"level": 4}, 0)
	_ok(_gs.players[0]["food_ration"] == 4, "food ration 4 (double) applied")

	_enqueue_apply(CT_SET_RATION_FOOD, {"level": 99}, 0)
	_ok(_gs.players[0]["food_ration"] == 4, "food ration clamped to max 4")

	# Ale ration
	_enqueue_apply(CT_SET_RATION_ALE, {"level": 3}, 0)
	_ok(_gs.players[0]["ale_ration"] == 3, "ale ration set to 3")

	# Invalid player_id — must not crash
	_enqueue_apply(CT_SET_TAX_RATE, {"rate": 1}, 99)
	_ok(true, "invalid player_id does not crash")

func _enqueue_apply(cmd_type: int, payload: Dictionary, pid: int) -> void:
	_cq.enqueue(cmd_type, payload, pid)
	for cmd in _cq.dequeue_all():
		_gs.apply_command(cmd)

# ─── SimulationClock ──────────────────────────────────────────────────────

func _test_sim_clock() -> void:
	print("── SimulationClock ──────────────────────────")

	_ok(_sc.TICK_RATE     == 20.0,  "tick rate 20 Hz")
	_ok(_sc.TICK_INTERVAL == 0.05,  "tick interval 50 ms")
	_ok(_sc.TICKS_PER_GAME_DAY == 240, "240 ticks per game day")

	_sc.set_speed(SPD_PAUSED)
	_ok(_sc.is_paused(),             "set_speed PAUSED -> is_paused()")

	_sc.resume()
	_ok(not _sc.is_paused(),         "resume() clears paused state")

	_sc.set_speed(SPD_FAST)
	_ok(_sc.game_speed == SPD_FAST,    "set_speed FAST")

	_sc.set_speed(SPD_FASTEST)
	_ok(_sc.game_speed == SPD_FASTEST, "set_speed FASTEST")

	# Clamp
	_sc.set_speed(-99)
	_ok(_sc.game_speed == SPD_PAUSED,   "speed clamped to PAUSED at lower bound")

	_sc.set_speed(999)
	_ok(_sc.game_speed == SPD_FASTEST,  "speed clamped to FASTEST at upper bound")

	_sc.set_speed(SPD_NORMAL)

	# Serialize / deserialize
	_sc.current_tick = 12345
	var snap = _sc.serialize()
	_sc.current_tick = 0
	_sc.deserialize(snap)
	_ok(_sc.current_tick == 12345, "clock current_tick serializes and restores")

	# game_day helper
	_sc.current_tick = 480  # = 2 game days exactly
	_ok(_sc.game_day() == 2,                "game_day() correct at tick 480")
	_ok(_sc.ticks_into_current_day() == 0,  "ticks_into_current_day() 0 at day boundary")

	_sc.current_tick = 250  # = day 1, tick 10
	_ok(_sc.game_day() == 1,                "game_day() correct at tick 250")
	_ok(_sc.ticks_into_current_day() == 10, "ticks_into_current_day() correct at tick 250")

	_sc.set_speed(SPD_PAUSED)

# ─── Helper ───────────────────────────────────────────────────────────────

func _ok(condition: bool, label: String) -> void:
	if condition:
		print("  ✓ " + label)
		_pass += 1
	else:
		print("  ✗ FAIL: " + label)
		_fail += 1
