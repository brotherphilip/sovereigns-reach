extends RefCounted
# Strategic world map data generator. Pure simulation — zero Node/Godot scene imports.
# Generates 55 cities, 5 faction territories, MST road network, resource deposits.

const MAP_WIDTH:   int = 1600
const MAP_HEIGHT:  int = 900
const MARGIN:      int = 80
const MIN_DIST:    int = 120
const CITY_COUNT:  int = 55
const FACTION_COUNT: int = 5

const RESOURCE_TYPES: Array = ["wood", "stone", "iron", "food"]
# Distribution weights for resource types
const RESOURCE_WEIGHTS: Array = [35, 30, 20, 15]

const FACTION_COLORS: Array = [
	"#c0392b",   # 0 — Crimson Throne
	"#2980b9",   # 1 — Azure Dominion
	"#27ae60",   # 2 — Emerald March
	"#8e44ad",   # 3 — Violet Pact
	"#d35400",   # 4 — Amber Hold
]
const FACTION_NAMES: Array = [
	"Crimson Throne", "Azure Dominion", "Emerald March",
	"Violet Pact", "Amber Hold",
]

const CITY_NAMES: Array = [
	"Ironvale", "Stonereach", "Greymoor", "Ashfield", "Hollowhaven",
	"Thornwick", "Coldwater", "Emberveil", "Ravensmere", "Coldspire",
	"Saltmarsh", "Duskholm", "Fenwallow", "Ironpeak", "Amberveil",
	"Silvercliff", "Dawnsward", "Mirefall", "Stonegate", "Ashcroft",
	"Bramblewood", "Cresthollow", "Deepwater", "Elmhurst", "Farrow",
	"Grimstone", "Hartwick", "Ivywood", "Jadecliff", "Kestrel",
	"Longmere", "Mistfall", "Nighthollow", "Oakenshield", "Pineholt",
	"Quarrystone", "Redmoor", "Sandgate", "Thistlewood", "Umbridge",
	"Valewatch", "Wolfden", "Yelford", "Zephyrcliff", "Aldgate",
	"Bridgemere", "Copperhill", "Dunmore", "Eastmarch", "Frostgate",
	"Goldvale", "Highbury", "Ironwall", "Jasperfield", "Kingsholm",
]

# ── Public API ────────────────────────────────────────────────────────────────

static func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var cities: Array   = _place_cities(rng)
	var factions: Array = _assign_factions(cities, rng)
	var roads: Array    = _build_road_network(cities, rng)
	var deposits: Array = _place_resource_deposits(rng, cities)
	_mark_player_start(cities)

	return {
		"cities":    cities,
		"factions":  factions,
		"roads":     roads,
		"deposits":  deposits,
		"seed":      seed_value,
	}

static func serialize(data: Dictionary) -> Dictionary:
	return data.duplicate(true)

static func deserialize(d: Dictionary) -> Dictionary:
	return d.duplicate(true)

# ── City placement (Poisson-disc) ─────────────────────────────────────────────

static func _place_cities(rng: RandomNumberGenerator) -> Array:
	var usable_w: int = MAP_WIDTH  - MARGIN * 2
	var usable_h: int = MAP_HEIGHT - MARGIN * 2
	var cell_size: float = float(MIN_DIST) / sqrt(2.0)
	var grid_cols: int = ceili(float(usable_w) / cell_size)
	var grid_rows: int = ceili(float(usable_h) / cell_size)
	# Sparse grid: cell → city index or -1
	var grid: Dictionary = {}

	var cities: Array = []
	# Use generous attempt budget — Poisson-disc reliably fills 55 cities in this area
	_try_place_pass(rng, cities, grid, grid_cols, grid_rows,
	                cell_size, usable_w, usable_h, MIN_DIST)

	# Assign names (cycle if overflow)
	for i in range(cities.size()):
		cities[i]["name"] = CITY_NAMES[i % CITY_NAMES.size()]
		cities[i]["id"]   = i
	return cities

static func _try_place_pass(rng, cities, grid, grid_cols, grid_rows, cell_size,
                             usable_w, usable_h, min_dist) -> bool:
	for _attempt in range(CITY_COUNT * 80):
		if cities.size() >= CITY_COUNT:
			return true
		var px: float = MARGIN + rng.randf() * usable_w
		var py: float = MARGIN + rng.randf() * usable_h
		if _is_valid_position(px, py, cities, grid, grid_cols, cell_size, min_dist):
			var city: Dictionary = {
				"id": -1, "name": "", "pos_x": px, "pos_y": py,
				"faction_id": -1, "is_capital": false, "is_player_start": false,
				"population": rng.randi_range(200, 2000),
				"troop_count": rng.randi_range(0, 80),
				"tier": rng.randi_range(0, 3),
				"connected_to": [],
			}
			var cx_cell: int = int((px - MARGIN) / cell_size)
			var cy_cell: int = int((py - MARGIN) / cell_size)
			grid[cx_cell * grid_rows + cy_cell] = cities.size()
			cities.append(city)
	return cities.size() >= CITY_COUNT

static func _is_valid_position(px: float, py: float, cities: Array, grid: Dictionary,
                                 grid_rows: int, cell_size: float, min_dist: int) -> bool:
	for other in cities:
		var dx: float = px - other["pos_x"]
		var dy: float = py - other["pos_y"]
		if dx * dx + dy * dy < min_dist * min_dist:
			return false
	return true

# ── Faction assignment ────────────────────────────────────────────────────────

static func _assign_factions(cities: Array, rng: RandomNumberGenerator) -> Array:
	var n: int = cities.size()
	if n == 0:
		return []

	# k-means++ capital selection
	var capital_indices: Array = []
	capital_indices.append(rng.randi_range(0, n - 1))
	for _f in range(FACTION_COUNT - 1):
		var best_idx: int  = 0
		var best_dist: float = -1.0
		for i in range(n):
			if i in capital_indices: continue
			var min_d: float = INF
			for ci in capital_indices:
				var dx: float = cities[i]["pos_x"] - cities[ci]["pos_x"]
				var dy: float = cities[i]["pos_y"] - cities[ci]["pos_y"]
				var d: float  = sqrt(dx*dx + dy*dy)
				if d < min_d: min_d = d
			if min_d > best_dist:
				best_dist = min_d
				best_idx  = i
		capital_indices.append(best_idx)

	# Mark capitals
	for fi in range(capital_indices.size()):
		cities[capital_indices[fi]]["is_capital"]  = true
		cities[capital_indices[fi]]["faction_id"]  = fi
		cities[capital_indices[fi]]["tier"]        = 3  # capitals are tier 3

	# Voronoi assignment for remaining cities
	for i in range(n):
		if cities[i]["is_capital"]: continue
		var best_fi: int   = 0
		var best_d: float  = INF
		for fi in range(capital_indices.size()):
			var ci: int      = capital_indices[fi]
			var dx: float    = cities[i]["pos_x"] - cities[ci]["pos_x"]
			var dy: float    = cities[i]["pos_y"] - cities[ci]["pos_y"]
			var d: float     = sqrt(dx*dx + dy*dy)
			if d < best_d:
				best_d  = d
				best_fi = fi
		cities[i]["faction_id"] = best_fi

	# Build faction records
	var factions: Array = []
	for fi in range(FACTION_COUNT):
		var city_ids: Array = []
		for c in cities:
			if c["faction_id"] == fi:
				city_ids.append(c["id"])
		factions.append({
			"id":             fi,
			"name":           FACTION_NAMES[fi],
			"color_hex":      FACTION_COLORS[fi],
			"capital_city_id": capital_indices[fi],
			"city_ids":       city_ids,
		})
	return factions

# ── Player start ──────────────────────────────────────────────────────────────

static func _mark_player_start(cities: Array) -> void:
	# Player starts at the faction capital nearest to map center
	var cx: float = MAP_WIDTH  * 0.5
	var cy: float = MAP_HEIGHT * 0.5
	var best_idx: int   = 0
	var best_d: float   = INF
	for i in range(cities.size()):
		if not cities[i]["is_capital"]: continue
		var dx: float = cities[i]["pos_x"] - cx
		var dy: float = cities[i]["pos_y"] - cy
		var d: float  = sqrt(dx*dx + dy*dy)
		if d < best_d:
			best_d   = d
			best_idx = i
	cities[best_idx]["is_player_start"] = true

# ── Road network (Prim's MST + extra edges) ───────────────────────────────────

static func _build_road_network(cities: Array, rng: RandomNumberGenerator) -> Array:
	var n: int = cities.size()
	if n < 2:
		return []

	# Prim's MST
	var in_tree: Array = []
	var roads: Array   = []
	in_tree.resize(n)
	in_tree.fill(false)
	in_tree[0] = true
	var tree_count: int = 1

	while tree_count < n:
		var best_cost: float = INF
		var best_u: int = -1
		var best_v: int = -1
		for u in range(n):
			if not in_tree[u]: continue
			for v in range(n):
				if in_tree[v]: continue
				var dx: float = cities[u]["pos_x"] - cities[v]["pos_x"]
				var dy: float = cities[u]["pos_y"] - cities[v]["pos_y"]
				var d: float  = sqrt(dx*dx + dy*dy)
				if d < best_cost:
					best_cost = d
					best_u = u; best_v = v
		if best_u < 0: break
		in_tree[best_v] = true
		tree_count += 1
		roads.append({"from_id": best_u, "to_id": best_v})
		cities[best_u]["connected_to"].append(best_v)
		cities[best_v]["connected_to"].append(best_u)

	# Add ~25 extra short edges for network redundancy
	# Build degree array
	var degree: Array = []
	degree.resize(n); degree.fill(0)
	for r in roads:
		degree[r["from_id"]] += 1
		degree[r["to_id"]]   += 1

	# Collect candidate short pairs not already in MST
	var added_pairs: Dictionary = {}
	for r in roads:
		added_pairs[_road_key(r["from_id"], r["to_id"])] = true

	var extras_added: int = 0
	for u in range(n):
		if extras_added >= 25: break
		for v in range(u + 1, n):
			if extras_added >= 25: break
			var key: String = _road_key(u, v)
			if added_pairs.has(key): continue
			if degree[u] >= 4 or degree[v] >= 4: continue
			var dx: float = cities[u]["pos_x"] - cities[v]["pos_x"]
			var dy: float = cities[u]["pos_y"] - cities[v]["pos_y"]
			var d: float  = sqrt(dx*dx + dy*dy)
			if d > 350.0: continue
			if rng.randf() < 0.40:
				roads.append({"from_id": u, "to_id": v})
				cities[u]["connected_to"].append(v)
				cities[v]["connected_to"].append(u)
				added_pairs[key] = true
				degree[u] += 1; degree[v] += 1
				extras_added += 1

	return roads

static func _road_key(a: int, b: int) -> String:
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	return "%d_%d" % [lo, hi]

# ── Resource deposits ─────────────────────────────────────────────────────────

static func _place_resource_deposits(rng: RandomNumberGenerator, cities: Array) -> Array:
	var deposits: Array = []
	var half_min: float = MIN_DIST * 0.5
	var target: int = rng.randi_range(80, 120)
	var attempts: int = 0

	while deposits.size() < target and attempts < target * 30:
		attempts += 1
		var px: float = MARGIN + rng.randf() * (MAP_WIDTH  - MARGIN * 2)
		var py: float = MARGIN + rng.randf() * (MAP_HEIGHT - MARGIN * 2)

		# Must be at least half_min from any city
		var too_close: bool = false
		for c in cities:
			var dx: float = px - c["pos_x"]
			var dy: float = py - c["pos_y"]
			if sqrt(dx*dx + dy*dy) < half_min:
				too_close = true
				break
		if too_close: continue

		# Weighted type selection
		var rtype: String = _weighted_resource(rng)
		deposits.append({"pos_x": px, "pos_y": py, "type": rtype})

	return deposits

static func _weighted_resource(rng: RandomNumberGenerator) -> String:
	var roll: int = rng.randi_range(0, 99)
	var acc: int  = 0
	for i in range(RESOURCE_WEIGHTS.size()):
		acc += RESOURCE_WEIGHTS[i]
		if roll < acc:
			return RESOURCE_TYPES[i]
	return RESOURCE_TYPES[0]
