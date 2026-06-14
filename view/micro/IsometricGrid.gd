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

# Terrain palette (WorldGrid.Terrain enum 0–10) — vivid, high-contrast tones.
const TERRAIN_COLORS: Array = [
	Color(0.38, 0.71, 0.34),  # 0 GRASS — lush meadow green
	Color(0.12, 0.40, 0.17),  # 1 FOREST — deep green
	Color(0.56, 0.57, 0.64),  # 2 MOUNTAIN — cool slate
	Color(0.16, 0.50, 0.93),  # 3 RIVER — vivid blue
	Color(0.44, 0.52, 0.24),  # 4 MARSH — olive
	Color(0.43, 0.43, 0.48),  # 5 ROCK — grey
	Color(0.66, 0.43, 0.26),  # 6 ORE_VEIN — rust
	Color(0.58, 0.82, 0.40),  # 7 VALLEY — bright lush
	Color(0.33, 0.73, 0.88),  # 8 COASTAL — shallow water
	Color(0.84, 0.71, 0.47),  # 9 ROAD — sand path
	Color(0.41, 0.33, 0.28),  # 10 RUIN — char brown
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
	# Flat, uniform fill per terrain type — no per-tile variation (that created a
	# visible grid that shimmered/"jumped between cells" while panning).
	var terrain: int = GameState.get_terrain_at(gx, gy)
	var fill: Color = TERRAIN_COLORS[mini(terrain, TERRAIN_COLORS.size() - 1)]
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
