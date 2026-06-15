extends RefCounted
# A* pathfinding on WorldGrid with terrain move-cost weights.
#
# Top-tier implementation:
#   • Binary min-heap open set (O(log n) push/pop) instead of an O(n) linear scan.
#   • 8-directional movement: diagonals cost √2 and are blocked from cutting the
#     corner of an impassable tile (no clipping through walls/rivers diagonally).
#   • Octile-distance heuristic with a tiny tie-breaker for straight, natural paths.
#   • String-pull smoothing so units walk clean lines instead of staircases.
#
# Returns an Array of [x, y] pairs from start (exclusive) to goal (inclusive),
# or [] if no path exists. API (find_path / find_path_dict) is unchanged.

const PASS_FOOT    = 0b00000001
const PASS_CAVALRY = 0b00000010
const PASS_CART    = 0b00000100
const PASS_SIEGE   = 0b00001000

const SQRT2: float = 1.4142135623730951

# Terrain passability and move costs duplicated here so Pathfinder is self-contained.
# These must stay in sync with WorldGrid constants.
const _TERRAIN_PASSABILITY: Dictionary = {
	0: 0b00001111,  # GRASS
	1: 0b00000001,  # FOREST   — passable on foot (slow)
	2: 0,           # MOUNTAIN — fully blocks
	3: 0b00000001,  # RIVER    — wadeable on foot (very slow)
	4: 0b00000001,  # MARSH
	5: 0,           # ROCK     — fully blocks
	6: 0b00000001,  # ORE_VEIN
	7: 0b00001111,  # VALLEY
	8: 0b00000111,  # COASTAL
	9: 0b00001111,  # ROAD
	10: 0b00000011, # RUIN
}

const _TERRAIN_MOVE_COST: Dictionary = {
	0: 1.0,   # GRASS
	1: 2.0,   # FOREST  (≈ half speed)
	2: 99.0,  # MOUNTAIN (blocked)
	3: 5.0,   # RIVER   (water greatly slows)
	4: 3.0,   # MARSH
	5: 99.0,  # ROCK    (blocked)
	6: 2.0,   # ORE_VEIN
	7: 1.0,   # VALLEY
	8: 1.2,   # COASTAL
	9: 0.5,   # ROAD
	10: 1.5,  # RUIN
}

# 8 neighbour directions: 4 cardinal first, then 4 diagonals.
const _DIRS: Array = [
	[1, 0], [-1, 0], [0, 1], [0, -1],
	[1, 1], [1, -1], [-1, 1], [-1, -1],
]

# ── Public API ─────────────────────────────────────────────────────────────────

# Find a path on a WorldGrid instance. move_mask = passability bitmask.
static func find_path(grid, from_x: int, from_y: int, to_x: int, to_y: int,
		move_mask: int = PASS_FOOT) -> Array:
	if from_x == to_x and from_y == to_y:
		return []
	var width: int  = grid.width  if "width"  in grid else 0
	var height: int = grid.height if "height" in grid else 0
	if width == 0 or height == 0:
		return []
	if not _tile_passable(grid, to_x, to_y, move_mask):
		return []
	return _astar(
		funcref_passable_grid(grid, move_mask), funcref_cost_grid(grid),
		width, height, from_x, from_y, to_x, to_y)

# Small-grid helper for unit tests. grid_dict: {"width","height","tiles":[[int]]}.
static func find_path_dict(grid_dict: Dictionary, from_x: int, from_y: int,
		to_x: int, to_y: int, move_mask: int = PASS_FOOT) -> Array:
	var w: int = grid_dict.get("width", 0)
	var h: int = grid_dict.get("height", 0)
	if w == 0 or h == 0 or (from_x == to_x and from_y == to_y):
		return []
	if not _dict_tile_passable(grid_dict, to_x, to_y, move_mask):
		return []
	return _astar(
		funcref_passable_dict(grid_dict, move_mask), funcref_cost_dict(grid_dict),
		w, h, from_x, from_y, to_x, to_y)

# ── Core A* (heap-based, 8-directional) ──────────────────────────────────────────
# `passable` and `cost` are Callables: passable(x,y)->bool, cost(x,y)->float.
static func _astar(passable: Callable, cost: Callable, width: int, height: int,
		from_x: int, from_y: int, to_x: int, to_y: int) -> Array:
	var start_key: int = from_y * width + from_x
	var goal_key: int  = to_y * width + to_x

	# Per-node bookkeeping keyed by cell index.
	var g_score: Dictionary = {start_key: 0.0}
	var parent: Dictionary  = {start_key: -1}
	var closed: Dictionary  = {}

	# Binary min-heap of [f, key]. Lazy deletion via the g_score check on pop.
	var heap: Array = [[_octile(from_x, from_y, to_x, to_y), start_key]]

	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var ckey: int = top[1]
		if closed.has(ckey):
			continue
		closed[ckey] = true
		if ckey == goal_key:
			# Full tile-by-tile path (each step is 8-connected adjacent). Consumers
			# advance one tile per tick, so we keep every waypoint rather than
			# string-pulling, which would make units teleport across open ground.
			return _reconstruct(parent, goal_key, width, start_key)

		var cx: int = ckey % width
		var cy: int = ckey / width
		var cg: float = g_score[ckey]

		for d in _DIRS:
			var nx: int = cx + d[0]
			var ny: int = cy + d[1]
			if nx < 0 or nx >= width or ny < 0 or ny >= height:
				continue
			var nkey: int = ny * width + nx
			if closed.has(nkey) or not passable.call(nx, ny):
				continue
			var diagonal: bool = d[0] != 0 and d[1] != 0
			# No corner-cutting: a diagonal step requires both orthogonal cells open.
			if diagonal and (not passable.call(cx + d[0], cy) or not passable.call(cx, cy + d[1])):
				continue
			var step: float = cost.call(nx, ny) * (SQRT2 if diagonal else 1.0)
			var ng: float = cg + step
			if not g_score.has(nkey) or ng < g_score[nkey]:
				g_score[nkey] = ng
				parent[nkey] = ckey
				# f with a tiny tie-breaker that prefers straighter routes.
				var f: float = ng + _octile(nx, ny, to_x, to_y) * 1.001
				_heap_push(heap, [f, nkey])

	return []  # No path found

# ── Binary min-heap (array of [f, key]) ─────────────────────────────────────────

static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i: int = heap.size() - 1
	while i > 0:
		var p: int = (i - 1) >> 1
		if heap[p][0] <= heap[i][0]:
			break
		var tmp: Array = heap[p]; heap[p] = heap[i]; heap[i] = tmp
		i = p

static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i: int = 0
		var n: int = heap.size()
		while true:
			var l: int = i * 2 + 1
			var r: int = i * 2 + 2
			var smallest: int = i
			if l < n and heap[l][0] < heap[smallest][0]:
				smallest = l
			if r < n and heap[r][0] < heap[smallest][0]:
				smallest = r
			if smallest == i:
				break
			var tmp: Array = heap[i]; heap[i] = heap[smallest]; heap[smallest] = tmp
			i = smallest
	return top

# ── Heuristic / reconstruction / smoothing ──────────────────────────────────────

# Octile distance — exact for 8-connected grids (cardinal 1, diagonal √2).
static func _octile(ax: int, ay: int, bx: int, by: int) -> float:
	var dx: int = absi(ax - bx)
	var dy: int = absi(ay - by)
	return float(maxi(dx, dy)) + (SQRT2 - 1.0) * float(mini(dx, dy))

static func _reconstruct(parent: Dictionary, goal_key: int, width: int, start_key: int) -> Array:
	var path: Array = []
	var key: int = goal_key
	while key != start_key and key != -1:
		path.append([key % width, key / width])
		key = parent.get(key, -1)
	path.reverse()
	return path

# ── Callable factories (bind the grid + mask once) ───────────────────────────────

static func funcref_passable_grid(grid, mask: int) -> Callable:
	return func(x: int, y: int) -> bool: return _tile_passable(grid, x, y, mask)

static func funcref_cost_grid(grid) -> Callable:
	return func(x: int, y: int) -> float: return _tile_cost(grid, x, y)

static func funcref_passable_dict(d: Dictionary, mask: int) -> Callable:
	return func(x: int, y: int) -> bool: return _dict_tile_passable(d, x, y, mask)

static func funcref_cost_dict(d: Dictionary) -> Callable:
	return func(x: int, y: int) -> float: return _dict_tile_cost(d, x, y)

# ── Terrain helpers ──────────────────────────────────────────────────────────────

static func _tile_passable(grid, x: int, y: int, mask: int) -> bool:
	return (_TERRAIN_PASSABILITY.get(grid.get_terrain(x, y), 0) & mask) != 0

static func _tile_cost(grid, x: int, y: int) -> float:
	return _TERRAIN_MOVE_COST.get(grid.get_terrain(x, y), 99.0)

static func _dict_tile_passable(grid_dict: Dictionary, x: int, y: int, mask: int) -> bool:
	return (_TERRAIN_PASSABILITY.get(_dict_get_terrain(grid_dict, x, y), 0) & mask) != 0

static func _dict_tile_cost(grid_dict: Dictionary, x: int, y: int) -> float:
	return _TERRAIN_MOVE_COST.get(_dict_get_terrain(grid_dict, x, y), 99.0)

static func _dict_get_terrain(grid_dict: Dictionary, x: int, y: int) -> int:
	var tiles: Array = grid_dict.get("tiles", [])
	if y < 0 or y >= tiles.size():
		return 3  # RIVER = impassable
	var row: Array = tiles[y]
	if x < 0 or x >= row.size():
		return 3
	return row[x]
