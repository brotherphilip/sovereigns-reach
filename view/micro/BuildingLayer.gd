extends Node2D
# Draws all buildings as 3D-appearance multi-polygon structures (painter's
# algorithm). Depth-sorted by grid_x + grid_y ascending (back-to-front).

const HALF_W: float = 32.0
const HALF_H: float = 16.0

# Category colors (BuildingRegistry.Category enum 0–4)
const CAT_COLORS: Array = [
	Color(0.67, 0.87, 0.98),  # 0 CIVIC — light blue
	Color(0.80, 0.64, 0.36),  # 1 HARVESTING — tan
	Color(0.76, 0.96, 0.64),  # 2 FOOD — light green
	Color(0.90, 0.45, 0.40),  # 3 MILITARY — red
	Color(0.62, 0.62, 0.80),  # 4 DEFENSE — steel blue
]

const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const BuildingRenderer  = preload("res://view/micro/BuildingRenderer.gd")

var _buildings:       Array = []
var _enemy_buildings: Array = []
var _structure_dirty: bool = true
var _has_fire:        bool = false
var _tick:            int = 0

# Ghost preview state (build-mode cursor)
var _ghost_type:  String = ""
var _ghost_gx:    int    = 0
var _ghost_gy:    int    = 0
var _ghost_valid: bool   = true

func set_ghost(btype: String, gx: int, gy: int, valid: bool) -> void:
	_ghost_type  = btype
	_ghost_gx    = gx
	_ghost_gy    = gy
	_ghost_valid = valid
	queue_redraw()

func clear_ghost() -> void:
	_ghost_type = ""
	queue_redraw()

func _ready() -> void:
	EventBus.simulation_tick.connect(_on_tick)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_demolished.connect(_on_building_removed)

func _process(_delta: float) -> void:
	if _ghost_type != "" or _has_fire:
		queue_redraw()

func _on_tick(tick: int) -> void:
	_tick = tick
	# Rebuild the lists only on structure change or daily (fog refresh); the per-tick
	# queue_redraw still repaints live visual state (fire / HP / construction).
	if _structure_dirty or tick % 240 == 0:
		_rebuild()
		_structure_dirty = false
	_has_fire = false
	for b in _buildings:
		if b is Dictionary and b.get("is_on_fire", false):
			_has_fire = true
			break
	queue_redraw()

func _on_building_placed(_pid, _btype, _gx, _gy, _bid) -> void:
	_structure_dirty = true

func _on_building_removed(_pid, _bid) -> void:
	_structure_dirty = true

func _rebuild() -> void:
	_buildings = []
	_enemy_buildings = []
	if GameState.players.size() > 0:
		_buildings = GameState.players[0].get("buildings", []).duplicate()
	for fac in GameState.ai_factions:
		if fac is Dictionary:
			for bld in fac.get("buildings", []):
				if bld is Dictionary and GameState.visibility.has("%d,%d" % [bld.get("grid_x", 0), bld.get("grid_y", 0)]):
					_enemy_buildings.append(bld)

func _draw() -> void:
	# Combine and depth-sort by grid_x + grid_y ascending (back-to-front)
	if _ghost_type != "":
		_draw_ghost()
	var all: Array = []
	for b in _enemy_buildings:
		if b is Dictionary: all.append({"b": b, "enemy": true})
	for b in _buildings:
		if b is Dictionary: all.append({"b": b, "enemy": false})
	all.sort_custom(func(a, e):
		var ad: int = a["b"].get("grid_x", 0) + a["b"].get("grid_y", 0)
		var ed: int = e["b"].get("grid_x", 0) + e["b"].get("grid_y", 0)
		return ad < ed)
	for entry in all:
		_draw_building(entry["b"], entry["enemy"])

func _draw_building(b: Dictionary, is_enemy: bool) -> void:
	var gx: int       = b.get("grid_x", 0)
	var gy: int       = b.get("grid_y", 0)
	var btype: String = b.get("type", "")
	var defn: Dictionary  = BuildingRegistry.lookup(btype)
	var w: int        = defn.get("width",  1)
	var h: int        = defn.get("height", 1)
	var cat: int      = defn.get("category", 0)
	var vs: Dictionary = BuildingRenderer.get_visual_state(b)

	var base_color: Color
	if is_enemy:
		base_color = Color(0.70, 0.20, 0.20)
	else:
		base_color = CAT_COLORS[mini(cat, CAT_COLORS.size() - 1)]
	match vs.get("state", "empty"):
		"empty":   base_color = base_color.darkened(0.4)
		"damaged": base_color = Color(0.8, 0.5, 0.3)
		"fire":    base_color = Color(1.0, 0.4, 0.1)
		"working": pass  # keep category color

	var max_w: int = defn.get("max_workers", 0)

	# Footprint corners in iso-space (painter's algorithm order)
	var cx: float    = (gx - gy) * HALF_W
	var cy: float    = (gx + gy) * HALF_H

	var top:   Vector2 = Vector2(cx,                    cy - HALF_H)
	var right: Vector2 = Vector2(cx + w * HALF_W,       cy + (w - 1) * HALF_H)
	var bot:   Vector2 = Vector2(cx + (w - h) * HALF_W, cy + (w + h - 1) * HALF_H)
	var left:  Vector2 = Vector2(cx - h * HALF_W,       cy + (h - 1) * HALF_H)

	var wall_height: float = 18.0 + (w + h) * 4.0

	# Lifted versions (wall tops)
	var top_up:   Vector2 = top   + Vector2(0, -wall_height)
	var right_up: Vector2 = right + Vector2(0, -wall_height)
	var bot_up:   Vector2 = bot   + Vector2(0, -wall_height)
	var left_up:  Vector2 = left  + Vector2(0, -wall_height)

	var center: Vector2 = (top + bot) * 0.5

	# ── Shadow ────────────────────────────────────────────────────────────────
	var shadow_off := Vector2(3.0, 5.0)
	draw_colored_polygon(PackedVector2Array([
		top + shadow_off, right + shadow_off,
		bot + shadow_off, left + shadow_off,
	]), Color(0.0, 0.0, 0.0, 0.22))

	# ── Left wall (top–left face) ─────────────────────────────────────────────
	draw_colored_polygon(PackedVector2Array([
		left, top, top_up, left_up,
	]), base_color.darkened(0.35))
	draw_polyline(PackedVector2Array([left, top, top_up, left_up, left]),
		Color.BLACK.lightened(0.7), 0.5)

	# ── Right wall (top–right face) ───────────────────────────────────────────
	draw_colored_polygon(PackedVector2Array([
		top, right, right_up, top_up,
	]), base_color.darkened(0.20))
	draw_polyline(PackedVector2Array([top, right, right_up, top_up, top]),
		Color.BLACK.lightened(0.7), 0.5)

	# ── Roof face (flat top diamond) ──────────────────────────────────────────
	var roof_col: Color = base_color.lightened(0.10)
	draw_colored_polygon(PackedVector2Array([
		top_up, right_up, bot_up, left_up,
	]), roof_col)

	# ── Ridge triangle (pitched roof apex) ───────────────────────────────────
	var ridge_h: float
	if cat == 2:  # FOOD — flat hay roof
		ridge_h = clampf(wall_height * 0.18, 4.0, 12.0)
	else:
		ridge_h = clampf(wall_height * 0.40, 8.0, 24.0)

	var ridge_apex: Vector2 = (top_up + bot_up) * 0.5 + Vector2(0, -ridge_h)
	draw_colored_polygon(PackedVector2Array([
		left_up, bot_up, ridge_apex,
	]), base_color.lightened(0.18))
	draw_colored_polygon(PackedVector2Array([
		top_up, right_up, ridge_apex,
	]), base_color.lightened(0.22))
	draw_polyline(PackedVector2Array([left_up, ridge_apex, bot_up]),
		Color.BLACK.lightened(0.8), 0.5)
	draw_polyline(PackedVector2Array([top_up, ridge_apex, right_up]),
		Color.BLACK.lightened(0.8), 0.5)

	# ── Per-type distinctive features ──────────────────────────────────────────
	_draw_building_topper(btype, cat, w, h, base_color,
		top, right, bot, left, top_up, right_up, bot_up, left_up, ridge_apex, center)

	# ── Under-construction scaffolding ─────────────────────────────────────────
	if not b.get("built", true):
		var wood := Color(0.62, 0.45, 0.24, 0.9)
		for corner in [top, right, bot, left]:
			draw_line(corner, corner + Vector2(0, -wall_height - 4.0), wood, 1.3)
		var bandy: float = -wall_height * 0.6
		draw_line(top + Vector2(0, bandy), right + Vector2(0, bandy), wood, 1.0)
		draw_line(right + Vector2(0, bandy), bot + Vector2(0, bandy), wood, 1.0)
		draw_line(bot + Vector2(0, bandy), left + Vector2(0, bandy), wood, 1.0)
		draw_line(left + Vector2(0, bandy), top + Vector2(0, bandy), wood, 1.0)

	# ── Outline ───────────────────────────────────────────────────────────────
	draw_polyline(PackedVector2Array([top, right, bot, left, top]),
		Color.WHITE.darkened(0.4), 0.8)

	# ── Label ─────────────────────────────────────────────────────────────────
	var name_str: String = defn.get("name", btype).left(12)
	# Slight outline for legibility over varied terrain, then the label.
	var label_pos: Vector2 = center + Vector2(-22, -wall_height - ridge_h + 6)
	draw_string(ThemeDB.fallback_font, label_pos + Vector2(1, 1),
		name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0, 0.5))
	draw_string(ThemeDB.fallback_font, label_pos,
		name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

	# ── No-worker alert icon ───────────────────────────────────────────────────
	if max_w > 0 and int(b.get("workers", 0)) == 0 and b.get("is_active", true):
		draw_string(ThemeDB.fallback_font, center + Vector2(-5, -wall_height - ridge_h - 2),
			"!", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.65, 0.1, 0.9))

	# ── HP bar ────────────────────────────────────────────────────────────────
	var hp_ratio: float = vs.get("hp_bar", 1.0)
	if hp_ratio < 0.99:
		var bar_w: float = float(w) * HALF_W * 2.0
		var bar_x: float = center.x - bar_w * 0.5
		var bar_y: float = top_up.y - 6.0
		draw_rect(Rect2(bar_x, bar_y, bar_w, 4.0), Color(0.3, 0.1, 0.1))
		var hp_col: Color = (
			Color(0.1, 0.9, 0.2).lerp(Color(0.95, 0.85, 0.05), 1.0 - clampf(hp_ratio * 2.0 - 1.0, 0.0, 1.0))
			if hp_ratio > 0.5
			else Color(0.95, 0.85, 0.05).lerp(Color(0.95, 0.15, 0.1), 1.0 - clampf(hp_ratio * 2.0, 0.0, 1.0))
		)
		draw_rect(Rect2(bar_x, bar_y, bar_w * hp_ratio, 4.0), hp_col)

	# ── Fire indicator (animated flicker) ────────────────────────────────────
	if vs.get("show_fire", false):
		var t: float       = Time.get_ticks_msec() * 0.001
		var f1: float      = 0.70 + 0.30 * sin(t * 7.3)
		var f2: float      = 0.80 + 0.20 * sin(t * 11.7 + 1.2)
		var fire_c: Vector2 = center + Vector2(0, -wall_height * 0.55)
		draw_circle(fire_c, 11.0 * f1, Color(1.0, 0.20, 0.0, 0.28))
		draw_circle(fire_c + Vector2(sin(t * 5.1) * 2.0, 0), 7.5 * f2, Color(1.0, 0.42, 0.0, 0.85))
		draw_circle(fire_c + Vector2(sin(t * 8.7) * 1.5, -2.5 * f1), 4.5 * f2, Color(1.0, 0.78, 0.1, 0.90))
		draw_circle(fire_c + Vector2(sin(t * 13.1) * 1.0, -5.0 * f2), 2.2 * f1, Color(1.0, 1.0, 0.65, 0.80))

# Distinctive per-building-type features drawn on top of the base massing, so
# each building type reads at a glance (church cross, keep flag, farm furrows…).
func _draw_building_topper(btype: String, cat: int, w: int, h: int, base_color: Color,
		top: Vector2, right: Vector2, bot: Vector2, left: Vector2,
		top_up: Vector2, right_up: Vector2, bot_up: Vector2, left_up: Vector2,
		ridge_apex: Vector2, center: Vector2) -> void:
	match btype:
		"church", "cathedral":
			var c: Vector2 = ridge_apex + Vector2(0, -4.0)
			draw_line(c, c + Vector2(0, -13.0), Color(0.96, 0.92, 0.62), 2.0)
			draw_line(c + Vector2(-4.0, -8.0), c + Vector2(4.0, -8.0), Color(0.96, 0.92, 0.62), 2.0)
		"village_hall", "keep":
			var ph: float = 17.0 if btype == "keep" else 12.0
			draw_line(ridge_apex, ridge_apex + Vector2(0, -ph), Color(0.42, 0.32, 0.20), 1.5)
			var fb: Vector2 = ridge_apex + Vector2(0, -ph)
			draw_colored_polygon(PackedVector2Array([fb, fb + Vector2(13.0, 4.0), fb + Vector2(0, 8.0)]),
				Color(0.78, 0.18, 0.18))
		"barracks", "siege_workshop":
			var bn: Vector2 = (top_up + right_up) * 0.5
			draw_rect(Rect2(bn.x - 3.0, bn.y - 2.0, 6.0, 14.0), Color(0.70, 0.18, 0.18))
			draw_colored_polygon(PackedVector2Array([
				Vector2(bn.x - 3.0, bn.y + 12.0), Vector2(bn.x + 3.0, bn.y + 12.0), Vector2(bn.x, bn.y + 16.0),
			]), Color(0.70, 0.18, 0.18))
		"granary", "stockpile":
			draw_circle(ridge_apex + Vector2(0, 2.0), 6.0, base_color.lightened(0.25))
			draw_arc(ridge_apex + Vector2(0, 2.0), 6.0, PI, TAU, 8, Color(0, 0, 0, 0.3), 1.0)
		"well":
			draw_circle(center, 5.0, Color(0.10, 0.20, 0.32))
			draw_arc(center + Vector2(0, -8.0), 7.0, PI, TAU, 8, Color(0.42, 0.32, 0.20), 2.0)
		"market", "trading_post":
			for i in range(4):
				var a: Vector2 = left_up.lerp(bot_up, float(i) / 4.0)
				var b: Vector2 = left_up.lerp(bot_up, float(i + 1) / 4.0)
				var col: Color = Color(0.86, 0.82, 0.76) if i % 2 == 0 else Color(0.76, 0.26, 0.20)
				draw_colored_polygon(PackedVector2Array([a, b, b + Vector2(0, 5.0), a + Vector2(0, 5.0)]), col)
		"apple_orchard", "wheat_farm", "hops_farm", "pig_farm", "dairy_farm", "mill", "bakery", "brewery", "inn":
			for i in range(1, 4):
				var t: float = float(i) / 4.0
				draw_line(top_up.lerp(left_up, t), right_up.lerp(bot_up, t), base_color.darkened(0.22), 0.8)
		_:
			if cat == 4 or cat == 3:  # walls / towers / military — crenellation merlons
				var steps: int = mini(4, w + h + 1)
				for i in range(steps):
					var mp: Vector2 = left_up.lerp(bot_up, (float(i) + 0.5) / float(steps))
					draw_rect(Rect2(mp.x - 3.0, mp.y - 5.0, 6.0, 5.0), base_color.lightened(0.3))
			elif cat == 1:  # harvesting — a small chimney/marker
				draw_rect(Rect2(ridge_apex.x - 2.0, ridge_apex.y - 6.0, 4.0, 8.0), Color(0.30, 0.25, 0.20))

func _draw_ghost() -> void:
	var pulse: float = 0.45 + 0.20 * sin(Time.get_ticks_msec() * 0.006)
	var tint: Color  = Color(0.35, 1.0, 0.35) if _ghost_valid else Color(1.0, 0.30, 0.30)

	var defn: Dictionary  = BuildingRegistry.lookup(_ghost_type)
	var w: int            = defn.get("width",  1)
	var h: int            = defn.get("height", 1)
	var cat: int          = defn.get("category", 0)
	var base: Color       = CAT_COLORS[mini(cat, CAT_COLORS.size() - 1)]
	var gc: Color         = base.lerp(tint, 0.55)

	var cx: float  = (_ghost_gx - _ghost_gy) * HALF_W
	var cy: float  = (_ghost_gx + _ghost_gy) * HALF_H

	var top:   Vector2 = Vector2(cx,                    cy - HALF_H)
	var right: Vector2 = Vector2(cx + w * HALF_W,       cy + (w - 1) * HALF_H)
	var bot:   Vector2 = Vector2(cx + (w - h) * HALF_W, cy + (w + h - 1) * HALF_H)
	var left:  Vector2 = Vector2(cx - h * HALF_W,       cy + (h - 1) * HALF_H)
	var wall_h: float  = 18.0 + (w + h) * 4.0
	var top_up:   Vector2 = top   + Vector2(0, -wall_h)
	var right_up: Vector2 = right + Vector2(0, -wall_h)
	var bot_up:   Vector2 = bot   + Vector2(0, -wall_h)
	var left_up:  Vector2 = left  + Vector2(0, -wall_h)

	# Floor
	draw_colored_polygon(PackedVector2Array([top, right, bot, left]),
		Color(gc.r, gc.g, gc.b, pulse * 0.45))
	# Left wall
	draw_colored_polygon(PackedVector2Array([left, top, top_up, left_up]),
		Color(gc.r * 0.70, gc.g * 0.70, gc.b * 0.70, pulse * 0.55))
	# Right wall
	draw_colored_polygon(PackedVector2Array([top, right, right_up, top_up]),
		Color(gc.r * 0.85, gc.g * 0.85, gc.b * 0.85, pulse * 0.55))
	# Roof
	draw_colored_polygon(PackedVector2Array([top_up, right_up, bot_up, left_up]),
		Color(gc.r, gc.g, gc.b, pulse * 0.65))
	# Outline edges
	var ol := Color(tint.r, tint.g, tint.b, minf(pulse + 0.25, 1.0))
	draw_polyline(PackedVector2Array([top, right, bot, left, top]), ol, 1.5)
	draw_polyline(PackedVector2Array([top_up, right_up, bot_up, left_up, top_up]), ol, 1.0)
	draw_polyline(PackedVector2Array([left, left_up]), ol, 0.8)
	draw_polyline(PackedVector2Array([top, top_up]),   ol, 0.8)
	draw_polyline(PackedVector2Array([right, right_up]), ol, 0.8)
