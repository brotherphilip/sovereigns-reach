extends RefCounted
# Validates building placement on the WorldGrid before committing to GameState.
# Called by GameState.apply_command() for PLACE_BUILDING commands.
# Returns a validation result dict, never mutates state.

const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const WorldGrid        = preload("res://simulation/world/WorldGrid.gd")
const CapitalSystem    = preload("res://simulation/world/CapitalSystem.gd")

enum ValidationResult {
	OK              = 0,
	OUT_OF_BOUNDS   = 1,
	OCCUPIED        = 2,
	WRONG_TERRAIN   = 3,
	MISSING_TECH    = 4,
	MISSING_RESOURCES = 5,
	OUTSIDE_BORDERS = 6,
	INVALID_TYPE    = 7,
	UNIQUE_EXISTS   = 8,
	TOO_CLOSE       = 9,
}

# Required empty-tile gap between non-defensive buildings (so towns aren't a solid
# block and paths can run between them). Walls/towers/gates and paths are exempt.
const BUILDING_GAP: int = 2

# Main validation entry point.
# Returns {"ok": bool, "code": ValidationResult, "message": String}
static func validate(
		building_type: String,
		grid_x: int,
		grid_y: int,
		grid: Object,           # WorldGrid instance
		player: Dictionary,
		world: Dictionary
) -> Dictionary:
	if not BuildingRegistry.is_valid_type(building_type):
		return _fail(ValidationResult.INVALID_TYPE, "Unknown building type: %s" % building_type)

	var defn: Dictionary = BuildingRegistry.lookup(building_type)
	var w: int = defn.get("width", 1)
	var h: int = defn.get("height", 1)

	# Bounds check for all tiles the building occupies
	for dy in range(h):
		for dx in range(w):
			if not grid.in_bounds(grid_x + dx, grid_y + dy):
				return _fail(ValidationResult.OUT_OF_BOUNDS, "Building extends out of bounds")

	# Occupancy check. Exception: a GATE may be raised directly over the player's OWN wall/fence —
	# it replaces that segment (handled in _cmd_place_building), so converting a wall run into a
	# gateway doesn't require demolishing first.
	var placing_gate: bool = defn.get("is_gate", false)
	for dy in range(h):
		for dx in range(w):
			var occ_id: int = grid.get_building_at(grid_x + dx, grid_y + dy)
			if occ_id != 0:
				if placing_gate and _is_own_wall(occ_id, player):
					continue
				return _fail(ValidationResult.OCCUPIED, "Tile (%d,%d) is occupied" % [grid_x+dx, grid_y+dy])

	# Paths are laid as ROAD terrain — only on walkable land, never water/cliffs.
	if BuildingRegistry.is_path(building_type):
		var pt: int = grid.get_terrain(grid_x, grid_y)
		if pt in [WorldGrid.Terrain.MOUNTAIN, WorldGrid.Terrain.ROCK, WorldGrid.Terrain.RIVER]:
			return _fail(ValidationResult.WRONG_TERRAIN, "Can't lay a path on water or cliffs")

	# Minimum spacing: keep a gap between non-defensive buildings so a town never
	# becomes a solid block (defensive works and paths are exempt; see needs_spacing).
	if BuildingRegistry.needs_spacing(building_type):
		var gap: int = BUILDING_GAP
		for b in player.get("buildings", []):
			if not b is Dictionary:
				continue
			var bt: String = b.get("type", "")
			if not BuildingRegistry.needs_spacing(bt):
				continue
			var bdef: Dictionary = BuildingRegistry.lookup(bt)
			var bx: int = b.get("grid_x", 0)
			var by: int = b.get("grid_y", 0)
			var bw: int = bdef.get("width", 1)
			var bh: int = bdef.get("height", 1)
			# The new footprint expanded by `gap` must not touch an existing footprint.
			if not (grid_x - gap > bx + bw - 1 or grid_x + w - 1 + gap < bx \
					or grid_y - gap > by + bh - 1 or grid_y + h - 1 + gap < by):
				return _fail(ValidationResult.TOO_CLOSE, "Too close to another building — leave a gap")

	# Terrain requirements
	var terrain_req: int = defn.get("terrain_req", 0)
	if terrain_req != 0:
		var all_valid: bool = true
		for dy in range(h):
			for dx in range(w):
				var terrain: int = grid.get_terrain(grid_x + dx, grid_y + dy)
				var terrain_bit: int = (1 << terrain)
				if not (terrain_bit & terrain_req):
					all_valid = false
					break
			if not all_valid:
				break
		if not all_valid:
			return _fail(ValidationResult.WRONG_TERRAIN, "Terrain not suitable for %s" % building_type)

	# Uniqueness — only one of certain buildings (e.g. village hall) per player.
	if defn.get("unique", false):
		for b in player.get("buildings", []):
			if b is Dictionary and b.get("type", "") == building_type:
				return _fail(ValidationResult.UNIQUE_EXISTS, "Only one %s is allowed" % building_type)

	# Tech requirements
	var player_techs: Array = player.get("tech_unlocks", [])
	for tech in defn.get("requires_tech", []):
		if not tech in player_techs:
			return _fail(ValidationResult.MISSING_TECH, "Requires tech: %s" % tech)

	# Resource cost check
	var cost: Dictionary = defn.get("cost", {})
	for res in cost:
		if res == "gold":
			if player.get("gold", 0) < cost[res]:
				return _fail(ValidationResult.MISSING_RESOURCES, "Not enough gold — sell goods at the market for coin")
		else:
			if player.get("resources", {}).get(res, 0) < cost[res]:
				# Say HOW to remedy it, not just WHAT: a raw resource (stone/wood/iron…) can be
				# gathered (quarry/woodcutter/mine) OR bought at the market. The tutorial asks for
				# stone-cost buildings (barracks/tower) without teaching a stone source, so a new
				# player who hits "Not enough stone" needs the next step spelled out. (iter287)
				return _fail(ValidationResult.MISSING_RESOURCES,
					"Not enough %s — gather more (quarry/woodcutter/mine) or buy it at the market" % res)

	# No build-area restriction: buildings may be placed on any valid free tile,
	# anywhere on the map (the old shire-influence radius limit was removed).
	return {"ok": true, "code": ValidationResult.OK, "message": ""}

# Calculates terrain yield modifier for the building's primary tile
static func get_terrain_yield(building_type: String, grid_x: int, grid_y: int, grid: Object) -> float:
	var defn: Dictionary = BuildingRegistry.lookup(building_type)
	if defn.is_empty():
		return 1.0
	var category = defn.get("category", -1)
	if category != BuildingRegistry.Category.FOOD:
		return 1.0  # Only farms care about terrain yield
	return grid.get_farm_yield(grid_x, grid_y)

# Deducts the building cost from player resources
static func deduct_cost(building_type: String, player: Dictionary) -> void:
	var cost: Dictionary = BuildingRegistry.lookup(building_type).get("cost", {})
	for res in cost:
		if res == "gold":
			player["gold"] = maxi(0, player.get("gold", 0) - cost[res])
		else:
			player["resources"][res] = maxi(0, player["resources"].get(res, 0) - cost[res])

# True if grid building id `building_id` is one of THIS player's wall/fence segments — the only
# thing a gate is allowed to be placed on top of (it replaces it).
static func _is_own_wall(building_id: int, player: Dictionary) -> bool:
	for b in player.get("buildings", []):
		if b is Dictionary and int(b.get("id", -1)) == building_id:
			return BuildingRegistry.lookup(b.get("type", "")).get("is_wall", false)
	return false

static func _fail(code: int, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
