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
	Terrain.RIVER:    PASSABLE_FOOT,                       # wadeable on foot, very slow
	Terrain.MARSH:    PASSABLE_FOOT,
	Terrain.ROCK:     0,  # solid boulders — fully blocks movement
	Terrain.ORE_VEIN: PASSABLE_FOOT,
	Terrain.VALLEY:   PASSABLE_FOOT | PASSABLE_CAVALRY | PASSABLE_CART | PASSABLE_SIEGE,
	Terrain.COASTAL:  PASSABLE_FOOT | PASSABLE_CAVALRY | PASSABLE_CART,
	Terrain.ROAD:     PASSABLE_FOOT | PASSABLE_CAVALRY | PASSABLE_CART | PASSABLE_SIEGE,
	Terrain.RUIN:     PASSABLE_FOOT | PASSABLE_CAVALRY,
}

# Movement cost multipliers for pathfinding (lower = faster travel). Drives both
# A* route choice AND per-tile movement speed, so units crawl through water and
# slow through forest while preferring open ground and roads.
const TERRAIN_MOVE_COST: Dictionary = {
	Terrain.GRASS:    1.0,
	Terrain.FOREST:   2.0,    # trees ≈ half speed
	Terrain.MOUNTAIN: 99.0,   # blocked
	Terrain.RIVER:    5.0,    # water greatly slows
	Terrain.MARSH:    3.0,
	Terrain.ROCK:     99.0,   # blocked
	Terrain.ORE_VEIN: 2.0,
	Terrain.VALLEY:   1.0,
	Terrain.COASTAL:  1.2,
	Terrain.ROAD:     0.5,  # Roads are 2× faster
	Terrain.RUIN:     1.5,
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
		if not in_bounds(x, y) or y >= height:
			break
		set_terrain(x, y, Terrain.RIVER)
		# Widen the channel for a more detailed look.
		if rng.randf() < 0.45:
			set_terrain(clampi(x + 1, 0, width - 1), y, Terrain.RIVER)
		if rng.randf() < 0.25:
			set_terrain(clampi(x - 1, 0, width - 1), y, Terrain.RIVER)
		# Meander.
		x = clampi(x + rng.randi_range(-1, 1), 0, width - 1)
		if rng.randf() < 0.30:
			x = clampi(x + rng.randi_range(-1, 1), 0, width - 1)
		y += 1
		# Occasionally fork a tributary.
		if allow_branch and j > 12 and rng.randf() < 0.045:
			_carve_river(rng, x, y, rng.randi_range(15, 45), false)

func _place_mountains(rng: RandomNumberGenerator) -> void:
	var chains: int = rng.randi_range(2, 4)
	for _i in range(chains):
		var cx: int = rng.randi_range(20, width - 20)
		var cy: int = rng.randi_range(20, height - 20)
		var length: int = rng.randi_range(15, 40)
		var x: int = cx
		var y: int = cy
		for _j in range(length):
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if rng.randf() < 0.7 and get_terrain(x + dx, y + dy) != Terrain.RIVER:
						set_terrain(x + dx, y + dy, Terrain.MOUNTAIN)
						if rng.randf() < 0.3:
							set_terrain(x + dx, y + dy, Terrain.ROCK)
							set_resource_density(x + dx, y + dy, rng.randi_range(60, 255))
			x += rng.randi_range(-2, 2)
			y += rng.randi_range(-2, 2)
			x = clampi(x, 0, width - 1)
			y = clampi(y, 0, height - 1)

# Many forest patches of varied size and density — dense cores, ragged edges.
func _place_forests(rng: RandomNumberGenerator) -> void:
	var patches: int = rng.randi_range(16, 26)
	for _i in range(patches):
		var cx: int = rng.randi_range(0, width - 1)
		var cy: int = rng.randi_range(0, height - 1)
		var radius: int = rng.randi_range(5, 18)
		var density: float = rng.randf_range(0.55, 0.95)
		for tile in get_tiles_in_radius(cx, cy, radius):
			if get_terrain(tile["x"], tile["y"]) != Terrain.GRASS:
				continue
			# Denser near the core, sparser at the rim, for organic edges.
			var dx: float = float(tile["x"] - cx)
			var dy: float = float(tile["y"] - cy)
			var edge: float = 1.0 - clampf(sqrt(dx * dx + dy * dy) / float(maxi(radius, 1)), 0.0, 1.0)
			if rng.randf() < density * (0.4 + 0.6 * edge):
				set_terrain(tile["x"], tile["y"], Terrain.FOREST)

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
	# Iron ore veins on/near mountains
	for y in range(height):
		for x in range(width):
			if get_terrain(x, y) == Terrain.MOUNTAIN and rng.randf() < 0.1:
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
