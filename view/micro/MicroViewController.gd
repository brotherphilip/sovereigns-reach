extends RefCounted
# GDD §2.3 — Isometric micro-view coordinate system and data extraction.
# Handles the 4-way rotation, screen↔grid coordinate mapping, build preview.
# All pure static functions — no Node, no scene tree dependency.

# Isometric tile dimensions (pixels) — matched by the TileMap configuration
const TILE_WIDTH:  int = 64
const TILE_HEIGHT: int = 32

# 4-way rotation: 0=NW, 1=NE, 2=SE, 3=SW
# Each rotation maps logical (x,y) to a different isometric screen origin.
# We store the transformation as {ax, ay, bx, by} so:
#   screen_x = tile_w/2 * (ax*x + bx*y)
#   screen_y = tile_h/2 * (ay*x + by*y)
const ROTATION_TRANSFORMS: Array = [
	{"ax":  1, "ay":  1, "bx": -1, "by":  1},  # 0 = NW facing
	{"ax":  1, "ay": -1, "bx":  1, "by":  1},  # 1 = NE facing
	{"ax": -1, "ay": -1, "bx":  1, "by": -1},  # 2 = SE facing
	{"ax": -1, "ay":  1, "bx": -1, "by": -1},  # 3 = SW facing
]

# Converts grid (gx, gy) to screen pixel coordinates for a given rotation.
# Returns {"screen_x": int, "screen_y": int}.
static func grid_to_screen(gx: int, gy: int, rotation: int = 0) -> Dictionary:
	var t: Dictionary = ROTATION_TRANSFORMS[clampi(rotation, 0, 3)]
	var sx: int = (TILE_WIDTH  / 2) * (t["ax"] * gx + t["bx"] * gy)
	var sy: int = (TILE_HEIGHT / 2) * (t["ay"] * gx + t["by"] * gy)
	return {"screen_x": sx, "screen_y": sy}

# Converts a screen pixel offset back to the nearest grid tile.
# Returns {"grid_x": int, "grid_y": int}.
static func screen_to_grid(screen_x: int, screen_y: int, rotation: int = 0) -> Dictionary:
	# Inverse of the isometric projection (approximate nearest tile)
	var px: float = float(screen_x) / float(TILE_WIDTH)
	var py: float = float(screen_y) / float(TILE_HEIGHT)
	match clampi(rotation, 0, 3):
		0: return {"grid_x": roundi(px + py), "grid_y": roundi(-px + py)}
		1: return {"grid_x": roundi(px - py), "grid_y": roundi( px + py)}
		2: return {"grid_x": roundi(-px - py), "grid_y": roundi(px - py)}
		3: return {"grid_x": roundi(-px + py), "grid_y": roundi(-px - py)}
	return {"grid_x": 0, "grid_y": 0}

# Returns build-preview validity data for placing a building type at (gx, gy).
# grid_data: the serialized WorldGrid dict (from GameState.world["grid"]).
# player: player Dictionary.
# Returns {"valid": bool, "reason": String}.
static func get_build_preview(building_type: String, gx: int, gy: int,
		player: Dictionary, world: Dictionary) -> Dictionary:
	const PlacementValidator = preload("res://simulation/buildings/PlacementValidator.gd")
	const BuildingRegistry   = preload("res://simulation/buildings/BuildingRegistry.gd")
	const WorldGrid          = preload("res://simulation/world/WorldGrid.gd")

	if not world.has("grid"):
		return {"valid": true, "reason": ""}  # No grid available (test mode)

	var grid: WorldGrid = WorldGrid.new()
	grid.deserialize(world["grid"])
	var result: Dictionary = PlacementValidator.validate(building_type, gx, gy, grid, player, world)
	return {"valid": result.get("ok", false), "reason": result.get("message", "")}

# Extracts all building rendering data for the player's current micro view.
# Returns Array[Dictionary] — one entry per building, each with grid coords and visual state.
static func get_building_render_list(player: Dictionary) -> Array:
	const BuildingRenderer = preload("res://view/micro/BuildingRenderer.gd")
	var result: Array = []
	for building in player.get("buildings", []):
		if not building is Dictionary:
			continue
		var vs: Dictionary = BuildingRenderer.get_visual_state(building)
		vs["grid_x"] = building.get("grid_x", 0)
		vs["grid_y"] = building.get("grid_y", 0)
		vs["id"] = building.get("id", -1)
		result.append(vs)
	return result

# Extracts all unit rendering data for the player.
# Returns Array[Dictionary] — one per alive unit.
static func get_unit_render_list(player: Dictionary) -> Array:
	const UnitRenderer = preload("res://view/micro/UnitRenderer.gd")
	var result: Array = []
	for unit in player.get("units", []):
		if not unit is Dictionary:
			continue
		var si: Dictionary = UnitRenderer.get_sprite_info(unit)
		si["pos_x"] = unit.get("pos_x", 0)
		si["pos_y"] = unit.get("pos_y", 0)
		si["id"] = unit.get("id", -1)
		result.append(si)
	return result
