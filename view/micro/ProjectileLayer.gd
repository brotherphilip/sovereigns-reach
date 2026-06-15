extends Node2D
# Draws arrows/bolts/sling-stones flying from a ranged unit to its target. The sim
# (GameState._tick_unit_attack) emits EventBus.projectile_fired on each ranged strike;
# we animate a short, arcing flight here so archers visibly shoot rather than dealing
# silent instant damage. Purely cosmetic — damage already resolved in the sim.

const HALF_W: float = 32.0
const HALF_H: float = 16.0

# Active shots: { p0, p1, born_ms, dur_ms, kind }
var _shots: Array = []

const _ARROW_MS: int = 280
const _BOLT_MS:  int = 220
const _STONE_MS: int = 560

func _ready() -> void:
	if EventBus.has_signal("projectile_fired"):
		EventBus.projectile_fired.connect(_on_projectile_fired)

func _iso(gx: float, gy: float) -> Vector2:
	return Vector2((gx - gy) * HALF_W, (gx + gy) * HALF_H)

func _on_projectile_fired(fx: int, fy: int, tx: int, ty: int, kind: String) -> void:
	var dur: int = _ARROW_MS
	match kind:
		"bolt":  dur = _BOLT_MS
		"stone": dur = _STONE_MS
	_shots.append({
		"p0": _iso(fx, fy) + Vector2(0, -12.0),   # leaves at bow/shoulder height
		"p1": _iso(tx, ty) + Vector2(0, -8.0),    # strikes the torso
		"born_ms": Time.get_ticks_msec(),
		"dur_ms": dur,
		"kind": kind,
	})
	queue_redraw()

func _process(_delta: float) -> void:
	if not _shots.is_empty():
		queue_redraw()

func _draw() -> void:
	var now: int = Time.get_ticks_msec()
	var alive: Array = []
	for s in _shots:
		var age: float = float(now - s["born_ms"]) / float(s["dur_ms"])
		if age >= 1.0:
			continue
		alive.append(s)
		var p0: Vector2 = s["p0"]
		var p1: Vector2 = s["p1"]
		var pos: Vector2 = p0.lerp(p1, age)
		# Parabolic arc: peak height scales with throw distance (stones loft higher).
		var loft: float = (p0.distance_to(p1) * 0.10 + 5.0) * (2.2 if s["kind"] == "stone" else 1.0)
		pos.y -= sin(age * PI) * loft
		# Heading: chord direction plus the arc's vertical tangent, so it noses over.
		var chord: Vector2 = p1 - p0
		var tangent_y: float = -cos(age * PI) * loft * PI
		var dir: Vector2 = (chord + Vector2(0, tangent_y)).normalized() if chord.length() > 0.001 else Vector2.RIGHT
		_draw_projectile(pos, dir, s["kind"])
	_shots = alive

func _draw_projectile(pos: Vector2, dir: Vector2, kind: String) -> void:
	match kind:
		"stone":
			draw_circle(pos, 2.6, Color(0.52, 0.50, 0.48))
			draw_circle(pos + Vector2(-0.8, -0.8), 1.2, Color(0.66, 0.64, 0.60))
		"bolt":
			var tail_b: Vector2 = pos - dir * 6.0
			draw_line(tail_b, pos, Color(0.82, 0.80, 0.74), 1.7)
			draw_line(pos, pos - dir.rotated(0.45) * 2.6, Color(0.90, 0.90, 0.94), 1.1)
			draw_line(pos, pos - dir.rotated(-0.45) * 2.6, Color(0.90, 0.90, 0.94), 1.1)
		_:  # arrow
			var tail: Vector2 = pos - dir * 8.5
			draw_line(tail, pos, Color(0.74, 0.60, 0.40), 1.2)                       # shaft
			draw_line(pos, pos - dir.rotated(0.4) * 3.0, Color(0.86, 0.86, 0.90), 1.0)  # head
			draw_line(pos, pos - dir.rotated(-0.4) * 3.0, Color(0.86, 0.86, 0.90), 1.0)
			draw_line(tail, tail - dir.rotated(0.6) * 3.0, Color(0.95, 0.95, 0.97), 1.0)  # fletching
			draw_line(tail, tail - dir.rotated(-0.6) * 3.0, Color(0.95, 0.95, 0.97), 1.0)
