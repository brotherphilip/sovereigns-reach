extends Node2D
# Animated river/water surface. Draws every water tile (RIVER / COASTAL) once as
# iso diamonds with the water_flow shader. The mesh is static — built a single time
# — and the GPU animates it via TIME, so it costs ~nothing per frame (no CPU redraw,
# off-screen pixels are clipped). Each tile's vertex colour bakes the local downstream
# flow direction (computed from the channel's shape) so the current follows the bends
# while running generally north→south.

const HALF_W: float = 32.0
const HALF_H: float = 16.0

const T_GRASS := 0
const T_RIVER := 3
const T_COASTAL := 8

var _built: bool = false

func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://view/micro/water_flow.gdshader")
	# Child order (added after terrain, before decor) keeps it above the flat water
	# tiles and below trees/buildings — no z_index override needed.

func _is_water(gx: int, gy: int) -> bool:
	var t: int = GameState.get_terrain_at(gx, gy)
	return t == T_RIVER or t == T_COASTAL

# Local downstream direction in screen space, baked into vertex colour. Rivers flow
# north→south (+gy), so we follow the centroid of the south-side water neighbours;
# where the channel bends, that centroid leans east/west and the flow bends with it.
func _flow_color(gx: int, gy: int) -> Color:
	var south := Vector2.ZERO
	var n: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if dy > 0 and _is_water(gx + dx, gy + dy):
				south += Vector2(dx, dy)
				n += 1
	var grid_dir := Vector2(0, 1) if n == 0 else (south / float(n))
	# Grid → iso screen direction (HALF_H/HALF_W = 0.5).
	var scr := Vector2(grid_dir.x - grid_dir.y, (grid_dir.x + grid_dir.y) * 0.5)
	if scr.length() < 0.001:
		scr = Vector2(-0.894, 0.447)  # default iso-south
	scr = scr.normalized()
	var type_flag: float = 1.0 if GameState.get_terrain_at(gx, gy) == T_COASTAL else 0.0
	return Color(scr.x * 0.5 + 0.5, scr.y * 0.5 + 0.5, type_flag, 1.0)

func _draw() -> void:
	var gs: Vector2i = GameState.get_grid_size()
	for gy in range(gs.y):
		for gx in range(gs.x):
			if not _is_water(gx, gy):
				continue
			var cx: float = (gx - gy) * HALF_W
			var cy: float = (gx + gy) * HALF_H
			var pts := PackedVector2Array([
				Vector2(cx, cy - HALF_H), Vector2(cx + HALF_W, cy),
				Vector2(cx, cy + HALF_H), Vector2(cx - HALF_W, cy),
			])
			var col: Color = _flow_color(gx, gy)
			draw_polygon(pts, PackedColorArray([col, col, col, col]))
	_built = true
