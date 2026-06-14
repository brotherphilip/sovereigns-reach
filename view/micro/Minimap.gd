extends Control
# Small viewport map showing terrain, buildings, units, and camera viewport.
# Click to pan camera to that location.

const MINIMAP_W: int = 180
const MINIMAP_H: int = 180
const MARGIN: int = 4

var _camera: Camera2D = null
var _map_w: int = 200
var _map_h: int = 200
var _minimap_size: Vector2 = Vector2(MINIMAP_W, MINIMAP_H)

func _ready() -> void:
	var gs: Vector2i = GameState.get_grid_size()
	_map_w = gs.x
	_map_h = gs.y
	size = Vector2(MINIMAP_W + MARGIN * 2, MINIMAP_H + MARGIN * 2)
	EventBus.simulation_tick.connect(_on_tick)
	set_process_input(true)

func _on_tick(_tick: int) -> void:
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _camera == null: return
		var local_pos: Vector2 = event.position - global_position
		if Rect2(Vector2(MARGIN, MARGIN), _minimap_size).has_point(local_pos):
			_pan_to_minimap_pos(local_pos - Vector2(MARGIN, MARGIN))
			get_viewport().set_input_as_handled()

func set_camera(cam: Camera2D) -> void:
	_camera = cam

func _pan_to_minimap_pos(minimap_coords: Vector2) -> void:
	if _camera == null: return
	var gx: float = minimap_coords.x / _minimap_size.x * _map_w
	var gy: float = minimap_coords.y / _minimap_size.y * _map_h
	var iso_pos: Vector2 = Vector2((gx - gy) * 32.0, (gx + gy) * 16.0)
	_camera.center_on(iso_pos)

func _draw() -> void:
	_draw_background()
	_draw_terrain()
	_draw_buildings()
	_draw_units()
	_draw_viewport_rect()
	_draw_border()

func _draw_background() -> void:
	var bg := Rect2(Vector2(MARGIN, MARGIN), _minimap_size)
	draw_rect(bg, Color(0.08, 0.10, 0.12, 0.95))

func _draw_border() -> void:
	var border_rect := Rect2(Vector2(MARGIN, MARGIN), _minimap_size)
	draw_rect(border_rect, Color(0.3, 0.3, 0.3, 1.0), false, 1.5)

func _draw_terrain() -> void:
	if GameState.world.is_empty(): return
	var terrain_grid: Array = GameState.world.get("terrain", [])
	if terrain_grid.is_empty(): return

	var scale_x: float = _minimap_size.x / _map_w
	var scale_y: float = _minimap_size.y / _map_h

	for gx in range(_map_w):
		for gy in range(_map_h):
			var idx: int = gy * _map_w + gx
			if idx >= terrain_grid.size(): continue
			var terrain_type: int = terrain_grid[idx]
			var col: Color = _get_terrain_color(terrain_type)
			var px: float = MARGIN + gx * scale_x
			var py: float = MARGIN + gy * scale_y
			draw_rect(Rect2(px, py, scale_x, scale_y), col)

func _get_terrain_color(terrain_type: int) -> Color:
	var colors: Array = [
		Color(0.49, 0.72, 0.49),  # GRASS
		Color(0.18, 0.42, 0.19),  # FOREST
		Color(0.55, 0.55, 0.55),  # MOUNTAIN
		Color(0.29, 0.56, 0.93),  # RIVER
		Color(0.55, 0.60, 0.30),  # MARSH
		Color(0.34, 0.34, 0.34),  # ROCK
		Color(0.61, 0.37, 0.25),  # ORE_VEIN
		Color(0.66, 0.83, 0.55),  # VALLEY
		Color(0.42, 0.70, 0.85),  # COASTAL
		Color(0.83, 0.71, 0.52),  # ROAD
		Color(0.40, 0.33, 0.27),  # RUIN
	]
	if terrain_type >= 0 and terrain_type < colors.size():
		return colors[terrain_type]
	return Color(0.5, 0.5, 0.5)

func _draw_buildings() -> void:
	if GameState.players.is_empty(): return
	var scale_x: float = _minimap_size.x / _map_w
	var scale_y: float = _minimap_size.y / _map_h

	for player in GameState.players:
		if not player is Dictionary: continue
		var buildings: Array = player.get("buildings", [])
		for bld in buildings:
			if not bld is Dictionary: continue
			var gx: int = bld.get("grid_x", 0)
			var gy: int = bld.get("grid_y", 0)
			var px: float = MARGIN + gx * scale_x
			var py: float = MARGIN + gy * scale_y
			var col: Color = Color(0.2, 0.8, 0.2, 0.8)
			draw_circle(px + scale_x * 0.5, py + scale_y * 0.5, 2.0, col)

	for faction in GameState.ai_factions:
		if not faction is Dictionary: continue
		var buildings: Array = faction.get("buildings", [])
		for bld in buildings:
			if not bld is Dictionary: continue
			var gx: int = bld.get("grid_x", 0)
			var gy: int = bld.get("grid_y", 0)
			var px: float = MARGIN + gx * scale_x
			var py: float = MARGIN + gy * scale_y
			var col: Color = Color(0.8, 0.2, 0.2, 0.8)
			draw_circle(px + scale_x * 0.5, py + scale_y * 0.5, 2.0, col)

func _draw_units() -> void:
	if GameState.players.is_empty(): return
	var scale_x: float = _minimap_size.x / _map_w
	var scale_y: float = _minimap_size.y / _map_h

	for player in GameState.players:
		if not player is Dictionary: continue
		var units: Array = player.get("units", [])
		for unit in units:
			if not unit is Dictionary: continue
			var gx: int = unit.get("grid_x", 0)
			var gy: int = unit.get("grid_y", 0)
			var px: float = MARGIN + gx * scale_x
			var py: float = MARGIN + gy * scale_y
			var col: Color = Color(0.4, 1.0, 0.4, 0.9)
			draw_circle(px + scale_x * 0.5, py + scale_y * 0.5, 1.5, col)

	for faction in GameState.ai_factions:
		if not faction is Dictionary: continue
		var units: Array = faction.get("units", [])
		for unit in units:
			if not unit is Dictionary: continue
			var gx: int = unit.get("grid_x", 0)
			var gy: int = unit.get("grid_y", 0)
			var px: float = MARGIN + gx * scale_x
			var py: float = MARGIN + gy * scale_y
			var col: Color = Color(1.0, 0.4, 0.4, 0.9)
			draw_circle(px + scale_x * 0.5, py + scale_y * 0.5, 1.5, col)

func _draw_viewport_rect() -> void:
	if _camera == null: return
	var scale_x: float = _minimap_size.x / _map_w
	var scale_y: float = _minimap_size.y / _map_h
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size == Vector2.ZERO:
		vp_size = Vector2(1280, 720)

	var cam_pos: Vector2 = _camera.position
	var cam_zoom: float = _camera.zoom.x
	var half_w: float = (vp_size.x * 0.5) / cam_zoom
	var half_h: float = (vp_size.y * 0.5) / cam_zoom

	# Corners of visible area in iso-screen space
	var left_sx: float = cam_pos.x - half_w
	var right_sx: float = cam_pos.x + half_w
	var top_sy: float = cam_pos.y - half_h
	var bottom_sy: float = cam_pos.y + half_h

	# Convert iso screen corners to grid coordinates
	# iso_pos = Vector2((gx - gy) * 32, (gx + gy) * 16)
	# Solving: sx = (gx - gy) * 32, sy = (gx + gy) * 16
	# gx = (sx / 32 + sy / 16) / 2
	# gy = (sy / 16 - sx / 32) / 2
	var tl_gx: float = (left_sx / 32.0 + top_sy / 16.0) * 0.5
	var tl_gy: float = (top_sy / 16.0 - left_sx / 32.0) * 0.5
	var tr_gx: float = (right_sx / 32.0 + top_sy / 16.0) * 0.5
	var tr_gy: float = (top_sy / 16.0 - right_sx / 32.0) * 0.5
	var br_gx: float = (right_sx / 32.0 + bottom_sy / 16.0) * 0.5
	var br_gy: float = (bottom_sy / 16.0 - right_sx / 32.0) * 0.5
	var bl_gx: float = (left_sx / 32.0 + bottom_sy / 16.0) * 0.5
	var bl_gy: float = (bottom_sy / 16.0 - left_sx / 32.0) * 0.5

	var corners: PackedVector2Array = [
		Vector2(MARGIN + tl_gx * scale_x, MARGIN + tl_gy * scale_y),
		Vector2(MARGIN + tr_gx * scale_x, MARGIN + tr_gy * scale_y),
		Vector2(MARGIN + br_gx * scale_x, MARGIN + br_gy * scale_y),
		Vector2(MARGIN + bl_gx * scale_x, MARGIN + bl_gy * scale_y),
	]
	draw_colored_polygon(corners, Color(0.8, 0.8, 0.2, 0.15))
	draw_polyline(PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]]),
		Color(0.8, 0.8, 0.2, 0.7), 1.5)
