extends Node2D
# Renders & animates the wildlife (deer) read from GameState.wildlife each frame.
# Procedural side-view deer whose animation matches its simulation state:
#   roam → walking gait, feed → head-down grazing, brood → resting/folded,
#   run → fast bounding. Facing flips with movement direction.

const HALF_W: float = 32.0
const HALF_H: float = 16.0

var _selected_id: int = -1

func set_selected(animal_id: int) -> void:
	_selected_id = animal_id

func _process(_delta: float) -> void:
	queue_redraw()  # cheap (a few dozen deer); drives the per-frame animation

func _draw() -> void:
	for a in GameState.wildlife:
		if not (a is Dictionary and a.get("is_alive", false)):
			continue
		var sx: float = (a["x"] - a["y"]) * HALF_W
		var sy: float = (a["x"] + a["y"]) * HALF_H
		_draw_deer(sx, sy, a)

func _draw_deer(sx: float, sy: float, a: Dictionary) -> void:
	var st: String = a.get("state", "roam")
	var face: float = a.get("facing", 1.0)
	var adult: bool = int(a.get("age", 0)) >= 1200
	var t: float = Time.get_ticks_msec() * 0.001
	var sel: bool = a.get("id", -1) == _selected_id

	# Coats: adults rich brown, fawns lighter with a dusting of spots.
	var coat: Color = Color(0.46, 0.31, 0.18) if adult else Color(0.62, 0.45, 0.28)
	var belly: Color = coat.lightened(0.22)
	var dark: Color  = coat.darkened(0.30)

	# Gait/pose parameters per state.
	var gait_speed: float = 0.0
	var gait_amp: float = 0.0
	var bob: float = 0.0          # vertical body bounce
	var body_drop: float = 0.0    # lower the whole body (resting)
	var head_down: float = 0.0    # 0 = head up, 1 = head to ground (grazing)
	match st:
		"run":
			gait_speed = 13.0; gait_amp = 6.0; bob = 2.2 * sin(t * 13.0)
		"roam":
			gait_speed = 6.0; gait_amp = 3.0; bob = 0.8 * sin(t * 6.0)
		"feed":
			head_down = 1.0; bob = 0.4 * sin(t * 2.5)   # gentle munch
		"brood":
			body_drop = 5.0   # settled on the ground
		_:
			pass
	var ph: float = t * gait_speed

	var scale: float = 1.0 if adult else 0.72
	# Work in local space: x to the right is "forward"; multiply by `face` to flip.
	var bx: float = sx
	var gy: float = sy - body_drop            # ground line for the feet
	var body_cy: float = gy - 11.0 * scale + bob

	if sel:
		draw_arc(Vector2(sx, gy - 6.0), 22.0, 0, TAU, 24,
			Color(1.0, 0.95, 0.3, 0.55 + 0.25 * sin(t * 4.0)), 2.0)

	# Ground shadow.
	draw_circle(Vector2(sx, gy + 1.0), 9.0 * scale, Color(0, 0, 0, 0.18))

	# Legs (two front, two back; alternating phase for a gait).
	var leg_top: float = body_cy + 4.0 * scale
	var hips: Array = [10.0, 7.0, -8.0, -11.0]   # x positions of the four legs (forward→back)
	var phases: Array = [0.0, PI, PI, 0.0]
	for i in range(hips.size()):
		var hx: float = bx + face * hips[i] * scale
		var swing: float = sin(ph + phases[i]) * gait_amp * scale
		var lift: float = maxf(0.0, sin(ph + phases[i])) * gait_amp * 0.5 * scale
		var foot := Vector2(hx + face * swing, gy - lift)
		if st == "brood":
			foot = Vector2(hx, gy + 1.0)   # folded under
		draw_line(Vector2(hx, leg_top), foot, dark, 2.2 * scale)

	# Body (rounded torso) + belly highlight.
	_oval(Vector2(bx, body_cy), 13.0 * scale, 7.0 * scale, coat)
	_oval(Vector2(bx, body_cy + 2.5 * scale), 10.0 * scale, 3.5 * scale, belly)

	# Tail (flicks while running).
	var tail_base := Vector2(bx - face * 12.0 * scale, body_cy - 1.0 * scale)
	var tail_tip := tail_base + Vector2(-face * 4.0, 5.0 + (1.5 * sin(t * 14.0) if st == "run" else 0.0)) * scale
	draw_line(tail_base, tail_tip, coat, 2.0 * scale)

	# Neck + head — raised when alert, dropped to the ground when grazing.
	var neck_base := Vector2(bx + face * 11.0 * scale, body_cy - 3.0 * scale)
	var head_up := Vector2(bx + face * 18.0 * scale, body_cy - 12.0 * scale)
	var head_graze := Vector2(bx + face * 17.0 * scale, gy - 2.0 * scale)
	var head := head_up.lerp(head_graze, head_down)
	draw_line(neck_base, head, coat, 3.0 * scale)
	_oval(head, 4.5 * scale, 3.2 * scale, coat)              # head
	_oval(head + Vector2(face * 3.5, 0.5) * scale, 2.2 * scale, 1.6 * scale, coat)  # muzzle
	# Eye.
	draw_circle(head + Vector2(face * 1.5, -1.0) * scale, 0.8 * scale, Color.BLACK)
	# Ears.
	draw_line(head + Vector2(-face * 1.0, -2.5) * scale, head + Vector2(-face * 4.0, -5.0) * scale, dark, 1.6 * scale)
	# Antlers for adult bucks.
	if adult:
		var ab := head + Vector2(face * 1.0, -3.0) * scale
		draw_line(ab, ab + Vector2(face * 2.0, -7.0) * scale, belly, 1.4)
		draw_line(ab + Vector2(face * 1.0, -3.5) * scale, ab + Vector2(face * 5.0, -5.5) * scale, belly, 1.2)
		draw_line(ab + Vector2(face * 1.0, -3.5) * scale, ab + Vector2(face * -1.5, -7.0) * scale, belly, 1.2)

# Filled ellipse (Godot has no draw_ellipse; approximate with a polygon).
func _oval(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(14):
		var ang: float = TAU * float(i) / 14.0
		pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
	draw_colored_polygon(pts, col)
