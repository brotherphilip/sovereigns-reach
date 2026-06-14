extends Node2D
# Terrain renderer. The map is split into a grid of TerrainChunk canvas items so
# the 2D renderer culls off-screen chunks — zoomed in, only the few visible chunks
# are drawn each frame (a single whole-map canvas item was re-submitting all ~40k
# tiles every frame regardless of zoom, which caused the lag at every zoom level).
# Terrain is static, so each chunk paints once. The build-mode hover highlight is a
# separate lightweight overlay so it never repaints the terrain.

const TILE_W: int = 64
const TILE_H: int = 32
const HALF_W: float = TILE_W * 0.5
const HALF_H: float = TILE_H * 0.5
const CHUNK: int = 16   # tiles per chunk side

const HoverOverlay = preload("res://view/micro/GridHoverOverlay.gd")
const TerrainChunk = preload("res://view/micro/TerrainChunk.gd")

var _camera: Camera2D = null   # kept for API compatibility
var _map_w: int = 200
var _map_h: int = 200
var _hover: Node2D = null
var _chunks: Array = []

func _ready() -> void:
	var gs: Vector2i = GameState.get_grid_size()
	_map_w = gs.x
	_map_h = gs.y
	for cy in range(0, _map_h, CHUNK):
		for cx in range(0, _map_w, CHUNK):
			var ch := TerrainChunk.new()
			add_child(ch)
			ch.setup(cx, cy, mini(cx + CHUNK, _map_w), mini(cy + CHUNK, _map_h))
			_chunks.append(ch)
	_hover = HoverOverlay.new()
	_hover.z_index = 1
	add_child(_hover)

func set_camera(cam: Camera2D) -> void:
	_camera = cam

func set_hover_tile(gx: int, gy: int, valid: bool) -> void:
	if _hover != null:
		_hover.set_tile(gx, gy, valid)

func clear_hover_tile() -> void:
	if _hover != null:
		_hover.clear_tile()

func refresh() -> void:
	for ch in _chunks:
		ch.queue_redraw()

# Convert grid position to iso screen position (center of tile)
static func grid_to_screen(gx: int, gy: int) -> Vector2:
	return Vector2((gx - gy) * HALF_W, (gx + gy) * HALF_H)

# Convert screen position to approximate grid tile
static func screen_to_grid(sx: float, sy: float) -> Vector2i:
	var gx: int = roundi(sx / HALF_W * 0.5 + sy / HALF_H * 0.5)
	var gy: int = roundi(sy / HALF_H * 0.5 - sx / HALF_W * 0.5)
	return Vector2i(gx, gy)
