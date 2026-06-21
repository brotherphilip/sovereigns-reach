extends Node2D
# Overlays the same fine grass-blade texture onto the RAISED terrace tops of the mountains
# as GrassDetailLayer puts on the open ground — so the cliff's grassy steps read as real turf
# matching the fields, not flat green caps. Multiply-blend (the grass_detail shader) preserves
# each terrace's tint. Drawn once, just above the cliff renderer (DecorChunk) so it sits on the
# terrace grass the renderer laid down.

const HALF_W: float = 32.0
const HALF_H: float = 16.0

# Same sub-pixel LOD cut as GrassDetailLayer: hide the whole-map blade overlay when zoomed out,
# where the texture is illegible and the single uncullable canvas item just burns frame time.
const DETAIL_MIN_ZOOM: float = 0.55

const MountainHeight = preload("res://view/micro/MountainHeight.gd")

var _camera: Camera2D = null

func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://view/micro/grass_detail.gdshader")
	material.set_shader_parameter("grass_tex", preload("res://view/micro/textures/grass_detail.png"))
	material.set_shader_parameter("strength", 0.7)   # match the ground grass detail
	set_process(true)

func set_camera(cam: Camera2D) -> void:
	_camera = cam

func _process(_delta: float) -> void:
	if _camera == null:
		return
	var want_visible: bool = _camera.zoom.x >= DETAIL_MIN_ZOOM
	if want_visible != visible:
		visible = want_visible

func _draw() -> void:
	# Batched into a single draw call (see GrassDetailLayer) — the per-tile draw_colored_polygon
	# was one draw call per mountain terrace tile in this single uncullable node.
	var gs: Vector2i = GameState.get_grid_size()
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	var base: int = 0
	for gy in range(gs.y):
		for gx in range(gs.x):
			if not MountainHeight.is_mountain(gx, gy):
				continue
			var e: float = MountainHeight.elevation(gx, gy)
			var cx: float = (gx - gy) * HALF_W
			var cy: float = (gx + gy) * HALF_H - e
			points.append(Vector2(cx, cy - HALF_H))
			points.append(Vector2(cx + HALF_W, cy))
			points.append(Vector2(cx, cy + HALF_H))
			points.append(Vector2(cx - HALF_W, cy))
			indices.append(base); indices.append(base + 1); indices.append(base + 2)
			indices.append(base); indices.append(base + 2); indices.append(base + 3)
			base += 4
	if points.is_empty():
		return
	var colors := PackedColorArray()
	colors.resize(points.size())
	colors.fill(Color(1, 1, 1, 1))
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), indices, points, colors)
