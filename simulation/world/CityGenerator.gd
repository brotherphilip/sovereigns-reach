extends RefCounted
# Deterministic town generator. A city's physical form is a pure function of its
# (seed, terrain, development level): generate() lays out the FULL build sequence
# once to fix stable positions, and each building carries a `min_dev`. A town at
# development D shows exactly the buildings with min_dev <= D — so raising
# development APPENDS buildings (accretive growth) without ever reshuffling the
# layout. No per-city storage needed beyond the development level.
#
# Pure simulation: operates on a WorldGrid + plain dicts; no Godot scene imports.

const WorldGrid     = preload("res://simulation/world/WorldGrid.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const BuildingState = preload("res://simulation/buildings/BuildingState.gd")
const BridgePlanner = preload("res://simulation/world/BridgePlanner.gd")

const MAX_DEV: int = 10

# Ordered build sequence (type, min development). Restricted to types placeable on
# grass/valley/flat so generation never fails for lack of special terrain. Higher
# development simply reveals more of this list.
const SEQUENCE: Array = [
	# Every town carries the SAME raw-material economy the player builds: a woodcutter to fell
	# timber and a stockpile to store it (so a watched AI town has real woodcutters working, not
	# just food + housing). It lives by this economy exactly like the player's seat.
	["village_hall", 0], ["hovel", 0], ["apple_orchard", 0], ["woodcutter_camp", 0], ["stockpile", 0], ["well", 0],
	["hovel", 1], ["market", 1], ["wheat_farm", 1], ["woodcutter_camp", 1],
	["hovel", 2], ["granary", 2], ["mill", 2], ["hovel", 2],
	["hovel", 3], ["brewery", 3], ["inn", 3], ["barracks", 3],
	["church", 4], ["hovel", 4], ["apple_orchard", 4], ["armory", 4],
	["bakery", 5], ["hovel", 5], ["stockpile", 5], ["woodcutter_camp", 5],
	["blacksmith", 6], ["hovel", 6], ["trading_post", 6], ["wheat_farm", 6],
	["hovel", 7], ["guildhall", 7], ["pig_farm", 7],
	["hovel", 8], ["cathedral", 8], ["hovel", 8],
	["dairy_farm", 9], ["hovel", 9], ["apothecary", 9],
	["inn", 10], ["hovel", 10], ["hovel", 10],
]

const GRASS: int = 0
const VALLEY: int = 7
const ROAD: int = 9
const RIVER: int = 3
const BRIDGE: int = 11

# Empty-tile gap reserved around each town building (matches the player's placement
# rule) so AI towns aren't a solid block — paths run through the gaps.
const TOWN_GAP: int = 2

# Defensive wall ring appears from development 5. The radius and shape VARY per town
# (seed-driven, see _town_profile) so settlements don't all read as the same square.
const RING_RADIUS: int = 9
const WALL_MIN_DEV: int = 5
const TOWER_MIN_DEV: int = 6
const GREAT_TOWER_MIN_DEV: int = 8

# ── Public API ─────────────────────────────────────────────────────────────────

# Full candidate layout with stable positions (dev-independent). Each entry:
# {type, gx, gy, min_dev, w, h}. Filter with visible_buildings() for a dev level.
static func generate(center_x: int, center_y: int, grid, seed_val: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var occupied: Dictionary = {}   # "x,y" -> true
	var candidates: Array = []

	# Per-town form (radius, wall shape, gates, fill axis) — fixed for this seed, so the
	# layout stays deterministic & accretive while every town reads differently.
	var prof: Dictionary = _town_profile(rng)

	# 1) Wall ring + gates + towers first, so interior buildings avoid them.
	_place_walls(center_x, center_y, grid, candidates, occupied, prof)

	# 2) Building sequence, filling rings from the town's preferred angle so settlements
	#    grow into varied silhouettes instead of identical radial sprawl. Buildings within
	#    the same development tier are shuffled per-seed so no two towns share an arrangement.
	for entry in _shuffled_sequence(rng):
		var btype: String = entry[0]
		var min_dev: int = entry[1]
		var defn: Dictionary = BuildingRegistry.lookup(btype)
		var w: int = defn.get("width", 1)
		var h: int = defn.get("height", 1)
		var spot: Vector2i = _find_spot(center_x, center_y, w, h, grid, occupied, prof["fill_angle"])
		if spot.x == -2147483648:
			continue  # no room — consistently dropped for this seed/grid
		# Reserve the footprint PLUS a one-tile gap so town buildings keep their spacing.
		_mark(occupied, spot.x - TOWN_GAP, spot.y - TOWN_GAP, w + 2 * TOWN_GAP, h + 2 * TOWN_GAP)
		candidates.append({
			"type": btype, "gx": spot.x, "gy": spot.y,
			"min_dev": min_dev, "w": w, "h": h,
		})
	return candidates

# Seed-driven town form. Deterministic (consumes only the passed rng).
#   radius      — wall ring half-size (8..12): hamlets vs sprawling burghs.
#   chamfer     — corner cut (0 = square keep, 2-3 = octagonal town) for shape variety.
#   gate_sides  — which walls have a gatehouse (always South, plus 0-2 more on big towns).
#   fill_angle  — the angle rings are filled from, so buildings cluster town-specifically.
static func _town_profile(rng: RandomNumberGenerator) -> Dictionary:
	var radius: int = RING_RADIUS + rng.randi_range(-1, 3)
	var chamfer: int = (rng.randi_range(2, 3) if rng.randf() < 0.6 else 0)
	var sides: Array = ["S"]
	var others: Array = ["N", "E", "W"]
	# Add 1 extra gate on a mid town, 2 on a large one — picked deterministically.
	var extra: int = (2 if radius >= 11 else (1 if radius >= 9 else 0))
	for i in range(extra):
		if others.is_empty():
			break
		var pick: int = rng.randi_range(0, others.size() - 1)
		sides.append(others[pick])
		others.remove_at(pick)
	return {
		"radius": radius,
		"chamfer": chamfer,
		"gate_sides": sides,
		"fill_angle": rng.randf() * TAU,
	}

# The build sequence with entries SHUFFLED within each development tier (so placement
# order — and thus the town's arrangement — varies by seed) while every tier keeps the
# exact same building SET, preserving accretive growth and the defence-tier guarantees.
static func _shuffled_sequence(rng: RandomNumberGenerator) -> Array:
	var by_dev: Dictionary = {}
	var order: Array = []   # dev levels in first-seen order
	for entry in SEQUENCE:
		var d: int = entry[1]
		if not by_dev.has(d):
			by_dev[d] = []
			order.append(d)
		by_dev[d].append(entry)
	var result: Array = []
	for d in order:
		var tier: Array = by_dev[d]
		# Fisher–Yates with the seeded rng (Array.shuffle would use the GLOBAL rng).
		for i in range(tier.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp = tier[i]; tier[i] = tier[j]; tier[j] = tmp
		result.append_array(tier)
	# Keep the village hall first overall, so it always takes the town's centre tile.
	for i in range(result.size()):
		if result[i][0] == "village_hall":
			var vh = result[i]; result.remove_at(i); result.insert(0, vh)
			break
	return result

# Candidates whose min_dev <= dev (the town as it looks at this development).
static func visible_buildings(candidates: Array, dev: int) -> Array:
	var result: Array = []
	for c in candidates:
		if c.get("min_dev", 0) <= dev:
			result.append(c)
	return result

# Convenience: ready-to-render BuildingState dicts for a city at its development.
# Buildings with min_dev <= prev_dev are finished; anything newly unlocked
# (prev_dev < min_dev <= dev) is placed UNBUILT so builder pawns raise it live.
# next_id is the starting building id; returns {buildings, next_id}.
static func building_dicts(center_x: int, center_y: int, grid, seed_val: int,
		dev: int, owner_id: int, next_id: int, prev_dev: int = -1) -> Dictionary:
	if prev_dev < 0:
		prev_dev = dev  # first generation: everything already standing
	var candidates: Array = generate(center_x, center_y, grid, seed_val)
	var visible: Array = visible_buildings(candidates, dev)
	# Pave the path network only between buildings that ACTUALLY EXIST at this
	# development — so the town never shows roads running to bare future plots.
	_lay_paths(center_x, center_y, visible, grid)
	var buildings: Array = []
	var nid: int = next_id
	for c in visible:
		var b: Dictionary = BuildingState.create(c["type"], owner_id, c["gx"], c["gy"], nid)
		if b.is_empty():
			continue
		nid += 1
		var defn: Dictionary = BuildingRegistry.lookup(c["type"])
		var newly: bool = c.get("min_dev", 0) > prev_dev
		if newly:
			b["built"] = false
			b["build_progress"] = 0.0
			b["build_required"] = float(maxi(1, defn.get("width", 1) * defn.get("height", 1))) * 100.0
		else:
			b["built"] = true
		buildings.append(b)
	return {"buildings": buildings, "next_id": nid}

# How developed a hand-built town is, from its standing building count — used by
# the feedback loop to advance the player's seat on the world map.
static func development_from_building_count(count: int) -> int:
	# Roughly inverts the SEQUENCE cadence: ~3–4 buildings per development level.
	return clampi(count / 4, 0, MAX_DEV)

# ── Placement helpers ──────────────────────────────────────────────────────────

# Spiral outward from the centre for the nearest block of w×h buildable, free tiles.
# Each ring is scanned starting from `fill_angle` (a per-town preference) so different
# towns fill their rings from different sides — giving each a distinct, lopsided growth
# pattern rather than the identical radial sprawl of a fixed raster scan.
static func _find_spot(cx: int, cy: int, w: int, h: int, grid, occupied: Dictionary, fill_angle: float = 0.0) -> Vector2i:
	for r in range(0, 40):
		if r == 0:
			if _block_free(cx, cy, w, h, grid, occupied):
				return Vector2i(cx, cy)
			continue
		var ring: Array = []
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r:
					ring.append(Vector2i(dx, dy))
		ring.sort_custom(func(a, b):
			return fposmod(atan2(a.y, a.x) - fill_angle, TAU) < fposmod(atan2(b.y, b.x) - fill_angle, TAU))
		for off in ring:
			if _block_free(cx + off.x, cy + off.y, w, h, grid, occupied):
				return Vector2i(cx + off.x, cy + off.y)
	return Vector2i(-2147483648, 0)  # sentinel: no room

static func _block_free(x: int, y: int, w: int, h: int, grid, occupied: Dictionary) -> bool:
	for dy in range(h):
		for dx in range(w):
			var tx: int = x + dx
			var ty: int = y + dy
			if grid != null:
				if not grid.in_bounds(tx, ty):
					return false
				var t: int = grid.get_terrain(tx, ty)
				if t != GRASS and t != VALLEY:
					return false
				if grid.get_building_at(tx, ty) != 0:
					return false
			if occupied.has("%d,%d" % [tx, ty]):
				return false
	return true

static func _mark(occupied: Dictionary, x: int, y: int, w: int, h: int) -> void:
	for dy in range(h):
		for dx in range(w):
			occupied["%d,%d" % [x + dx, y + dy]] = true

# Carve a ROAD network for the buildings that exist at this development. Rather than a
# separate spoke per building, each building links to the NEAREST tile already on the
# network with a single straight-then-bent track that stops the moment it joins an
# existing road — so branches merge into T-junctions/crossroads and the town isn't
# carpeted in roads. Only open grass/valley is paved; footprints are never crossed.
static func _lay_paths(cx: int, cy: int, visible: Array, grid) -> void:
	if grid == null or visible.is_empty():
		return
	var footprints: Dictionary = {}
	for c in visible:
		for dy in range(int(c["h"])):
			for dx in range(int(c["w"])):
				footprints["%d,%d" % [int(c["gx"]) + dx, int(c["gy"]) + dy]] = true
	# Connection nodes: each real building (walls/towers excluded), nearest-first so the
	# trunk forms before the branches.
	var nodes: Array = []
	for c in visible:
		var d: Dictionary = BuildingRegistry.lookup(c["type"])
		if d.get("is_wall", false) or d.get("is_tower", false):
			continue
		nodes.append(Vector2i(int(c["gx"]) + int(c["w"]) / 2, int(c["gy"]) + int(c["h"]) / 2))
	nodes.sort_custom(func(a, b):
		return absi(a.x - cx) + absi(a.y - cy) < absi(b.x - cx) + absi(b.y - cy))
	# The town centre seeds the network.
	var road_tiles: Dictionary = {"%d,%d" % [cx, cy]: true}
	for node in nodes:
		var target: Vector2i = _nearest_road(node, road_tiles, cx, cy)
		_carve_to_network(node, target, grid, footprints, road_tiles)

# The road tile (or the centre) closest to `node`, so a new building joins the network
# by the shortest branch instead of running its own road all the way to the centre.
static func _nearest_road(node: Vector2i, road_tiles: Dictionary, cx: int, cy: int) -> Vector2i:
	var best := Vector2i(cx, cy)
	var best_d: int = 1 << 30
	for key in road_tiles:
		var parts: PackedStringArray = key.split(",")
		var rx: int = int(parts[0])
		var ry: int = int(parts[1])
		var d: int = absi(node.x - rx) + absi(node.y - ry)
		if d < best_d:
			best_d = d
			best = Vector2i(rx, ry)
	return best

# Lay a single L-shaped track from a building to its target, choosing the bend
# orientation that crosses the fewest footprints, and stopping as soon as it meets an
# existing road (a clean junction) so roads share trunks instead of stacking up.
static func _carve_to_network(from: Vector2i, target: Vector2i, grid, footprints: Dictionary, road_tiles: Dictionary) -> void:
	var horiz := _l_tiles(from, target, true)
	var vert := _l_tiles(from, target, false)
	var pts: Array = horiz if _footprint_hits(horiz, footprints) <= _footprint_hits(vert, footprints) else vert
	var last_dry: Vector2i = from
	for p in pts:
		var key: String = "%d,%d" % [p.x, p.y]
		if road_tiles.has(key) or (grid.in_bounds(p.x, p.y) and grid.get_terrain(p.x, p.y) == ROAD):
			road_tiles[key] = true
			return  # joined the existing network — T-junction / crossroad
		# A river in the way is spanned with a real bridge (anchored on the last dry tile)
		# so the road carries on across the water instead of dead-ending at the bank.
		if grid.in_bounds(p.x, p.y) and grid.get_terrain(p.x, p.y) == RIVER:
			var plan: Dictionary = BridgePlanner.plan_towards(grid, last_dry.x, last_dry.y, target.x, target.y)
			if not plan.get("ok", false):
				return  # uncrossable here — leave the road stub on the near bank
			for wc in plan.get("cells", []):
				grid.set_terrain(wc.x, wc.y, BRIDGE)
				road_tiles["%d,%d" % [wc.x, wc.y]] = true
			continue  # the bridged tiles are now passable; keep paving on the far bank
		if _paint_road(p.x, p.y, grid, footprints):
			road_tiles[key] = true
			last_dry = p
		elif grid.in_bounds(p.x, p.y) and grid.get_terrain(p.x, p.y) in [GRASS, VALLEY, ROAD, BRIDGE]:
			last_dry = p

# Tiles along an L-path from a→b (excludes a), one bend; horiz_first picks which leg.
static func _l_tiles(a: Vector2i, b: Vector2i, horiz_first: bool) -> Array:
	var pts: Array = []
	var x: int = a.x
	var y: int = a.y
	if horiz_first:
		while x != b.x: x += signi(b.x - x); pts.append(Vector2i(x, y))
		while y != b.y: y += signi(b.y - y); pts.append(Vector2i(x, y))
	else:
		while y != b.y: y += signi(b.y - y); pts.append(Vector2i(x, y))
		while x != b.x: x += signi(b.x - x); pts.append(Vector2i(x, y))
	return pts

static func _footprint_hits(pts: Array, footprints: Dictionary) -> int:
	var n: int = 0
	for p in pts:
		if footprints.has("%d,%d" % [p.x, p.y]):
			n += 1
	return n

# Paints one ROAD tile; returns true if it actually paved open grass/valley.
static func _paint_road(x: int, y: int, grid, footprints: Dictionary) -> bool:
	if not grid.in_bounds(x, y):
		return false
	if footprints.has("%d,%d" % [x, y]):
		return false
	var t: int = grid.get_terrain(x, y)
	if t == GRASS or t == VALLEY:
		grid.set_terrain(x, y, ROAD)
		return true
	return false

# Palisade ring (square or octagonal per the town profile), a gatehouse on each chosen
# side (nudged to a passable spot), corner lookout towers, and great towers just outside
# the corners at high dev. Radius/shape/gates all come from the seed-driven profile.
static func _place_walls(cx: int, cy: int, grid, candidates: Array, occupied: Dictionary, prof: Dictionary) -> void:
	var r: int = prof.get("radius", RING_RADIUS)
	var c: int = prof.get("chamfer", 0)
	# Gatehouses first (1x2), so the perimeter leaves their opening.
	for side in prof.get("gate_sides", ["S"]):
		_place_gate(cx, cy, r, String(side), grid, candidates, occupied)
	# Palisade perimeter for this town's shape.
	for t in _wall_perimeter(cx, cy, r, c):
		_try_wall(t.x, t.y, "wooden_palisade", WALL_MIN_DEV, grid, candidates, occupied)
	# Corner lookout towers (pulled in by the chamfer on an octagonal town).
	var cr: int = r - c
	for corner in [Vector2i(cx - cr, cy - cr), Vector2i(cx + cr, cy - cr), Vector2i(cx - cr, cy + cr), Vector2i(cx + cr, cy + cr)]:
		_try_wall(corner.x, corner.y, "lookout_tower", TOWER_MIN_DEV, grid, candidates, occupied)
	# Great towers just outside the corners (stone-age might).
	for corner in [Vector2i(cx - r - 2, cy - r - 2), Vector2i(cx + r + 1, cy - r - 2), Vector2i(cx - r - 2, cy + r + 1), Vector2i(cx + r + 1, cy + r + 1)]:
		if _block_free(corner.x, corner.y, 2, 2, grid, occupied):
			_mark(occupied, corner.x, corner.y, 2, 2)
			candidates.append({"type": "great_tower", "gx": corner.x, "gy": corner.y, "min_dev": GREAT_TOWER_MIN_DEV, "w": 2, "h": 2})

# Perimeter tiles of a square (c=0) or octagonal (c>0) wall ring of half-size r.
static func _wall_perimeter(cx: int, cy: int, r: int, c: int) -> Array:
	var tiles: Array = []
	for x in range(cx - r + c, cx + r - c + 1):
		tiles.append(Vector2i(x, cy - r))
		tiles.append(Vector2i(x, cy + r))
	for y in range(cy - r + c, cy + r - c + 1):
		tiles.append(Vector2i(cx - r, y))
		tiles.append(Vector2i(cx + r, y))
	for i in range(1, c):   # diagonal corner cuts (octagon)
		tiles.append(Vector2i(cx - r + i, cy - r + c - i))   # NW
		tiles.append(Vector2i(cx + r - i, cy - r + c - i))   # NE
		tiles.append(Vector2i(cx - r + i, cy + r - c + i))   # SW
		tiles.append(Vector2i(cx + r - i, cy + r - c + i))   # SE
	return tiles

# One gatehouse (1x2) at a wall side's midpoint, walked along the wall until it finds a
# passable footprint, so a gate is never stranded in water or against the map edge.
static func _place_gate(cx: int, cy: int, r: int, side: String, grid, candidates: Array, occupied: Dictionary) -> void:
	var base: Vector2i
	var along: Vector2i
	match side:
		"N": base = Vector2i(cx, cy - r); along = Vector2i(1, 0)
		"E": base = Vector2i(cx + r, cy); along = Vector2i(0, 1)
		"W": base = Vector2i(cx - r, cy); along = Vector2i(0, 1)
		_:   base = Vector2i(cx, cy + r); along = Vector2i(1, 0)   # South (default)
	for off in [0, 1, -1, 2, -2]:
		var gx: int = base.x + along.x * off
		var gy: int = base.y + along.y * off
		if _block_free(gx, gy, 1, 2, grid, occupied):
			_mark(occupied, gx, gy, 1, 2)
			candidates.append({"type": "gatehouse", "gx": gx, "gy": gy, "min_dev": WALL_MIN_DEV, "w": 1, "h": 2})
			return

static func _try_wall(x: int, y: int, btype: String, min_dev: int, grid, candidates: Array, occupied: Dictionary) -> void:
	if _block_free(x, y, 1, 1, grid, occupied):
		_mark(occupied, x, y, 1, 1)
		candidates.append({"type": btype, "gx": x, "gy": y, "min_dev": min_dev, "w": 1, "h": 1})
