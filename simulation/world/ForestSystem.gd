extends RefCounted
# A LIVING FOREST. Every wooded tile is a tree with a growth STAGE that advances over time at
# its own pace; adult trees occasionally seed a sapling into an empty neighbour, a new lone
# sapling rarely sprouts somewhere fresh, and felled tiles regrow from a stump. Only ADULT
# trees may be felled — so a managed woodland rotates rather than being clear-cut to nothing.
#
# Pure simulation: state lives in world["trees"] (save-safe) as tile_index -> [stage, growth,
# rate, regrow]. Terrain stays FOREST while a tree stands (path/slow), GRASS once felled.

const WorldGrid = preload("res://simulation/world/WorldGrid.gd")

enum { SAPLING = 0, YOUNG = 1, ADULT = 2, STUMP = 3 }

# Growth added per game-day, randomised per tree so a stand matures unevenly.
const GROW_MIN: float = 0.022
const GROW_MAX: float = 0.045
const SPREAD_CHANCE: float = 0.020     # per adult per day: seed an empty neighbour
const NEW_SEED_CHANCE: float = 0.25    # per day (realm-wide): one fresh lone sapling somewhere
const STUMP_REGROW_DAYS: int = 8       # a felled stump sits this long, then sprouts a sapling
const FELL_WOOD: int = 14              # logs yielded by felling one adult

# ── Tile-key helpers ────────────────────────────────────────────────────────────────────
# Keys are STRINGS of the flat index so world["trees"] survives JSON save/load intact (JSON
# object keys are always strings — an int-keyed dict would come back string-keyed and orphan
# every tree). Use key_for(grid,x,y) everywhere (sim and view) so they always match.
static func key_for(grid, x: int, y: int) -> String: return str(y * grid.width + x)
static func _key(grid, x: int, y: int) -> String: return str(y * grid.width + x)

static func _state(world: Dictionary) -> Dictionary:
	if not world.has("trees"):
		world["trees"] = {}
	return world["trees"]

# Seed the forest from the map's existing FOREST tiles — all start as established adults with a
# per-tree growth pace (so future regrowth/spread varies). Idempotent.
static func init_from_grid(world: Dictionary, grid, rng: RandomNumberGenerator) -> void:
	if world.get("trees_init", false):
		return
	var trees: Dictionary = _state(world)
	for y in range(grid.height):
		for x in range(grid.width):
			if grid.get_terrain(x, y) == WorldGrid.Terrain.FOREST:
				trees[_key(grid, x, y)] = [ADULT, 1.0, rng.randf_range(GROW_MIN, GROW_MAX), 0]
	world["trees_init"] = true

# One game-day of forest life: grow, regrow stumps, spread, rare new seed.
static func tick(world: Dictionary, grid, rng: RandomNumberGenerator) -> void:
	var trees: Dictionary = _state(world)
	var to_seed: Array = []          # tiles to turn into new saplings (deferred to avoid mutating mid-loop)
	for k in trees.keys():
		var t: Array = trees[k]
		var stage: int = int(t[0])
		if stage == STUMP:
			t[3] = int(t[3]) - 1
			if int(t[3]) <= 0:
				t[0] = SAPLING; t[1] = 0.0       # sprout anew
				var sx: int = int(k) % grid.width
				var sy: int = int(k) / grid.width
				grid.set_terrain(sx, sy, WorldGrid.Terrain.FOREST)
			continue
		if stage < ADULT:
			t[1] = float(t[1]) + float(t[2])
			if float(t[1]) >= 1.0:
				t[0] = stage + 1; t[1] = 0.0
		elif rng.randf() < SPREAD_CHANCE:
			var ax: int = int(k) % grid.width
			var ay: int = int(k) / grid.width
			var nx: int = ax + rng.randi_range(-1, 1)
			var ny: int = ay + rng.randi_range(-1, 1)
			if _can_seed(grid, world, nx, ny):
				to_seed.append(_key(grid, nx, ny))
	# Rare brand-new lone sapling somewhere fresh on the map.
	if rng.randf() < NEW_SEED_CHANCE:
		var rx: int = rng.randi_range(2, grid.width - 3)
		var ry: int = rng.randi_range(2, grid.height - 3)
		if _can_seed(grid, world, rx, ry):
			to_seed.append(_key(grid, rx, ry))
	for k2 in to_seed:
		trees[k2] = [SAPLING, 0.0, rng.randf_range(GROW_MIN, GROW_MAX), 0]
		grid.set_terrain(int(k2) % grid.width, int(k2) / grid.width, WorldGrid.Terrain.FOREST)

# A tile can sprout a sapling if it's open grass with no building/tree already.
static func _can_seed(grid, world: Dictionary, x: int, y: int) -> bool:
	if not grid.in_bounds(x, y):
		return false
	if grid.get_terrain(x, y) != WorldGrid.Terrain.GRASS:
		return false
	if grid.get_building_at(x, y) != 0:
		return false
	return not _state(world).has(_key(grid, x, y))

# Only fully-grown adults are fellable.
static func is_adult(world: Dictionary, grid, x: int, y: int) -> bool:
	var t = _state(world).get(_key(grid, x, y))
	return t != null and int(t[0]) == ADULT

# Fell the adult at (x,y): yields wood, leaves a regrowing stump, clears the terrain to grass.
static func fell(world: Dictionary, grid, x: int, y: int) -> int:
	var k: String = _key(grid, x, y)
	var t = _state(world).get(k)
	if t == null or int(t[0]) != ADULT:
		return 0
	t[0] = STUMP; t[1] = 0.0; t[3] = STUMP_REGROW_DAYS
	grid.set_terrain(x, y, WorldGrid.Terrain.GRASS)
	return FELL_WOOD

# Rendering helpers: stage (-1 none / 0..3) and growth fraction within stage (for morphing).
static func stage_at(world: Dictionary, grid, x: int, y: int) -> int:
	var t = _state(world).get(_key(grid, x, y))
	return int(t[0]) if t != null else -1

static func growth_at(world: Dictionary, grid, x: int, y: int) -> float:
	var t = _state(world).get(_key(grid, x, y))
	return clampf(float(t[1]), 0.0, 1.0) if t != null else 0.0
