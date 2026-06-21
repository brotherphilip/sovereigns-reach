extends SceneTree
# Locks the SHIRE-LOSS alert (iter306). When a besieger overruns one of the player's shires (the
# siege_assembled "success" block), the shire silently flipped owner — only the macro map flashed it,
# which is invisible from the city view where you'd be during a siege. GameState now fires a
# player-facing realm_notice on the loss. This verifies: with the player holding a shire and a
# besieger at the walls, an assembled siege captures the shire AND raises a "shire" notice.
# Run: godot --headless --script tests/TestShireLossAlert.gd

const AIFaction = preload("res://simulation/ai/AIFaction.gd")
const UnitState = preload("res://simulation/units/UnitState.gd")
const TPD: int = 240

var _shire_notices := 0
var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	var clock = root.get_node_or_null("SimulationClock")
	var eb = root.get_node_or_null("EventBus")
	if gs == null or clock == null or eb == null:
		print("FATAL: autoloads missing"); quit(1); return
	eb.realm_notice.connect(_on_notice)
	_run(gs, clock)
	print("\n=== Shire-Loss-Alert Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _on_notice(text, _tone) -> void:
	if String(text).findn("shire") >= 0:
		_shire_notices += 1

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _run(gs, clock) -> void:
	gs.players.clear(); gs.ai_factions.clear(); gs.citizens.clear()
	gs._grid = null
	clock.current_tick = 0
	gs.setup_world(2468, 8)
	gs.initialize_player(0, "Holder", 50, 50)
	gs.citizens.clear(); gs.wildlife.clear()
	gs._catch_up_mode = false
	var p: Dictionary = gs.players[0]
	# Give the player a shire to lose, and register it in the world.
	p["shire_ids"] = [777]
	p["shire_id"] = 777
	gs.world["shires"] = [{"id": 777, "owner_id": 0, "owner_is_player": true}]
	# A besieger faction primed to assemble next day, with units AT the walls (so the success block runs).
	gs.add_ai_faction(AIFaction.ARCHETYPE_BANDIT, 70, 70)
	var fac: Dictionary = gs.ai_factions[0]
	fac["days_alive"] = AIFaction.PLAYER_GRACE_DAYS + 10
	fac["siege_assembly"] = {"target_player_id": 0, "target_x": 50, "target_y": 50,
		"ticks_elapsed": AIFaction.SIEGE_ASSEMBLY_TICKS - TPD}
	fac["units"] = [
		UnitState.create("armed_peasant", int(fac.get("id", -1)), 50, 50, 8001),
		UnitState.create("armed_peasant", int(fac.get("id", -1)), 51, 50, 8002),
	]
	_shire_notices = 0

	# Tick one day boundary → siege assembles → shire captured + alert.
	var next_boundary: int = TPD
	for t in range(1, next_boundary + 1):
		clock.current_tick = t
		gs.simulate_tick(t)

	# (owner_id can't be used as the proof — the first faction's id is 0, colliding with player 0;
	# owner_is_player flipping to false is the real capture signal.)
	ok("the besieger captured the player's shire", gs.world["shires"][0].get("owner_is_player", true) == false)
	ok("the player's shire_ids shrank (lost the holding)", p.get("shire_ids", [777]).size() == 0)
	ok("a player-facing SHIRE-LOSS notice fired", _shire_notices >= 1)
