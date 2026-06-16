extends SceneTree
# Phase 9 headless test suite: WorldMapData, WorldMapController, ShireMap(60).
# Run: godot --headless --script tests/TestPhase9.gd

const WorldMapData       = preload("res://simulation/world/WorldMapData.gd")
const WorldMapController = preload("res://view/worldmap/WorldMapController.gd")
const ShireMap           = preload("res://simulation/world/ShireMap.gd")

var _pass: int = 0
var _fail: int = 0

func _init() -> void:
	print("\n╔══════════════════════════════════════════════╗")
	print("║  SOVEREIGN'S REACH — PHASE 9 TEST SUITE     ║")
	print("╚══════════════════════════════════════════════╝\n")

	await process_frame

	_test_worldmapdata()
	_test_worldmapcontroller()
	_test_army_inspect()
	_test_battle_markers()
	_test_shiremap_60()

	print("")
	if _fail == 0:
		print("✓ ALL %d TESTS PASSED" % _pass)
	else:
		print("✗ %d PASSED  %d FAILED" % [_pass, _fail])
	print("")
	quit(0 if _fail == 0 else 1)

# ── WorldMapData ──────────────────────────────────────────────────────────────

func _test_worldmapdata() -> void:
	print("── WorldMapData ──")
	var data: Dictionary = WorldMapData.generate(42)

	# Basic structure
	_ok(data.has("cities"),   "data has cities key")
	_ok(data.has("factions"), "data has factions key")
	_ok(data.has("roads"),    "data has roads key")
	_ok(data.has("deposits"), "data has deposits key")

	var cities: Array   = data["cities"]
	var factions: Array = data["factions"]
	var roads: Array    = data["roads"]
	var deposits: Array = data["deposits"]

	# City count
	_ok(cities.size() == WorldMapData.CITY_COUNT,
		"city count == %d (got %d)" % [WorldMapData.CITY_COUNT, cities.size()])

	# All cities in bounds
	var in_bounds: bool = true
	for c in cities:
		if c["pos_x"] < WorldMapData.MARGIN or c["pos_x"] > WorldMapData.MAP_WIDTH  - WorldMapData.MARGIN \
		or c["pos_y"] < WorldMapData.MARGIN or c["pos_y"] > WorldMapData.MAP_HEIGHT - WorldMapData.MARGIN:
			in_bounds = false
			break
	_ok(in_bounds, "all cities within map margins")

	# Minimum spacing
	var ok_spacing: bool = true
	for i in range(cities.size()):
		for j in range(i + 1, cities.size()):
			var dx: float = cities[i]["pos_x"] - cities[j]["pos_x"]
			var dy: float = cities[i]["pos_y"] - cities[j]["pos_y"]
			if sqrt(dx*dx + dy*dy) < float(WorldMapData.MIN_DIST) - 1.0:
				ok_spacing = false
				break
		if not ok_spacing: break
	_ok(ok_spacing, "all cities at least MIN_DIST apart")

	# Faction count
	_ok(factions.size() == WorldMapData.FACTION_COUNT,
		"faction count == %d (got %d)" % [WorldMapData.FACTION_COUNT, factions.size()])

	# Exactly FACTION_COUNT capitals
	var cap_count: int = 0
	for c in cities:
		if c["is_capital"]: cap_count += 1
	_ok(cap_count == WorldMapData.FACTION_COUNT,
		"exactly %d faction capitals" % WorldMapData.FACTION_COUNT)

	# Every city has a faction_id
	var all_assigned: bool = true
	for c in cities:
		if c["faction_id"] < 0: all_assigned = false
	_ok(all_assigned, "every city has a faction_id >= 0")

	# Exactly one player start
	var start_count: int = 0
	for c in cities:
		if c["is_player_start"]: start_count += 1
	_ok(start_count == 1, "exactly one player_start city")

	# Player start is a capital
	var start_is_capital: bool = false
	for c in cities:
		if c["is_player_start"] and c["is_capital"]:
			start_is_capital = true
	_ok(start_is_capital, "player start city is a faction capital")

	# Road count >= CITY_COUNT - 1 (MST minimum)
	_ok(roads.size() >= WorldMapData.CITY_COUNT - 1,
		"road count >= MST minimum %d (got %d)" % [WorldMapData.CITY_COUNT - 1, roads.size()])

	# All road endpoints in valid range
	var roads_valid: bool = true
	for r in roads:
		if r["from_id"] < 0 or r["from_id"] >= cities.size() \
		or r["to_id"]   < 0 or r["to_id"]   >= cities.size():
			roads_valid = false
	_ok(roads_valid, "all road endpoints have valid city IDs")

	# Graph connectivity check (BFS from city 0 must reach all cities)
	var visited: Array = []
	visited.resize(cities.size())
	visited.fill(false)
	var queue: Array = [0]
	visited[0] = true
	var visited_count: int = 1
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for nbr in cities[cur]["connected_to"]:
			if not visited[nbr]:
				visited[nbr] = true
				visited_count += 1
				queue.append(nbr)
	_ok(visited_count == cities.size(), "road network is fully connected (BFS)")

	# Resource deposits
	_ok(deposits.size() >= 80, "at least 80 resource deposits (got %d)" % deposits.size())

	# All deposit types valid
	var valid_types: bool = true
	for d in deposits:
		if not d["type"] in WorldMapData.RESOURCE_TYPES:
			valid_types = false
	_ok(valid_types, "all deposit types are valid resource types")

	# Determinism: same seed produces same first city position
	var data2: Dictionary = WorldMapData.generate(42)
	var cities2: Array    = data2["cities"]
	_ok(cities.size() == cities2.size() and
		abs(cities[0]["pos_x"] - cities2[0]["pos_x"]) < 0.01 and
		abs(cities[0]["pos_y"] - cities2[0]["pos_y"]) < 0.01,
		"same seed produces same result (determinism)")

	# Different seed produces different cities
	var data3: Dictionary = WorldMapData.generate(999)
	var cities3: Array    = data3["cities"]
	var different: bool   = abs(cities[0]["pos_x"] - cities3[0]["pos_x"]) > 1.0
	_ok(different, "different seeds produce different layouts")

	# Serialize/deserialize round-trip
	var ser:   Dictionary = WorldMapData.serialize(data)
	var deser: Dictionary = WorldMapData.deserialize(ser)
	_ok(deser["cities"].size() == cities.size(), "serialize/deserialize round-trip preserves city count")

	# ── Biome continent ───────────────────────────────────────────────────────
	var biome: Dictionary = data.get("biome", {})
	_ok(not biome.is_empty(), "data has a biome field")
	_ok(biome.get("tiles", PackedByteArray()).size() == WorldMapData.BIOME_COLS * WorldMapData.BIOME_ROWS,
		"biome tiles cover the whole grid")
	_ok(biome.get("territory", PackedByteArray()).size() == WorldMapData.BIOME_COLS * WorldMapData.BIOME_ROWS,
		"territory grid covers the whole grid")
	# Every city sits on non-sea, non-mountain land.
	var on_land: bool = true
	for c in cities:
		var b: int = WorldMapData.biome_at(biome, c["pos_x"], c["pos_y"])
		if b == WorldMapData.B_SEA or b == WorldMapData.B_MOUNTAIN:
			on_land = false
	_ok(on_land, "no city sits on sea or mountain")
	# Some sea exists (it's a continent, not a full grid of land).
	var sea_cells: int = 0
	for t in biome["tiles"]:
		if t == WorldMapData.B_SEA:
			sea_cells += 1
	_ok(sea_cells > 100, "the map has an ocean around the continent (got %d sea cells)" % sea_cells)

# ── WorldMapController ────────────────────────────────────────────────────────

func _test_worldmapcontroller() -> void:
	print("── WorldMapController ──")
	var data: Dictionary = WorldMapData.generate(42)

	var render_list: Array = WorldMapController.get_city_render_list(data)
	_ok(render_list.size() == WorldMapData.CITY_COUNT,
		"get_city_render_list returns %d items" % WorldMapData.CITY_COUNT)

	# Check render item fields
	if render_list.size() > 0:
		var item: Dictionary = render_list[0]
		_ok(item.has("pos"),         "render item has pos field")
		_ok(item.has("name"),        "render item has name field")
		_ok(item.has("faction_color"), "render item has faction_color field")
		_ok(item.has("tier"),        "render item has tier field")
		_ok(item.has("is_player_start"), "render item has is_player_start field")

	var road_list: Array = WorldMapController.get_road_render_list(data)
	_ok(road_list.size() >= WorldMapData.CITY_COUNT - 1,
		"get_road_render_list returns enough roads")
	if road_list.size() > 0:
		var r: Dictionary = road_list[0]
		_ok(r.has("from_pos") and r.has("to_pos"), "road item has from_pos and to_pos")

	var faction_list: Array = WorldMapController.get_faction_territory_list(data)
	_ok(faction_list.size() == WorldMapData.FACTION_COUNT,
		"get_faction_territory_list returns %d items" % WorldMapData.FACTION_COUNT)
	if faction_list.size() > 0:
		var f: Dictionary = faction_list[0]
		_ok(f.has("center_pos") and f.has("color_hex") and f.has("radius"),
			"faction territory item has center_pos, color_hex, radius")

	var deposit_list: Array = WorldMapController.get_resource_deposit_list(data)
	_ok(deposit_list.size() >= 80, "get_resource_deposit_list returns >= 80 items")
	if deposit_list.size() > 0:
		var d: Dictionary = deposit_list[0]
		_ok(d.has("pos") and d.has("type"), "deposit item has pos and type")

	# find_city_near: player start should be findable near its own position
	var player_city: Dictionary = WorldMapController.get_player_start_city(data)
	_ok(not player_city.is_empty(), "get_player_start_city returns non-empty dict")
	var ps: Vector2 = Vector2(player_city["pos_x"], player_city["pos_y"])
	var found_id: int = WorldMapController.find_city_near(data, ps, 10.0)
	_ok(found_id == player_city["id"],
		"find_city_near finds player start at its own position")

	# find_city_near: far-away point returns -1
	var far_id: int = WorldMapController.find_city_near(data, Vector2(-999, -999), 5.0)
	_ok(far_id == -1, "find_city_near returns -1 for out-of-range point")

	# Army size bands: 0:1-10, 1:11-30, 2:31-60, 3:61-100, 4:100+ (boundary values).
	_ok(WorldMapController.size_band(1) == 0 and WorldMapController.size_band(10) == 0, "1-10 → band 0")
	_ok(WorldMapController.size_band(11) == 1 and WorldMapController.size_band(30) == 1, "11-30 → band 1")
	_ok(WorldMapController.size_band(31) == 2 and WorldMapController.size_band(60) == 2, "31-60 → band 2")
	_ok(WorldMapController.size_band(61) == 3 and WorldMapController.size_band(100) == 3, "61-100 → band 3")
	_ok(WorldMapController.size_band(101) == 4 and WorldMapController.size_band(500) == 4, "100+ → band 4")

# ── Army inspection (click a marching host on the map) ───────────────────────
# get_army_render_list must surface who/how-many/where-bound/ETA, and find_army_near
# must pick the host at its true (distance-scaled) mid-road position.
func _test_army_inspect() -> void:
	print("── Army inspect (click-to-read marching host) ──")
	var CampaignSystem = preload("res://simulation/strategic/CampaignSystem.gd")
	# Two same-owner cities 540px apart (→ 3-day leg); render list takes the MAP dict.
	var map_data: Dictionary = {
		"cities": [
			{"id": 0, "pos_x": 0.0, "pos_y": 0.0, "name": "Hold", "owner_faction_id": 1, "faction_id": 1, "connected_to": [1], "garrison": 5, "development": 3},
			{"id": 1, "pos_x": 540.0, "pos_y": 0.0, "name": "Bastion", "owner_faction_id": 1, "faction_id": 1, "connected_to": [0], "garrison": 0, "development": 3},
		],
		"kingdoms": [{"id": 1, "name": "Test Realm", "armies": [], "treasury": 1000, "resources": {}}],
		"factions": [{"id": 1, "color_hex": "#cc4444"}],
		"player_faction_id": 1,
	}
	var world: Dictionary = {"world_map": map_data}
	var kingdom: Dictionary = map_data["kingdoms"][0]
	var aid: int = CampaignSystem.raise_army(world, kingdom, 0, 12)
	_ok(CampaignSystem.launch_campaign(world, kingdom, aid, 1), "army launched on a campaign")

	# At launch (march_frac 0) the host sits on its origin city; the render entry is rich.
	var armies: Array = WorldMapController.get_army_render_list(map_data)
	_ok(armies.size() == 1, "render list has the one marching host")
	var a0: Dictionary = armies[0]
	_ok(int(a0.get("size", 0)) == 12, "host reports its troop count (12)")
	_ok(String(a0.get("owner_name", "")) == "Test Realm", "host reports its owner kingdom name")
	_ok(String(a0.get("dest_name", "")) == "Bastion", "host reports its destination city")
	_ok(int(a0.get("eta_days", 0)) == 3, "host reports the distance-scaled ETA (3 days)")
	_ok(bool(a0.get("moving", false)), "host is flagged as moving")
	_ok(bool(a0.get("is_player", false)), "host owned by the player faction is flagged is_player (drives the on-map ETA tag)")

	# find_army_near picks it at its position; an off-road point finds nothing.
	var hit: Dictionary = WorldMapController.find_army_near(map_data, a0.get("pos", Vector2.ZERO), 16.0)
	_ok(not hit.is_empty() and int(hit.get("army_id", -1)) == aid, "find_army_near picks the host at its marker")
	var miss: Dictionary = WorldMapController.find_army_near(map_data, Vector2(-999, -999), 16.0)
	_ok(miss.is_empty(), "find_army_near returns {} for an empty patch of map")

	# After a day's march the marker has crept toward the destination (true progress).
	CampaignSystem.tick_armies(world, kingdom, [], 240)
	var moved: Array = WorldMapController.get_army_render_list(map_data, 0.4)
	_ok(moved.size() == 1 and moved[0].get("pos", Vector2.ZERO).x > 1.0,
		"after a day the marker has crept along the road (distance-scaled)")
	_ok(int(moved[0].get("eta_days", 0)) == 2, "ETA counted down to 2 days after one day's march")

# ── Battle markers (recently-contested cities fade on the map) ───────────────────
func _test_battle_markers() -> void:
	print("── Battle markers (fading contested-city flags) ──")
	var map_data: Dictionary = {
		"cities": [
			{"id": 0, "pos_x": 100.0, "pos_y": 100.0, "name": "Aldermoor"},
			{"id": 1, "pos_x": 300.0, "pos_y": 200.0, "name": "Greywater"},
			{"id": 2, "pos_x": 500.0, "pos_y": 50.0, "name": "Oldstone"},
		],
		"recent_battles": [
			{"city_id": 0, "day": 10, "captured": true},   # just now (fresh)
			{"city_id": 1, "day": 7,  "captured": false},  # 3 days old (fading)
			{"city_id": 2, "day": 2,  "captured": true},   # 8 days old (stale → dropped)
		],
	}
	var markers: Array = WorldMapController.get_battle_render_list(map_data, 10, 6)
	_ok(markers.size() == 2, "stale battles (older than fade window) are dropped (got %d)" % markers.size())
	# Fresh battle (age 0) → fade_frac ~0; the 3-day-old one → ~0.5.
	var by_pos := {}
	for m in markers:
		by_pos[m["pos"]] = m
	var fresh: Dictionary = by_pos.get(Vector2(100.0, 100.0), {})
	var older: Dictionary = by_pos.get(Vector2(300.0, 200.0), {})
	_ok(not fresh.is_empty() and fresh.get("fade_frac", 1.0) < 0.01, "fresh battle has ~0 fade")
	_ok(not fresh.is_empty() and fresh.get("captured", false) == true, "captured flag carried through")
	_ok(not older.is_empty() and absf(older.get("fade_frac", 0.0) - 0.5) < 0.01, "3-day-old battle is half-faded")
	# A future-dated entry (clock rewound) is ignored, and an empty list is safe.
	var none: Array = WorldMapController.get_battle_render_list({"cities": [], "recent_battles": []}, 10, 6)
	_ok(none.is_empty(), "no recent_battles → no markers")

# ── ShireMap 60 ───────────────────────────────────────────────────────────────

func _test_shiremap_60() -> void:
	print("── ShireMap (60 shires) ──")
	var sm := ShireMap.new()
	sm.generate_default(200, 200, 60)
	_ok(sm.shires.size() == 60, "ShireMap generates 60 shires (got %d)" % sm.shires.size())

	# All shires have unique IDs
	var ids: Dictionary = {}
	var unique: bool = true
	for s in sm.shires:
		if ids.has(s["id"]): unique = false
		ids[s["id"]] = true
	_ok(unique, "all 60 shire IDs are unique")

	# All shires have names
	var named: bool = true
	for s in sm.shires:
		if s["name"] == "": named = false
	_ok(named, "all 60 shires have non-empty names")

	# Capital positions within grid
	var in_bounds: bool = true
	for s in sm.shires:
		if s["capital_x"] < 0 or s["capital_x"] >= 200 \
		or s["capital_y"] < 0 or s["capital_y"] >= 200:
			in_bounds = false
	_ok(in_bounds, "all 60 shire capitals are within map bounds")

	# MAX_SHIRES is 60
	_ok(ShireMap.MAX_SHIRES == 60, "ShireMap.MAX_SHIRES == 60")

# ── Helper ────────────────────────────────────────────────────────────────────

func _ok(condition: bool, label: String) -> void:
	if condition:
		print("  ✓ " + label)
		_pass += 1
	else:
		print("  ✗ FAIL: " + label)
		_fail += 1
