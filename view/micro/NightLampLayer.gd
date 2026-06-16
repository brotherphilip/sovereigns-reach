extends Node2D
# Additive building lights for the night. Drawn ABOVE the darkening wash (NightLayer)
# with an ADD blend mode, so each lamp genuinely brightens the ground around it (a real
# pool of light with smooth radial falloff) instead of being a flat colour overlay.
# Each building gets a wide warm glow + a soft inner core + a bright flame point.
# Self-driven from the simulation clock.

const SeasonSystem     = preload("res://simulation/world/SeasonSystem.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

const HALF_W: float = 32.0          # must match BuildingLayer's iso half-tile
const HALF_H: float = 16.0
const GLOW_RADIUS: float = 130.0    # how far each lamp's light reaches (was ~48)
const CORE_RADIUS: float = 55.0
const WARM: Color = Color(1.0, 0.78, 0.42)   # lamp-light colour

var _night: float = 0.0
var _buildings: Array = []
var _refresh_accum: float = 1.0
var _grad: GradientTexture2D = null
var _t: float = 0.0   # wall-clock seconds, for flame flicker

func _ready() -> void:
	# Additive blend so the light ADDS to the darkened scene below.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	# A smooth radial gradient (bright centre → transparent edge) = soft light falloff.
	var g := Gradient.new()
	g.set_offset(0, 0.0); g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	g.set_offset(g.get_point_count() - 1, 1.0); g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	_grad = GradientTexture2D.new()
	_grad.gradient = g
	_grad.fill = GradientTexture2D.FILL_RADIAL
	_grad.fill_from = Vector2(0.5, 0.5)
	_grad.fill_to = Vector2(1.0, 0.5)
	_grad.width = 128
	_grad.height = 128

func _process(delta: float) -> void:
	_t += delta
	var n: float = SeasonSystem.night_factor(SimulationClock.current_tick)
	_refresh_accum += delta
	if _refresh_accum >= 1.0:
		_refresh_accum = 0.0
		_refresh_buildings()
	if n > 0.02 or _night > 0.02:
		_night = n
		queue_redraw()
	else:
		_night = n

func _refresh_buildings() -> void:
	var arr: Array = []
	if GameState.players.size() > 0:
		arr = GameState.players[0].get("buildings", []).duplicate()
	for fac in GameState.ai_factions:
		if fac is Dictionary:
			for b in fac.get("buildings", []):
				if b is Dictionary:
					arr.append(b)
	_buildings = arr

func _draw() -> void:
	if _night < 0.03 or _grad == null:
		return
	# Lights ramp in over dusk and reach full at deep night.
	var lit: float = smoothstep(0.1, 0.7, _night)
	if lit <= 0.0:
		return
	for b in _buildings:
		if not (b is Dictionary) or not b.get("built", true):
			continue
		if BuildingRegistry.is_path(String(b.get("type", ""))):
			continue
		var gx: int = int(b.get("grid_x", 0))
		var gy: int = int(b.get("grid_y", 0))
		var c: Vector2 = Vector2((gx - gy) * HALF_W, (gx + gy) * HALF_H) - Vector2(0, HALF_H * 0.5)
		# Each lamp gets a unique phase so the town's torches flicker out of sync.
		var phase: float = float((gx * 7 + gy * 13) % 628) * 0.01
		_draw_light(c, lit, phase)

func _draw_light(c: Vector2, lit: float, phase: float) -> void:
	# One wide, SOFT, STEADY glow pool (the level of glow the player liked). It only
	# breathes very gently — no hard pulsing inner ring (that was the distracting part).
	var breath: float = 1.0 + 0.04 * sin(_t * 1.6 + phase)
	_blit(c, GLOW_RADIUS, Color(WARM.r, WARM.g, WARM.b, 0.50 * lit * breath))
	# The actual torch flame: a small lick of fire that flickers in height + sways.
	_draw_flame(c, lit, phase)

func _draw_flame(c: Vector2, lit: float, phase: float) -> void:
	# Irregular fire flicker (fast + a faster harmonic) and a lateral lick/sway.
	var fl: float = 0.72 + 0.22 * sin(_t * 13.0 + phase) + 0.12 * sin(_t * 23.0 + phase * 2.1)
	var h: float = 8.5 * maxf(fl, 0.4)
	var sway: float = 1.5 * sin(_t * 9.0 + phase * 1.7) + 0.7 * sin(_t * 17.0 + phase)
	var bw: float = 2.7
	var tip: Vector2 = c + Vector2(sway, -h)
	# Outer flame (orange).
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-bw, 0.6), c + Vector2(-bw * 0.7, -h * 0.45), tip,
		c + Vector2(bw * 0.7, -h * 0.45), c + Vector2(bw, 0.6)]),
		Color(1.0, 0.45, 0.12, 0.9 * lit))
	# Inner flame (bright yellow), smaller and swaying a touch less.
	var ih: float = h * 0.58
	var itip: Vector2 = c + Vector2(sway * 0.6, -ih)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-bw * 0.5, 0.4), c + Vector2(-bw * 0.32, -ih * 0.5), itip,
		c + Vector2(bw * 0.32, -ih * 0.5), c + Vector2(bw * 0.5, 0.4)]),
		Color(1.0, 0.85, 0.45, 0.95 * lit))
	# Tiny hot core at the wick.
	draw_circle(c + Vector2(0, -1.0), 1.3, Color(1.0, 0.95, 0.72, lit))

func _blit(c: Vector2, r: float, col: Color) -> void:
	draw_texture_rect(_grad, Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, col)
