extends SceneTree
# Guards choice-event RESOLVE idempotency (iter269). A World Event that carries `choices` applies
# its effect on RESOLVE (deferred from the daily tick). Without a pending-event guard the resolve
# COMMAND was replayable → re-banking the reward (e.g. barons_loan = +150 gold every time). GameState
# now records fired choice events as pending and consumes each once, so a duplicate/stray resolve
# command is a harmless no-op.
# Run: godot --headless --script tests/TestEventChoice.gd

var _gs: Node = null
var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		print("FATAL: GameState autoload not found"); quit(1); return
	_run()
	print("\n=== Event Choice Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond:
		_pass += 1; print("  PASS: %s" % label)
	else:
		_fail += 1; print("  FAIL: %s" % label)

func _resolve(eid: String, idx: int) -> bool:
	return _gs._cmd_resolve_event_choice({"player_id": 0, "payload": {"event_id": eid, "choice_index": idx}})

func _run() -> void:
	print("\n[Choice-event resolve is idempotent — no reward re-banking]")
	_gs.players.clear()
	_gs.ai_factions.clear()
	_gs._grid = null
	_gs.setup_world(12345, 8)
	_gs.initialize_player(0, "Tester", 50, 50)
	var p: Dictionary = _gs.players[0]
	p["gold"] = 100
	# Mark barons_loan as pending, exactly as the daily tick does when a choice event fires.
	_gs.world["pending_choice_events"] = ["barons_loan"]

	# First resolve: the loan lands (choice 0 = "+150 gold, −6 popularity").
	ok("first resolve of a pending event succeeds", _resolve("barons_loan", 0))
	ok("the loan reward banked once (+150 gold → 250)", int(p.get("gold", 0)) == 250)
	ok("the event is consumed (no longer pending)", "barons_loan" not in _gs.world.get("pending_choice_events", []))

	# Second resolve of the SAME event (a replayed/stray command): rejected, no re-bank.
	var g: int = int(p.get("gold", 0))
	ok("a duplicate resolve is rejected (idempotent)", not _resolve("barons_loan", 0))
	ok("the reward was NOT re-banked on the duplicate", int(p.get("gold", 0)) == g)

	# Resolving an event that never fired (not pending) is also rejected — no out-of-band rewards.
	ok("resolving a never-fired event is rejected", not _resolve("saints_relic", 0))
	ok("gold unchanged by the rejected out-of-band resolve", int(p.get("gold", 0)) == g)
