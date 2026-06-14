extends RefCounted
# Fog of war (enemy fog). Computes which tiles player 0 can currently see, from the
# vision radius of their buildings (watchtowers see farthest) and units. Enemy
# buildings/units outside this set are hidden by the render layers. Terrain stays
# visible — this is an economic builder, so fog only gates ENEMIES.

const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const TechTree         = preload("res://simulation/tech/TechTree.gd")

const DEFAULT_BUILDING_VISION := 6
const UNIT_VISION := 4

# Rebuild state.visibility (Dictionary of "x,y" -> true) for player 0.
static func recompute(state) -> void:
	state.visibility.clear()
	if state.players.is_empty():
		return
	var player = state.players[0]
	for b in player.get("buildings", []):
		if b is Dictionary:
			var r: int = BuildingRegistry.coverage_radius(b.get("type", ""))
			if r <= 0:
				r = DEFAULT_BUILDING_VISION
			_mark_circle(state.visibility, b.get("grid_x", 0), b.get("grid_y", 0), r)
	var scout_bonus: int = int(TechTree.get_all_modifiers(player).get("scout_vision_radius", 0))
	for u in player.get("units", []):
		if u is Dictionary:
			var vision: int = UNIT_VISION
			if u.get("type", "") == "scout" and scout_bonus > 0:
				vision += scout_bonus
			_mark_circle(state.visibility, u.get("pos_x", 0), u.get("pos_y", 0), vision)

static func _mark_circle(vis: Dictionary, cx: int, cy: int, r: int) -> void:
	var r2: int = r * r
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r2:
				vis["%d,%d" % [cx + dx, cy + dy]] = true

static func is_visible(state, x: int, y: int) -> bool:
	return state.visibility.has("%d,%d" % [x, y])
