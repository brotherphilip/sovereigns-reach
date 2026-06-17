extends SceneTree
# Save/load round-trip regression (iter151). The reworked world-map (PackedByteArray biome)
# + JSON's int→float coercion broke save/load: deserialize threw on the RNG-reseed XOR and
# the biome came back as a base64 String. This guards the fix: a full serialize → SaveManager
# (JSON file) → load → deserialize cycle must preserve the new strategic state and a usable
# biome, with NO exceptions.
# Run: godot --headless --script tests/TestSaveLoad.gd

const CM = preload("res://simulation/strategic/CampaignMap.gd")
const SM = preload("res://simulation/persistence/SaveManager.gd")
const WorldMapData = preload("res://simulation/world/WorldMapData.gd")
const SAVE_PATH := "user://test_saveload.save"

var _pass := 0
var _fail := 0

func _init() -> void:
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		print("FATAL: GameState autoload not found"); quit(1); return
	_run(gs)
	print("\n=== SaveLoad Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _run(gs) -> void:
	print("\n[Save/load round-trip with a world_map]")
	gs.world = {}
	gs.players = []
	gs.ai_factions = []
	gs.world["world_map"] = WorldMapData.generate(12345)
	gs.ensure_strategic_initialized()
	var pfid: int = CM.player_faction_id(gs.world)
	gs.world["player_title_index"] = 3
	gs.world["tutorial_index"] = 5
	# Capture a 2nd village so ownership state is non-trivial.
	for c in CM.cities(gs.world):
		if CM.owner_of(c) == CM.INDEPENDENT_FACTION_ID:
			CM.set_owner(gs.world, c.get("id", -1), pfid)
			break
	var holdings_before: int = CM.faction_city_count(gs.world, pfid)
	var tiles_before: int = gs.world["world_map"]["biome"]["tiles"].size()

	# Round-trip through the real JSON save file.
	var saved: bool = SM.save(gs.serialize(), SAVE_PATH)
	ok("save() succeeds", saved and SM.save_exists(SAVE_PATH))
	gs.world = {}
	gs.players = []
	var loaded: Dictionary = SM.load_save(SAVE_PATH)
	ok("load_save() returns data", not loaded.is_empty())
	gs.deserialize(loaded)   # must not throw

	# Strategic state preserved.
	ok("player faction preserved", CM.player_faction_id(gs.world) == pfid)
	ok("holdings preserved (%d)" % holdings_before, CM.faction_city_count(gs.world, pfid) == holdings_before and holdings_before >= 2)
	ok("player_title_index preserved", int(gs.world.get("player_title_index", -1)) == 3)
	ok("tutorial_index preserved", int(gs.world.get("tutorial_index", -1)) == 5)

	# Biome restored as a usable PackedByteArray (not a base64 String), full size.
	var biome: Dictionary = gs.world.get("world_map", {}).get("biome", {})
	var tiles = biome.get("tiles", null)
	ok("biome tiles is a PackedByteArray", tiles is PackedByteArray)
	ok("biome tiles full size (%d)" % tiles_before, tiles is PackedByteArray and tiles.size() == tiles_before)
