extends SceneTree
# Save/load round-trip coverage for the CITIZENS state (people / needs / lineage) — the richest
# persisted state that had NO real JSON round-trip test (citizens ride in serialize()'s
# `citizens.duplicate(true)`). JSON coerces numbers to floats and dict keys to Strings on load, so
# this proves: per-citizen needs (hp/food/warmth) survive as usable floats, family LINEAGE survives
# (parent-id links still register as kin via PeopleSystem._related's int() coercion), the alive/dead
# split is preserved, and both NeedsSystem and PeopleSystem keep ticking on the reloaded array.
# Run: godot --headless --script tests/TestSaveLoadCitizens.gd

const SM = preload("res://simulation/persistence/SaveManager.gd")
const PeopleSystem = preload("res://simulation/world/PeopleSystem.gd")
const NeedsSystem = preload("res://simulation/world/NeedsSystem.gd")
const CitizenSystem = preload("res://simulation/world/CitizenSystem.gd")
const SAVE_PATH := "user://test_saveload_citizens.save"

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		print("FATAL: GameState autoload not found"); quit(1); return
	_run(gs)
	print("\n=== SaveLoad Citizens Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _by_id(citizens: Array, id: int):
	for c in citizens:
		if c is Dictionary and int(c.get("id", -1)) == id:
			return c
	return null

func _run(gs) -> void:
	print("\n[Round-trip preserves citizen needs + lineage]")
	gs.world = {}
	gs.players = [{"id": 0, "food": {}}]
	gs.ai_factions = []
	# Build well-formed citizens via the real factory, then override the fields under test.
	# Alice (mother) and Bob (her son, DIFFERENT surname so kinship must match on the parent-id
	# link, not the family name) + a dead citizen to prove the alive/dead split survives.
	var seed_rng := RandomNumberGenerator.new(); seed_rng.seed = 7
	var alice: Dictionary = CitizenSystem.make_citizen(1, 50.0, 50.0, seed_rng, 0, {"surname": "Ashwood"})
	alice["is_alive"] = true; alice["stage"] = "adult"; alice["hp"] = 90.0; alice["food"] = 80.0; alice["warmth"] = 70.0
	var bob: Dictionary = CitizenSystem.make_citizen(2, 50.0, 50.0, seed_rng, 0, {"surname": "Riverton"})
	bob["is_alive"] = true; bob["stage"] = "adult"; bob["hp"] = 55.0; bob["food"] = 12.0; bob["warmth"] = 8.0
	bob["mother_id"] = 1   # Bob's mother is Alice — the parent-id link the kin check must preserve
	var corpse: Dictionary = CitizenSystem.make_citizen(3, 50.0, 50.0, seed_rng, 0, {"surname": "Coldwell"})
	corpse["is_alive"] = false; corpse["hp"] = 0.0; corpse["food"] = 0.0; corpse["warmth"] = 0.0
	gs.citizens = [alice, bob, corpse]
	var count_before: int = gs.citizens.size()
	var living_before: int = PeopleSystem.living_count(gs.citizens)
	var related_before: bool = PeopleSystem._related(gs.citizens[0], gs.citizens[1])
	ok("precondition: Alice & Bob register as kin before save", related_before)

	# --- Round-trip through the real JSON save file ---
	var saved: bool = SM.save(gs.serialize(), SAVE_PATH)
	ok("save() succeeds", saved and SM.save_exists(SAVE_PATH))
	gs.citizens = []
	var loaded: Dictionary = SM.load_save(SAVE_PATH)
	ok("load_save() returns data", not loaded.is_empty())
	gs.deserialize(loaded)   # must not throw

	ok("citizen count preserved (%d)" % count_before, gs.citizens.size() == count_before)
	ok("living_count preserved (%d)" % living_before, PeopleSystem.living_count(gs.citizens) == living_before)

	var alice_l = _by_id(gs.citizens, 1)
	var bob_l = _by_id(gs.citizens, 2)
	var corpse_l = _by_id(gs.citizens, 3)
	ok("Alice survived the round-trip", alice_l != null)
	ok("Bob survived the round-trip", bob_l != null)
	if alice_l == null or bob_l == null:
		return

	# Needs survive as usable floats.
	ok("Bob's hp preserved (55)", is_equal_approx(float(bob_l.get("hp", -1)), 55.0))
	ok("Bob's food preserved (12)", is_equal_approx(float(bob_l.get("food", -1)), 12.0))
	ok("Bob's warmth preserved (8)", is_equal_approx(float(bob_l.get("warmth", -1)), 8.0))
	ok("Bob's surname preserved", String(bob_l.get("surname", "")) == "Riverton")
	ok("the dead citizen stays dead", corpse_l != null and not corpse_l.get("is_alive", true))

	# LINEAGE survives the float coercion of mother_id / id (the inbreeding guard depends on this).
	ok("Alice & Bob STILL register as kin after load (parent-id link survived)",
		PeopleSystem._related(alice_l, bob_l))

	# Both systems keep ticking on the reloaded array (no crash; needs are live & mutable).
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var bob_food_pre: float = float(bob_l.get("food", 0.0))
	var dead: Array = NeedsSystem.tick_day(gs.citizens, gs.players[0], 0, rng)
	ok("NeedsSystem.tick_day runs on the reloaded array (returns an Array)", dead is Array)
	ok("reloaded needs are live & mutable (Bob's food burned down a tick)",
		float(bob_l.get("food", 999.0)) < bob_food_pre)

	SM.delete_save(SAVE_PATH)
