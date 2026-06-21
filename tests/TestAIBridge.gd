extends SceneTree
# Proof harness for AI land management: a watched/AI town whose building is cut off by a river
# RAISES A BRIDGE to reach it (BridgePlanner), and TEARS DOWN a building it can't reach at all.
# Drives the live GameState with a hand-carved river so the cut-off is unambiguous.
# Run: godot --headless --script tests/TestAIBridge.gd

const WorldGrid     = preload("res://simulation/world/WorldGrid.gd")
const BuildingState = preload("res://simulation/buildings/BuildingState.gd")
const Pathfinder    = preload("res://simulation/pathfinding/Pathfinder.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		print("FATAL: no GameState autoload"); quit(1); return
	_test_bridges_cut_off_building(gs)
	_test_demolishes_unreachable_building(gs)
	print("\n=== AI Bridge Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _setup(gs, grid_w: int, river_x0: int, river_x1: int, bld_x: int) -> Dictionary:
	gs.setup_world(777, 8)
	gs.initialize_player(0, "Test", 10, 20)
	# Replace the generated map with a clean grass field split by a full-height river, so the
	# far building is UNAMBIGUOUSLY cut off (no land detour to confuse the reachability scan).
	var grid := WorldGrid.new(grid_w, 40)
	for y in range(40):
		for rx in range(river_x0, river_x1 + 1):
			grid.set_terrain(rx, y, WorldGrid.Terrain.RIVER)
	gs._grid = grid
	var p: Dictionary = gs.players[0]
	p["keep_x"] = 10; p["keep_y"] = 20
	p["resources"]["wood"] = 999; p["resources"]["stone"] = 999; p["gold"] = 99999
	# A building on the FAR (right) bank, registered on the grid.
	var bid: int = 5000
	var b: Dictionary = BuildingState.create("woodcutter_camp", 0, bld_x, 20, bid)
	b["built"] = true
	p["buildings"].append(b)
	for dy in range(3):
		for dx in range(2):
			grid.set_building_at(bld_x + dx, 20 + dy, bid)
	return {"gs": gs, "grid": grid, "player": p, "bid": bid}

func _test_bridges_cut_off_building(gs) -> void:
	print("\n[AI bridges a building cut off by a river]")
	var ctx := _setup(gs, 40, 20, 21, 30)   # 2-wide river — spannable
	var grid = ctx["grid"]; var p = ctx["player"]
	var spot: Vector2i = gs._free_tile_beside(30, 20, 2, 3)
	ok("the far building is cut off before the bridge",
		Pathfinder.find_path(grid, 10, 20, spot.x, spot.y, 1, true).is_empty())
	gs._ai_manage_crossings(p)
	var has_bridge := false
	for bb in p["buildings"]:
		if bb is Dictionary and String(bb.get("type", "")) == "bridge":
			has_bridge = true
	ok("the AI raised a bridge", has_bridge)
	ok("the building is now REACHABLE across the bridge",
		not Pathfinder.find_path(grid, 10, 20, spot.x, spot.y, 1, true).is_empty())

func _test_demolishes_unreachable_building(gs) -> void:
	print("\n[AI tears down a building it cannot reach at all]")
	# A river far wider than a single bridge can span (> MAX_WATER) → no crossing possible.
	var ctx := _setup(gs, 70, 20, 40, 55)
	var p = ctx["player"]
	var before: int = p["buildings"].size()
	gs._ai_manage_crossings(p)
	var has_woodcutter := false
	var has_bridge := false
	for bb in p["buildings"]:
		if bb is Dictionary and String(bb.get("type", "")) == "woodcutter_camp":
			has_woodcutter = true
		if bb is Dictionary and String(bb.get("type", "")) == "bridge":
			has_bridge = true
	ok("no bridge was built (river too wide to span)", not has_bridge)
	ok("the unreachable building was demolished", not has_woodcutter and p["buildings"].size() < before)
