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
		# Per-building flame flicker: a gentle pulse with a phase unique to each lamp so
		# the lit town shimmers like real firelight rather than sitting flat.
		var phase: float = float((gx * 7 + gy * 13) % 628) * 0.01
		var flicker: float = 1.0 + 0.10 * sin(_t * 6.3 + phase) + 0.05 * sin(_t * 11.7 + phase * 1.7)
		_draw_light(c, lit, flicker)

func _draw_light(c: Vector2, lit: float, flicker: float) -> void:
	# Wide soft glow (reaches far) — additive, so it lifts the dark ground to warm light.
	_blit(c, GLOW_RADIUS, Color(WARM.r, WARM.g, WARM.b, 0.45 * lit * flicker))
	# Brighter inner core near the lamp.
	_blit(c, CORE_RADIUS * flicker, Color(WARM.r, WARM.g, WARM.b, 0.55 * lit * flicker))
	# The flame itself — a small near-white point that bobs a touch.
	draw_circle(c, 3.5 * flicker, Color(1.0, 0.95, 0.7, 0.95 * lit))

func _blit(c: Vector2, r: float, col: Color) -> void:
	draw_texture_rect(_grad, Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, col)
