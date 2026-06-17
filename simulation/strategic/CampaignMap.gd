extends RefCounted
# Strategic-layer state + graph helpers for the world map.
# Pure simulation — operates on plain Dictionaries inside world.world_map, so it
# is fully JSON/save-safe and headless-testable. No Node/Godot scene imports.
#
# "The other cities" live here: the 55-city / 5-faction world map. ensure_initialized()
# upgrades the static generator output into a living strategic state — every city
# gets an owner/garrison/development, every faction becomes a Kingdom that can grow,
# build, raise armies, wage campaigns and conduct diplomacy through the sibling
# modules (KingdomEconomy, CampaignSystem, KingdomAI).

const MAX_DEVELOPMENT: int = 10

# The player is NOT one of the great houses — they own a single small village at start
# and grow by capturing. A dedicated faction id keeps their holdings distinct from the
# AI great houses (0..N-1) and from ownerless independents.
const PLAYER_FACTION_ID: int = 99
const INDEPENDENT_FACTION_ID: int = -2  # ownerless village (mirrors WorldMapData)

# Per-faction personality weights (0..1). Keyed by faction index. Drives the AI
# brain; derived deterministically so saves/headless runs are reproducible.
const PERSONALITIES: Array = [
	{"aggression": 0.90, "expansion": 0.70, "economy": 0.40, "defense": 0.50},  # 0 Crimson Throne
	{"aggression": 0.40, "expansion": 0.60, "economy": 0.90, "defense": 0.60},  # 1 Azure Dominion
	{"aggression": 0.55, "expansion": 0.85, "economy": 0.60, "defense": 0.45},  # 2 Emerald March
	{"aggression": 0.75, "expansion": 0.50, "economy": 0.55, "defense": 0.70},  # 3 Violet Pact
	{"aggression": 0.60, "expansion": 0.60, "economy": 0.65, "defense": 0.80},  # 4 Amber Hold
]
const DEFAULT_PERSONALITY: Dictionary = {"aggression": 0.6, "expansion": 0.6, "economy": 0.6, "defense": 0.6}

# ── Initialization ─────────────────────────────────────────────────────────────

# Idempotent: turns the static world_map into a living strategic state. Safe to
# call every tick (returns immediately once initialized).
static func ensure_initialized(world: Dictionary, players: Array = []) -> bool:
	var wm: Dictionary = world.get("world_map", {})
	if wm.is_empty() or not wm.has("cities"):
		return false
	if wm.get("strategic_init", false):
		return true

	# Upgrade each city with mutable strategic fields. Ownership starts from the
	# generator's faction_id (a great house, or INDEPENDENT for the many small villages).
	var start_city_id: int = -1
	for c in wm["cities"]:
		if not c is Dictionary:
			continue
		c["owner_faction_id"] = c.get("faction_id", INDEPENDENT_FACTION_ID)
		var tier: int = c.get("tier", 0)
		c["development"] = clampi(tier, 0, MAX_DEVELOPMENT)
		# Garrison seeded from the generator's troop_count, with a floor so even
		# sleepy hamlets can be defended/contested.
		c["garrison"] = maxi(c.get("troop_count", 0), 4 + tier * 2)
		c["unrest"] = 0.0
		if c.get("is_player_start", false):
			start_city_id = c.get("id", -1)

	# The player owns exactly ONE small village to begin with — hand it to the player
	# faction (it was independent in the generator output).
	if start_city_id >= 0:
		var sc: Dictionary = city_by_id(world, start_city_id)
		if not sc.is_empty():
			sc["owner_faction_id"] = PLAYER_FACTION_ID
			sc["development"] = 0
			sc["garrison"] = maxi(sc.get("garrison", 0), 6)

	# Build a Kingdom per great house, plus a dedicated PLAYER kingdom.
	var kingdoms: Array = []
	for f in wm.get("factions", []):
		if not f is Dictionary:
			continue
		var fid: int = f.get("id", kingdoms.size())
		kingdoms.append({
			"id": fid,
			"name": f.get("name", "Faction %d" % fid),
			"color_hex": f.get("color_hex", "#888888"),
			"is_player": false,
			"is_alive": true,
			"treasury": 150,
			"resources": {"wood": 80, "stone": 40, "iron": 20, "food": 90},
			"armies": [],
			"next_army_id": fid * 100000 + 1,
			"personality": (PERSONALITIES[fid].duplicate() if fid >= 0 and fid < PERSONALITIES.size() else DEFAULT_PERSONALITY.duplicate()),
			"relations": {},
			"tribute_cooldown_until": 0,
			# bookkeeping / telemetry
			"cities_captured": 0,
			"cities_lost": 0,
		})

	# The player's own kingdom — drives armies via player commands (no AI brain).
	kingdoms.append({
		"id": PLAYER_FACTION_ID,
		"name": "Your Domain",
		"color_hex": "#d4af37",
		"is_player": true,
		"is_alive": true,
		"treasury": 150,
		"resources": {"wood": 30, "stone": 10, "iron": 0, "food": 50},
		"armies": [],
		"next_army_id": PLAYER_FACTION_ID * 100000 + 1,
		"personality": DEFAULT_PERSONALITY.duplicate(),
		"relations": {},
		"tribute_cooldown_until": 0,
		"cities_captured": 0,
		"cities_lost": 0,
	})

	# Default diplomacy: everyone neutral toward everyone else.
	for k in kingdoms:
		for other in kingdoms:
			if other["id"] != k["id"]:
				k["relations"][str(other["id"])] = "neutral"

	wm["kingdoms"] = kingdoms
	wm["player_faction_id"] = PLAYER_FACTION_ID
	wm["strategic_init"] = true
	world["world_map"] = wm
	return true

# The player is always their own dedicated faction now (owns a single starting village),
# never one of the great houses the start village happened to sit near.
static func _resolve_player_faction(_world: Dictionary, _players: Array) -> int:
	return PLAYER_FACTION_ID

# ── City accessors ─────────────────────────────────────────────────────────────

static func cities(world: Dictionary) -> Array:
	return world.get("world_map", {}).get("cities", [])

static func city_by_id(world: Dictionary, city_id: int) -> Dictionary:
	if city_id < 0:
		return {}
	var cs: Array = cities(world)
	# Generator assigns id == array index, but capture never reorders the array,
	# so the fast path is valid; guard it and fall back to a scan just in case.
	if city_id < cs.size() and cs[city_id] is Dictionary and cs[city_id].get("id", -1) == city_id:
		return cs[city_id]
	for c in cs:
		if c is Dictionary and c.get("id", -1) == city_id:
			return c
	return {}

static func owner_of(city: Dictionary) -> int:
	return city.get("owner_faction_id", city.get("faction_id", -1))

static func set_owner(world: Dictionary, city_id: int, new_fid: int) -> void:
	var c: Dictionary = city_by_id(world, city_id)
	if c.is_empty():
		return
	c["owner_faction_id"] = new_fid

static func neighbor_ids(city: Dictionary) -> Array:
	return city.get("connected_to", [])

static func faction_city_ids(world: Dictionary, faction_id: int) -> Array:
	var result: Array = []
	for c in cities(world):
		if c is Dictionary and owner_of(c) == faction_id:
			result.append(c.get("id", -1))
	return result

static func faction_city_count(world: Dictionary, faction_id: int) -> int:
	return faction_city_ids(world, faction_id).size()

# Enemy/neutral cities directly adjacent to a city this faction owns — the set of
# legal first-strike campaign targets. Returns Array of city ids (deduped).
static func frontier_targets(world: Dictionary, faction_id: int) -> Array:
	var seen: Dictionary = {}
	var result: Array = []
	for c in cities(world):
		if not (c is Dictionary and owner_of(c) == faction_id):
			continue
		for nid in neighbor_ids(c):
			var n: Dictionary = city_by_id(world, nid)
			if n.is_empty():
				continue
			if owner_of(n) == faction_id:
				continue
			if not seen.has(nid):
				seen[nid] = true
				result.append(nid)
	return result

# ── Kingdom accessors ──────────────────────────────────────────────────────────

static func kingdoms(world: Dictionary) -> Array:
	return world.get("world_map", {}).get("kingdoms", [])

static func kingdom_by_id(world: Dictionary, faction_id: int) -> Dictionary:
	for k in kingdoms(world):
		if k is Dictionary and k.get("id", -1) == faction_id:
			return k
	return {}

static func player_faction_id(world: Dictionary) -> int:
	return world.get("world_map", {}).get("player_faction_id", -1)

static func alive_kingdom_count(world: Dictionary) -> int:
	var n: int = 0
	for k in kingdoms(world):
		if k is Dictionary and k.get("is_alive", false):
			n += 1
	return n

# ── Graph search ───────────────────────────────────────────────────────────────

# Shortest hop path between two cities over the road network. Returns the list of
# city ids to traverse *after* the start, ending at to_id (empty if unreachable
# or already there). BFS — roads are unweighted hops at the strategic scale.
static func bfs_path(world: Dictionary, from_id: int, to_id: int) -> Array:
	if from_id == to_id:
		return []
	var start: Dictionary = city_by_id(world, from_id)
	if start.is_empty():
		return []
	var came_from: Dictionary = {from_id: -1}
	var queue: Array = [from_id]
	var head: int = 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		if cur == to_id:
			break
		var c: Dictionary = city_by_id(world, cur)
		for nid in neighbor_ids(c):
			if not came_from.has(nid):
				came_from[nid] = cur
				queue.append(nid)
	if not came_from.has(to_id):
		return []
	# Reconstruct.
	var rev: Array = []
	var node: int = to_id
	while node != from_id and node != -1:
		rev.append(node)
		node = came_from.get(node, -1)
	rev.reverse()
	return rev

# Defensive value of a city = garrison plus fortification from development/tier.
static func city_defense(city: Dictionary) -> int:
	var garrison: int = city.get("garrison", 0)
	var dev: int = city.get("development", city.get("tier", 0))
	var fort: int = dev * 3
	if city.get("is_capital", false):
		fort += 15
	return garrison + fort

# Soft cap on how large a garrison a city can sustain (scales with development).
static func garrison_cap(city: Dictionary) -> int:
	var dev: int = city.get("development", city.get("tier", 0))
	var base: int = 10 + dev * 6
	if city.get("is_capital", false):
		base += 20
	return base
