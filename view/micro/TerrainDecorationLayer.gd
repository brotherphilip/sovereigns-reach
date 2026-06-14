extends Node2D
# Renders static terrain decorations (trees, peaks, rocks, water) above the iso
# tile grid but below buildings. Terrain never changes at runtime, so the whole
# map is painted ONCE and cached — it no longer repaints every simulation tick
# (which was redrawing thousands of decorations 20×/sec and helped cause the
# zoom-out lag). Terrain enum matches WorldGrid.Terrain (0-10).

const HALF_W: float = 32.0
const HALF_H: float = 16.0

# Terrain enum values that get decorations
const T_FOREST:   int = 1
const T_MOUNTAIN: int = 2
const T_RIVER:    int = 3
const T_ROCK:     int = 5
const T_COASTAL:  int = 8

var _camera: Camera2D = null   # kept for API compatibility (culling no longer needed)
var _map_w:  int      = 200
var _map_h:  int      = 200

func _ready() -> void:
	var gs: Vector2i = GameState.get_grid_size()
	_map_w = gs.x
	_map_h = gs.y
	queue_redraw()  # paint decorations once

func set_camera(cam: Camera2D) -> void:
	_camera = cam

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	for gy in range(_map_h):
		for gx in range(_map_w):
			_draw_decor(gx, gy)

func _draw_decor(gx: int, gy: int) -> void:
	var terrain: int = GameState.get_terrain_at(gx, gy)
	var cx: float = (gx - gy) * HALF_W
	var cy: float = (gx + gy) * HALF_H
	match terrain:
		T_FOREST:   _draw_tree(cx, cy)
		T_MOUNTAIN: _draw_mountain(cx, cy)
		T_ROCK:     _draw_rock(cx, cy)
		T_RIVER:    _draw_river(cx, cy)
		T_COASTAL:  _draw_coastal(cx, cy)

# ── Decorations ───────────────────────────────────────────────────────────────

func _draw_tree(cx: float, cy: float) -> void:
	# Brown trunk
	draw_rect(Rect2(cx - 2.0, cy - 4.0, 4.0, 8.0), Color(0.45, 0.28, 0.14))
	# Lower canopy tier
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx,       cy - 16.0),
		Vector2(cx + 10.0, cy - 2.0),
		Vector2(cx - 10.0, cy - 2.0),
	]), Color(0.15, 0.45, 0.18))
	# Upper canopy tier (brighter)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx,       cy - 26.0),
		Vector2(cx + 6.0,  cy - 14.0),
		Vector2(cx - 6.0,  cy - 14.0),
	]), Color(0.20, 0.55, 0.22))
	# Canopy outline
	draw_polyline(PackedVector2Array([
		Vector2(cx,       cy - 26.0),
		Vector2(cx + 6.0,  cy - 14.0),
		Vector2(cx - 6.0,  cy - 14.0),
		Vector2(cx,       cy - 26.0),
	]), Color(0.10, 0.32, 0.12, 0.6), 0.8)

func _draw_mountain(cx: float, cy: float) -> void:
	# Left flank (drawn first, appears behind)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 10.0, cy),
		Vector2(cx - 4.0,  cy - 20.0),
		Vector2(cx + 4.0,  cy - 14.0),
		Vector2(cx + 2.0,  cy),
	]), Color(0.48, 0.48, 0.50))
	# Main peak
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 8.0, cy),
		Vector2(cx,       cy - 28.0),
		Vector2(cx + 8.0, cy),
		Vector2(cx + 4.0, cy + 2.0),
		Vector2(cx - 4.0, cy + 2.0),
	]), Color(0.58, 0.58, 0.60))
	# Snow cap
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx,      cy - 28.0),
		Vector2(cx + 5.0, cy - 18.0),
		Vector2(cx - 5.0, cy - 18.0),
	]), Color(0.96, 0.97, 1.00, 0.90))
	# Peak outline
	draw_polyline(PackedVector2Array([
		Vector2(cx - 8.0, cy),
		Vector2(cx,       cy - 28.0),
		Vector2(cx + 8.0, cy),
	]), Color(0.30, 0.30, 0.32, 0.7), 0.8)

func _draw_rock(cx: float, cy: float) -> void:
	# Three small irregular quads scattered around centre
	var col: Color = Color(0.42, 0.40, 0.40)
	var lit: Color = col.lightened(0.15)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 8.0, cy - 2.0),
		Vector2(cx - 3.0, cy - 6.0),
		Vector2(cx + 1.0, cy - 2.0),
		Vector2(cx - 3.0, cy + 1.0),
	]), col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx + 2.0, cy - 1.0),
		Vector2(cx + 8.0, cy - 5.0),
		Vector2(cx + 9.0, cy + 1.0),
		Vector2(cx + 4.0, cy + 3.0),
	]), lit)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 2.0, cy + 2.0),
		Vector2(cx + 3.0, cy),
		Vector2(cx + 3.0, cy + 5.0),
		Vector2(cx - 2.0, cy + 6.0),
	]), col.darkened(0.1))

func _draw_river(cx: float, cy: float) -> void:
	var col: Color = Color(0.55, 0.75, 1.0, 0.55)
	draw_arc(Vector2(cx - 4.0, cy + 2.0), 7.0,  0.1 * PI, 0.9 * PI, 12, col, 1.8)
	draw_arc(Vector2(cx + 4.0, cy - 2.0), 7.0,  1.1 * PI, 1.9 * PI, 12, col, 1.8)

func _draw_coastal(cx: float, cy: float) -> void:
	draw_arc(Vector2(cx, cy + 4.0), 12.0, 0.15 * PI, 0.85 * PI, 14,
		Color(0.80, 0.88, 1.0, 0.45), 2.5)
