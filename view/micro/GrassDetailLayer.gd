extends Node2D
# Overlays fine grass-blade texture onto the green ground tiles (GRASS / VALLEY / MARSH) by
# drawing them once as iso diamonds with the grass_detail shader (multiply blend). The flat
# TerrainChunk underneath supplies the season/biome colour; this adds the turf detail on top.
# Static mesh (built once), GPU-sampled — ~no per-frame cost; off-screen chunks are culled.
# Sits above terrain, below water/decor/buildings (added in that child order).

const HALF_W: float = 32.0
const HALF_H: float = 16.0

# Below this zoom the blade texture is sub-pixel — illegible — so the whole layer hides. This
# single canvas item paints every green tile at once (no per-chunk culling), so dropping it when
# zoomed out removes tens of thousands of polygons from the frames that lag most. Matches the
# decor/tree LOD tier (TerrainDecorationLayer 0.55, TreeLayer 0.45) so detail fades together.
const DETAIL_MIN_ZOOM: float = 0.55

# Terrains that read as green ground and get blade detail (not water/rock/road/mountain).
# FOREST is included too: its ground is painted as grass (trees drawn on top by TreeLayer),
# so the turf under the trees gets the same blade texture as the open fields.
const DETAIL_TERRAIN: Array = [0, 1, 4, 7]   # GRASS, FOREST, MARSH, VALLEY

var _camera: Camera2D = null

func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://view/micro/grass_detail.gdshader")
	material.set_shader_parameter("grass_tex", preload("res://view/micro/textures/grass_detail.png"))
	material.set_shader_parameter("strength", 0.85)   # crisper blade detail so grass reads as grass (not over-darkened)
	set_process(true)
	# Repaint when a building is placed/removed so freshly-stamped farmland tiles drop their grass
	# blades (the field renders its own crop in TerrainChunk).
	EventBus.building_placed.connect(func(_p, _t, _x, _y, _b): queue_redraw())
	EventBus.building_demolished.connect(func(_p, _b): queue_redraw())

func set_camera(cam: Camera2D) -> void:
	_camera = cam

func _process(_delta: float) -> void:
	if _camera == null:
		return
	var want_visible: bool = _camera.zoom.x >= DETAIL_MIN_ZOOM
	if want_visible != visible:
		visible = want_visible

func _draw() -> void:
	# One batched triangle array for every green tile (the shader samples by world position, so
	# no per-poly UVs are needed). The old per-tile draw_colored_polygon meant ~one draw call per
	# green tile — tens of thousands — all in this single uncullable node. This is now one call.
	var gs: Vector2i = GameState.get_grid_size()
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	var base: int = 0
	for gy in range(gs.y):
		for gx in range(gs.x):
			if GameState.get_terrain_at(gx, gy) not in DETAIL_TERRAIN:
				continue
			if GameState.get_field_crop_at(gx, gy) != 0:
				continue   # farmland tiles render their own crop (TerrainChunk) — no grass blades
			var cx: float = (gx - gy) * HALF_W
			var cy: float = (gx + gy) * HALF_H
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
