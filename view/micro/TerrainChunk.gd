extends Node2D
# One CHUNK×CHUNK block of terrain tiles, painted once. Splitting the map into
# many small canvas items lets Godot's 2D renderer cull the off-screen chunks —
# so zoomed in, only the handful of visible chunks are drawn each frame instead
# of the whole 200×200 map. Terrain is static, so each chunk paints once.

const HALF_W: float = 32.0
const HALF_H: float = 16.0

const SeasonSystem = preload("res://simulation/world/SeasonSystem.gd")

# Vegetation terrains that recolour with the season (grass/forest/marsh/valley).
const VEG_TERRAIN: Array = [0, 1, 4, 7]

const TERRAIN_COLORS: Array = [
	Color(0.38, 0.71, 0.34),  # 0 GRASS
	Color(0.12, 0.40, 0.17),  # 1 FOREST
	Color(0.56, 0.57, 0.64),  # 2 MOUNTAIN
	Color(0.16, 0.50, 0.93),  # 3 RIVER
	Color(0.44, 0.52, 0.24),  # 4 MARSH
	Color(0.43, 0.43, 0.48),  # 5 ROCK
	Color(0.66, 0.43, 0.26),  # 6 ORE_VEIN
	Color(0.58, 0.82, 0.40),  # 7 VALLEY
	Color(0.33, 0.73, 0.88),  # 8 COASTAL
	Color(0.84, 0.71, 0.47),  # 9 ROAD
	Color(0.41, 0.33, 0.28),  # 10 RUIN
]

var _x0: int = 0
var _y0: int = 0
var _x1: int = 0
var _y1: int = 0

func _ready() -> void:
	# Terrain is otherwise static, but the season repaints the land and the player can
	# lay paths at runtime — so listen and repaint when our cells change.
	if EventBus.has_signal("season_changed"):
		EventBus.season_changed.connect(func(_s, _n): queue_redraw())
	if EventBus.has_signal("terrain_painted"):
		EventBus.terrain_painted.connect(func(x, y):
			if x >= _x0 and x < _x1 and y >= _y0 and y < _y1:
				queue_redraw())

func setup(x0: int, y0: int, x1: int, y1: int) -> void:
	_x0 = x0; _y0 = y0; _x1 = x1; _y1 = y1
	queue_redraw()

func _draw() -> void:
	var season: int = int(GameState.world.get("season", SeasonSystem.Season.SUMMER))
	for gy in range(_y0, _y1):
		for gx in range(_x0, _x1):
			var t: int = GameState.get_terrain_at(gx, gy)
			var fill: Color = _season_fill(t, TERRAIN_COLORS[mini(t, TERRAIN_COLORS.size() - 1)], season)
			var cx: float = (gx - gy) * HALF_W
			var cy: float = (gx + gy) * HALF_H
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx, cy - HALF_H), Vector2(cx + HALF_W, cy),
				Vector2(cx, cy + HALF_H), Vector2(cx - HALF_W, cy),
			]), fill)

# Recolour a tile for the season: vegetation greens up in spring, deepens in summer,
# turns gold in autumn and is blanketed pale in winter; rock/water barely shift.
func _season_fill(t: int, base: Color, season: int) -> Color:
	if t not in VEG_TERRAIN:
		if season == SeasonSystem.Season.WINTER:
			return base.lerp(Color(0.80, 0.85, 0.92), 0.12)
		return base
	match season:
		SeasonSystem.Season.SPRING: return base.lerp(Color(0.55, 0.82, 0.42), 0.30)
		SeasonSystem.Season.SUMMER: return base
		SeasonSystem.Season.AUTUMN: return base.lerp(Color(0.74, 0.56, 0.24), 0.40)
		SeasonSystem.Season.WINTER: return base.lerp(Color(0.85, 0.88, 0.94), 0.58)
	return base
