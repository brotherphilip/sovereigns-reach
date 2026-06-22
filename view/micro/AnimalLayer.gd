extends Node2D
# Renders & animates the wildlife read from GameState.wildlife each frame. Each species
# (deer, boar, fox, rabbit) is a fully procedural side-view body whose animation matches
# its simulation state:
#   roam → walking/trotting/hopping gait, feed → head-down grazing/rooting/nibbling,
#   brood → resting (deer fold, boar lies, fox curls asleep, rabbit loafs),
#   run → fast bounding/charge/leaping. Facing flips with movement direction.

const HALF_W: float = 32.0
const HALF_H: float = 16.0
const ADULT_AGE: int = 1200   # matches WildlifeSystem.ADULT_AGE (young → adult art)
const SEL_GOLD := Color(1.0, 0.95, 0.3, 1.0)

var _selected_id: int = -1

func set_selected(animal_id: int) -> void:
	_selected_id = animal_id

func _process(_delta: float) -> void:
	queue_redraw()  # cheap (a few dozen animals); drives the per-frame animation

func _draw() -> void:
	for a in GameState.wildlife:
		if not (a is Dictionary and a.get("is_alive", false)):
			continue
		var sx: float = (a["x"] - a["y"]) * HALF_W
		var sy: float = (a["x"] + a["y"]) * HALF_H
		match a.get("type", "deer"):
			"boar":   _draw_boar(sx, sy, a)
			"fox":    _draw_fox(sx, sy, a)
			"rabbit": _draw_rabbit(sx, sy, a)
			_:        _draw_deer(sx, sy, a)

# Pulsing golden selection ring (shared by all species).
func _sel_ring(sx: float, gy: float, r: float, t: float) -> void:
	var col := SEL_GOLD
	col.a = 0.55 + 0.25 * sin(t * 4.0)
	draw_arc(Vector2(sx, gy - 4.0), r, 0, TAU, 24, col, 2.0)

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

# ── Fox ─────────────────────────────────────────────────────────────────────
# Slender rust-red body, cream chest/cheeks, dark stockings, big triangular ears and a
# white-tipped brush tail (the signature). roam → trot, feed → quick ground sniffing,
# run → stretched bound with the tail streaming, brood → curled asleep with the brush
# wrapped over the nose.
func _draw_fox(sx: float, sy: float, a: Dictionary) -> void:
	var st: String = a.get("state", "roam")
	var face: float = a.get("facing", 1.0)
	var adult: bool = int(a.get("age", 0)) >= ADULT_AGE
	var t: float = Time.get_ticks_msec() * 0.001
	var sel: bool = a.get("id", -1) == _selected_id

	var coat: Color = Color(0.80, 0.40, 0.13) if adult else Color(0.70, 0.48, 0.31)
	var cream: Color = Color(0.94, 0.91, 0.83)
	var dark: Color = Color(0.17, 0.12, 0.10)
	var coat_d: Color = coat.darkened(0.24)
	var scale: float = 0.84 if adult else 0.58

	var gait_speed: float = 0.0
	var gait_amp: float = 0.0
	var bob: float = 0.0
	var head_down: float = 0.0
	var stretch: float = 1.0
	var curl: float = 0.0
	match st:
		"run":   gait_speed = 15.0; gait_amp = 6.0; bob = 2.2 * sin(t * 15.0); stretch = 1.18
		"roam":  gait_speed = 8.5; gait_amp = 3.0; bob = 0.9 * sin(t * 8.5)
		"feed":  head_down = 1.0; bob = 0.5 * sin(t * 9.0)
		"brood": curl = 1.0
		_: pass
	var ph: float = t * gait_speed

	var bx: float = sx
	var gy: float = sy
	var body_cy: float = gy - 8.0 * scale + bob

	if sel:
		_sel_ring(sx, gy, 20.0, t)
	draw_circle(Vector2(sx, gy + 1.0), 8.0 * scale, Color(0, 0, 0, 0.16))

	# Curled-asleep pose: a compact ring with the brush curling over a tucked head.
	if curl > 0.5:
		var c := Vector2(bx, gy - 5.0 * scale)
		_oval(c, 11.0 * scale, 7.5 * scale, coat)
		_oval(c + Vector2(0, 2.2 * scale), 7.5 * scale, 4.0 * scale, cream)
		for i in range(6):
			var u: float = float(i) / 5.0
			var tp := c + Vector2(face * (7.0 - 13.0 * u), -2.0 + 6.0 * u) * scale
			_oval(tp, (4.6 - 1.6 * u) * scale, (4.0 - 1.4 * u) * scale, cream if i >= 5 else coat.lerp(cream, u * 0.2))
		var hd := c + Vector2(face * 6.5, 1.5) * scale
		_oval(hd, 4.0 * scale, 3.2 * scale, coat)
		_oval(hd + Vector2(face * 1.0, 1.2) * scale, 2.4 * scale, 1.5 * scale, cream)
		draw_circle(hd + Vector2(face * 3.0, 0.4) * scale, 0.7 * scale, dark)  # nose
		# folded ear — keep real area so the triangulator never sees a collinear sliver.
		draw_colored_polygon(PackedVector2Array([
			hd + Vector2(face * 0.6, -1.6) * scale,
			hd + Vector2(-face * 3.6, -4.6) * scale,
			hd + Vector2(-face * 2.4, -1.2) * scale]), dark)
		return

	# Legs — thin dark stockings with little paws.
	var leg_top: float = body_cy + 3.0 * scale
	var hips: Array = [8.0, 5.5, -6.0, -8.5]
	var phases: Array = [0.0, PI, PI, 0.0]
	for i in range(hips.size()):
		var hx: float = bx + face * hips[i] * scale * stretch
		var swing: float = sin(ph + phases[i]) * gait_amp * scale
		var lift: float = maxf(0.0, sin(ph + phases[i])) * gait_amp * 0.5 * scale
		var foot := Vector2(hx + face * swing, gy - lift)
		draw_line(Vector2(hx, leg_top), foot, dark, 1.8 * scale)
		_oval(foot, 1.3 * scale, 0.9 * scale, dark)

	# Brush tail — coat fading to a white tip, streaming and swaying (lifts when running).
	var tail_lift: float = -3.0 if st == "run" else 1.5
	var tbase := Vector2(bx - face * 9.0 * scale * stretch, body_cy - 1.0 * scale)
	for i in range(6):
		var u: float = float(i) / 5.0
		var sway: float = sin(t * (10.0 if st == "run" else 3.0) - u * 2.0) * (2.0 if st == "run" else 1.0)
		var tp := tbase + Vector2(-face * (3.0 + 9.0 * u), tail_lift * u + sway) * scale
		_oval(tp, (4.8 - 2.4 * u) * scale, (4.2 - 2.1 * u) * scale, cream if i >= 5 else coat.lerp(cream, u * 0.22))

	# Body — slender oval with a cream chest/belly.
	_oval(Vector2(bx, body_cy), 10.0 * scale * stretch, 5.2 * scale, coat)
	_oval(Vector2(bx + face * 3.0 * scale, body_cy + 2.2 * scale), 6.0 * scale, 2.6 * scale, cream)

	# Neck + head (raised when alert, dropped when sniffing).
	var neck := Vector2(bx + face * 8.0 * scale * stretch, body_cy - 2.0 * scale)
	var head_up := Vector2(bx + face * 13.0 * scale, body_cy - 6.0 * scale)
	var head_low := Vector2(bx + face * 14.0 * scale, gy - 2.0 * scale)
	var head := head_up.lerp(head_low, head_down)
	draw_line(neck, head, coat, 3.2 * scale)
	# Big pointed ears: dark backs, rust front.
	var etw: float = sin(t * 5.0) * 0.6
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(-face * 1.5, -2.4) * scale, head + Vector2(-face * 0.5 + etw, -7.8) * scale,
		head + Vector2(face * 1.5, -2.0) * scale]), dark)
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(face * 1.0, -2.4) * scale, head + Vector2(face * 3.2 + etw, -7.0) * scale,
		head + Vector2(face * 3.5, -1.6) * scale]), coat_d)
	# Head mass + cream cheek + pointed snout.
	_oval(head, 4.0 * scale, 3.2 * scale, coat)
	_oval(head + Vector2(face * 1.2, 1.6) * scale, 3.0 * scale, 1.8 * scale, cream)
	var snout := head + Vector2(face * 5.6, 0.7) * scale
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(face * 2.0, -1.4) * scale, snout, head + Vector2(face * 2.0, 2.2) * scale]), coat)
	draw_circle(snout, 1.0 * scale, dark)
	draw_circle(head + Vector2(face * 1.4, -0.8) * scale, 0.8 * scale, Color.BLACK)  # eye

# ── Boar ────────────────────────────────────────────────────────────────────
# Bulky dark-bristled body, hunched shoulder hump, a spiny mane ridge, short stout legs,
# a big low-slung wedge head with snout disc and (adult) tusks. roam → heavy trudge,
# feed → rooting the ground (snout digs, dirt flies), run → head-low charge, brood →
# lying down. Piglets are tan with stripes.
func _draw_boar(sx: float, sy: float, a: Dictionary) -> void:
	var st: String = a.get("state", "roam")
	var face: float = a.get("facing", 1.0)
	var adult: bool = int(a.get("age", 0)) >= ADULT_AGE
	var t: float = Time.get_ticks_msec() * 0.001
	var sel: bool = a.get("id", -1) == _selected_id

	var coat: Color = Color(0.28, 0.23, 0.20) if adult else Color(0.55, 0.42, 0.29)
	var belly: Color = coat.lightened(0.12)
	var dark: Color = Color(0.13, 0.10, 0.09)
	var bristle: Color = coat.darkened(0.30)
	var snoutc: Color = Color(0.42, 0.33, 0.31)
	var scale: float = 1.05 if adult else 0.64

	var gait_speed: float = 0.0
	var gait_amp: float = 0.0
	var bob: float = 0.0
	var body_drop: float = 0.0
	var head_down: float = 0.0
	var root: float = 0.0
	match st:
		"run":   gait_speed = 12.0; gait_amp = 4.5; bob = 1.6 * sin(t * 12.0); head_down = 0.55
		"roam":  gait_speed = 5.0; gait_amp = 2.2; bob = 0.6 * sin(t * 5.0)
		"feed":  head_down = 1.0; root = 1.0; bob = 0.3 * sin(t * 3.0)
		"brood": body_drop = 5.0
		_: pass
	var ph: float = t * gait_speed

	var bx: float = sx
	var gy: float = sy - body_drop
	var body_cy: float = gy - 12.0 * scale + bob

	if sel:
		_sel_ring(sx, gy, 26.0, t)
	draw_circle(Vector2(sx, gy + 1.0), 12.0 * scale, Color(0, 0, 0, 0.20))

	# Legs — short and stout.
	var leg_top: float = body_cy + 5.0 * scale
	var hips: Array = [9.0, 6.0, -7.0, -10.0]
	var phases: Array = [0.0, PI, PI, 0.0]
	for i in range(hips.size()):
		var hx: float = bx + face * hips[i] * scale
		var swing: float = sin(ph + phases[i]) * gait_amp * scale
		var lift: float = maxf(0.0, sin(ph + phases[i])) * gait_amp * 0.4 * scale
		var foot := Vector2(hx + face * swing, gy - lift)
		if st == "brood":
			foot = Vector2(hx, gy + 1.0)
		draw_line(Vector2(hx, leg_top), foot, dark, 3.0 * scale)
		_oval(Vector2(foot.x, gy + 0.5), 1.6 * scale, 1.0 * scale, dark)  # hoof

	# Tail — thin with a tuft.
	var tb := Vector2(bx - face * 13.0 * scale, body_cy - 2.0 * scale)
	var tt := tb + Vector2(-face * 2.0, -3.0 + sin(t * 8.0) * 1.0) * scale
	draw_line(tb, tt, dark, 1.6 * scale)
	_oval(tt, 1.6 * scale, 1.6 * scale, bristle)

	# Body — barrel rump + a higher shoulder hump (hunched), light belly.
	_oval(Vector2(bx - face * 3.0 * scale, body_cy + 1.0 * scale), 14.0 * scale, 9.0 * scale, coat)
	_oval(Vector2(bx + face * 6.0 * scale, body_cy - 2.0 * scale), 10.5 * scale, 9.5 * scale, coat)
	_oval(Vector2(bx - face * 1.0 * scale, body_cy + 5.0 * scale), 11.0 * scale, 3.5 * scale, belly)
	# Piglet stripes.
	if not adult:
		for k in range(3):
			var yo: float = body_cy + (-2.0 + k * 3.0) * scale
			draw_line(Vector2(bx - 9.0 * scale, yo), Vector2(bx + 8.0 * scale, yo), bristle, 1.2 * scale)

	# Spiny mane ridge running nape→rump, swaying gently.
	for i in range(8):
		var u: float = float(i) / 7.0
		var base := Vector2(bx + face * (9.0 - 19.0 * u) * scale, body_cy - 8.0 * scale + 2.0 * u * scale)
		var sway: float = sin(t * 4.0 + u * 4.0) * 1.0 * scale
		var tip := base + Vector2(-face * 1.0 + sway, -4.5 - 2.2 * sin(u * PI)) * scale
		draw_line(base, tip, bristle, 1.7 * scale)

	# Head — large low wedge; lowers to the ground when rooting (with a digging jitter).
	var head_up := Vector2(bx + face * 15.0 * scale, body_cy - 1.0 * scale)
	var head_dn := Vector2(bx + face * 16.0 * scale, gy - 3.0 * scale)
	var jit: float = (sin(t * 20.0) * 1.5 * scale) if root > 0.5 else 0.0
	var head := head_up.lerp(head_dn, head_down) + Vector2(0, jit)
	# Neck wedge linking shoulders to head.
	draw_colored_polygon(PackedVector2Array([
		Vector2(bx + face * 4.0 * scale, body_cy - 6.0 * scale),
		Vector2(bx + face * 5.0 * scale, body_cy + 5.0 * scale),
		head + Vector2(0, 5.0 * scale), head + Vector2(0, -5.0 * scale)]), coat)
	_oval(head, 6.5 * scale, 5.2 * scale, coat)
	# Snout disc + nostrils.
	var snout := head + Vector2(face * 6.8, 1.2) * scale
	_oval(snout, 2.8 * scale, 2.3 * scale, snoutc)
	draw_circle(snout + Vector2(face * 0.8, -0.5) * scale, 0.5 * scale, dark)
	draw_circle(snout + Vector2(face * 0.8, 0.9) * scale, 0.5 * scale, dark)
	# Tusks (adult) — pale, curving up.
	if adult:
		var tk := head + Vector2(face * 5.2, 2.0) * scale
		draw_line(tk, tk + Vector2(face * 2.2, -3.4) * scale, Color(0.92, 0.90, 0.82), 1.7 * scale)
		draw_line(tk + Vector2(face * 0.4, 0.4) * scale, tk + Vector2(face * 1.0, -2.2) * scale, Color(0.92, 0.90, 0.82), 1.2 * scale)
	draw_circle(head + Vector2(face * 1.8, -2.2) * scale, 0.8 * scale, Color.BLACK)  # eye
	# Small back-swept ear — a proper triangle with real area (the old three points were
	# almost collinear, which made Godot's triangulator fail every frame).
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(-face * 1.4, -3.6) * scale,
		head + Vector2(-face * 5.2, -6.4) * scale,
		head + Vector2(-face * 3.4, -2.0) * scale]), bristle)
	# Kicked-up dirt while rooting.
	if root > 0.5:
		for k in range(3):
			var dp := snout + Vector2(face * (2.0 + k * 1.5), 2.5 + sin(t * 15.0 + float(k)) * 1.8) * scale
			draw_circle(dp, 0.8 * scale, Color(0.40, 0.30, 0.20, 0.7))

# ── Rabbit ──────────────────────────────────────────────────────────────────
# Tiny, round, grey-brown with a big rounded haunch, long upright ears (pink inner), a
# twitching nose and a white scut. Distinct HOP gait: the whole body rises in an arc
# (shadow shrinks with height); ears lay back at speed. feed → sit & nibble, brood →
# crouched "loaf" with ears flat.
func _draw_rabbit(sx: float, sy: float, a: Dictionary) -> void:
	var st: String = a.get("state", "roam")
	var face: float = a.get("facing", 1.0)
	var adult: bool = int(a.get("age", 0)) >= ADULT_AGE
	var t: float = Time.get_ticks_msec() * 0.001
	var sel: bool = a.get("id", -1) == _selected_id

	var coat: Color = Color(0.56, 0.48, 0.39) if adult else Color(0.67, 0.59, 0.49)
	var belly: Color = Color(0.90, 0.86, 0.78)
	var dark: Color = Color(0.27, 0.23, 0.19)
	var pink: Color = Color(0.86, 0.56, 0.56)
	var scale: float = 0.58 if adult else 0.42

	var hop_speed: float = 0.0
	var hop_amp: float = 0.0
	var ear_back: float = 0.0
	var crouch: float = 0.0
	var nibble: float = 0.0
	match st:
		"run":   hop_speed = 8.5; hop_amp = 9.0; ear_back = 1.0
		"roam":  hop_speed = 3.2; hop_amp = 4.0
		"feed":  nibble = 1.0; crouch = 0.45
		"brood": crouch = 1.0; ear_back = 1.0
		_: pass
	var hp: float = t * hop_speed
	var hop: float = maxf(0.0, sin(hp))           # 0 grounded → 1 apex
	var lift: float = hop * hop_amp * scale
	var stretch: float = 1.0 + (0.25 * hop if st == "run" else 0.0)

	var bx: float = sx
	var gy: float = sy
	var body_cy: float = gy - 5.0 * scale - lift + crouch * 2.0 * scale

	if sel:
		_sel_ring(sx, gy, 15.0, t)
	# Shadow shrinks as it leaves the ground (height cue).
	draw_circle(Vector2(sx, gy + 1.0), (6.0 - 2.0 * hop) * scale, Color(0, 0, 0, 0.16))

	# Big hind foot (planted low, tucks up mid-hop) + thin front paw.
	_oval(Vector2(bx - face * 4.0 * scale, gy - lift * 0.4), 3.4 * scale * stretch, 1.6 * scale, coat)
	draw_line(Vector2(bx + face * 3.0 * scale, body_cy + 2.0 * scale),
		Vector2(bx + face * 4.0 * scale, gy - lift * 0.7), dark, 1.6 * scale)

	# Haunch (signature rounded rear) + body + cream belly + scut.
	_oval(Vector2(bx - face * 3.0 * scale, body_cy + 1.0 * scale), 6.5 * scale, 5.6 * scale, coat)
	_oval(Vector2(bx, body_cy), 6.5 * scale * stretch, 4.6 * scale, coat)
	_oval(Vector2(bx + face * 1.0 * scale, body_cy + 2.2 * scale), 5.0 * scale, 2.4 * scale, belly)
	_oval(Vector2(bx - face * 7.0 * scale, body_cy + 0.5 * scale), 2.2 * scale, 2.2 * scale, belly)

	# Head — round, sits forward; quick nibble dips when feeding.
	var head := Vector2(bx + face * 6.0 * scale, body_cy - 3.0 * scale - crouch * 1.0 * scale)
	if nibble > 0.5:
		head += Vector2(0, sin(t * 16.0) * 0.8 * scale)
	# Long ears — upright by default, swept back at speed/rest; pink inner stripe.
	var etw: float = sin(t * 4.0) * 0.5
	for eo in [-1.2 * scale, 1.6 * scale]:
		var ebase := head + Vector2(0, -2.5 * scale) + Vector2(eo, 0)
		var up_tip := ebase + Vector2(face * 0.5 + etw, -9.0 * scale)
		var bk_tip := ebase + Vector2(-face * 5.5 * scale, -1.0 * scale)
		var etip := up_tip.lerp(bk_tip, ear_back)
		draw_line(ebase, etip, coat, 2.6 * scale)
		draw_line(ebase.lerp(etip, 0.18), ebase.lerp(etip, 0.82), pink, 1.0 * scale)
	_oval(head, 3.7 * scale, 3.2 * scale, coat)
	_oval(head + Vector2(face * 1.0, 1.2) * scale, 2.4 * scale, 1.6 * scale, belly)
	# Twitching nose + eye.
	draw_circle(head + Vector2(face * 3.2, 0.6) * scale + Vector2(sin(t * 12.0) * 0.3 * scale, 0), 0.7 * scale, pink)
	draw_circle(head + Vector2(face * 1.4, -0.6) * scale, 0.9 * scale, Color.BLACK)

# Filled ellipse (Godot has no draw_ellipse; approximate with a polygon).
func _oval(c: Vector2, rx: float, ry: float, col: Color) -> void:
	rx = absf(rx)
	ry = absf(ry)
	if not (is_finite(c.x) and is_finite(c.y)) or rx < 0.01 or ry < 0.01:
		return
	# Build the points around the ORIGIN (small magnitudes) and translate via the
	# canvas transform. A tiny polygon (e.g. a 1px foot) built at the animal's large
	# world coords makes Godot's triangulator lose precision and fail ("triangulation
	# failed"); building locally then translating keeps it exact.
	var pts := PackedVector2Array()
	for i in range(14):
		var ang: float = TAU * float(i) / 14.0
		pts.append(Vector2(cos(ang) * rx, sin(ang) * ry))
	draw_set_transform(c)
	draw_colored_polygon(pts, col)
	draw_set_transform(Vector2.ZERO)
