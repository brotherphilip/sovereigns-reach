extends RefCounted
# Validates building placement on the WorldGrid before committing to GameState.
# Called by GameState.apply_command() for PLACE_BUILDING commands.
# Returns a validation result dict, never mutates state.

const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const WorldGrid        = preload("res://simulation/world/WorldGrid.gd")

enum ValidationResult {
	OK              = 0,
	OUT_OF_BOUNDS   = 1,
	OCCUPIED        = 2,
	WRONG_TERRAIN   = 3,
	MISSING_TECH    = 4,
	MISSING_RESOURCES = 5,
	OUTSIDE_BORDERS = 6,
	INVALID_TYPE    = 7,
}

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

	# Occupancy check
	for dy in range(h):
		for dx in range(w):
			if grid.get_building_at(grid_x + dx, grid_y + dy) != 0:
				return _fail(ValidationResult.OCCUPIED, "Tile (%d,%d) is occupied" % [grid_x+dx, grid_y+dy])

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
				return _fail(ValidationResult.MISSING_RESOURCES, "Not enough gold")
		else:
			if player.get("resources", {}).get(res, 0) < cost[res]:
				return _fail(ValidationResult.MISSING_RESOURCES, "Not enough %s" % res)

	# Border check: must be within player's shire influence
	var shire_id: int = player.get("shire_id", -1)
	if shire_id >= 0 and world.has("shires"):
		var shire: Dictionary = {}
		for s in world.get("shires", []):
			if s["id"] == shire_id:
				shire = s
				break
		if not shire.is_empty():
			var cap_x: int = shire.get("capital_x", grid_x)
			var cap_y: int = shire.get("capital_y", grid_y)
			var radius: int = shire.get("influence_radius", 999)
			var dx: int = grid_x - cap_x
			var dy: int = grid_y - cap_y
			if dx * dx + dy * dy > radius * radius:
				return _fail(ValidationResult.OUTSIDE_BORDERS, "Outside shire influence radius")

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

static func _fail(code: int, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
