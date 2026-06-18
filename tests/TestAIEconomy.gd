extends SceneTree
# AI economy symmetry (iter176, user-directed). The AI must obey the SAME storage limits as
# the player: raw goods are capped at (keep cellar + built stockpiles), food at (granaries),
# production HALTS when full, and the AI builds MORE stockpiles/granaries to grow its stores —
# no resources "out of nowhere". Mirrors StorageSystem / FoodSystem.
# Run: godot --headless --script tests/TestAIEconomy.gd

const AIFaction = preload("res://simulation/ai/AIFaction.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	_run()
	print("\n=== AI Economy Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _run() -> void:
	print("\n[AI obeys the player's storage limits]")
	var f: Dictionary = AIFaction.make_faction(1, "Test", AIFaction.ARCHETYPE_IRONHAND, 50, 50)
	f["population"] = 30
	var world: Dictionary = {}

	var raw_over: bool = false
	var food_over: bool = false
	for day in range(1, 401):
		AIFaction.tick(f, world, day * 240)
		if AIFaction._raw_stored(f) > AIFaction._raw_capacity(f):
			raw_over = true
		if AIFaction._food_stored(f) > AIFaction._food_capacity(f):
			food_over = true

	var stockpiles: int = 0
	var granaries: int = 0
	for b in f.get("buildings", []):
		var bt: String = b if b is String else b.get("type", "")
		if bt == "stockpile": stockpiles += 1
		elif bt == "granary": granaries += 1

	ok("raw store NEVER exceeds capacity (production halts when full)", not raw_over)
	ok("food store NEVER exceeds capacity", not food_over)
	ok("AI built stockpiles to grow storage when full (multiplied)", stockpiles >= 2)
	ok("AI built at least one granary", granaries >= 1)
	# Capacity must actually scale with built stockpiles (base 500 + 100 each).
	ok("raw capacity scales with built stockpiles", AIFaction._raw_capacity(f) == AIFaction.RAW_BASE + stockpiles * 100)

	# Resources come only from buildings it paid for + staffed: a faction with NO workforce
	# earns nothing (no free income).
	var idle: Dictionary = AIFaction.make_faction(2, "Idle", AIFaction.ARCHETYPE_BANDIT, 60, 60)
	idle["population"] = 0
	var g0: int = idle.get("gold", 0)
	var w0: int = int(idle.get("resources", {}).get("wood", 0))
	for day in range(1, 30):
		AIFaction.tick(idle, world, day * 240)
	ok("a workforce-less faction earns no goods (no free income)",
		idle.get("gold", 0) <= g0 and int(idle.get("resources", {}).get("wood", 0)) <= w0)
