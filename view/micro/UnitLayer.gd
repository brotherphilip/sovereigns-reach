extends Node2D
# Draws all units (player + AI) as colored circles on the isometric grid.
# Player units: player color; AI units: red with archetype icon.

const HALF_W: float = 32.0
const HALF_H: float = 16.0
const UNIT_RADIUS: float = 8.0

# Player tint colors matching MacroViewController.SHIRE_COLORS
const PLAYER_COLORS: Array = [
	Color(0.31, 0.76, 0.97),  # player 0 — blue
	Color(0.51, 0.78, 0.52),  # player 1 — green
	Color(1.00, 0.72, 0.30),  # player 2 — amber
	Color(0.90, 0.45, 0.45),  # player 3 — red
]

const UnitRenderer = preload("res://view/micro/UnitRenderer.gd")

var _player_units: Array = []
var _ai_units: Array = []
var _selected_unit_id: int = -1

func _ready() -> void:
	EventBus.simulation_tick.connect(_on_tick)

func _on_tick(_tick: int) -> void:
	if GameState.players.size() > 0:
		_player_units = GameState.players[0].get("units", []).duplicate()
	_ai_units = []
	for fac in GameState.ai_factions:
		if fac is Dictionary:
			for unit in fac.get("units", []):
				if unit is Dictionary and GameState.visibility.has("%d,%d" % [unit.get("pos_x", 0), unit.get("pos_y", 0)]):
					_ai_units.append(unit)
	queue_redraw()

func set_selected(uid: int) -> void:
	_selected_unit_id = uid
	queue_redraw()

func _draw() -> void:
	for unit in _ai_units:
		if not unit is Dictionary: continue
		_draw_unit(unit, true)
	for unit in _player_units:
		if not unit is Dictionary: continue
		_draw_unit(unit, false)

func _draw_unit(unit: Dictionary, is_enemy: bool) -> void:
	var gx: int = unit.get("pos_x", 0)
	var gy: int = unit.get("pos_y", 0)
	var cx: float = (gx - gy) * HALF_W
	var cy: float = (gx + gy) * HALF_H

	var si: Dictionary = UnitRenderer.get_sprite_info(unit)
	var alive: bool = si.get("is_alive", false)
	if not alive:
		draw_line(Vector2(cx - 5, cy - 5), Vector2(cx + 5, cy + 5), Color(0.3, 0.3, 0.3), 2.0)
		draw_line(Vector2(cx + 5, cy - 5), Vector2(cx - 5, cy + 5), Color(0.3, 0.3, 0.3), 2.0)
		return

	var fill: Color
	if is_enemy:
		fill = Color(0.90, 0.20, 0.20)
	else:
		var oid: int = unit.get("owner_id", 0)
		fill = PLAYER_COLORS[mini(oid, PLAYER_COLORS.size() - 1)]

	# Selection ring (player units only)
	if not is_enemy and unit.get("id", -1) == _selected_unit_id:
		draw_circle(Vector2(cx, cy), UNIT_RADIUS + 4.0, Color(1.0, 1.0, 0.2, 0.5))

	draw_circle(Vector2(cx, cy), UNIT_RADIUS, fill)
	draw_arc(Vector2(cx, cy), UNIT_RADIUS, 0, TAU, 12, Color.WHITE.darkened(0.2), 1.0)

	# HP bar above unit
	var hp: int     = unit.get("hp", 1)
	var max_hp: int = unit.get("max_hp", 1)
	var ratio: float = float(hp) / float(maxi(max_hp, 1))
	if ratio < 0.99:
		var bw: float = UNIT_RADIUS * 2.5
		var bar_col: Color = Color(0.2, 0.9, 0.2) if not is_enemy else Color(0.9, 0.4, 0.1)
		draw_rect(Rect2(cx - bw * 0.5, cy - UNIT_RADIUS - 7, bw, 3), Color(0.3, 0.1, 0.1))
		draw_rect(Rect2(cx - bw * 0.5, cy - UNIT_RADIUS - 7, bw * ratio, 3), bar_col)

	# Unit type label
	var label: String = unit.get("type", "?").left(3).to_upper()
	draw_string(ThemeDB.fallback_font, Vector2(cx - 8, cy + 4), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color.WHITE)
