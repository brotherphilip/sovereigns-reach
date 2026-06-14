extends Node2D
# Renders the village campfire (GameState.campfire) once the hall is built: a
# low-poly ring of stones, crossed logs, and animated flame tongues in the same
# faceted style as the trees and pawns. Villagers gather around it; recruits muster here.

const HALF_W: float = 32.0
const HALF_H: float = 16.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var fire: Dictionary = GameState.campfire
	if not (fire is Dictionary and fire.get("active", false)):
		return
	var fx: float = fire.get("x", 0.0)
	var fy: float = fire.get("y", 0.0)
	var sx: float = (fx - fy) * HALF_W
	var sy: float = (fx + fy) * HALF_H
	var t: float = Time.get_ticks_msec() * 0.001
	var flick: float = 0.80 + 0.20 * sin(t * 8.3) + 0.08 * sin(t * 19.0 + 1.3)

	# ── Ground glow (warm light cast on the dirt) ──────────────────────────────
	draw_circle(Vector2(sx, sy + 1.0), 22.0 * flick, Color(1.0, 0.55, 0.12, 0.10))
	draw_circle(Vector2(sx, sy + 1.0), 13.0 * flick, Color(1.0, 0.62, 0.18, 0.14))

	# ── Stone ring ─────────────────────────────────────────────────────────────
	for i in range(8):
		var a: float = float(i) * TAU / 8.0
		var p := Vector2(sx + cos(a) * 11.0, sy + sin(a) * 5.5)
		var stone: Color = Color(0.52, 0.52, 0.56) if i % 2 == 0 else Color(0.44, 0.44, 0.49)
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(-2.6, 0.6), p + Vector2(-1.2, -2.0),
			p + Vector2(2.4, -1.4), p + Vector2(2.8, 1.2), p + Vector2(0.4, 2.0),
		]), stone)
		draw_polyline(PackedVector2Array([
			p + Vector2(-2.6, 0.6), p + Vector2(-1.2, -2.0),
			p + Vector2(2.4, -1.4), p + Vector2(2.8, 1.2), p + Vector2(0.4, 2.0),
			p + Vector2(-2.6, 0.6),
		]), Color(0.22, 0.22, 0.26, 0.6), 0.6)

	# ── Crossed logs ───────────────────────────────────────────────────────────
	var log_dark := Color(0.34, 0.22, 0.12)
	var log_lite := Color(0.46, 0.30, 0.16)
	_draw_log(Vector2(sx, sy + 1.0), Vector2(-9, 2.5), Vector2(9, -2.5), log_dark)
	_draw_log(Vector2(sx, sy + 1.0), Vector2(-8, -3.0), Vector2(8, 3.0), log_lite)
	# Ember bed
	draw_circle(Vector2(sx, sy), 4.0 * flick, Color(1.0, 0.45, 0.08, 0.85))

	# ── Flame tongues (faceted low-poly triangles, orange→amber→white) ─────────
	var base_y: float = sy - 2.0
	_draw_flame(sx, base_y, 8.0, 22.0 * flick, t * 6.1, Color(0.95, 0.28, 0.05, 0.92))
	_draw_flame(sx, base_y, 5.6, 16.0 * flick, t * 8.7 + 1.0, Color(1.0, 0.55, 0.08, 0.95))
	_draw_flame(sx, base_y, 3.2, 10.0 * (0.85 + 0.15 * sin(t * 13.0)), t * 12.0 + 2.0, Color(1.0, 0.85, 0.30, 0.95))
	# Inner white-hot core
	var core_h: float = 5.0 * (0.85 + 0.15 * sin(t * 16.0 + 0.7))
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx - 1.6, base_y), Vector2(sx + 1.6, base_y), Vector2(sx, base_y - core_h),
	]), Color(1.0, 0.97, 0.78, 0.9))

	# ── Sparks ─────────────────────────────────────────────────────────────────
	for i in range(3):
		var sp: float = fposmod(t * 0.6 + float(i) * 0.37, 1.0)
		var sxp: float = sx + sin(t * 4.0 + float(i) * 2.1) * 5.0
		var syp: float = base_y - sp * 26.0
		draw_circle(Vector2(sxp, syp), 1.0 * (1.0 - sp), Color(1.0, 0.8, 0.4, 1.0 - sp))

func _draw_log(c: Vector2, a: Vector2, b: Vector2, col: Color) -> void:
	var p0 := c + a
	var p1 := c + b
	var n := (p1 - p0).orthogonal().normalized() * 1.8
	draw_colored_polygon(PackedVector2Array([p0 + n, p1 + n, p1 - n, p0 - n]), col)
	draw_circle(p0, 1.9, col.lightened(0.2))
	draw_circle(p1, 1.9, col.lightened(0.2))

# A single faceted flame: a tall triangle plus a side facet, with a wavering apex.
func _draw_flame(sx: float, base_y: float, half_w: float, height: float, phase: float, col: Color) -> void:
	var sway: float = sin(phase) * (half_w * 0.35)
	var apex := Vector2(sx + sway, base_y - height)
	var mid_l := Vector2(sx - half_w, base_y)
	var mid_r := Vector2(sx + half_w, base_y)
	var waist := Vector2(sx + sway * 0.4, base_y - height * 0.45)
	# Left facet (darker) and right facet (the body) for a low-poly shaded look.
	draw_colored_polygon(PackedVector2Array([mid_l, waist, apex]), col.darkened(0.12))
	draw_colored_polygon(PackedVector2Array([mid_r, waist, apex]), col)
