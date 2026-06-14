extends Node2D
# Renders the world terrain as an isometric grid using _draw().
# Terrain is static, so the whole map is painted ONCE into this canvas item and
# cached by the renderer — panning/zooming no longer re-runs _draw (which, when
# zoomed out, used to rebuild ~40k polygons every frame and caused the lag).
# The build-mode hover highlight lives on a separate lightweight overlay so it
# can update without repainting the terrain.

const TILE_W: int = 64
const TILE_H: int = 32
const HALF_W: float = TILE_W * 0.5
const HALF_H: float = TILE_H * 0.5

const HoverOverlay = preload("res://view/micro/GridHoverOverlay.gd")

# Terrain palette (WorldGrid.Terrain enum 0–10) — cohesive, slightly richer tones.
const TERRAIN_COLORS: Array = [
	Color(0.46, 0.69, 0.42),  # 0 GRASS
	Color(0.20, 0.44, 0.23),  # 1 FOREST
	Color(0.53, 0.53, 0.57),  # 2 MOUNTAIN
	Color(0.26, 0.53, 0.86),  # 3 RIVER
	Color(0.47, 0.53, 0.31),  # 4 MARSH
	Color(0.40, 0.40, 0.43),  # 5 ROCK
	Color(0.60, 0.41, 0.29),  # 6 ORE_VEIN
	Color(0.62, 0.79, 0.49),  # 7 VALLEY
	Color(0.45, 0.74, 0.82),  # 8 COASTAL
	Color(0.80, 0.69, 0.49),  # 9 ROAD
	Color(0.39, 0.32, 0.27),  # 10 RUIN
]

var _camera: Camera2D = null   # kept for API compatibility (culling no longer needed)
var _map_w: int = 200
var _map_h: int = 200
var _hover: Node2D = null

func _ready() -> void:
	var gs: Vector2i = GameState.get_grid_size()
	_map_w = gs.x
	_map_h = gs.y
	_hover = HoverOverlay.new()
	_hover.z_index = 1
	add_child(_hover)
	queue_redraw()  # paint terrain once

func set_camera(cam: Camera2D) -> void:
	_camera = cam

# Build-mode hover highlight (delegated to the cheap overlay).
func set_hover_tile(gx: int, gy: int, valid: bool) -> void:
	if _hover != null:
		_hover.set_tile(gx, gy, valid)

func clear_hover_tile() -> void:
	if _hover != null:
		_hover.clear_tile()

# Repaint the terrain (only needed if terrain data ever changes at runtime).
func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	# Whole map, painted once. Filled tiles only (no per-tile borders) for a clean
	# flat-iso look and far fewer draw commands.
	for gy in range(_map_h):
		for gx in range(_map_w):
			_draw_tile(gx, gy)

func _draw_tile(gx: int, gy: int) -> void:
	var terrain: int = GameState.get_terrain_at(gx, gy)
	var base: Color = TERRAIN_COLORS[mini(terrain, TERRAIN_COLORS.size() - 1)]
	# Subtle deterministic per-tile variation so large fields don't look flat.
	var n: float = sin(float(gx) * 12.9898 + float(gy) * 78.233)
	n = n - floor(n)                      # fract → 0..1
	var shade: float = 0.94 + 0.12 * n    # ±6% brightness
	var fill := Color(base.r * shade, base.g * shade, base.b * shade, 1.0)
	var cx: float = (gx - gy) * HALF_W
	var cy: float = (gx + gy) * HALF_H
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, cy - HALF_H), Vector2(cx + HALF_W, cy),
		Vector2(cx, cy + HALF_H), Vector2(cx - HALF_W, cy),
	]), fill)

# Convert grid position to iso screen position (center of tile)
static func grid_to_screen(gx: int, gy: int) -> Vector2:
	return Vector2((gx - gy) * HALF_W, (gx + gy) * HALF_H)

# Convert screen position to approximate grid tile
static func screen_to_grid(sx: float, sy: float) -> Vector2i:
	var gx: int = roundi(sx / HALF_W * 0.5 + sy / HALF_H * 0.5)
	var gy: int = roundi(sy / HALF_H * 0.5 - sx / HALF_W * 0.5)
	return Vector2i(gx, gy)
