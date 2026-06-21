extends SceneTree
# Save/load round-trip coverage for the NEWER world state added since the iter151 round-trip fix —
# diplomacy tribute demands (iter275-277), the choice-event pending list (iter269), faction
# grievance/embargo, and the shared clock tick that tribute DEADLINES are measured against. These
# ride in world/ai_factions (whole-dict serialized), but JSON coerces every number to a float and
# every dict key to a String on load, so a demand's deadline_tick / amount / player_id must still
# be USABLE as ints afterward (else owed_tribute mis-fires and a deferred demand is lost or wrongly
# expired). A full serialize → SaveManager (JSON file) → load → deserialize cycle must preserve them.
# Run: godot --headless --script tests/TestSaveLoadDiplomacy.gd

const SM = preload("res://simulation/persistence/SaveManager.gd")
const WorldMapData = preload("res://simulation/world/WorldMapData.gd")
const DiplomacySystem = preload("res://simulation/ai/DiplomacySystem.gd")
const SAVE_PATH := "user://test_saveload_diplo.save"
const TPD: int = 240

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	var clock = root.get_node_or_null("SimulationClock")
	if gs == null or clock == null:
		print("FATAL: GameState/SimulationClock autoload not found"); quit(1); return
	_run(gs, clock)
	print("\n=== SaveLoad Diplomacy Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _run(gs, clock) -> void:
	print("\n[Round-trip preserves tribute demands / pending events / clock]")
	gs.world = {}
	gs.players = []
	gs.ai_factions = []
	gs.world["world_map"] = WorldMapData.generate(12345)
	gs.ensure_strategic_initialized()
	gs.initialize_player(0, "Tester", 50, 50)

	# Stamp a known clock tick — tribute deadlines are relative to it.
	clock.current_tick = 12000
	var now: int = 12000
	var deadline: int = now + TPD * 7   # a live, unanswered 7-day demand

	# A rival mid-grievance with: a DEFERRED (unfulfilled) tribute demand, an embargo, and a
	# second already-fulfilled demand that must NOT resurface after load.
	var fac := {
		"id": 4242, "name": "Ashen Barony", "is_alive": true, "archetype": "ashen_barony",
		"threat_level": 61.0, "grievance": 22.5,
		"embargoed_players": [0],
		"tribute_demands": [
			{"player_id": 0, "resource": "gold", "amount": 90, "deadline_tick": deadline, "fulfilled": false},
			{"player_id": 0, "resource": "iron", "amount": 15, "deadline_tick": deadline, "fulfilled": false},
			{"player_id": 0, "resource": "stone", "amount": 30, "deadline_tick": deadline, "fulfilled": true},
		],
	}
	gs.ai_factions.append(fac)
	gs.world["pending_choice_events"] = ["barons_loan"]

	# --- Round-trip through the real JSON save file ---
	var saved: bool = SM.save(gs.serialize(), SAVE_PATH)
	ok("save() succeeds", saved and SM.save_exists(SAVE_PATH))
	gs.world = {}
	gs.players = []
	gs.ai_factions = []
	clock.current_tick = 0   # wipe so we prove the load restores it
	var loaded: Dictionary = SM.load_save(SAVE_PATH)
	ok("load_save() returns data", not loaded.is_empty())
	gs.deserialize(loaded)   # must not throw
	if loaded.has("clock"):
		clock.deserialize(loaded["clock"])

	# --- Clock tick restored (deadlines depend on it) ---
	ok("clock tick restored to %d" % now, int(clock.current_tick) == now)

	# --- Locate the faction after load ---
	var f = null
	for ff in gs.ai_factions:
		if ff is Dictionary and int(ff.get("id", -1)) == 4242:
			f = ff
			break
	ok("the rival faction survived the round-trip", f != null)
	if f == null:
		return

	# --- Diplomacy state usable after the JSON float/string coercion ---
	ok("grievance preserved", is_equal_approx(float(f.get("grievance", 0.0)), 22.5))
	ok("embargo on player 0 preserved (numeric id match across JSON float coercion)",
		DiplomacySystem.is_embargoed(f, 0))
	# Re-embargoing a player whose id reloaded as a float must NOT append a duplicate.
	var embargo_n: int = f.get("embargoed_players", []).size()
	DiplomacySystem.mark_embargoed(f, 0)
	ok("re-embargo after load is de-duplicated (no float/int twin)",
		f.get("embargoed_players", []).size() == embargo_n)
	ok("all three demand records survived", f.get("tribute_demands", []).size() == 3)

	var owed: Dictionary = DiplomacySystem.owed_tribute(f, 0, now)
	var dm: Dictionary = owed.get("demands", {})
	ok("owed_tribute still surfaces the deferred demand after load", not dm.is_empty())
	ok("owed gold amount intact (90)", int(dm.get("gold", 0)) == 90)
	ok("owed iron amount intact (15)", int(dm.get("iron", 0)) == 15)
	ok("the fulfilled stone demand does NOT resurface", not dm.has("stone"))
	ok("deadline_tick survived as a usable FUTURE tick", int(owed.get("deadline_tick", 0)) == deadline)
	ok("the demand still reads as live (not falsely expired)", int(owed.get("deadline_tick", 0)) >= int(clock.current_tick))

	# --- Choice-event pending list preserved (else a fired event re-banks or is lost) ---
	ok("pending_choice_events preserved", "barons_loan" in gs.world.get("pending_choice_events", []))

	SM.delete_save(SAVE_PATH)
