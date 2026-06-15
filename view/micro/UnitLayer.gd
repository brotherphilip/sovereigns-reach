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
const UnitArt      = preload("res://view/micro/UnitArt.gd")

var _player_units: Array = []
var _ai_units: Array = []
var _selected_unit_id: int = -1

# Smoothed display position (grid coords) per unit id, so troops glide between
# tiles instead of snapping each sim tick (matches the villager pawns' motion).
# We MEASURE the real-time interval between a unit's tile-steps and glide at exactly
# that rate, so the figure is always in motion between tiles (no step-pause-step) and
# it auto-calibrates across unit speeds, terrain, and game-speed multipliers.
var _disp: Dictionary = {}        # uid -> smoothed display pos (grid coords)
var _last_tile: Dictionary = {}   # uid -> the true tile we are gliding toward
var _step_dt: Dictionary = {}     # uid -> measured seconds between tile steps (EMA)
var _since: Dictionary = {}       # uid -> seconds since the true tile last changed
const _SNAP_DIST: float = 3.0     # tiles; beyond this we jump (spawn / teleport)
const _STEP_DT_DEFAULT: float = 0.4

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

func _process(delta: float) -> void:
	# Units are continuously animated (limbs swing, archers draw, siege arms wind),
	# so redraw every frame whenever any are present.
	if not _player_units.is_empty() or not _ai_units.is_empty() \
			or not _damage_popups.is_empty() or not _death_anims.is_empty():
		_update_display_positions(delta)
		queue_redraw()

# Glide each unit's drawn position toward its true tile at the unit's own measured
# step rate, so movement reads as a continuous walk rather than discrete hops.
func _update_display_positions(delta: float) -> void:
	var seen: Dictionary = {}
	for arr in [_player_units, _ai_units]:
		for unit in arr:
			if not (unit is Dictionary):
				continue
			var uid: int = unit.get("id", -1)
			if uid < 0:
				continue
			seen[uid] = true
			var target := Vector2(unit.get("pos_x", 0), unit.get("pos_y", 0))
			# First sight, or a teleport/respawn — jump straight there.
			if not _disp.has(uid) or (_disp[uid] as Vector2).distance_to(target) > _SNAP_DIST:
				_disp[uid] = target
				_last_tile[uid] = target
				_step_dt[uid] = _STEP_DT_DEFAULT
				_since[uid] = 0.0
				continue
			# A tile-step just happened: learn how long it took (EMA) and reset the timer.
			if target != (_last_tile.get(uid, target) as Vector2):
				var dt: float = maxf(0.05, float(_since.get(uid, _STEP_DT_DEFAULT)))
				_step_dt[uid] = lerpf(float(_step_dt.get(uid, dt)), dt, 0.5)
				_last_tile[uid] = target
				_since[uid] = 0.0
			else:
				_since[uid] = float(_since.get(uid, 0.0)) + delta
			# Glide toward the true tile so we cover the remaining gap over ~one step
			# interval — always moving, trailing by at most a tile.
			var d: Vector2 = _disp[uid]
			var to := target - d
			var dist := to.length()
			if dist > 0.0001:
				var sdt: float = maxf(0.08, float(_step_dt.get(uid, _STEP_DT_DEFAULT)))
				var move := (delta / sdt)              # tiles this frame (1 tile per step interval)
				_disp[uid] = d + to / dist * minf(move, dist)
	# Drop bookkeeping for units that are gone.
	for k in _disp.keys():
		if not seen.has(k):
			_disp.erase(k)
			_last_tile.erase(k)
			_step_dt.erase(k)
			_since.erase(k)

# Smoothed grid position for a unit (falls back to its true tile).
func _grid_pos(unit: Dictionary) -> Vector2:
	return _disp.get(unit.get("id", -1), Vector2(unit.get("pos_x", 0), unit.get("pos_y", 0)))

func _on_tick(_tick: int) -> void:
	if GameState.players.size() > 0:
		_player_units = GameState.players[0].get("units", []).duplicate()
	_ai_units = []
	for fac in GameState.ai_factions:
		if fac is Dictionary:
			for unit in fac.get("units", []):
				# Fog of war disabled for now: show all enemy units, not just the
				# ones standing on a tile the player currently sees.
				if unit is Dictionary:
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
	# Smoothed (eased) position so troops glide between tiles, not snap.
	var gpos: Vector2 = _grid_pos(unit)
	var cx: float = (gpos.x - gpos.y) * HALF_W
	var cy: float = (gpos.x + gpos.y) * HALF_H

	var si: Dictionary = UnitRenderer.get_sprite_info(unit)
	var alive: bool = si.get("is_alive", false)
	if not alive:
		draw_line(Vector2(cx - 5, cy - 5), Vector2(cx + 5, cy + 5), Color(0.3, 0.3, 0.3), 2.0)
		draw_line(Vector2(cx + 5, cy - 5), Vector2(cx - 5, cy + 5), Color(0.3, 0.3, 0.3), 2.0)
		return

	var morale_ratio: float = 1.0
	if not is_enemy:
		var morale: int = unit.get("morale", 100)
		morale_ratio = float(morale) / float(maxi(unit.get("max_morale", 100), 1))

	# Team tint: enemies red, players their faction color. Low morale shifts blue.
	var team: Color
	if is_enemy:
		team = Color(0.82, 0.24, 0.22)
	else:
		var oid: int = unit.get("owner_id", 0)
		team = PLAYER_COLORS[mini(oid, PLAYER_COLORS.size() - 1)]
		if morale_ratio < 0.35:
			team = team.lerp(Color(0.30, 0.35, 0.82), 0.4)

	# Hit-flash: white pop when HP just dropped.
	var uid: int = unit.get("id", -1)
	var flash: float = 0.0
	if uid >= 0 and _hit_flash.has(uid):
		var flash_age: float = float(Time.get_ticks_msec() - _hit_flash[uid]) / float(_FLASH_LIFE_MS)
		flash = maxf(0.0, 1.0 - flash_age)

	# Selection ring (player units only) — pulsing glow under the feet.
	if not is_enemy and uid == _selected_unit_id:
		var ts: float     = Time.get_ticks_msec() * 0.004
		var pulse: float  = 0.45 + 0.30 * sin(ts)
		var ring_r: float = 9.0 + 2.0 * sin(ts * 1.3)
		draw_circle(Vector2(cx, cy + 1.0), ring_r, Color(1.0, 1.0, 0.2, pulse))
		draw_arc(Vector2(cx, cy + 1.0), ring_r, 0, TAU, 18, Color(1.0, 1.0, 0.4, pulse + 0.2), 1.2)

	# Detailed, animated per-type body (feet at the tile centre).
	var now_s: float = Time.get_ticks_msec() * 0.001
	UnitArt.draw_unit(self, Vector2(cx, cy), unit, team, now_s, flash)

	# HP bar floating above the (now taller) figure.
	var hp: int     = unit.get("hp", 1)
	var max_hp: int = unit.get("max_hp", 1)
	var ratio: float = float(hp) / float(maxi(max_hp, 1))
	var bar_y: float = cy - 28.0
	if ratio < 0.99:
		var bw: float = 16.0
		var bar_col: Color
		if is_enemy:
			bar_col = Color(0.9, 0.4, 0.1)
		elif ratio > 0.5:
			bar_col = Color(0.2, 0.9, 0.2).lerp(Color(0.95, 0.85, 0.05), 1.0 - clampf(ratio * 2.0 - 1.0, 0.0, 1.0))
		else:
			bar_col = Color(0.95, 0.85, 0.05).lerp(Color(0.95, 0.15, 0.1), 1.0 - clampf(ratio * 2.0, 0.0, 1.0))
		draw_rect(Rect2(cx - bw * 0.5, bar_y, bw, 2.6), Color(0.18, 0.06, 0.06))
		draw_rect(Rect2(cx - bw * 0.5, bar_y, bw * ratio, 2.6), bar_col)

	# Morale warning — blue ↓ above unit when morale is critically low.
	if not is_enemy and morale_ratio < 0.35:
		draw_string(ThemeDB.fallback_font, Vector2(cx - 3, bar_y - 4.0),
			"↓", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.55, 1.0, 0.9))
