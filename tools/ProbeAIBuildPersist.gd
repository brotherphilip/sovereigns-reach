extends SceneTree
# Validates the AI-town build PERSISTENCE fix (iter312). Previously a spectated town regenerated from
# its development number on every entry with everything built — so construction "popped in" on click
# and reset across visits. Now each city remembers `spec_seen_dev` (how far the player watched it
# build): development NOT yet watched complete arrives UNDER CONSTRUCTION, and completed development
# persists. This probe drives the real enter/leave flow and checks:
#   (1) on entry, the latest development is under construction (not all built),
#   (2) after watching it complete + leaving, re-entry shows it BUILT (no reset),
#   (3) development that accrued while away is shown being built on return.
# Run: godot --headless --script tools/ProbeAIBuildPersist.gd

const CM = preload("res://simulation/strategic/CampaignMap.gd")
const WorldMapData = preload("res://simulation/world/WorldMapData.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		print("FATAL: no GameState"); quit(1); return
	_run(gs)
	print("\n=== AI-Build-Persist Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _unbuilt(gs) -> int:
	var n := 0
	for b in gs.players[0].get("buildings", []):
		if b is Dictionary and not b.get("built", true):
			n += 1
	return n

func _run(gs) -> void:
	gs.players.clear(); gs.ai_factions.clear(); gs.citizens.clear()
	gs.world = {}; gs._grid = null
	gs.setup_world(2468, 8)
	gs.world["world_map"] = WorldMapData.generate(2468)   # cities live here
	gs.initialize_player(0, "Watcher", 100, 100)
	gs.ensure_strategic_initialized()

	# Pick a city and give it a few development levels to build.
	var cid := -1
	for c in CM.cities(gs.world):
		cid = int(c.get("id", -1)); break
	if cid < 0:
		ok("a city exists to spectate", false); return
	var city: Dictionary = CM.city_by_id(gs.world, cid)
	city["development"] = 4
	city.erase("spec_seen_dev")   # fresh: never watched
	var dev := 4

	# ── Entry 1: first visit → latest level should be UNDER CONSTRUCTION ──
	gs.stash_seat_snapshot()
	gs.enter_spectator_city(cid, 100, 100, 2468)
	var total: int = gs.players[0].get("buildings", []).size()
	var unbuilt1 := _unbuilt(gs)
	print("  [entry 1] dev=%d  buildings=%d  under_construction=%d" % [dev, total, unbuilt1])
	ok("on first entry the latest development is UNDER CONSTRUCTION (not all popped-in)", unbuilt1 > 0)
	ok("the town is still mostly built (only the newest level is rising)", unbuilt1 < total)

	# Simulate the town finishing construction, then leave.
	for b in gs.players[0].get("buildings", []):
		if b is Dictionary:
			b["built"] = true
	gs.restore_seat_snapshot()
	ok("leaving a fully-built town persists spec_seen_dev = dev", int(city.get("spec_seen_dev", -1)) == dev)

	# ── Entry 2: re-visit (nothing new developed) → all BUILT, no construction reset ──
	gs.stash_seat_snapshot()
	gs.enter_spectator_city(cid, 100, 100, 2468)
	var unbuilt2 := _unbuilt(gs)
	print("  [entry 2] under_construction=%d" % unbuilt2)
	ok("re-entering a town you watched complete shows it BUILT (no construction reset)", unbuilt2 == 0)
	gs.restore_seat_snapshot()

	# ── Entry 3: development grew while away → the new level is shown being built ──
	city["development"] = dev + 2
	gs.stash_seat_snapshot()
	gs.enter_spectator_city(cid, 100, 100, 2468)
	var unbuilt3 := _unbuilt(gs)
	print("  [entry 3] dev=%d  under_construction=%d" % [dev + 2, unbuilt3])
	ok("development that accrued while away is shown BEING BUILT on return", unbuilt3 > 0)
