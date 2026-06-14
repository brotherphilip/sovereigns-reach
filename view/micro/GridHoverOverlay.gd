extends Node2D
# Lightweight overlay that draws only the single build-mode hover tile, so hover
# updates never force the (static, cached) terrain grid to repaint all its tiles.

const HALF_W: float = 32.0
const HALF_H: float = 16.0

var _active: bool = false
var _gx: int = 0
var _gy: int = 0
var _valid: bool = true

func set_tile(gx: int, gy: int, valid: bool) -> void:
	_active = true
	_gx = gx
	_gy = gy
	_valid = valid
	queue_redraw()

func clear_tile() -> void:
	if not _active:
		return
	_active = false
	queue_redraw()

func _draw() -> void:
	if not _active:
		return
	var cx: float = (_gx - _gy) * HALF_W
	var cy: float = (_gx + _gy) * HALF_H
	var pts := PackedVector2Array([
		Vector2(cx, cy - HALF_H), Vector2(cx + HALF_W, cy),
		Vector2(cx, cy + HALF_H), Vector2(cx - HALF_W, cy),
	])
	var fill: Color = Color(0.25, 1.0, 0.45, 0.22) if _valid else Color(1.0, 0.25, 0.25, 0.22)
	var line: Color = Color(0.35, 1.0, 0.55, 0.95) if _valid else Color(1.0, 0.30, 0.30, 0.95)
	draw_colored_polygon(pts, fill)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), line, 1.5)
