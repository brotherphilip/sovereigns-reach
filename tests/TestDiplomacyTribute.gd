extends SceneTree
# Guards the tribute affordability invariant (iter275). Accepting an AI faction's tribute
# demand must require paying it IN FULL: previously accept() deducted only maxi(0, have-amt),
# so a player short on (or entirely without) the goods could "Accept", pay nothing or a
# fraction, and STILL buy a 14-day peace window + grievance relief — a free-peace exploit
# that also silently drained partial stock. accept() now returns false and changes nothing
# when the coffers fall short; the DiplomacyPanel disables Accept and the command no-ops.
# Run: godot --headless --script tests/TestDiplomacyTribute.gd

const DiplomacySystem = preload("res://simulation/ai/DiplomacySystem.gd")
const AIFaction = preload("res://simulation/ai/AIFaction.gd")
const TPD: int = 240

var _gs: Node = null
var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_run()
	print("\n=== Diplomacy Tribute Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond:
		_pass += 1; print("  PASS: %s" % label)
	else:
		_fail += 1; print("  FAIL: %s" % label)

func _mk_faction(id: int, grievance: float) -> Dictionary:
	return {
		"id": id, "grievance": grievance, "embargoed_players": [],
		"tribute_demands": [{"player_id": 0, "fulfilled": false}],
	}

func _run() -> void:
	print("\n[can_afford: full stock required across gold / food / resources]")
	ok("affordable when gold exactly meets demand",
		DiplomacySystem.can_afford({"gold": 50, "food": {}, "resources": {}}, {"gold": 50}))
	ok("NOT affordable when one gold short",
		not DiplomacySystem.can_afford({"gold": 49, "food": {}, "resources": {}}, {"gold": 50}))
	ok("food demand checked against food stock",
		DiplomacySystem.can_afford({"gold": 0, "food": {"ale": 8}, "resources": {}}, {"ale": 8}))
	ok("resource demand checked against resource stock",
		not DiplomacySystem.can_afford({"gold": 0, "food": {}, "resources": {"wood": 3}}, {"wood": 4}))
	ok("untracked resource counts as zero (unaffordable)",
		not DiplomacySystem.can_afford({"gold": 0, "food": {}, "resources": {}}, {"iron": 1}))
	ok("empty demand is trivially affordable",
		DiplomacySystem.can_afford({"gold": 0, "food": {}, "resources": {}}, {}))
	ok("mixed demand fails if ANY component is short",
		not DiplomacySystem.can_afford({"gold": 100, "food": {"ale": 1}, "resources": {}}, {"gold": 40, "ale": 5}))

	print("\n[accept (affordable): full payment, peace bought, grievance soothed]")
	var p := {"id": 0, "gold": 100, "food": {"ale": 5}, "resources": {"wood": 10}}
	var fac := _mk_faction(9, 30.0)
	var paid: bool = DiplomacySystem.accept(p, {"gold": 40, "wood": 5}, fac, 1000)
	ok("affordable accept returns true", paid)
	ok("gold paid in full (100 - 40)", int(p["gold"]) == 60)
	ok("wood paid in full (10 - 5)", int(p["resources"]["wood"]) == 5)
	ok("demand marked fulfilled", fac["tribute_demands"][0]["fulfilled"] == true)
	ok("peace window bought", int(fac.get("tribute_peace_until", 0)) == 1000 + AIFaction.TRIBUTE_PEACE_DAYS * TPD)
	ok("grievance soothed", is_equal_approx(fac["grievance"], maxf(0.0, 30.0 - AIFaction.GRIEVANCE_ON_ACCEPT)))

	print("\n[accept (unaffordable): NO partial drain, NO peace, NO relief]")
	var p2 := {"id": 0, "gold": 100, "food": {"ale": 1}, "resources": {"wood": 10}}
	var fac2 := _mk_faction(9, 30.0)
	var paid2: bool = DiplomacySystem.accept(p2, {"gold": 40, "ale": 5}, fac2, 1000)  # ale short: have 1, need 5
	ok("unaffordable accept returns false", not paid2)
	ok("gold NOT partially drained (still 100)", int(p2["gold"]) == 100)
	ok("ale NOT partially drained (still 1)", int(p2["food"]["ale"]) == 1)
	ok("demand NOT marked fulfilled", fac2["tribute_demands"][0]["fulfilled"] == false)
	ok("NO peace window bought", not fac2.has("tribute_peace_until"))
	ok("grievance NOT soothed (still 30)", is_equal_approx(fac2["grievance"], 30.0))

	print("\n[accept with zero stock: cannot buy peace for free]")
	var broke := {"id": 0, "gold": 0, "food": {}, "resources": {}}
	var fac3 := _mk_faction(9, 12.0)
	ok("penniless accept of a gold demand returns false",
		not DiplomacySystem.accept(broke, {"gold": 10}, fac3, 1000))
	ok("no free peace for the penniless", not fac3.has("tribute_peace_until"))

	# Command-path guard (the authoritative pipeline the UI drives).
	if _gs == null:
		print("  (skip command-path: GameState autoload absent)")
		return
	print("\n[command path: unaffordable accept no-ops, demand still stands]")
	_gs.players.clear(); _gs.ai_factions.clear(); _gs._grid = null
	_gs.setup_world(777, 8)
	_gs.initialize_player(0, "Tester", 50, 50)
	var pp: Dictionary = _gs.players[0]
	pp["gold"] = 5
	var f := _mk_faction(42, 20.0)
	_gs.ai_factions.append(f)
	var consumed: bool = _gs._cmd_diplomacy_response(
		{"player_id": 0, "payload": {"faction_id": 42, "accept": true, "demands": {"gold": 500}}})
	ok("command is consumed (returns true)", consumed)
	ok("unaffordable command paid nothing (gold still 5)", int(pp["gold"]) == 5)
	ok("demand still active (not fulfilled)", f["tribute_demands"][0]["fulfilled"] == false)
	ok("no peace bought via the command", not f.has("tribute_peace_until"))

	# And the same command WITH funds pays through cleanly. Advance the shared clock so the
	# peace window (which is only bought when tick > 0) actually engages.
	var clock := root.get_node_or_null("SimulationClock")
	if clock != null:
		clock.current_tick = 5000
	pp["gold"] = 800
	var consumed2: bool = _gs._cmd_diplomacy_response(
		{"player_id": 0, "payload": {"faction_id": 42, "accept": true, "demands": {"gold": 500}}})
	ok("affordable command consumed", consumed2)
	ok("affordable command paid in full (800 - 500)", int(pp["gold"]) == 300)
	ok("demand now fulfilled", f["tribute_demands"][0]["fulfilled"] == true)
	ok("peace bought via the affordable command", f.has("tribute_peace_until"))
