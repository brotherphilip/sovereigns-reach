extends Node2D
# Day/night lighting for the city view. Added LAST to _world_root so it draws on top
# of the world: a cool darkening wash at night, with a warm lamp glow at every built
# building that lights the ground around it. Self-driven from the simulation clock.

const SeasonSystem     = preload("res://simulation/world/SeasonSystem.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

const HALF_W: float = 32.0          # must match BuildingLayer's iso half-tile
const HALF_H: float = 16.0
const MAX_DARK: float = 0.60        # deepest-night wash alpha (keep play readable)
const NIGHT_TINT: Color = Color(0.05, 0.07, 0.20)   # moonlit blue

var _night: float = 0.0
var _buildings: Array = []
var _refresh_accum: float = 1.0

func _process(delta: float) -> void:
	var n: float = SeasonSystem.night_factor(SimulationClock.current_tick)
	_refresh_accum += delta
	if _refresh_accum >= 1.0:
		_refresh_accum = 0.0
		_refresh_buildings()
	# Repaint while there's any darkness (the lamp flames flicker subtly with the clock).
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
	if _night < 0.03:
		return
	# Darkening wash over the whole iso map (huge rect; it pans/zooms with the world).
	draw_rect(Rect2(Vector2(-9000, -3000), Vector2(18000, 12000)),
		Color(NIGHT_TINT.r, NIGHT_TINT.g, NIGHT_TINT.b, _night * MAX_DARK))
	# Warm lamp pools at each built building, cutting through the dark.
	for b in _buildings:
		if not (b is Dictionary) or not b.get("built", true):
			continue
		var btype: String = String(b.get("type", ""))
		if BuildingRegistry.is_path(btype):
			continue
		var gx: int = int(b.get("grid_x", 0))
		var gy: int = int(b.get("grid_y", 0))
		var c: Vector2 = Vector2((gx - gy) * HALF_W, (gx + gy) * HALF_H)
		_draw_lamp(c)

func _draw_lamp(c: Vector2) -> void:
	var g: float = _night
	var lamp: Vector2 = c + Vector2(0, -HALF_H * 0.5)   # hung by the eave
	draw_circle(lamp, 48.0, Color(1.0, 0.80, 0.40, 0.09 * g))
	draw_circle(lamp, 30.0, Color(1.0, 0.82, 0.45, 0.13 * g))
	draw_circle(lamp, 15.0, Color(1.0, 0.86, 0.52, 0.18 * g))
	draw_circle(lamp, 3.0,  Color(1.0, 0.96, 0.72, 0.95 * g))   # the lamp flame
