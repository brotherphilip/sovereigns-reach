extends Node2D
# Renders the world terrain as an isometric grid using _draw().
# Reads terrain data from GameState and redraws when the tick fires.
# Only draws tiles visible within the camera viewport for performance.

const TILE_W: int = 64
const TILE_H: int = 32
const HALF_W: float = TILE_W * 0.5
const HALF_H: float = TILE_H * 0.5

# Terrain colors (matching WorldGrid.Terrain enum 0–10)
const TERRAIN_COLORS: Array = [
	Color(0.49, 0.72, 0.49),  # 0 GRASS
	Color(0.18, 0.42, 0.19),  # 1 FOREST
	Color(0.55, 0.55, 0.55),  # 2 MOUNTAIN
	Color(0.29, 0.56, 0.93),  # 3 RIVER
	Color(0.55, 0.60, 0.30),  # 4 MARSH
	Color(0.34, 0.34, 0.34),  # 5 ROCK
	Color(0.61, 0.37, 0.25),  # 6 ORE_VEIN
	Color(0.66, 0.83, 0.55),  # 7 VALLEY
	Color(0.42, 0.70, 0.85),  # 8 COASTAL
	Color(0.83, 0.71, 0.52),  # 9 ROAD
	Color(0.40, 0.33, 0.27),  # 10 RUIN
]
const TERRAIN_BORDER: Array = [
	Color(0.36, 0.56, 0.36),  # GRASS border
	Color(0.12, 0.28, 0.13),  # FOREST border
	Color(0.38, 0.38, 0.38),  # MOUNTAIN border
	Color(0.20, 0.40, 0.70),  # RIVER border
	Color(0.38, 0.42, 0.20),  # MARSH border
	Color(0.22, 0.22, 0.22),  # ROCK border
	Color(0.42, 0.24, 0.16),  # ORE border
	Color(0.48, 0.64, 0.38),  # VALLEY border
	Color(0.28, 0.52, 0.68),  # COASTAL border
	Color(0.62, 0.52, 0.36),  # ROAD border
	Color(0.25, 0.20, 0.15),  # RUIN border
]

var _camera: Camera2D = null
var _map_w: int = 200
var _map_h: int = 200
var _last_cam_pos: Vector2 = Vector2.INF
var _last_cam_zoom: float = -1.0

# Hover highlight state (build-mode cursor)
var _hover_active: bool  = false
var _hover_gx:     int   = 0
var _hover_gy:     int   = 0
var _hover_valid:  bool  = true

func set_hover_tile(gx: int, gy: int, valid: bool) -> void:
	_hover_active = true
	_hover_gx     = gx
	_hover_gy     = gy
	_hover_valid  = valid
	queue_redraw()

func clear_hover_tile() -> void:
	_hover_active = false
	queue_redraw()

func _ready() -> void:
	var gs: Vector2i = GameState.get_grid_size()
	_map_w = gs.x
	_map_h = gs.y
	EventBus.simulation_tick.connect(_on_tick)

func _on_tick(tick: int) -> void:
	# Terrain is static; redraws are driven by camera movement (_process below).
	# Keep a low-frequency safety-net redraw in case terrain ever changes.
	if tick % 30 == 0:
		queue_redraw()

func _process(_delta: float) -> void:
	if _camera == null:
		return
	if _camera.position != _last_cam_pos or _camera.zoom.x != _last_cam_zoom:
		_last_cam_pos = _camera.position
		_last_cam_zoom = _camera.zoom.x
		queue_redraw()

func set_camera(cam: Camera2D) -> void:
	_camera = cam

func _draw() -> void:
	if _camera == null:
		_draw_range(0, 0, _map_w, _map_h)
		return

	# Calculate visible tile range based on camera
	var vp_size: Vector2 = get_viewport_rect().size
	var cam_pos: Vector2 = _camera.position
	var cam_zoom: float  = _camera.zoom.x
	var half_w: float    = (vp_size.x * 0.5) / cam_zoom + TILE_W * 2
	var half_h: float    = (vp_size.y * 0.5) / cam_zoom + TILE_H * 2

	# Corners of visible area in iso-screen space
	var left_sx: float  = cam_pos.x - half_w
	var right_sx: float = cam_pos.x + half_w
	var top_sy: float   = cam_pos.y - half_h
	var bot_sy: float   = cam_pos.y + half_h

	# Approximate tile range: sx = (gx-gy)*HALF_W, sy = (gx+gy)*HALF_H
	var margin: int = 3
	var min_diff: int = floori(left_sx  / HALF_W) - margin
	var max_diff: int = ceili(right_sx  / HALF_W) + margin
	var min_sum: int  = floori(top_sy   / HALF_H) - margin
	var max_sum: int  = ceili(bot_sy    / HALF_H) + margin

	# Iterate: gx = (diff + sum) / 2, gy = (sum - diff) / 2
	for s in range(min_sum, max_sum + 1):
		for d in range(min_diff, max_diff + 1):
			if (s + d) % 2 != 0:
				continue
			var gx: int = (d + s) / 2
			var gy: int = (s - d) / 2
			if gx < 0 or gx >= _map_w or gy < 0 or gy >= _map_h:
				continue
			_draw_tile(gx, gy)

	if _hover_active:
		_draw_hover_highlight()

func _draw_range(x0: int, y0: int, x1: int, y1: int) -> void:
	for gy in range(y0, y1):
		for gx in range(x0, x1):
			_draw_tile(gx, gy)

func _draw_tile(gx: int, gy: int) -> void:
	var terrain: int = GameState.get_terrain_at(gx, gy)
	var fill_color: Color = TERRAIN_COLORS[mini(terrain, TERRAIN_COLORS.size() - 1)]
	var border_color: Color = TERRAIN_BORDER[mini(terrain, TERRAIN_BORDER.size() - 1)]
	var cx: float = (gx - gy) * HALF_W
	var cy: float = (gx + gy) * HALF_H
	var pts := PackedVector2Array([
		Vector2(cx,        cy - HALF_H),
		Vector2(cx + HALF_W, cy),
		Vector2(cx,        cy + HALF_H),
		Vector2(cx - HALF_W, cy),
	])
	draw_colored_polygon(pts, fill_color)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
		border_color, 0.5)

# Convert grid position to iso screen position (center of tile)
static func grid_to_screen(gx: int, gy: int) -> Vector2:
	return Vector2((gx - gy) * HALF_W, (gx + gy) * HALF_H)

# Convert screen position to approximate grid tile
static func screen_to_grid(sx: float, sy: float) -> Vector2i:
	var gx: int = roundi(sx / HALF_W * 0.5 + sy / HALF_H * 0.5)
	var gy: int = roundi(sy / HALF_H * 0.5 - sx / HALF_W * 0.5)
	return Vector2i(gx, gy)

func _draw_hover_highlight() -> void:
	var cx: float = (_hover_gx - _hover_gy) * HALF_W
	var cy: float = (_hover_gx + _hover_gy) * HALF_H
	var pts := PackedVector2Array([
		Vector2(cx,          cy - HALF_H),
		Vector2(cx + HALF_W, cy),
		Vector2(cx,          cy + HALF_H),
		Vector2(cx - HALF_W, cy),
	])
	var fill_col: Color = Color(0.25, 1.0, 0.25, 0.18) if _hover_valid else Color(1.0, 0.20, 0.20, 0.20)
	var line_col: Color = Color(0.30, 1.0, 0.30, 0.85) if _hover_valid else Color(1.0, 0.25, 0.25, 0.85)
	draw_colored_polygon(pts, fill_col)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), line_col, 1.5)
