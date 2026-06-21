extends Node2D
# Ambient wildlife in the sky — purely a VIEW effect (no game-sim / no save state), driven by
# _process(delta) so it's smooth and frame-rate independent. Several FLOCKS of little white
# cockatiels (each a boids swarm) and a handful of solitary soaring EAGLES are scattered ACROSS
# THE WHOLE MAP and roam it — picking far destinations and crossing the land — so they're not
# tethered to the town. Now and then a flock drops to perch in the trees; at night they roost.

const HALF_W: float = 32.0
const HALF_H: float = 16.0

const FlockState = preload("res://simulation/world/SeasonSystem.gd")

const NUM_FLOCKS: int = 5
const FLOCK_SIZE: int = 11
const EAGLES_MIN: int = 5
const EAGLES_MAX: int = 7

# Cockatiel boids tuning.
const COCK_CRUISE: float = 80.0
const COCK_MAX: float = 120.0
const COCK_MIN: float = 40.0
const COH: float = 0.9
const ALIGN: float = 1.2
const SEP: float = 230.0
const SEP_R: float = 16.0
const SEEK: float = 50.0
const CRUISE_ALT: float = 80.0
const ARRIVE: float = 140.0     # within this of its goal, a flock picks a new far destination

var _t: float = 0.0
var _init_done: bool = false
var _flocks: Array = []
var _eagles: Array = []

# Camera kept only so a freshly-entered scene seeds the FIRST flock near the view; the rest
# spawn across the map and everyone roams freely.
var _camera: Camera2D = null

func set_camera(cam: Camera2D) -> void:
	_camera = cam

func _is_night() -> bool:
	return FlockState.is_night(SimulationClock.current_tick)

# A random point anywhere over the playable map (tile → world px).
func _rand_map_point() -> Vector2:
	var gx: int = randi_range(8, 192)
	var gy: int = randi_range(8, 192)
	return Vector2((gx - gy) * HALF_W, (gx + gy) * HALF_H)

func _ensure_init() -> void:
	if _init_done:
		return
	for fi in range(NUM_FLOCKS):
		var anchor := _rand_map_point()
		if fi == 0 and _camera != null:
			anchor = _camera.get_screen_center_position()   # one flock greets the player
		var birds: Array = []
		for _i in range(FLOCK_SIZE):
			birds.append({
				"pos": anchor + Vector2(randf_range(-60.0, 60.0), randf_range(-60.0, 60.0)),
				"vel": Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * COCK_CRUISE,
				"wing": randf() * TAU, "alt": CRUISE_ALT + randf_range(-14.0, 14.0),
				"perch": Vector2.ZERO,
			})
		_flocks.append({
			"birds": birds, "goal": _rand_map_point(), "mode": "fly",
			"mode_timer": randf_range(14.0, 30.0), "perch": Vector2.ZERO,
		})
	var n_eagles: int = randi_range(EAGLES_MIN, EAGLES_MAX)
	for _i in range(n_eagles):
		var ec := _rand_map_point()
		_eagles.append({
			"center": ec, "target": _rand_map_point(), "ang": randf() * TAU,
			"rad": randf_range(80.0, 150.0), "spin": randf_range(0.16, 0.30) * (1.0 if randf() < 0.5 else -1.0),
			"pos": ec, "vel": Vector2.RIGHT, "wing": randf() * TAU,
			"alt": 130.0 + randf_range(-25.0, 35.0), "flap": 0.0,
		})
	_init_done = true

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_ensure_init()
	_t += delta
	var night := _is_night()
	for f in _flocks:
		_update_flock(f, delta, night)
	_update_eagles(delta, night)
	queue_redraw()

# ── Cockatiel flock ──────────────────────────────────────────────────────────────
func _update_flock(f: Dictionary, delta: float, night: bool) -> void:
	var birds: Array = f["birds"]
	# Flock centroid for cohesion / perch search.
	var center := Vector2.ZERO
	var mean_vel := Vector2.ZERO
	for b in birds:
		center += b["pos"]
		mean_vel += b["vel"]
	center /= float(birds.size())
	mean_vel /= float(birds.size())

	f["mode_timer"] -= delta
	# Mood: roost at night; otherwise wheel across the map, settling in the trees now and then.
	if night:
		if f["mode"] != "perch" and f["mode"] != "descend":
			_begin_descent(f, center)
	elif f["mode"] == "fly":
		# Reached the destination → strike out for a far new one (explore the whole map).
		if center.distance_to(f["goal"]) < ARRIVE:
			f["goal"] = _rand_map_point()
		if f["mode_timer"] <= 0.0:
			_begin_descent(f, center)
	elif f["mode"] == "descend":
		var landed := 0
		for b in birds:
			if b["alt"] < 6.0 and b["pos"].distance_to(b["perch"]) < 12.0:
				landed += 1
		if landed >= birds.size() - 2:
			f["mode"] = "perch"
			f["mode_timer"] = randf_range(5.0, 11.0)
	elif f["mode"] == "perch" and not night and f["mode_timer"] <= 0.0:
		f["mode"] = "fly"
		f["mode_timer"] = randf_range(18.0, 36.0)
		f["goal"] = _rand_map_point()

	for i in range(birds.size()):
		var b: Dictionary = birds[i]
		if f["mode"] == "perch":
			b["pos"] = b["pos"].lerp(b["perch"], clampf(delta * 3.0, 0.0, 1.0))
			b["alt"] = lerpf(b["alt"], 0.0, clampf(delta * 3.0, 0.0, 1.0))
			b["vel"] = Vector2.ZERO
			b["wing"] += delta * 2.0   # the odd settling flutter
			continue
		var steer := Vector2.ZERO
		if f["mode"] == "descend":
			steer += (b["perch"] - b["pos"]) * 1.6
			b["alt"] = lerpf(b["alt"], 0.0, clampf(delta * 1.1, 0.0, 1.0))
		else:
			steer += (center - b["pos"]) * COH
			steer += (mean_vel - b["vel"]) * ALIGN
			for j in range(birds.size()):
				if j == i:
					continue
				var d: Vector2 = b["pos"] - birds[j]["pos"]
				var dl: float = d.length()
				if dl > 0.001 and dl < SEP_R:
					steer += (d / dl) * (SEP * (SEP_R - dl) / SEP_R)
			steer += (f["goal"] - b["pos"]).normalized() * SEEK
			if randf() < 0.004:   # a bird breaks off; cohesion reels it back
				steer += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * 280.0
			b["alt"] = lerpf(b["alt"], CRUISE_ALT + sin(_t * 1.3 + i) * 7.0, clampf(delta * 1.5, 0.0, 1.0))
		b["vel"] += steer * delta
		b["vel"] = b["vel"].limit_length(COCK_MAX)
		if b["vel"].length() < COCK_MIN:
			b["vel"] = (b["vel"].normalized() if b["vel"].length() > 0.001 else Vector2.RIGHT) * COCK_MIN
		b["pos"] += b["vel"] * delta
		b["wing"] += delta * 11.5   # a clear, steady ~1.8 Hz wing-beat

func _begin_descent(f: Dictionary, center: Vector2) -> void:
	var perch := _find_perch_near(center)
	f["mode"] = "descend"
	f["mode_timer"] = 16.0
	for b in f["birds"]:
		b["perch"] = perch + Vector2(randf_range(-24.0, 24.0), randf_range(-12.0, 6.0))

# Find a treetop near a world point to settle on; else a spot just below it.
func _find_perch_near(at: Vector2) -> Vector2:
	var gx0: int = int(floor(at.x / (2.0 * HALF_W) + at.y / (2.0 * HALF_H)))
	var gy0: int = int(floor(at.y / (2.0 * HALF_H) - at.x / (2.0 * HALF_W)))
	for _try in range(48):
		var gx: int = gx0 + (randi() % 15) - 7
		var gy: int = gy0 + (randi() % 15) - 7
		if GameState.get_terrain_at(gx, gy) == 1:   # FOREST
			return Vector2((gx - gy) * HALF_W, (gx + gy) * HALF_H - 12.0)
	return at + Vector2(0.0, 40.0)

# ── Eagles ───────────────────────────────────────────────────────────────────────
func _update_eagles(delta: float, night: bool) -> void:
	for e in _eagles:
		# The soaring centre wanders the whole map: drift toward a target, pick a new far one
		# on arrival, so each eagle ranges across the land rather than circling one spot.
		if e["center"].distance_to(e["target"]) < 120.0:
			e["target"] = _rand_map_point()
		e["center"] = e["center"].move_toward(e["target"], 34.0 * delta)
		var prev: Vector2 = e["pos"]
		if night:
			e["alt"] = lerpf(e["alt"], 0.0, clampf(delta * 0.6, 0.0, 1.0))
			e["pos"] = e["pos"].lerp(_find_perch_near(e["pos"]), clampf(delta * 0.6, 0.0, 1.0))
		else:
			e["ang"] += e["spin"] * delta
			e["alt"] = lerpf(e["alt"], 134.0 + sin(_t * 0.5) * 10.0, clampf(delta, 0.0, 1.0))
			e["pos"] = e["center"] + Vector2(cos(e["ang"]) * e["rad"], sin(e["ang"]) * e["rad"] * 0.5)
		e["vel"] = e["pos"] - prev
		e["wing"] += delta * 4.0
		e["flap"] = lerpf(e["flap"], 0.25 + 0.9 * float(randf() < 0.012), clampf(delta * 2.0, 0.0, 1.0))

# ── Drawing ──────────────────────────────────────────────────────────────────────
func _draw() -> void:
	if not _init_done:
		return
	for f in _flocks:
		for b in f["birds"]:
			_draw_cockatiel(b)
	for e in _eagles:
		_draw_eagle(e)

func _draw_cockatiel(b: Dictionary) -> void:
	var ground: Vector2 = b["pos"]
	var flap: float = sin(b["wing"])             # -1 (wings down) … +1 (wings up)
	var perched: bool = b["alt"] < 6.0
	if perched:
		flap = -0.9                              # folded at rest
	# Body bobs up on the power (down) stroke — a lively flight cue.
	var bob: float = -absf(flap) * 1.6
	var p: Vector2 = ground - Vector2(0.0, b["alt"] - bob)
	var sh: float = clampf(1.0 - b["alt"] / 120.0, 0.2, 1.0)
	draw_circle(ground + Vector2(0.0, 2.0), 2.4 * sh, Color(0.0, 0.0, 0.0, 0.12 * sh))
	var face: float = 1.0 if b["vel"].x >= 0.0 else -1.0
	# Wings sweep a BIG arc: tips swing high above the body on the upstroke and well below on
	# the down, so the flap is unmistakable. Drawn as bent strokes (flap-safe, no degenerate
	# polygons) — an elbow gives them a real wing shape.
	var ty: float = -flap * 8.5                  # wing-tip vertical travel
	var tx: float = 6.4 - absf(flap) * 1.8       # span foreshortens at the extremes of the beat
	var white := Color(0.97, 0.97, 0.93)
	var shdr := p + Vector2(0.0, -1.0)
	draw_polyline(PackedVector2Array([shdr, p + Vector2(-face * 3.0, ty * 0.5 - 0.5), p + Vector2(-face * tx, ty - 1.0)]), white, 1.8)
	draw_polyline(PackedVector2Array([shdr, p + Vector2(face * 3.0, ty * 0.5 - 0.5), p + Vector2(face * tx, ty - 1.0)]), white, 1.8)
	draw_circle(p, 1.9, white)
	var hp: Vector2 = p + Vector2(face * 2.2, -1.1)
	draw_circle(hp, 1.2, white)
	draw_line(hp + Vector2(0.0, -0.8), hp + Vector2(face * 0.6, -3.6), Color(0.95, 0.82, 0.42), 1.0)
	draw_circle(hp + Vector2(face * 0.6, 0.3), 0.5, Color(0.95, 0.58, 0.30))

func _draw_eagle(e: Dictionary) -> void:
	var ground: Vector2 = e["pos"]
	var flap: float = sin(e["wing"]) * (0.4 + e["flap"])
	var p: Vector2 = ground - Vector2(0.0, e["alt"] - absf(flap) * 1.5)
	var sh: float = clampf(1.0 - e["alt"] / 160.0, 0.15, 1.0)
	draw_circle(ground + Vector2(0.0, 2.0), 5.0 * sh, Color(0.0, 0.0, 0.0, 0.13 * sh))
	var face: float = 1.0 if e["vel"].x >= 0.0 else -1.0
	var wtip: float = -flap * 8.5 - 2.0          # broad, slow wing-beats over a soaring V
	var body := Color(0.28, 0.20, 0.12)
	var wing := Color(0.22, 0.15, 0.09)
	# Broad bent wings as thick strokes (flap-safe).
	var esh := p + Vector2(0.0, -1.0)
	draw_polyline(PackedVector2Array([esh, p + Vector2(-6.5, wtip * 0.5 - 1.0), p + Vector2(-13.0, wtip)]), wing, 2.6)
	draw_polyline(PackedVector2Array([esh, p + Vector2(6.5, wtip * 0.5 - 1.0), p + Vector2(13.0, wtip)]), wing.lightened(0.05), 2.6)
	draw_colored_polygon(PackedVector2Array([p, p + Vector2(-face * 5.0, 2.0), p + Vector2(-face * 3.5, -1.2)]), body)
	draw_circle(p, 2.5, body)
	draw_circle(p + Vector2(face * 3.0, -0.6), 1.6, Color(0.93, 0.92, 0.88))
	draw_circle(p + Vector2(face * 4.2, -0.6), 0.7, Color(0.92, 0.78, 0.30))
