extends Control
# Renders the strategic world map via _draw().
# Accepts WorldMapController render lists; emits city_clicked(city_id).

signal city_clicked(city_id: int)

const WorldMapController = preload("res://view/worldmap/WorldMapController.gd")
const WorldMapData       = preload("res://simulation/world/WorldMapData.gd")

var _data: Dictionary = {}
var _hovered_city_id: int = -1

# Cached render lists rebuilt on apply_data
var _city_list:    Array = []
var _road_list:    Array = []
var _faction_list: Array = []
var _deposit_list: Array = []

func apply_data(world_map_data: Dictionary) -> void:
	_data         = world_map_data
	_city_list    = WorldMapController.get_city_render_list(_data)
	_road_list    = WorldMapController.get_road_render_list(_data)
	_faction_list = WorldMapController.get_faction_territory_list(_data)
	_deposit_list = WorldMapController.get_resource_deposit_list(_data)
	mouse_filter  = Control.MOUSE_FILTER_STOP
	queue_redraw()

func _draw() -> void:
	if _data.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.19, 0.10))
		return
	_draw_background()
	_draw_faction_territories()
	_draw_roads()
	_draw_resource_deposits()
	_draw_cities()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var city_id: int = WorldMapController.find_city_near(_data, event.position, 24.0)
		if city_id >= 0:
			city_clicked.emit(city_id)
	elif event is InputEventMouseMotion:
		var hov: int = WorldMapController.find_city_near(_data, event.position, 24.0)
		if hov != _hovered_city_id:
			_hovered_city_id = hov
			queue_redraw()

# ── Background ────────────────────────────────────────────────────────────────

const _BG_BLOBS: Array = [
	[0.12, 0.18, 200, 140, Color(0.80, 0.74, 0.55, 0.5)],
	[0.82, 0.10, 240, 100, Color(0.74, 0.68, 0.50, 0.5)],
	[0.50, 0.88, 280,  90, Color(0.78, 0.72, 0.52, 0.5)],
	[0.08, 0.72, 160, 140, Color(0.72, 0.66, 0.48, 0.5)],
	[0.75, 0.58, 210, 120, Color(0.82, 0.76, 0.56, 0.5)],
	[0.38, 0.25, 180,  80, Color(0.76, 0.70, 0.51, 0.5)],
	[0.90, 0.80, 150, 170, Color(0.70, 0.64, 0.46, 0.5)],
	[0.28, 0.65, 200, 110, Color(0.84, 0.78, 0.58, 0.4)],
	[0.62, 0.42, 140, 100, Color(0.77, 0.71, 0.53, 0.4)],
	[0.18, 0.45, 170,  80, Color(0.73, 0.67, 0.49, 0.5)],
	[0.55, 0.55, 310, 150, Color(0.71, 0.65, 0.47, 0.3)],
]

func _draw_background() -> void:
	# Warm parchment base
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.87, 0.80, 0.62))
	# Terrain variation blobs
	for blob in _BG_BLOBS:
		var cx: float  = blob[0] * size.x
		var cy: float  = blob[1] * size.y
		var rx: float  = blob[2]
		var ry: float  = blob[3]
		var col: Color = blob[4]
		_draw_ellipse_poly(cx, cy, rx, ry, col)
	# Vignette
	draw_rect(Rect2(0, 0, size.x, 30), Color(0.60, 0.50, 0.30, 0.3))
	draw_rect(Rect2(0, size.y - 30, size.x, 30), Color(0.60, 0.50, 0.30, 0.3))

func _draw_ellipse_poly(cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var SIDES: int = 10
	for i in range(SIDES):
		var a: float = TAU * float(i) / float(SIDES)
		pts.append(Vector2(cx + rx * cos(a), cy + ry * sin(a)))
	draw_colored_polygon(pts, col)

# ── Faction territories ────────────────────────────────────────────────────────

func _draw_faction_territories() -> void:
	for f in _faction_list:
		var col: Color = Color.from_string(f["color_hex"], Color.GRAY)
		col.a = 0.16
		draw_circle(f["center_pos"], f["radius"], col)
		# Faction name label near capital
		draw_string(ThemeDB.fallback_font, f["center_pos"] + Vector2(-40, f["radius"] + 14),
			f.get("name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color.from_string(f["color_hex"], Color.GRAY).lightened(0.2))

# ── Roads ─────────────────────────────────────────────────────────────────────

const ROAD_COLOR: Color = Color(0.55, 0.40, 0.25, 0.70)

func _draw_roads() -> void:
	for r in _road_list:
		var fp: Vector2 = r["from_pos"]
		var tp: Vector2 = r["to_pos"]
		# Slight curve via perpendicular midpoint offset
		var mid: Vector2 = (fp + tp) * 0.5
		var perp: Vector2 = (tp - fp).orthogonal().normalized() * 14.0
		mid += perp
		draw_polyline(PackedVector2Array([fp, mid, tp]), ROAD_COLOR, 1.5)

# ── Resource deposits ─────────────────────────────────────────────────────────

func _draw_resource_deposits() -> void:
	for d in _deposit_list:
		var p: Vector2  = d["pos"]
		var t: String   = d["type"]
		match t:
			"wood":  _draw_wood_icon(p)
			"stone": _draw_stone_icon(p)
			"iron":  _draw_iron_icon(p)
			"food":  _draw_food_icon(p)

func _draw_wood_icon(p: Vector2) -> void:
	# Crossed axe — two diagonal lines
	var col := Color(0.40, 0.26, 0.12)
	draw_line(p + Vector2(-5, -5), p + Vector2(5, 5),  col, 2.0)
	draw_line(p + Vector2(5,  -5), p + Vector2(-5, 5), col, 2.0)
	# Small circle handle
	draw_circle(p, 2.5, col)

func _draw_stone_icon(p: Vector2) -> void:
	# Stack of 3 small quads (stone pile)
	var col := Color(0.55, 0.55, 0.55)
	draw_rect(Rect2(p.x - 5, p.y + 1,  10, 4), col)
	draw_rect(Rect2(p.x - 4, p.y - 3,   8, 4), col.lightened(0.1))
	draw_rect(Rect2(p.x - 3, p.y - 7,   6, 4), col.lightened(0.2))

func _draw_iron_icon(p: Vector2) -> void:
	# Crossed pickaxes
	var col := Color(0.50, 0.50, 0.58)
	draw_line(p + Vector2(-6, -3), p + Vector2(6,  3), col, 2.5)
	draw_line(p + Vector2(-6,  3), p + Vector2(6, -3), col, 2.5)
	draw_circle(p, 2.0, col)

func _draw_food_icon(p: Vector2) -> void:
	# Wheat sheaf: vertical stem + 5 radiating arcs
	var col := Color(0.72, 0.58, 0.18)
	draw_line(p + Vector2(0, 6), p + Vector2(0, -6), col, 1.5)
	for i in range(5):
		var a: float = (-PI * 0.3) + float(i) * (PI * 0.6 / 4.0)
		draw_line(p, p + Vector2(sin(a) * 6, -cos(a) * 6 - 2), col, 1.5)

# ── Cities ────────────────────────────────────────────────────────────────────

func _draw_cities() -> void:
	for c in _city_list:
		var p:    Vector2 = c["pos"]
		var col:  Color   = Color.from_string(c["faction_color"], Color.GRAY)
		var tier: int     = c.get("tier", 0)
		var is_player: bool = c.get("is_player_start", false)
		var is_hovered: bool = c.get("id", -1) == _hovered_city_id

		# Player start gold ring
		if is_player:
			draw_arc(p, 20.0, 0, TAU, 24, Color(0.95, 0.78, 0.10, 0.85), 3.0)

		# Hover highlight
		if is_hovered:
			draw_arc(p, 18.0, 0, TAU, 24, Color.WHITE.darkened(0.1), 2.0)

		_draw_castle_icon(p, col, tier, is_player)

		# City name
		var name_col: Color = Color(0.15, 0.10, 0.05) if not is_player else Color(0.60, 0.45, 0.10)
		draw_string(ThemeDB.fallback_font, p + Vector2(-30, 20), c.get("name", ""),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, name_col)

		# Pop/troop count (only for capitals or player start)
		if c.get("is_capital", false) or is_player:
			var info: String = "%d pop · %d troops" % [c.get("population", 0), c.get("troop_count", 0)]
			draw_string(ThemeDB.fallback_font, p + Vector2(-30, 30), info,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.30, 0.22, 0.12, 0.8))

func _draw_castle_icon(p: Vector2, faction_col: Color, tier: int, is_player: bool) -> void:
	var scale: float = 8.0 + tier * 4.0  # tier 0=8, 1=12, 2=16, 3=20
	var body_col: Color = faction_col if not is_player else Color(0.91, 0.76, 0.26)
	var dark_col: Color = body_col.darkened(0.35)

	# Keep body (rectangle)
	var bw: float = scale * 1.4
	var bh: float = scale * 1.2
	draw_rect(Rect2(p.x - bw * 0.5, p.y - bh, bw, bh), body_col)
	draw_rect(Rect2(p.x - bw * 0.5, p.y - bh, bw, bh), dark_col, false, 1.0)

	# Two flanking towers
	var tw: float = scale * 0.7
	var th: float = scale * 1.5
	for side in [-1, 1]:
		var tx: float = p.x + side * (bw * 0.5 + tw * 0.3) - tw * 0.5
		draw_rect(Rect2(tx, p.y - th, tw, th), body_col)
		draw_rect(Rect2(tx, p.y - th, tw, th), dark_col, false, 0.8)
		# Battlements (3 merlons)
		var mw: float = tw / 3.5
		for m in range(3):
			var mx: float = tx + float(m) * (tw / 3.0) + mw * 0.15
			draw_rect(Rect2(mx, p.y - th - scale * 0.35, mw, scale * 0.35),
				body_col.lightened(0.15))

	# Gate arch (darker circle bottom of keep body)
	draw_arc(p + Vector2(0, -scale * 0.4), scale * 0.35,
		PI, TAU, 8, dark_col.darkened(0.3), 2.0)

	# Flag on tallest tower
	var flag_x: float = p.x + bw * 0.5 + tw * 0.35
	var flag_top: Vector2 = Vector2(flag_x, p.y - th - scale * 0.8)
	draw_line(Vector2(flag_x, p.y - th), flag_top, dark_col, 1.5)
	draw_colored_polygon(PackedVector2Array([
		flag_top,
		flag_top + Vector2(scale * 0.7, scale * 0.25),
		flag_top + Vector2(0, scale * 0.5),
	]), body_col.lightened(0.2))
