extends RefCounted
# Strategic world map data generator. Pure simulation — zero Node/Godot scene imports.
# Generates a procedural biome continent (sea/coast/plains/forest/hills/mountains +
# rivers), then 55 cities placed on habitable land, 5 faction territories that follow
# the terrain, an MST road network, and terrain-tied resource deposits.

const MAP_WIDTH:   int = 1600
const MAP_HEIGHT:  int = 900
const MARGIN:      int = 80
const MIN_DIST:    int = 120
const CITY_COUNT:  int = 80
const FACTION_COUNT: int = 4          # number of AI "great houses" (was 5 equal kingdoms)
const GREAT_HOUSE_CLUSTER: int = 6    # villages each great house claims around its capital
const INDEPENDENT_FACTION_ID: int = -2  # ownerless small village — capturable by player or houses

# Biome grid resolution (each cell ≈ 20×20 px).
const BIOME_COLS: int = 80
const BIOME_ROWS: int = 45

# Biome cell types.
const B_SEA:      int = 0
const B_COAST:    int = 1
const B_PLAINS:   int = 2
const B_FOREST:   int = 3
const B_HILLS:    int = 4
const B_MOUNTAIN: int = 5
const B_RIVER:    int = 6

# Cities may sit on these (habitable land); sea/mountain/river are rejected first.
const HABITABLE: Array = [B_PLAINS, B_COAST, B_FOREST, B_HILLS]

const RESOURCE_TYPES: Array = ["wood", "stone", "iron", "food"]

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

	var biome: Dictionary = _gen_biome(seed_value)
	var cities: Array      = _place_cities(rng, biome)
	var factions: Array    = _assign_factions(cities, rng)
	var roads: Array       = _build_road_network(cities, rng)
	var territory: PackedByteArray = _build_territory(cities, biome)
	var deposits: Array    = _place_resource_deposits(rng, cities, biome)
	_mark_player_start(cities)

	biome["territory"] = territory
	return {
		"cities":    cities,
		"factions":  factions,
		"roads":     roads,
		"deposits":  deposits,
		"biome":     biome,
		"seed":      seed_value,
	}

static func serialize(data: Dictionary) -> Dictionary:
	return data.duplicate(true)

static func deserialize(d: Dictionary) -> Dictionary:
	return d.duplicate(true)

# ── Biome generation (value-noise continent) ──────────────────────────────────

static func _gen_biome(seed_value: int) -> Dictionary:
	var tiles := PackedByteArray()
	var elev := PackedFloat32Array()
	tiles.resize(BIOME_COLS * BIOME_ROWS)
	elev.resize(BIOME_COLS * BIOME_ROWS)
	var cx: float = (BIOME_COLS - 1) * 0.5
	var cy: float = (BIOME_ROWS - 1) * 0.5
	for gy in range(BIOME_ROWS):
		for gx in range(BIOME_COLS):
			# Fractal value noise for the base land/height shape, raised so the
			# interior is solidly land (the continent must seat all the cities).
			var e: float = _fbm(float(gx) / 13.0, float(gy) / 13.0, seed_value) + 0.08
			# Radial falloff sinks only the outer rim into the sea → a broad continent
			# ringed by ocean.
			var ndx: float = (gx - cx) / cx
			var ndy: float = (gy - cy) / cy
			var edge: float = sqrt(ndx * ndx * 1.05 + ndy * ndy)
			e -= smoothstep(0.72, 1.32, edge) * 0.55
			var i: int = gy * BIOME_COLS + gx
			elev[i] = e
	# Classify cells from elevation + a moisture field.
	for gy in range(BIOME_ROWS):
		for gx in range(BIOME_COLS):
			var i: int = gy * BIOME_COLS + gx
			var e: float = elev[i]
			var b: int
			if e < 0.32:
				b = B_SEA
			elif e > 0.86:
				b = B_MOUNTAIN
			elif e > 0.74:
				b = B_HILLS
			else:
				var m: float = _fbm(float(gx) / 8.0 + 40.0, float(gy) / 8.0 - 17.0, seed_value ^ 0x5151)
				b = B_FOREST if m > 0.56 else B_PLAINS
			tiles[i] = b
	# Coastlines: land cells touching the sea become coast.
	var coast := tiles.duplicate()
	for gy in range(BIOME_ROWS):
		for gx in range(BIOME_COLS):
			var i: int = gy * BIOME_COLS + gx
			if tiles[i] == B_SEA or tiles[i] == B_MOUNTAIN:
				continue
			if _touches_sea(tiles, gx, gy):
				coast[i] = B_COAST
	var biome := {
		"cols": BIOME_COLS, "rows": BIOME_ROWS,
		"cell_w": float(MAP_WIDTH) / float(BIOME_COLS),
		"cell_h": float(MAP_HEIGHT) / float(BIOME_ROWS),
		"tiles": coast,
		"elev": elev,
	}
	_carve_rivers(biome, seed_value)
	return biome

static func _touches_sea(tiles: PackedByteArray, gx: int, gy: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx: int = gx + dx
			var ny: int = gy + dy
			if nx < 0 or ny < 0 or nx >= BIOME_COLS or ny >= BIOME_ROWS:
				continue
			if tiles[ny * BIOME_COLS + nx] == B_SEA:
				return true
	return false

# A few rivers descending from the highest inland cells to the sea.
static func _carve_rivers(biome: Dictionary, seed_value: int) -> void:
	var tiles: PackedByteArray = biome["tiles"]
	var elev: PackedFloat32Array = biome["elev"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x71726
	var sources: int = 4
	for _s in range(sources):
		# Start from a random high (mountain/hills) cell.
		var sx: int = rng.randi_range(BIOME_COLS / 5, BIOME_COLS * 4 / 5)
		var sy: int = rng.randi_range(BIOME_ROWS / 5, BIOME_ROWS * 4 / 5)
		var gx: int = sx
		var gy: int = sy
		for _step in range(BIOME_COLS + BIOME_ROWS):
			var i: int = gy * BIOME_COLS + gx
			if tiles[i] == B_SEA:
				break
			if tiles[i] != B_MOUNTAIN:
				tiles[i] = B_RIVER
			# Flow to the lowest 8-neighbour.
			var best_e: float = elev[i]
			var bx: int = gx
			var by: int = gy
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx: int = gx + dx
					var ny: int = gy + dy
					if nx < 0 or ny < 0 or nx >= BIOME_COLS or ny >= BIOME_ROWS:
						continue
					var e: float = elev[ny * BIOME_COLS + nx]
					if e < best_e:
						best_e = e
						bx = nx; by = ny
			if bx == gx and by == gy:
				break   # local minimum (lake) — stop
			gx = bx; gy = by

# ── Value noise ────────────────────────────────────────────────────────────────

static func _hash01(ix: int, iy: int, seed_value: int) -> float:
	var h: int = (ix * 374761393 + iy * 668265263 + seed_value * 69069) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h) / 2147483647.0

static func _vnoise(fx: float, fy: float, seed_value: int) -> float:
	var x0: int = floori(fx)
	var y0: int = floori(fy)
	var tx: float = smoothstep(0.0, 1.0, fx - float(x0))
	var ty: float = smoothstep(0.0, 1.0, fy - float(y0))
	var a: float = _hash01(x0, y0, seed_value)
	var b: float = _hash01(x0 + 1, y0, seed_value)
	var c: float = _hash01(x0, y0 + 1, seed_value)
	var d: float = _hash01(x0 + 1, y0 + 1, seed_value)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)

static func _fbm(fx: float, fy: float, seed_value: int) -> float:
	var total: float = 0.0
	var amp: float = 0.55
	var freq: float = 1.0
	for o in range(4):
		total += _vnoise(fx * freq, fy * freq, seed_value + o * 1013) * amp
		freq *= 2.0
		amp *= 0.5
	return total

# ── Biome lookup ────────────────────────────────────────────────────────────────

static func biome_at(biome: Dictionary, px: float, py: float) -> int:
	var gx: int = clampi(int(px / biome["cell_w"]), 0, BIOME_COLS - 1)
	var gy: int = clampi(int(py / biome["cell_h"]), 0, BIOME_ROWS - 1)
	return biome["tiles"][gy * BIOME_COLS + gx]

# ── City placement (jittered hex lattice, culled by terrain) ───────────────────
#
# 55 cities at MIN_DIST spacing is near the packing limit for this map, so random
# dart-throwing jams well short. A hexagonal lattice (spacing > MIN_DIST) keeps every
# pair correctly spaced BY CONSTRUCTION and packs efficiently; we cull points that
# fall on sea/mountain, lightly jitter the rest, shuffle, and keep CITY_COUNT — the
# terrain holes plus the dropped surplus make the layout read as an organic continent
# rather than a uniform grid, while always reaching the full count.
static func _place_cities(rng: RandomNumberGenerator, biome: Dictionary) -> Array:
	const SPACING: float = 126.0          # > MIN_DIST so neighbours never crowd
	const JITTER: float = 3.0             # min pair stays SPACING - 2*JITTER = 120
	var row_h: float = SPACING * sqrt(3.0) * 0.5
	var on_land: Array = []               # habitable lattice points
	var on_fringe: Array = []             # river/other non-sea, non-mountain points
	var row: int = 0
	var y: float = float(MARGIN) + row_h * 0.5
	while y <= MAP_HEIGHT - MARGIN:
		var x: float = float(MARGIN) + (SPACING * 0.5 if (row % 2) == 1 else 0.0)
		while x <= MAP_WIDTH - MARGIN:
			var px: float = clampf(x + rng.randf_range(-JITTER, JITTER), MARGIN, MAP_WIDTH - MARGIN)
			var py: float = clampf(y + rng.randf_range(-JITTER, JITTER), MARGIN, MAP_HEIGHT - MARGIN)
			var b: int = biome_at(biome, px, py)
			if b in HABITABLE:
				on_land.append(Vector2(px, py))
			elif b != B_SEA and b != B_MOUNTAIN:
				on_fringe.append(Vector2(px, py))
			x += SPACING
		y += row_h
		row += 1

	_shuffle(on_land, rng)
	_shuffle(on_fringe, rng)
	var chosen: Array = on_land.slice(0, CITY_COUNT)
	# Top up from river banks etc. if habitable land alone fell short.
	var k: int = 0
	while chosen.size() < CITY_COUNT and k < on_fringe.size():
		chosen.append(on_fringe[k])
		k += 1

	var cities: Array = []
	for i in range(mini(chosen.size(), CITY_COUNT)):
		var p: Vector2 = chosen[i]
		cities.append({
			"id": i, "name": _city_name(i),
			"pos_x": p.x, "pos_y": p.y,
			"faction_id": -1, "is_capital": false, "is_player_start": false,
			"population": rng.randi_range(200, 2000),
			"troop_count": rng.randi_range(0, 80),
			"tier": rng.randi_range(0, 3),
			"connected_to": [],
		})
	return cities

# Unique village name; appends an ordinal once the base list wraps (80 villages > 56 names).
static func _city_name(i: int) -> String:
	var n: int = CITY_NAMES.size()
	if i < n:
		return CITY_NAMES[i]
	return "%s %d" % [CITY_NAMES[i % n], (i / n) + 1]

# Deterministic Fisher–Yates shuffle (seeded rng → reproducible layouts).
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

# ── Faction assignment (k-means++ capitals + Voronoi) ──────────────────────────

# New model (Stronghold-Kingdoms-style): a few AI "great houses" each hold a SMALL
# cluster around their capital; everything else starts INDEPENDENT (small, capturable).
# The player (assigned later in CampaignMap) begins owning a single independent village.
static func _assign_factions(cities: Array, rng: RandomNumberGenerator) -> Array:
	var n: int = cities.size()
	if n == 0:
		return []

	# Spread great-house capitals (k-means++ style: each next is farthest from chosen).
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

	# Everyone starts independent; great houses then claim a tight cluster.
	for c in cities:
		c["faction_id"] = INDEPENDENT_FACTION_ID
		c["is_capital"] = false

	for fi in range(capital_indices.size()):
		var cap: int = capital_indices[fi]
		cities[cap]["is_capital"] = true
		cities[cap]["faction_id"] = fi
		# Great houses now start FROM SCRATCH, like the player — an undeveloped seat they
		# must build up over time (KingdomAI invests turn by turn). They keep only the
		# head-start of holding a cluster of villages, not prebuilt development.
		cities[cap]["tier"]        = 0
		cities[cap]["development"] = 0
		# Claim the nearest still-independent villages for this house.
		var order: Array = []
		for i in range(n):
			if i == cap or cities[i]["is_capital"]: continue
			var dx: float = cities[i]["pos_x"] - cities[cap]["pos_x"]
			var dy: float = cities[i]["pos_y"] - cities[cap]["pos_y"]
			order.append({"i": i, "d": dx * dx + dy * dy})
		order.sort_custom(func(a, b): return a["d"] < b["d"])
		var claimed: int = 0
		for entry in order:
			if claimed >= GREAT_HOUSE_CLUSTER: break
			var idx: int = entry["i"]
			if cities[idx]["faction_id"] != INDEPENDENT_FACTION_ID: continue
			cities[idx]["faction_id"] = fi
			cities[idx]["tier"]        = 0   # claimed villages also start undeveloped
			cities[idx]["development"] = 0
			claimed += 1

	# Independent villages start small.
	for c in cities:
		if c["faction_id"] == INDEPENDENT_FACTION_ID:
			c["tier"] = mini(int(c.get("tier", 1)), 1)

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

# Per-biome-cell faction ownership (faction_id+1; 0 = neutral/sea/mountain), assigned
# to the nearest city's faction so territory borders follow the organic city spread.
static func _build_territory(cities: Array, biome: Dictionary) -> PackedByteArray:
	var terr := PackedByteArray()
	terr.resize(BIOME_COLS * BIOME_ROWS)
	var tiles: PackedByteArray = biome["tiles"]
	var cw: float = biome["cell_w"]
	var ch: float = biome["cell_h"]
	for gy in range(BIOME_ROWS):
		for gx in range(BIOME_COLS):
			var i: int = gy * BIOME_COLS + gx
			if tiles[i] == B_SEA or tiles[i] == B_MOUNTAIN:
				terr[i] = 0
				continue
			var px: float = (gx + 0.5) * cw
			var py: float = (gy + 0.5) * ch
			var best_d: float = INF
			var best_f: int = INDEPENDENT_FACTION_ID
			for c in cities:
				var dx: float = px - c["pos_x"]
				var dy: float = py - c["pos_y"]
				var d: float = dx * dx + dy * dy
				if d < best_d:
					best_d = d
					best_f = int(c["faction_id"])
			terr[i] = (best_f + 1) if best_f >= 0 else 0
	return terr

# ── Player start ──────────────────────────────────────────────────────────────

static func _mark_player_start(cities: Array) -> void:
	# The player begins as ONE small INDEPENDENT village near the map centre — not a
	# great-house capital. Pick the independent, non-capital city closest to centre.
	var cx: float = MAP_WIDTH  * 0.5
	var cy: float = MAP_HEIGHT * 0.5
	var best_idx: int   = -1
	var best_d: float   = INF
	for i in range(cities.size()):
		if cities[i].get("is_capital", false): continue
		if int(cities[i].get("faction_id", INDEPENDENT_FACTION_ID)) != INDEPENDENT_FACTION_ID: continue
		var dx: float = cities[i]["pos_x"] - cx
		var dy: float = cities[i]["pos_y"] - cy
		var d: float  = sqrt(dx*dx + dy*dy)
		if d < best_d:
			best_d   = d
			best_idx = i
	# Fallbacks: any non-capital, else city 0.
	if best_idx < 0:
		for i in range(cities.size()):
			if not cities[i].get("is_capital", false):
				best_idx = i
				break
	if best_idx < 0 and not cities.is_empty():
		best_idx = 0
	if best_idx >= 0:
		cities[best_idx]["is_player_start"] = true
		cities[best_idx]["tier"] = 0   # you start at the very bottom

# ── Road network (Prim's MST + extra edges) ───────────────────────────────────

static func _build_road_network(cities: Array, rng: RandomNumberGenerator) -> Array:
	var n: int = cities.size()
	if n < 2:
		return []

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

	var degree: Array = []
	degree.resize(n); degree.fill(0)
	for r in roads:
		degree[r["from_id"]] += 1
		degree[r["to_id"]]   += 1

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

# ── Resource deposits (tied to biome) ──────────────────────────────────────────

static func _place_resource_deposits(rng: RandomNumberGenerator, cities: Array, biome: Dictionary) -> Array:
	var deposits: Array = []
	var half_min: float = MIN_DIST * 0.5
	var target: int = rng.randi_range(95, 130)
	var attempts: int = 0

	while deposits.size() < target and attempts < target * 60:
		attempts += 1
		var px: float = MARGIN + rng.randf() * (MAP_WIDTH  - MARGIN * 2)
		var py: float = MARGIN + rng.randf() * (MAP_HEIGHT - MARGIN * 2)
		# Resource type follows the land: forests give wood, hills/mountains stone &
		# iron, plains food. Sea/coast/river carry no deposit.
		var b: int = biome_at(biome, px, py)
		var rtype: String = ""
		match b:
			B_FOREST:   rtype = "wood"
			B_HILLS:    rtype = "stone" if rng.randf() < 0.6 else "iron"
			B_MOUNTAIN: rtype = "iron" if rng.randf() < 0.6 else "stone"
			B_PLAINS:   rtype = "food"
			_:          continue
		var too_close: bool = false
		for c in cities:
			var dx: float = px - c["pos_x"]
			var dy: float = py - c["pos_y"]
			if sqrt(dx*dx + dy*dy) < half_min:
				too_close = true
				break
		if too_close: continue
		deposits.append({"pos_x": px, "pos_y": py, "type": rtype})

	return deposits
