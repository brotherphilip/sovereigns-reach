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

const MAX_DEV: int = 10

# Ordered build sequence (type, min development). Restricted to types placeable on
# grass/valley/flat so generation never fails for lack of special terrain. Higher
# development simply reveals more of this list.
const SEQUENCE: Array = [
	["village_hall", 0], ["hovel", 0], ["apple_orchard", 0], ["well", 0],
	["hovel", 1], ["market", 1], ["wheat_farm", 1],
	["hovel", 2], ["granary", 2], ["mill", 2], ["hovel", 2],
	["hovel", 3], ["brewery", 3], ["inn", 3], ["barracks", 3],
	["church", 4], ["hovel", 4], ["apple_orchard", 4], ["armory", 4],
	["bakery", 5], ["hovel", 5],
	["blacksmith", 6], ["hovel", 6], ["trading_post", 6], ["wheat_farm", 6],
	["hovel", 7], ["guildhall", 7], ["pig_farm", 7],
	["hovel", 8], ["cathedral", 8], ["hovel", 8],
	["dairy_farm", 9], ["hovel", 9], ["apothecary", 9],
	["inn", 10], ["hovel", 10], ["hovel", 10],
]

const GRASS: int = 0
const VALLEY: int = 7

# Defensive wall ring appears from development 5. Radius scales the town size.
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

	# 1) Wall ring + gates + towers first, so interior buildings avoid them.
	_place_walls(center_x, center_y, grid, candidates, occupied)

	# 2) Linear building sequence, spiralling out from the town centre, kept inside
	#    the wall ring where possible.
	for entry in SEQUENCE:
		var btype: String = entry[0]
		var min_dev: int = entry[1]
		var defn: Dictionary = BuildingRegistry.lookup(btype)
		var w: int = defn.get("width", 1)
		var h: int = defn.get("height", 1)
		var spot: Vector2i = _find_spot(center_x, center_y, w, h, grid, occupied)
		if spot.x == -2147483648:
			continue  # no room — consistently dropped for this seed/grid
		_mark(occupied, spot.x, spot.y, w, h)
		candidates.append({
			"type": btype, "gx": spot.x, "gy": spot.y,
			"min_dev": min_dev, "w": w, "h": h,
		})
	return candidates

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
	var buildings: Array = []
	var nid: int = next_id
	for c in visible_buildings(candidates, dev):
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
static func _find_spot(cx: int, cy: int, w: int, h: int, grid, occupied: Dictionary) -> Vector2i:
	for r in range(0, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue  # current ring only
				var x: int = cx + dx
				var y: int = cy + dy
				if _block_free(x, y, w, h, grid, occupied):
					return Vector2i(x, y)
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

# Square palisade ring at RING_RADIUS, a gatehouse at the south edge, lookout
# towers at the corners, and great towers just outside the corners at high dev.
static func _place_walls(cx: int, cy: int, grid, candidates: Array, occupied: Dictionary) -> void:
	var r: int = RING_RADIUS
	var gate_x: int = cx
	var gate_y: int = cy + r
	# Gatehouse (1x2) at the south edge mid — placed first so the ring skips it.
	if _block_free(gate_x, gate_y, 1, 2, grid, occupied):
		_mark(occupied, gate_x, gate_y, 1, 2)
		candidates.append({"type": "gatehouse", "gx": gate_x, "gy": gate_y, "min_dev": WALL_MIN_DEV, "w": 1, "h": 2})
	# Palisade perimeter.
	for x in range(cx - r, cx + r + 1):
		_try_wall(x, cy - r, "wooden_palisade", WALL_MIN_DEV, grid, candidates, occupied)
		_try_wall(x, cy + r, "wooden_palisade", WALL_MIN_DEV, grid, candidates, occupied)
	for y in range(cy - r + 1, cy + r):
		_try_wall(cx - r, y, "wooden_palisade", WALL_MIN_DEV, grid, candidates, occupied)
		_try_wall(cx + r, y, "wooden_palisade", WALL_MIN_DEV, grid, candidates, occupied)
	# Corner lookout towers.
	for corner in [Vector2i(cx - r, cy - r), Vector2i(cx + r, cy - r), Vector2i(cx - r, cy + r), Vector2i(cx + r, cy + r)]:
		_try_wall(corner.x, corner.y, "lookout_tower", TOWER_MIN_DEV, grid, candidates, occupied)
	# Great towers just outside the corners (stone-age might).
	for corner in [Vector2i(cx - r - 2, cy - r - 2), Vector2i(cx + r + 1, cy - r - 2), Vector2i(cx - r - 2, cy + r + 1), Vector2i(cx + r + 1, cy + r + 1)]:
		if _block_free(corner.x, corner.y, 2, 2, grid, occupied):
			_mark(occupied, corner.x, corner.y, 2, 2)
			candidates.append({"type": "great_tower", "gx": corner.x, "gy": corner.y, "min_dev": GREAT_TOWER_MIN_DEV, "w": 2, "h": 2})

static func _try_wall(x: int, y: int, btype: String, min_dev: int, grid, candidates: Array, occupied: Dictionary) -> void:
	if _block_free(x, y, 1, 1, grid, occupied):
		_mark(occupied, x, y, 1, 1)
		candidates.append({"type": btype, "gx": x, "gy": y, "min_dev": min_dev, "w": 1, "h": 1})
