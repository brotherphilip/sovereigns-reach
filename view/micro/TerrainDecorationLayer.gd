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

# Decorations (trees/mountains/rocks) are the heaviest layer — thousands of
# multi-polygon sprites. They're also illegible when zoomed far out, so we hide
# the whole layer below this zoom to keep zoomed-out performance smooth (the GPU
# then skips all those draws). Hiding a cached canvas item does NOT re-run _draw.
const DECOR_MIN_ZOOM: float = 0.55

var _camera: Camera2D = null
var _map_w:  int      = 200
var _map_h:  int      = 200

func _ready() -> void:
	var gs: Vector2i = GameState.get_grid_size()
	_map_w = gs.x
	_map_h = gs.y
	set_process(true)
	queue_redraw()  # paint decorations once

func set_camera(cam: Camera2D) -> void:
	_camera = cam

func _process(_delta: float) -> void:
	if _camera == null:
		return
	var want_visible: bool = _camera.zoom.x >= DECOR_MIN_ZOOM
	if want_visible != visible:
		visible = want_visible

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	for gy in range(_map_h):
		for gx in range(_map_w):
			_draw_decor(gx, gy)

# Deterministic per-tile pseudo-random value in [0,1).
func _h(gx: int, gy: int, salt: int) -> float:
	var n: float = sin(float(gx) * 127.1 + float(gy) * 311.7 + float(salt) * 74.7) * 43758.5453
	return n - floor(n)

func _draw_decor(gx: int, gy: int) -> void:
	var terrain: int = GameState.get_terrain_at(gx, gy)
	var cx: float = (gx - gy) * HALF_W
	var cy: float = (gx + gy) * HALF_H
	match terrain:
		T_FOREST:   _draw_forest(cx, cy, gx, gy)
		T_MOUNTAIN: _draw_mountain(cx, cy, gx, gy)
		T_ROCK:     _draw_rock(cx, cy, gx, gy)
		T_RIVER:    _draw_river(cx, cy)
		T_COASTAL:  _draw_coastal(cx, cy)

# A small cluster of 1–3 varied trees per forest tile → dense, organic woods.
func _draw_forest(cx: float, cy: float, gx: int, gy: int) -> void:
	var count: int = 1 + int(_h(gx, gy, 1) * 3.0)
	for i in range(count):
		var ox: float = (_h(gx, gy, 10 + i) - 0.5) * 24.0
		var oy: float = (_h(gx, gy, 20 + i) - 0.5) * 12.0
		var s: float  = 0.7 + _h(gx, gy, 30 + i) * 0.7
		var hue: float = _h(gx, gy, 40 + i)
		_draw_one_tree(cx + ox, cy + oy, s, hue)

# ── Decorations ───────────────────────────────────────────────────────────────

# A single leafy tree (rounded overlapping canopy) at scale s, green hue 0..1.
func _draw_one_tree(cx: float, cy: float, s: float, hue: float) -> void:
	draw_rect(Rect2(cx - 1.6 * s, cy - 4.0 * s, 3.2 * s, 9.0 * s), Color(0.40, 0.26, 0.14))
	var dark: Color = Color(0.10, 0.34, 0.14).lerp(Color(0.17, 0.43, 0.13), hue)
	var lite: Color = dark.lightened(0.16)
	draw_circle(Vector2(cx, cy - 9.0 * s), 8.0 * s, dark)
	draw_circle(Vector2(cx - 3.0 * s, cy - 13.0 * s), 6.0 * s, dark)
	draw_circle(Vector2(cx + 3.0 * s, cy - 13.0 * s), 6.0 * s, lite)
	draw_circle(Vector2(cx, cy - 18.0 * s), 5.0 * s, lite)

# Solid shaded mountain mass (lit + shadow face + snow). Clustered tiles merge
# into a continuous massif.
func _draw_mountain(cx: float, cy: float, gx: int, gy: int) -> void:
	var h: float = 30.0 + _h(gx, gy, 2) * 18.0
	var w: float = 18.0 + _h(gx, gy, 3) * 6.0
	var baseL := Vector2(cx - w, cy + 5.0)
	var baseR := Vector2(cx + w, cy + 5.0)
	var peak  := Vector2(cx + (_h(gx, gy, 4) - 0.5) * 8.0, cy - h)
	var mid   := Vector2(cx, cy + 3.0)
	draw_colored_polygon(PackedVector2Array([baseL, baseR, Vector2(cx, cy + 9.0)]), Color(0, 0, 0, 0.16))
	draw_colored_polygon(PackedVector2Array([peak, baseR, mid]), Color(0.40, 0.40, 0.46))  # shadow face
	draw_colored_polygon(PackedVector2Array([peak, baseL, mid]), Color(0.57, 0.57, 0.63))  # lit face
	var snow_y: float = peak.y + h * 0.30
	draw_colored_polygon(PackedVector2Array([
		peak, Vector2(peak.x + w * 0.30, snow_y), Vector2(peak.x - w * 0.30, snow_y),
	]), Color(0.95, 0.96, 1.0, 0.95))
	draw_polyline(PackedVector2Array([baseL, peak, baseR]), Color(0.22, 0.22, 0.27, 0.7), 1.0)

# Solid grey boulder mound (impassable rock).
func _draw_rock(cx: float, cy: float, gx: int, gy: int) -> void:
	var s: float = 0.8 + _h(gx, gy, 5) * 0.6
	var col := Color(0.46, 0.45, 0.49)
	draw_circle(Vector2(cx, cy + 4.0), 7.0 * s, Color(0, 0, 0, 0.15))  # ground shadow
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 9.0 * s, cy + 2.0), Vector2(cx - 5.0 * s, cy - 7.0 * s),
		Vector2(cx + 3.0 * s, cy - 8.0 * s), Vector2(cx + 9.0 * s, cy - 1.0),
		Vector2(cx + 5.0 * s, cy + 5.0), Vector2(cx - 4.0 * s, cy + 5.0),
	]), col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 3.0 * s, cy - 4.0 * s), Vector2(cx + 2.0 * s, cy - 6.0 * s),
		Vector2(cx + 1.0 * s, cy - 1.0),
	]), col.lightened(0.20))
	draw_polyline(PackedVector2Array([
		Vector2(cx - 9.0 * s, cy + 2.0), Vector2(cx - 5.0 * s, cy - 7.0 * s),
		Vector2(cx + 3.0 * s, cy - 8.0 * s), Vector2(cx + 9.0 * s, cy - 1.0),
	]), Color(0.25, 0.25, 0.29, 0.6), 0.8)

func _draw_river(cx: float, cy: float) -> void:
	var col: Color = Color(0.55, 0.75, 1.0, 0.55)
	draw_arc(Vector2(cx - 4.0, cy + 2.0), 7.0,  0.1 * PI, 0.9 * PI, 12, col, 1.8)
	draw_arc(Vector2(cx + 4.0, cy - 2.0), 7.0,  1.1 * PI, 1.9 * PI, 12, col, 1.8)

func _draw_coastal(cx: float, cy: float) -> void:
	draw_arc(Vector2(cx, cy + 4.0), 12.0, 0.15 * PI, 0.85 * PI, 14,
		Color(0.80, 0.88, 1.0, 0.45), 2.5)
