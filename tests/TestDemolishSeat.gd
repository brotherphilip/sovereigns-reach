extends SceneTree
# Guards the SEAT-demolish protection (iter281). The HUD hides the Demolish button for the village
# hall / keep ("the seat can't be razed by hand; losing it is a defeat") — but the Delete-key path
# (PlayerInputHandler._try_demolish_selected) enqueued a raw demolish command with NO type guard, so
# selecting your own hall and pressing Delete razed the seat: no refund, and it emits
# building_demolished (not building_destroyed), so the loss screen never fires → a seat-less, broken
# realm. The guard now lives in the authoritative command (_cmd_demolish_building), where every path
# converges. This locks it: the seat is un-demolishable from any path; normal buildings still demolish.
# Run: godot --headless --script tests/TestDemolishSeat.gd

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		print("FATAL: GameState autoload not found"); quit(1); return
	_run(gs)
	print("\n=== Demolish Seat Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _has(gs, bid: int) -> bool:
	for b in gs.players[0].get("buildings", []):
		if b is Dictionary and int(b.get("id", -1)) == bid:
			return true
	return false

func _demolish(gs, bid: int) -> bool:
	return gs._cmd_demolish_building({"player_id": 0, "payload": {"building_id": bid}})

func _run(gs) -> void:
	gs.players.clear()
	gs.ai_factions.clear()
	gs._grid = null
	gs.setup_world(4242, 8)
	gs.initialize_player(0, "Tester", 50, 50)
	# Replace the starting buildings with a known set: a seat + a normal building.
	gs.players[0]["buildings"] = [
		{"id": 901, "type": "village_hall", "grid_x": 50, "grid_y": 50, "built": true},
		{"id": 902, "type": "hovel",        "grid_x": 52, "grid_y": 50, "built": true},
		{"id": 903, "type": "keep",         "grid_x": 54, "grid_y": 50, "built": true},
	]

	print("\n[the seat (village hall / keep) can't be demolished by hand]")
	ok("demolishing the village_hall is REJECTED", not _demolish(gs, 901))
	ok("the village_hall is still standing", _has(gs, 901))
	ok("demolishing the keep is REJECTED", not _demolish(gs, 903))
	ok("the keep is still standing", _has(gs, 903))

	print("\n[a normal building still demolishes]")
	ok("demolishing the hovel SUCCEEDS", _demolish(gs, 902))
	ok("the hovel is removed", not _has(gs, 902))

	print("\n[demolishing a nonexistent building fails cleanly]")
	ok("demolishing an unknown id returns false", not _demolish(gs, 99999))
	ok("the seat survived the whole sequence", _has(gs, 901) and _has(gs, 903))
