extends RefCounted
# A* pathfinding on WorldGrid with terrain move-cost weights.
# Operates on a WorldGrid instance (or a Dictionary with "terrain_rows" for tests).
# Returns an Array of [x, y] pairs from start (exclusive) to goal (inclusive).
# Returns [] if no path exists.
#
# Passability mask constants mirror WorldGrid:
const PASS_FOOT    = 0b00000001
const PASS_CAVALRY = 0b00000010
const PASS_CART    = 0b00000100
const PASS_SIEGE   = 0b00001000

# Terrain passability and move costs duplicated here so Pathfinder is self-contained.
# These must stay in sync with WorldGrid constants.
const _TERRAIN_PASSABILITY: Dictionary = {
	0: 0b00001111,  # GRASS
	1: 0b00000001,  # FOREST
	2: 0b00000001,  # MOUNTAIN
	3: 0,           # RIVER
	4: 0b00000001,  # MARSH
	5: 0b00000001,  # ROCK
	6: 0b00000001,  # ORE_VEIN
	7: 0b00001111,  # VALLEY
	8: 0b00000111,  # COASTAL
	9: 0b00001111,  # ROAD
	10: 0b00000011, # RUIN
}

const _TERRAIN_MOVE_COST: Dictionary = {
	0: 1.0,   # GRASS
	1: 2.5,   # FOREST
	2: 3.0,   # MOUNTAIN
	3: 99.0,  # RIVER
	4: 2.0,   # MARSH
	5: 2.0,   # ROCK
	6: 2.0,   # ORE_VEIN
	7: 1.0,   # VALLEY
	8: 1.2,   # COASTAL
	9: 0.5,   # ROAD
	10: 1.5,  # RUIN
}

# Find path on a WorldGrid instance.
# move_mask: passability bitmask (PASS_FOOT, PASS_CAVALRY, etc.)
# Returns Array of [x, y] (first step is the tile after the start; last is goal).
static func find_path(grid, from_x: int, from_y: int, to_x: int, to_y: int,
		move_mask: int = PASS_FOOT) -> Array:
	if from_x == to_x and from_y == to_y:
		return []

	var width: int  = grid.width  if "width"  in grid else 0
	var height: int = grid.height if "height" in grid else 0
	if width == 0 or height == 0:
		return []

	# Check target passability
	if not _tile_passable(grid, to_x, to_y, move_mask):
		return []

	var start_key: int = from_y * width + from_x
	var goal_key:  int = to_y   * width + to_x

	# open_set: Dictionary key -> {g, f, parent}
	var open_set: Dictionary  = {}
	var closed_set: Dictionary = {}

	open_set[start_key] = {
		"g": 0.0,
		"f": _heuristic(from_x, from_y, to_x, to_y),
		"parent": -1,
		"x": from_x, "y": from_y,
	}

	var iterations: int = 0
	var max_iterations: int = width * height

	while not open_set.is_empty() and iterations < max_iterations:
		iterations += 1
		# Pick the open node with the lowest f score
		var best_key: int = -1
		var best_f: float = INF
		for k in open_set:
			if open_set[k]["f"] < best_f:
				best_f = open_set[k]["f"]
				best_key = k
		if best_key == -1:
			break

		var current: Dictionary = open_set[best_key]
		open_set.erase(best_key)
		closed_set[best_key] = current

		if best_key == goal_key:
			return _reconstruct(closed_set, best_key, width, start_key)

		var cx: int = current["x"]
		var cy: int = current["y"]
		var g: float = current["g"]

		# 4-directional neighbours
		for dir in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + dir[0]
			var ny: int = cy + dir[1]
			if nx < 0 or nx >= width or ny < 0 or ny >= height:
				continue
			var nkey: int = ny * width + nx
			if closed_set.has(nkey):
				continue
			if not _tile_passable(grid, nx, ny, move_mask):
				continue
			var move_cost: float = _tile_cost(grid, nx, ny)
			var ng: float = g + move_cost
			if not open_set.has(nkey) or ng < open_set[nkey]["g"]:
				open_set[nkey] = {
					"g": ng,
					"f": ng + _heuristic(nx, ny, to_x, to_y),
					"parent": best_key,
					"x": nx, "y": ny,
				}

	return []  # No path found

# ── Small-grid helper (for unit tests with a simple Dictionary grid) ─────────
# grid_dict: {"width":W, "height":H, "tiles": Array[Array[int]]}
# tiles[y][x] = terrain int
static func find_path_dict(grid_dict: Dictionary, from_x: int, from_y: int,
		to_x: int, to_y: int, move_mask: int = PASS_FOOT) -> Array:
	var w: int = grid_dict.get("width", 0)
	var h: int = grid_dict.get("height", 0)
	if w == 0 or h == 0 or from_x == to_x and from_y == to_y:
		return []

	var start_key: int = from_y * w + from_x
	var goal_key:  int = to_y   * w + to_x

	# Check target passability
	if not _dict_tile_passable(grid_dict, to_x, to_y, move_mask):
		return []

	var open_set: Dictionary   = {}
	var closed_set: Dictionary = {}

	open_set[start_key] = {
		"g": 0.0,
		"f": _heuristic(from_x, from_y, to_x, to_y),
		"parent": -1,
		"x": from_x, "y": from_y,
	}

	var max_iterations: int = w * h

	for _i in range(max_iterations):
		if open_set.is_empty():
			break
		var best_key: int = -1
		var best_f: float = INF
		for k in open_set:
			if open_set[k]["f"] < best_f:
				best_f = open_set[k]["f"]
				best_key = k
		if best_key == -1:
			break

		var current: Dictionary = open_set[best_key]
		open_set.erase(best_key)
		closed_set[best_key] = current

		if best_key == goal_key:
			return _reconstruct(closed_set, best_key, w, start_key)

		var cx: int = current["x"]
		var cy: int = current["y"]
		var g: float = current["g"]

		for dir in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + dir[0]
			var ny: int = cy + dir[1]
			if nx < 0 or nx >= w or ny < 0 or ny >= h:
				continue
			var nkey: int = ny * w + nx
			if closed_set.has(nkey):
				continue
			if not _dict_tile_passable(grid_dict, nx, ny, move_mask):
				continue
			var ng: float = g + _dict_tile_cost(grid_dict, nx, ny)
			if not open_set.has(nkey) or ng < open_set[nkey]["g"]:
				open_set[nkey] = {
					"g": ng,
					"f": ng + _heuristic(nx, ny, to_x, to_y),
					"parent": best_key,
					"x": nx, "y": ny,
				}

	return []

# ── Internal helpers ─────────────────────────────────────────────────────────

static func _heuristic(ax: int, ay: int, bx: int, by: int) -> float:
	return float(absi(ax - bx) + absi(ay - by))

static func _reconstruct(closed_set: Dictionary, goal_key: int, width: int,
		start_key: int) -> Array:
	var path: Array = []
	var key: int = goal_key
	while key != start_key and key != -1:
		var node: Dictionary = closed_set.get(key, {})
		path.append([node.get("x", 0), node.get("y", 0)])
		key = node.get("parent", -1)
	path.reverse()
	return path

static func _tile_passable(grid, x: int, y: int, mask: int) -> bool:
	var terrain: int = grid.get_terrain(x, y)
	return (_TERRAIN_PASSABILITY.get(terrain, 0) & mask) != 0

static func _tile_cost(grid, x: int, y: int) -> float:
	var terrain: int = grid.get_terrain(x, y)
	return _TERRAIN_MOVE_COST.get(terrain, 99.0)

static func _dict_tile_passable(grid_dict: Dictionary, x: int, y: int, mask: int) -> bool:
	var terrain: int = _dict_get_terrain(grid_dict, x, y)
	return (_TERRAIN_PASSABILITY.get(terrain, 0) & mask) != 0

static func _dict_tile_cost(grid_dict: Dictionary, x: int, y: int) -> float:
	var terrain: int = _dict_get_terrain(grid_dict, x, y)
	return _TERRAIN_MOVE_COST.get(terrain, 99.0)

static func _dict_get_terrain(grid_dict: Dictionary, x: int, y: int) -> int:
	var tiles: Array = grid_dict.get("tiles", [])
	if y < 0 or y >= tiles.size():
		return 3  # RIVER = impassable
	var row: Array = tiles[y]
	if x < 0 or x >= row.size():
		return 3
	return row[x]
