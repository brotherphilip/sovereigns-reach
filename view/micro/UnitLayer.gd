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

var _prev_hp: Dictionary = {}
var _damage_popups: Array = []
var _hit_flash: Dictionary = {}
var _prev_alive: Dictionary = {}
var _death_anims: Array = []
const _POPUP_LIFE_MS: int = 1400
const _FLASH_LIFE_MS: int = 220
const _DEATH_ANIM_MS: int = 700

func _ready() -> void:
	EventBus.simulation_tick.connect(_on_tick)

func _process(_delta: float) -> void:
	if _selected_unit_id >= 0 or not _damage_popups.is_empty() or not _hit_flash.is_empty() or not _death_anims.is_empty():
		queue_redraw()

func _on_tick(_tick: int) -> void:
	if GameState.players.size() > 0:
		_player_units = GameState.players[0].get("units", []).duplicate()
	_ai_units = []
	for fac in GameState.ai_factions:
		if fac is Dictionary:
			for unit in fac.get("units", []):
				if unit is Dictionary and GameState.visibility.has("%d,%d" % [unit.get("pos_x", 0), unit.get("pos_y", 0)]):
					_ai_units.append(unit)

	var now_ms: int = Time.get_ticks_msec()
	var all_units: Array = []
	all_units.append_array(_player_units)
	all_units.append_array(_ai_units)
	for unit in all_units:
		if not unit is Dictionary: continue
		var uid: int = unit.get("id", -1)
		if uid < 0: continue
		var cur_hp: int = int(unit.get("hp", 0))
		if _prev_hp.has(uid):
			var dmg: int = _prev_hp[uid] - cur_hp
			if dmg > 0 and unit.get("is_alive", false):
				var gx: int = unit.get("pos_x", 0)
				var gy: int = unit.get("pos_y", 0)
				var pop_pos := Vector2((gx - gy) * HALF_W, (gx + gy) * HALF_H - UNIT_RADIUS - 8)
				_damage_popups.append({"pos": pop_pos, "text": "-%d" % dmg, "born_ms": now_ms})
				_hit_flash[uid] = now_ms
		_prev_hp[uid] = cur_hp
		var is_alive: bool = unit.get("is_alive", false)
		if _prev_alive.get(uid, true) and not is_alive:
			var gx: int = unit.get("pos_x", 0)
			var gy: int = unit.get("pos_y", 0)
			_death_anims.append({"pos": Vector2((gx - gy) * HALF_W, (gx + gy) * HALF_H), "born_ms": now_ms})
		_prev_alive[uid] = is_alive
	_damage_popups = _damage_popups.filter(func(p): return now_ms - p["born_ms"] < _POPUP_LIFE_MS)
	_death_anims  = _death_anims.filter(func(a): return now_ms - a["born_ms"] < _DEATH_ANIM_MS)
	var expired: Array = _hit_flash.keys().filter(func(k): return now_ms - _hit_flash[k] >= _FLASH_LIFE_MS)
	for k in expired: _hit_flash.erase(k)

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

	var now_ms: int = Time.get_ticks_msec()
	for popup in _damage_popups:
		var age: float = clampf(float(now_ms - popup["born_ms"]) / float(_POPUP_LIFE_MS), 0.0, 1.0)
		var alpha: float = 1.0 - age
		var y_off: float = age * -26.0
		draw_string(ThemeDB.fallback_font,
			popup["pos"] + Vector2(0, y_off),
			popup["text"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(1.0, 0.88, 0.30, alpha))

	for anim in _death_anims:
		var age: float = clampf(float(now_ms - anim["born_ms"]) / float(_DEATH_ANIM_MS), 0.0, 1.0)
		var alpha: float = 1.0 - age
		var r: float = UNIT_RADIUS + age * 22.0
		draw_circle(anim["pos"], r, Color(1.0, 0.55, 0.1, alpha * 0.45))
		draw_arc(anim["pos"], r, 0.0, TAU, 16, Color(1.0, 0.82, 0.25, alpha), 2.0)

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

	var morale_ratio: float = 1.0
	if not is_enemy:
		var morale: int = unit.get("morale", 100)
		morale_ratio = float(morale) / float(maxi(unit.get("max_morale", 100), 1))
		if morale_ratio < 0.35:
			fill = fill.lerp(Color(0.30, 0.35, 0.82), 0.38)

	# Hit-flash: briefly lerp toward white when HP just dropped
	var uid: int = unit.get("id", -1)
	if uid >= 0 and _hit_flash.has(uid):
		var flash_age: float = float(Time.get_ticks_msec() - _hit_flash[uid]) / float(_FLASH_LIFE_MS)
		fill = fill.lerp(Color.WHITE, maxf(0.0, 1.0 - flash_age))

	# Selection ring (player units only) — pulsing glow
	if not is_enemy and unit.get("id", -1) == _selected_unit_id:
		var t: float      = Time.get_ticks_msec() * 0.004
		var pulse: float  = 0.45 + 0.30 * sin(t)
		var ring_r: float = UNIT_RADIUS + 3.0 + 2.0 * sin(t * 1.3)
		draw_circle(Vector2(cx, cy), ring_r, Color(1.0, 1.0, 0.2, pulse))

	draw_circle(Vector2(cx, cy), UNIT_RADIUS, fill)
	draw_arc(Vector2(cx, cy), UNIT_RADIUS, 0, TAU, 12, Color.WHITE.darkened(0.2), 1.0)

	# HP bar above unit
	var hp: int     = unit.get("hp", 1)
	var max_hp: int = unit.get("max_hp", 1)
	var ratio: float = float(hp) / float(maxi(max_hp, 1))
	if ratio < 0.99:
		var bw: float = UNIT_RADIUS * 2.5
		var bar_col: Color
		if is_enemy:
			bar_col = Color(0.9, 0.4, 0.1)
		elif ratio > 0.5:
			bar_col = Color(0.2, 0.9, 0.2).lerp(Color(0.95, 0.85, 0.05), 1.0 - clampf(ratio * 2.0 - 1.0, 0.0, 1.0))
		else:
			bar_col = Color(0.95, 0.85, 0.05).lerp(Color(0.95, 0.15, 0.1), 1.0 - clampf(ratio * 2.0, 0.0, 1.0))
		draw_rect(Rect2(cx - bw * 0.5, cy - UNIT_RADIUS - 7, bw, 3), Color(0.3, 0.1, 0.1))
		draw_rect(Rect2(cx - bw * 0.5, cy - UNIT_RADIUS - 7, bw * ratio, 3), bar_col)

	# Unit type label
	var label: String = unit.get("type", "?").left(3).to_upper()
	draw_string(ThemeDB.fallback_font, Vector2(cx - 8, cy + 4), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color.WHITE)

	# Morale warning symbol — blue ↓ above unit when morale is critically low
	if not is_enemy and morale_ratio < 0.35:
		draw_string(ThemeDB.fallback_font, Vector2(cx - 3, cy - UNIT_RADIUS - 10),
			"↓", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.55, 1.0, 0.9))
