extends RefCounted
# Pure data class — no Node inheritance, no Godot scene dependencies.
# The 200×200 world map is stored as flat Arrays for cache efficiency
# and JSON serialization readiness.
#
# Coordinate system: (0,0) = top-left, X = right, Y = down.
# Isometric rendering maps this to screen space in the View layer.

# Terrain types (GDD §2.1 — Macro View Topography)
enum Terrain {
	GRASS       = 0,  # Buildable, farmable
	FOREST      = 1,  # Timber source, bandit camps spawn here
	MOUNTAIN    = 2,  # Iron/stone nodes, no farms, safe from cavalry
	RIVER       = 3,  # Impassable without bridge
	MARSH       = 4,  # Pitch rig placement
	ROCK        = 5,  # Stone quarry placement
	ORE_VEIN    = 6,  # Iron mine placement
	VALLEY      = 7,  # High fertility, extra farm yield
	COASTAL     = 8,  # Port access, Merchant Prince expansion target
	ROAD        = 9,  # Movement speed bonus
	RUIN        = 10, # Destroyed settlement remnant
	BRIDGE      = 11, # Crossing laid over a river — the only way foot/cart cross water
}

# Passability masks — packed as bitfield per terrain (for pathfinding in Phase 6)
const PASSABLE_FOOT: int    = 0b00000001  # infantry
const PASSABLE_CAVALRY: int = 0b00000010  # cavalry (blocked by mountain/marsh)
const PASSABLE_CART: int    = 0b00000100  # trade carts (need road or flat terrain)
const PASSABLE_SIEGE: int   = 0b00001000  # siege engines (flat terrain only)

# Terrain passability table [terrain] -> passability_bitmask
const TERRAIN_PASSABILITY: Dictionary = {
	Terrain.GRASS:    PASSABLE_FOOT | PASSABLE_CAVALRY | PASSABLE_CART | PASSABLE_SIEGE,
	Terrain.FOREST:   PASSABLE_FOOT,                       # passable, ~half speed
	Terrain.MOUNTAIN: 0,  # solid mass — fully blocks movement
	Terrain.RIVER:    0,  # deep water — fully blocks; cross only via a BRIDGE
	Terrain.MARSH:    PASSABLE_FOOT,
	Terrain.ROCK:     0,  # solid boulders — fully blocks movement
	Terrain.ORE_VEIN: PASSABLE_FOOT,
	Terrain.VALLEY:   PASSABLE_FOOT | PASSABLE_CAVALRY | PASSABLE_CART | PASSABLE_SIEGE,
	Terrain.COASTAL:  PASSABLE_FOOT | PASSABLE_CAVALRY | PASSABLE_CART,
	Terrain.ROAD:     PASSABLE_FOOT | PASSABLE_CAVALRY | PASSABLE_CART | PASSABLE_SIEGE,
	Terrain.RUIN:     PASSABLE_FOOT | PASSABLE_CAVALRY,
	Terrain.BRIDGE:   PASSABLE_FOOT | PASSABLE_CAVALRY | PASSABLE_CART | PASSABLE_SIEGE,
}

# Movement cost multipliers for pathfinding (lower = faster travel). Drives both
# A* route choice AND per-tile movement speed, so units crawl through water and
# slow through forest while preferring open ground and roads.
const TERRAIN_MOVE_COST: Dictionary = {
	Terrain.GRASS:    1.0,
	Terrain.FOREST:   2.0,    # trees ≈ half speed
	Terrain.MOUNTAIN: 99.0,   # blocked
	Terrain.RIVER:    99.0,   # blocked — cross only via a bridge
	Terrain.MARSH:    3.0,
	Terrain.ROCK:     99.0,   # blocked
	Terrain.ORE_VEIN: 2.0,
	Terrain.VALLEY:   1.0,
	Terrain.COASTAL:  1.2,
	Terrain.ROAD:     0.5,  # Roads are 2× faster
	Terrain.RUIN:     1.5,
	Terrain.BRIDGE:   0.6,  # cross the water briskly, like a good road
}

# Farm yield multipliers per terrain (GDD §3.1.4)
const TERRAIN_FARM_YIELD: Dictionary = {
	Terrain.GRASS:   1.0,
	Terrain.VALLEY:  1.5,
	Terrain.FOREST:  0.0,
	Terrain.MOUNTAIN:0.0,
	Terrain.RIVER:   0.0,
	Terrain.MARSH:   0.0,
	Terrain.ROCK:    0.0,
	Terrain.ORE_VEIN:0.0,
	Terrain.COASTAL: 0.6,
	Terrain.ROAD:    0.8,
	Terrain.RUIN:    0.5,
	Terrain.BRIDGE:  0.0,
}

const DEFAULT_WIDTH: int  = 200
const DEFAULT_HEIGHT: int = 200

var width: int  = DEFAULT_WIDTH
var height: int = DEFAULT_HEIGHT

# Flat arrays indexed by y * width + x for cache-friendly access
var _terrain: PackedByteArray   # Terrain enum values
var _shire_id: PackedByteArray  # Which shire owns this tile (255 = unclaimed)
var _elevation: PackedByteArray # 0–255 relative height (for visual layering)
var _resource_density: PackedByteArray # 0–255 (how rich this resource tile is)
var _building_id: PackedInt32Array   # 0 = empty, >0 = building occupies tile
var _unit_id: PackedInt32Array       # 0 = empty, >0 = unit on tile
var _field: PackedByteArray          # 1 = walkable "field" tile (orchard/farm rows)
# Crop on this tile, so the REAL terrain renders as farmland (no fake building floor): 0 none,
# 1 wheat, 2 orchard-grass, 3 pasture, 4 mud (pen), 5 hops. Set when a field building registers on
# the grid; rebuilt from the buildings on load (not serialised), like _building_id / _field.
var _field_crop: PackedByteArray

func _init(w: int = DEFAULT_WIDTH, h: int = DEFAULT_HEIGHT) -> void:
	width = w
	height = h
	var size: int = width * height
	_terrain           = PackedByteArray()
	_terrain.resize(size)
	_shire_id          = PackedByteArray()
	_shire_id.resize(size)
	_elevation         = PackedByteArray()
	_elevation.resize(size)
	_resource_density  = PackedByteArray()
	_resource_density.resize(size)
	_building_id       = PackedInt32Array()
	_building_id.resize(size)
	_unit_id           = PackedInt32Array()
	_unit_id.resize(size)
	_field             = PackedByteArray()
	_field.resize(size)
	_field_crop        = PackedByteArray()
	_field_crop.resize(size)
	_terrain.fill(Terrain.GRASS)
	_shire_id.fill(255)

# --- Coordinate validation ---

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height

func _idx(x: int, y: int) -> int:
	return y * width + x

# --- Terrain accessors ---

func get_terrain(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return Terrain.RIVER  # Out-of-bounds treated as impassable
	return _terrain[_idx(x, y)]

func set_terrain(x: int, y: int, terrain: Terrain) -> void:
	if in_bounds(x, y):
		_terrain[_idx(x, y)] = terrain

func get_move_cost(x: int, y: int) -> float:
	return TERRAIN_MOVE_COST.get(get_terrain(x, y), 99.0)

func get_farm_yield(x: int, y: int) -> float:
	return TERRAIN_FARM_YIELD.get(get_terrain(x, y), 0.0)

func is_passable(x: int, y: int, move_type: int) -> bool:
	var mask: int = TERRAIN_PASSABILITY.get(get_terrain(x, y), 0)
	return (mask & move_type) != 0

func is_buildable(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	if _building_id[_idx(x, y)] != 0:
		return false
	var t: int = get_terrain(x, y)
	return t != Terrain.RIVER and t != Terrain.MOUNTAIN and t != Terrain.ROCK

# --- Shire accessors ---

func get_shire(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 255
	return _shire_id[_idx(x, y)]

func set_shire(x: int, y: int, shire_id: int) -> void:
	if in_bounds(x, y):
		_shire_id[_idx(x, y)] = shire_id

# --- Building/unit tile occupation ---

func get_building_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return _building_id[_idx(x, y)]

func set_building_at(x: int, y: int, building_id: int) -> void:
	if in_bounds(x, y):
		_building_id[_idx(x, y)] = building_id

# "Field" tiles (orchards, farms) stay registered as buildings for placement
# collision but are walkable so villagers can toil AMONG the rows/trees.
func set_field_crop_at(x: int, y: int, crop: int) -> void:
	if in_bounds(x, y):
		_field_crop[_idx(x, y)] = crop

func get_field_crop_at(x: int, y: int) -> int:
	return _field_crop[_idx(x, y)] if in_bounds(x, y) else 0

func set_field_at(x: int, y: int, is_field: bool) -> void:
	if in_bounds(x, y):
		_field[_idx(x, y)] = 1 if is_field else 0

func is_field_at(x: int, y: int) -> bool:
	return in_bounds(x, y) and _field[_idx(x, y)] == 1

func get_unit_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return _unit_id[_idx(x, y)]

func set_unit_at(x: int, y: int, unit_id: int) -> void:
	if in_bounds(x, y):
		_unit_id[_idx(x, y)] = unit_id

# --- Resource density ---

func get_resource_density(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return _resource_density[_idx(x, y)]

func set_resource_density(x: int, y: int, density: int) -> void:
	if in_bounds(x, y):
		_resource_density[_idx(x, y)] = clampi(density, 0, 255)

# --- Area queries ---

func get_tiles_of_type(terrain: Terrain) -> Array:
	var result: Array = []
	for y in range(height):
		for x in range(width):
			if _terrain[_idx(x, y)] == terrain:
				result.append({"x": x, "y": y})
	return result

func get_tiles_in_radius(cx: int, cy: int, radius: int) -> Array:
	var result: Array = []
	var r2: int = radius * radius
	for y in range(max(0, cy - radius), min(height, cy + radius + 1)):
		for x in range(max(0, cx - radius), min(width, cx + radius + 1)):
			var dx: int = x - cx
			var dy: int = y - cy
			if dx * dx + dy * dy <= r2:
				result.append({"x": x, "y": y})
	return result

func count_terrain_in_radius(cx: int, cy: int, radius: int, terrain: Terrain) -> int:
	var count: int = 0
	for tile in get_tiles_in_radius(cx, cy, radius):
		if get_terrain(tile["x"], tile["y"]) == terrain:
			count += 1
	return count

# Allocation-free presence check within a radius (early-exits on first match).
# Hot path for map generation — avoids the Array/Dictionary churn of
# count_terrain_in_radius when only "is any nearby?" is needed.
func _has_terrain_near(cx: int, cy: int, radius: int, terrain: int) -> bool:
	var r2: int = radius * radius
	var y0: int = maxi(0, cy - radius)
	var y1: int = mini(height, cy + radius + 1)
	var x0: int = maxi(0, cx - radius)
	var x1: int = mini(width, cx + radius + 1)
	for y in range(y0, y1):
		var row: int = y * width
		var dy: int = y - cy
		for x in range(x0, x1):
			var dx: int = x - cx
			if dx * dx + dy * dy <= r2 and _terrain[row + x] == terrain:
				return true
	return false

# --- Map generation (seeded procedural) ---

func generate(seed_value: int, shire_count: int = 8) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	_place_mountains(rng)
	_place_rivers(rng)
	_place_forests(rng)
	_place_rocks(rng)
	_place_resource_nodes(rng)
	_place_valleys(rng)
	_place_coastal(rng)

# Meandering, widening rivers that spawn tributaries, plus a lake basin.
func _place_rivers(rng: RandomNumberGenerator) -> void:
	var main_rivers: int = rng.randi_range(2, 3)
	for _i in range(main_rivers):
		_carve_river(rng, rng.randi_range(20, width - 20), 0, height + 10, true)
	# A lake somewhere inland.
	var lx: int = rng.randi_range(40, width - 40)
	var ly: int = rng.randi_range(40, height - 40)
	for tile in get_tiles_in_radius(lx, ly, rng.randi_range(5, 9)):
		set_terrain(tile["x"], tile["y"], Terrain.RIVER)

func _carve_river(rng: RandomNumberGenerator, sx: int, sy: int, length: int, allow_branch: bool) -> void:
	var x: int = sx
	var y: int = sy
	for j in range(length):
		if y < 0 or y >= height:
			break
		# Always a solid band at least 2 cells wide (x..x+1), occasionally swelling to 3-4.
		var lo: int = x
		var hi: int = x + 1
		if rng.randf() < 0.30:
			lo -= 1
		if rng.randf() < 0.30:
			hi += 1
		_carve_river_row(y, lo, hi)
		# Meander, then bridge the horizontal shift on THIS row so the channel never
		# pinches off (a diagonal jump would otherwise leave a 1-cell gap).
		var nx: int = x + rng.randi_range(-1, 1)
		if rng.randf() < 0.30:
			nx += rng.randi_range(-1, 1)
		nx = clampi(nx, 0, width - 1)
		_carve_river_row(y, mini(x, nx), maxi(x, nx) + 1)
		x = nx
		y += 1
		# Occasionally fork a tributary.
		if allow_branch and j > 12 and rng.randf() < 0.045:
			_carve_river(rng, x, y, rng.randi_range(15, 45), false)

# Carve a contiguous run of RIVER cells across one row (inclusive, clamped to the map).
func _carve_river_row(y: int, x0: int, x1: int) -> void:
	for cx in range(x0, x1 + 1):
		set_terrain(clampi(cx, 0, width - 1), y, Terrain.RIVER)

func _place_mountains(rng: RandomNumberGenerator) -> void:
	# A few CHUNKY massifs — each a tight cluster of big overlapping lobes that fuse into one
	# solid hill (deep interior tiles → tall terraced peaks), not a thin meandering ridge that
	# would read as a maze of walls. No holes, no embedded rock/ore.
	var ranges: int = rng.randi_range(2, 3)
	for _i in range(ranges):
		var x: int = rng.randi_range(20, width - 20)
		var y: int = rng.randi_range(20, height - 20)
		var lobes: int = rng.randi_range(3, 6)
		for _j in range(lobes):
			for tile in get_tiles_in_radius(x, y, rng.randi_range(4, 7)):
				if get_terrain(tile["x"], tile["y"]) != Terrain.RIVER:
					set_terrain(tile["x"], tile["y"], Terrain.MOUNTAIN)
			# Keep the lobes close so they heavily overlap into one compact mass.
			x = clampi(x + rng.randi_range(-4, 4), 0, width - 1)
			y = clampi(y + rng.randi_range(-4, 4), 0, height - 1)

# Many forest patches of varied size and density. Each is an irregular, lobed amoeba (not a
# clean disc) with internal clearings and a scatter of lone outlier trees, so a wood reads as
# organic copse-and-glade rather than a solid square block.
func _place_forests(rng: RandomNumberGenerator) -> void:
	var patches: int = rng.randi_range(14, 22)
	for _i in range(patches):
		var cx: int = rng.randi_range(0, width - 1)
		var cy: int = rng.randi_range(0, height - 1)
		var radius: int = rng.randi_range(5, 16)
		var density: float = rng.randf_range(0.5, 0.9)
		# Lobed outline: the effective radius wobbles with the angle, so the edge is ragged
		# and the patch bulges and pinches like real woodland, not a circle.
		var ph1: float = rng.randf() * TAU
		var ph2: float = rng.randf() * TAU
		var a1: float = rng.randf_range(0.25, 0.45)
		var a2: float = rng.randf_range(0.12, 0.28)
		for tile in get_tiles_in_radius(cx, cy, radius + 4):
			var tx: int = tile["x"]
			var ty: int = tile["y"]
			if get_terrain(tx, ty) != Terrain.GRASS:
				continue
			var dx: float = float(tx - cx)
			var dy: float = float(ty - cy)
			var dist: float = sqrt(dx * dx + dy * dy)
			var ang: float = atan2(dy, dx)
			var eff: float = float(radius) * (1.0 + a1 * sin(ang * 3.0 + ph1) + a2 * sin(ang * 5.0 + ph2))
			if dist > eff:
				continue
			# Internal clearings: a low-frequency wave punches glades so it isn't a solid mass.
			if sin(float(tx) * 0.5 + ph1) * sin(float(ty) * 0.5 + ph2) > 0.62:
				continue
			var edge: float = 1.0 - clampf(dist / maxf(eff, 1.0), 0.0, 1.0)
			if rng.randf() < density * (0.3 + 0.7 * edge):
				set_terrain(tx, ty, Terrain.FOREST)
		# A few lone outlier trees scattered beyond the canopy — stragglers and seedlings.
		for _j in range(rng.randi_range(2, 5)):
			var ox: int = clampi(cx + rng.randi_range(-radius - 6, radius + 6), 0, width - 1)
			var oy: int = clampi(cy + rng.randi_range(-radius - 6, radius + 6), 0, height - 1)
			if get_terrain(ox, oy) == Terrain.GRASS:
				set_terrain(ox, oy, Terrain.FOREST)

# Scattered solid rock outcrops (impassable) dotting the grassland.
func _place_rocks(rng: RandomNumberGenerator) -> void:
	var clumps: int = rng.randi_range(8, 16)
	for _i in range(clumps):
		var cx: int = rng.randi_range(8, width - 8)
		var cy: int = rng.randi_range(8, height - 8)
		for tile in get_tiles_in_radius(cx, cy, rng.randi_range(1, 3)):
			if get_terrain(tile["x"], tile["y"]) == Terrain.GRASS and rng.randf() < 0.6:
				set_terrain(tile["x"], tile["y"], Terrain.ROCK)

func _place_resource_nodes(rng: RandomNumberGenerator) -> void:
	# Iron ore veins in the FOOTHILLS — on grass touching the mountain mass, never inside
	# it. This keeps the massif a clean solid cliff while the ore sits minable at its base.
	for y in range(height):
		for x in range(width):
			if get_terrain(x, y) == Terrain.GRASS \
					and _has_terrain_near(x, y, 1, Terrain.MOUNTAIN) and rng.randf() < 0.20:
				set_terrain(x, y, Terrain.ORE_VEIN)
				set_resource_density(x, y, rng.randi_range(80, 255))
	# Marsh/pitch near rivers
	for y in range(height):
		for x in range(width):
			if get_terrain(x, y) == Terrain.GRASS:
				if _has_terrain_near(x, y, 3, Terrain.RIVER) and rng.randf() < 0.15:
					set_terrain(x, y, Terrain.MARSH)

func _place_valleys(rng: RandomNumberGenerator) -> void:
	var count: int = rng.randi_range(4, 8)
	for _i in range(count):
		var cx: int = rng.randi_range(10, width - 10)
		var cy: int = rng.randi_range(10, height - 10)
		var radius: int = rng.randi_range(8, 20)
		for tile in get_tiles_in_radius(cx, cy, radius):
			if get_terrain(tile["x"], tile["y"]) == Terrain.GRASS:
				set_terrain(tile["x"], tile["y"], Terrain.VALLEY)
				set_resource_density(tile["x"], tile["y"], rng.randi_range(100, 200))

func _place_coastal(rng: RandomNumberGenerator) -> void:
	# Top and bottom edges are coastal
	for x in range(width):
		if get_terrain(x, 0) != Terrain.RIVER:
			set_terrain(x, 0, Terrain.COASTAL)
		if get_terrain(x, height - 1) != Terrain.RIVER:
			set_terrain(x, height - 1, Terrain.COASTAL)

# --- Serialization ---
# Stored as compact base64-encoded packed arrays in GameState.world

func serialize() -> Dictionary:
	return {
		"width": width,
		"height": height,
		"terrain": Marshalls.raw_to_base64(_terrain),
		"shire_id": Marshalls.raw_to_base64(_shire_id),
		"elevation": Marshalls.raw_to_base64(_elevation),
		"resource_density": Marshalls.raw_to_base64(_resource_density),
	}

func deserialize(data: Dictionary) -> void:
	width  = data.get("width",  DEFAULT_WIDTH)
	height = data.get("height", DEFAULT_HEIGHT)
	var size: int = width * height
	_terrain          = Marshalls.base64_to_raw(data.get("terrain", ""))
	_shire_id         = Marshalls.base64_to_raw(data.get("shire_id", ""))
	_elevation        = Marshalls.base64_to_raw(data.get("elevation", ""))
	_resource_density = Marshalls.base64_to_raw(data.get("resource_density", ""))
	_building_id      = PackedInt32Array()
	_building_id.resize(size)
	_unit_id          = PackedInt32Array()
	_unit_id.resize(size)
	_field            = PackedByteArray()
	_field.resize(size)
	_field_crop       = PackedByteArray()
	_field_crop.resize(size)
