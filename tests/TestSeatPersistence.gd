extends SceneTree
# Guards the seat-persistence fix: leaving the city for the world map (or spectating a
# rival town, which overwrites players[0]) used to wipe your hand-built seat because every
# CityViewScene entry re-ran setup_world + initialize_player. stash/restore_seat_snapshot
# must preserve your buildings, resources, units and grid placements across that clobber.
# Run: godot --headless --script tests/TestSeatPersistence.gd

const BuildingState = preload("res://simulation/buildings/BuildingState.gd")

var _gs: Node = null
var _pass := 0
var _fail := 0

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		print("FATAL: no GameState"); quit(1); return

	# Build a seat: a world, a player, a hall, distinctive resources.
	_gs.world = {"player_seat_city_id": 5, "selected_city_id": 5}
	_gs.spectator_mode = false
	_gs.setup_world(4242, 8)
	_gs.initialize_player(0, "Test", 100, 100)
	var p: Dictionary = _gs.players[0]
	p["resources"]["wood"] = 777
	p["gold"] = 555
	var hall: Dictionary = BuildingState.create("village_hall", 0, 100, 100, 1)
	hall["built"] = true
	p["buildings"] = [hall]
	_gs._register_buildings_in_grid(p["buildings"])
	var built_bid: int = _gs._grid.get_building_at(100, 100)
	ok("hall is registered on the grid before leaving", built_bid == 1)

	print("\n[stash on leave]")
	_gs.stash_seat_snapshot()
	ok("a snapshot exists for the seat city (5)", _gs.has_seat_snapshot_for(5))
	ok("no snapshot claimed for a different city", not _gs.has_seat_snapshot_for(9))

	print("\n[clobber: simulate a spectator visit / fresh entry]")
	_gs.setup_world(4242, 8)          # regenerates the grid (wipes building cells)
	_gs.initialize_player(0, "Test", 20, 20)   # resets players[0] to lean start
	ok("clobber wiped the resources", int(_gs.players[0]["resources"].get("wood", 0)) != 777)
	ok("clobber wiped the buildings", _gs.players[0].get("buildings", []).is_empty())
	ok("clobber wiped the grid placement", _gs._grid.get_building_at(100, 100) == 0)

	print("\n[restore on return]")
	ok("restore succeeds", _gs.restore_seat_snapshot())
	var rp: Dictionary = _gs.players[0]
	ok("resources restored (wood 777)", int(rp["resources"].get("wood", 0)) == 777)
	ok("gold restored (555)", int(rp.get("gold", 0)) == 555)
	ok("buildings restored (the hall)", rp.get("buildings", []).size() == 1 and rp["buildings"][0].get("type", "") == "village_hall")
	ok("grid placement re-registered", _gs._grid.get_building_at(100, 100) == 1)
	ok("not in spectator mode after restore", not _gs.spectator_mode)

	print("\n=== Seat Persistence Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
