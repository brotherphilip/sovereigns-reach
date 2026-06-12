extends Node2D
# Draws all player buildings as colored rectangles on top of the isometric terrain.
# Listens to EventBus signals to add/remove buildings; redraws every tick.

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

var _buildings: Array = []        # player buildings
var _enemy_buildings: Array = []  # AI faction buildings

func _ready() -> void:
	EventBus.simulation_tick.connect(_on_tick)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_demolished.connect(_on_building_removed)

func _on_tick(_tick: int) -> void:
	_refresh()

func _on_building_placed(_pid, _btype, _gx, _gy, _bid) -> void:
	_refresh()

func _on_building_removed(_pid, _bid) -> void:
	_refresh()

func _refresh() -> void:
	_buildings = []
	_enemy_buildings = []
	if GameState.players.size() > 0:
		_buildings = GameState.players[0].get("buildings", []).duplicate()
	for fac in GameState.ai_factions:
		if fac is Dictionary:
			for bld in fac.get("buildings", []):
				if bld is Dictionary:
					_enemy_buildings.append(bld)
	queue_redraw()

func _draw() -> void:
	for building in _enemy_buildings:
		if not building is Dictionary: continue
		_draw_building(building, true)
	for building in _buildings:
		if not building is Dictionary: continue
		_draw_building(building, false)

func _draw_building(b: Dictionary, is_enemy: bool) -> void:
	var gx: int  = b.get("grid_x", 0)
	var gy: int  = b.get("grid_y", 0)
	var btype: String = b.get("type", "")
	var defn: Dictionary = BuildingRegistry.lookup(btype)
	var w: int   = defn.get("width", 1)
	var h: int   = defn.get("height", 1)
	var cat: int = defn.get("category", 0)
	var vs: Dictionary = BuildingRenderer.get_visual_state(b)

	var base_color: Color
	if is_enemy:
		base_color = Color(0.70, 0.20, 0.20)
	else:
		base_color = CAT_COLORS[mini(cat, CAT_COLORS.size() - 1)]
	match vs.get("state", "empty"):
		"empty":    base_color = base_color.darkened(0.4)
		"damaged":  base_color = Color(0.8, 0.5, 0.3)
		"fire":     base_color = Color(1.0, 0.4, 0.1)
		"working":  pass  # keep category color

	# Draw footprint outline + fill
	# Center of top-left tile in iso
	var cx: float = (gx - gy) * HALF_W
	var cy: float = (gx + gy) * HALF_H

	# For a w×h building, compute the four corners of the footprint diamond
	var top_x: float = cx
	var top_y: float = cy - HALF_H
	var right_x: float = cx + (w + 0) * HALF_W
	var right_y: float = cy + (w - 1) * HALF_H
	var bot_x: float   = cx + (w - h) * HALF_W
	var bot_y: float   = cy + (w + h - 1) * HALF_H
	var left_x: float  = cx - h * HALF_W
	var left_y: float  = cy + (h - 1) * HALF_H

	var pts := PackedVector2Array([
		Vector2(top_x, top_y),
		Vector2(right_x, right_y),
		Vector2(bot_x, bot_y),
		Vector2(left_x, left_y),
	])
	draw_colored_polygon(pts, base_color)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
		Color.WHITE.darkened(0.3), 1.0)

	# Label (short name)
	var name_str: String = defn.get("name", btype).left(10)
	var center := Vector2((top_x + bot_x) * 0.5, (top_y + bot_y) * 0.5)
	draw_string(ThemeDB.fallback_font, center + Vector2(-20, 4), name_str,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)

	# HP bar
	var hp_ratio: float = vs.get("hp_bar", 1.0)
	if hp_ratio < 0.99:
		var bar_w: float = float(w) * HALF_W * 2.0
		var bar_x: float = center.x - bar_w * 0.5
		var bar_y: float = top_y - 6.0
		draw_rect(Rect2(bar_x, bar_y, bar_w, 4.0), Color(0.3, 0.1, 0.1))
		draw_rect(Rect2(bar_x, bar_y, bar_w * hp_ratio, 4.0), Color(0.1, 0.9, 0.2))

	# Fire indicator
	if vs.get("show_fire", false):
		draw_circle(center, 8.0, Color(1.0, 0.5, 0.0, 0.8))
