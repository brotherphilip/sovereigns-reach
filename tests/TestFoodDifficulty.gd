extends SceneTree
# Locks: difficulty scales LIVE food consumption (iter297). The DifficultySystem food_consumption
# modifier (PEACEFUL 0.7 / NORMAL 1.0 / HARD 1.25 / SIEGE_LORD 1.5) was honoured only by the DEAD
# FoodSystem.tick, never by the live ResourceTick.tick_food_consumption path — so difficulty silently
# did not change hunger in the real game. ResourceTick now applies it. This verifies the live path's
# per-day demand scales with difficulty, and that NORMAL is the unchanged 1.0 baseline.
# Run: godot --headless --script tests/TestFoodDifficulty.gd

const ResourceTick = preload("res://simulation/economy/ResourceTick.gd")
const Difficulty   = preload("res://simulation/core/DifficultySystem.gd")
const TPD: int = 240

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		print("FATAL: no GameState"); quit(1); return
	_run(gs)
	print("\n=== Food-Difficulty Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

# Food the live path would consume in one day at the given difficulty (plenty in store, so the
# result is the demand, not a shortage cap).
func _consumed_at(gs, level: int) -> int:
	gs.players.clear()
	gs._grid = null
	gs.setup_world(99, 8)
	gs.initialize_player(0, "Eater", 50, 50)
	var p: Dictionary = gs.players[0]
	p["population"] = 40
	p["food_ration"] = 2
	p["food"] = {"apples": 1000000}
	Difficulty.current = level   # set AFTER setup so nothing resets it
	var changes: Dictionary = ResourceTick.tick_food_consumption(p, TPD)
	var total: int = 0
	for k in changes:
		total += -int(changes[k])
	return total

func _run(gs) -> void:
	var orig: int = Difficulty.current
	var peaceful: int = _consumed_at(gs, Difficulty.Level.PEACEFUL)
	var normal: int   = _consumed_at(gs, Difficulty.Level.NORMAL)
	var hard: int     = _consumed_at(gs, Difficulty.Level.HARD)
	var siege: int    = _consumed_at(gs, Difficulty.Level.SIEGE_LORD)
	Difficulty.current = orig
	print("  consumed/day: peaceful=%d normal=%d hard=%d siege=%d" % [peaceful, normal, hard, siege])
	ok("NORMAL eats a positive baseline", normal > 0)
	ok("PEACEFUL eats LESS than NORMAL (difficulty mod 0.7 applied)", peaceful < normal)
	ok("HARD eats MORE than NORMAL (mod 1.25 applied)", hard > normal)
	ok("SIEGE_LORD eats the most (mod 1.5 applied)", siege > hard)
