extends Node2D
# Renders & animates villager pawns from GameState.citizens. Procedural little
# people whose animation matches their state: walking gait (walk/wander), standing
# (idle/work), and hammering with a raised mallet (build). Builders carry a tool.

const HALF_W: float = 32.0
const HALF_H: float = 16.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	for c in GameState.citizens:
		if not (c is Dictionary and c.get("is_alive", false)):
			continue
		var sx: float = (c["x"] - c["y"]) * HALF_W
		var sy: float = (c["x"] + c["y"]) * HALF_H
		_draw_citizen(sx, sy, c)

func _draw_citizen(sx: float, sy: float, c: Dictionary) -> void:
	var st: String = c.get("state", "idle")
	var face: float = c.get("facing", 1.0)
	var builder: bool = c.get("role", "") == "builder"
	var t: float = Time.get_ticks_msec() * 0.001
	var moving: bool = st == "walk" or st == "wander"

	var tunic: Color = Color(0.30, 0.42, 0.55) if builder else Color(0.50, 0.36, 0.22)
	var skin: Color = Color(0.86, 0.70, 0.55)
	var dark: Color = tunic.darkened(0.3)

	var gait: float = (sin(t * 9.0) if moving else 0.0)
	var bob: float = (abs(sin(t * 9.0)) * 1.2 if moving else 0.0)
	var gy: float = sy            # feet on the ground
	var hip: float = gy - 7.0 - bob
	var shoulder: float = gy - 13.0 - bob

	# Shadow.
	draw_circle(Vector2(sx, gy + 1.0), 4.5, Color(0, 0, 0, 0.18))

	# Legs (swing when moving).
	draw_line(Vector2(sx, hip), Vector2(sx - 2.0 + gait * 2.5, gy), dark, 1.8)
	draw_line(Vector2(sx, hip), Vector2(sx + 2.0 - gait * 2.5, gy), dark, 1.8)

	# Torso.
	draw_line(Vector2(sx, hip), Vector2(sx, shoulder), tunic, 4.0)

	# Arms / tool.
	if st == "build":
		# Hammering: swing a mallet up and down.
		var swing: float = sin(t * 10.0) * 0.9
		var hand := Vector2(sx + face * (4.0 + 2.0 * swing), shoulder - 4.0 + swing * 6.0)
		draw_line(Vector2(sx, shoulder), hand, skin, 1.8)
		draw_line(hand, hand + Vector2(face * 5.0, -3.0), Color(0.4, 0.28, 0.16), 1.6)   # handle
		draw_rect(Rect2(hand.x + face * 4.0 - 2.0, hand.y - 4.5, 4.0, 4.0), Color(0.55, 0.55, 0.6))  # head
	else:
		var arm_swing: float = gait * 2.0
		draw_line(Vector2(sx, shoulder), Vector2(sx + face * 3.0 + arm_swing, hip + 1.0), skin, 1.6)
		if builder:
			# Mallet slung over the shoulder when not building.
			draw_line(Vector2(sx, shoulder), Vector2(sx - face * 3.0, shoulder - 6.0), Color(0.4, 0.28, 0.16), 1.6)
			draw_rect(Rect2(sx - face * 3.0 - 2.0, shoulder - 8.5, 4.0, 3.5), Color(0.55, 0.55, 0.6))

	# Head.
	draw_circle(Vector2(sx, shoulder - 3.0), 3.0, skin)
