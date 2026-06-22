extends RefCounted
# Wandering animal herds (deer, boar, fox, rabbit — see TYPES). Pure-data simulation:
# every animal is a JSON-serializable Dictionary in GameState.wildlife, advanced
# deterministically from a seeded RNG each tick. Herding (boids-lite cohesion +
# separation), slow roaming, a state machine (roam / feed / brood / run), threat flight,
# and slow breeding. Each species carries its own size band, speed, toughness and idle
# rhythm via TYPES. The view layer reads these fields to render & animate per species.

# ── States ────────────────────────────────────────────────────────────────────
const STATE_ROAM  = "roam"    # ambling toward the herd, light wander
const STATE_FEED  = "feed"    # head-down grazing, stationary
const STATE_BROOD = "brood"   # resting, stationary
const STATE_RUN   = "run"     # fleeing a threat, fast

# ── Tuning (grid tiles; ticks at 20/s) ───────────────────────────────────────
const ROAM_SPEED: float = 0.018    # ~0.36 tiles/s — slow amble
const RUN_SPEED: float  = 0.13     # bounding flight
const THREAT_RADIUS: float = 9.0   # tiles; deer flee units within this
const SAFE_TICKS: int = 60         # keep running this long after threat clears

const COHESION: float = 0.55       # pull toward herd centre
const SEPARATION: float = 1.1      # push off close neighbours
const SEPARATION_RADIUS: float = 1.8
const WANDER: float = 0.5          # random steering

const ROAM_TICKS := Vector2i(120, 320)
const FEED_TICKS := Vector2i(160, 360)
const BROOD_TICKS := Vector2i(200, 480)

const ADULT_AGE: int = 1200        # ticks before an animal can breed
const HERD_CAP: int = 9            # max animals per herd (deer; per-type cap in TYPES)
const BREED_INTERVAL: int = 1800   # min ticks between births per herd
const FAWN_MAX_HP: int = 12
const ADULT_MAX_HP: int = 24

# ── Species ──────────────────────────────────────────────────────────────────
# Per-type tuning. herd = group-size band at spawn; cap = breeding cap; speed scales
# the roam/run velocity; feed_w/brood_w bias the idle state pick (rest is roam) so each
# species has its own rhythm (boar roots a lot, fox rests curled, rabbit nibbles &
# freezes, deer grazes). hp tunes toughness. All JSON-safe primitives.
const TYPES := {
	"deer":   {"herd": Vector2i(5, 7), "cap": 9,  "speed": 1.0,  "adult_hp": 24, "young_hp": 12, "feed_w": 0.45, "brood_w": 0.20},
	"boar":   {"herd": Vector2i(4, 6), "cap": 7,  "speed": 0.82, "adult_hp": 34, "young_hp": 16, "feed_w": 0.55, "brood_w": 0.14},
	"fox":    {"herd": Vector2i(2, 4), "cap": 5,  "speed": 1.32, "adult_hp": 16, "young_hp": 8,  "feed_w": 0.28, "brood_w": 0.38},
	"rabbit": {"herd": Vector2i(4, 7), "cap": 12, "speed": 1.18, "adult_hp": 8,  "young_hp": 5,  "feed_w": 0.50, "brood_w": 0.26},
}

static func cfg(type: String) -> Dictionary:
	return TYPES.get(type, TYPES["deer"])

# ── Spawning ──────────────────────────────────────────────────────────────────

static func make_animal(id: int, herd_id: int, x: float, y: float, adult: bool,
		type: String = "deer") -> Dictionary:
	var c: Dictionary = cfg(type)
	var amax: int = c["adult_hp"]
	var ymax: int = c["young_hp"]
	return {
		"id": id, "type": type, "herd_id": herd_id,
		"x": x, "y": y, "vx": 0.0, "vy": 0.0,
		"state": STATE_ROAM, "state_ticks": 1,
		"facing": 1.0, "age": ADULT_AGE if adult else 0,
		"hp": amax if adult else ymax,
		"max_hp": amax if adult else ymax,
		"is_alive": true, "anim": 0.0,
	}

# Spawns a herd of `count` animals of `type` clustered near (cx,cy). next_id is the first
# id to use; returns the next free id after the herd. One young per group to start.
static func spawn_herd(wildlife: Array, herd_id: int, cx: float, cy: float, count: int,
		rng: RandomNumberGenerator, next_id: int, type: String = "deer") -> int:
	for _i in range(count):
		var ox: float = rng.randf_range(-2.5, 2.5)
		var oy: float = rng.randf_range(-2.5, 2.5)
		var adult: bool = _i < count - 1   # one fawn/kit/piglet per herd to start
		wildlife.append(make_animal(next_id, herd_id, cx + ox, cy + oy, adult, type))
		next_id += 1
	return next_id

# ── Per-tick update ───────────────────────────────────────────────────────────

# Advances all wildlife one tick.
#   threats: Array of {"x": float, "y": float} (unit positions to flee).
#   grid: WorldGrid (for passability) or null.
# Returns the (possibly increased) next animal id after any births.
static func tick(wildlife: Array, threats: Array, grid, rng: RandomNumberGenerator,
		tick_count: int, next_id: int) -> int:
	# Herd centroids for cohesion.
	var sums: Dictionary = {}   # herd_id -> [sx, sy, n]
	for a in wildlife:
		if not (a is Dictionary and a.get("is_alive", false)):
			continue
		var hid: int = a.get("herd_id", 0)
		var s: Array = sums.get(hid, [0.0, 0.0, 0])
		s[0] += a["x"]; s[1] += a["y"]; s[2] += 1
		sums[hid] = s

	for a in wildlife:
		if not (a is Dictionary and a.get("is_alive", false)):
			continue
		a["age"] = a.get("age", 0) + 1
		var hid: int = a.get("herd_id", 0)
		var s: Array = sums.get(hid, [a["x"], a["y"], 1])
		var ctr := Vector2(s[0] / float(s[2]), s[1] / float(s[2]))
		_tick_animal(a, ctr, wildlife, threats, grid, rng)

	# Slow breeding, per herd.
	next_id = _maybe_breed(wildlife, sums, rng, tick_count, next_id)
	return next_id

static func _tick_animal(a: Dictionary, centroid: Vector2, wildlife: Array,
		threats: Array, grid, rng: RandomNumberGenerator) -> void:
	var pos := Vector2(a["x"], a["y"])
	var threat := _nearest_threat(pos, threats)
	var spd: float = cfg(a.get("type", "deer"))["speed"]

	if threat != Vector2.INF:
		# Flee directly away from the threat.
		a["state"] = STATE_RUN
		a["state_ticks"] = SAFE_TICKS
		var away := (pos - threat)
		if away.length() < 0.01:
			away = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		away = away.normalized()
		a["vx"] = away.x * RUN_SPEED * spd
		a["vy"] = away.y * RUN_SPEED * spd
	else:
		a["state_ticks"] = int(a.get("state_ticks", 0)) - 1
		match a.get("state", STATE_ROAM):
			STATE_RUN:
				if a["state_ticks"] <= 0:
					_enter(a, STATE_ROAM, rng)
			STATE_ROAM:
				var steer := _roam_steer(a, pos, centroid, wildlife, rng)
				a["vx"] = steer.x * ROAM_SPEED * spd
				a["vy"] = steer.y * ROAM_SPEED * spd
				if a["state_ticks"] <= 0:
					_enter(a, _pick_idle(rng, a.get("type", "deer")), rng)
			_:  # FEED / BROOD — stationary
				a["vx"] = 0.0
				a["vy"] = 0.0
				if a["state_ticks"] <= 0:
					_enter(a, STATE_ROAM, rng)

	# Move, respecting terrain (don't wade into water/rock/mountain).
	var nx: float = a["x"] + a["vx"]
	var ny: float = a["y"] + a["vy"]
	if _passable(grid, nx, ny):
		a["x"] = nx
		a["y"] = ny
	else:
		# Bounce off the obstacle so the herd flows around it.
		a["vx"] = -a["vx"] * 0.6
		a["vy"] = -a["vy"] * 0.6
	if absf(a["vx"]) > 0.001:
		a["facing"] = 1.0 if a["vx"] > 0.0 else -1.0
	# Animation phase advances with movement speed (view also uses state).
	a["anim"] = fposmod(a.get("anim", 0.0) + Vector2(a["vx"], a["vy"]).length() * 6.0 + 0.04, TAU)

static func _roam_steer(a: Dictionary, pos: Vector2, centroid: Vector2,
		wildlife: Array, rng: RandomNumberGenerator) -> Vector2:
	var steer := Vector2.ZERO
	# Cohesion: toward herd centre.
	var to_centre := centroid - pos
	if to_centre.length() > 0.5:
		steer += to_centre.normalized() * COHESION
	# Separation: away from close herd-mates.
	var hid: int = a.get("herd_id", 0)
	for o in wildlife:
		if o == a or not (o is Dictionary and o.get("is_alive", false)):
			continue
		if o.get("herd_id", -1) != hid:
			continue
		var d := pos - Vector2(o["x"], o["y"])
		var dist := d.length()
		if dist < SEPARATION_RADIUS and dist > 0.001:
			steer += d.normalized() * SEPARATION * (1.0 - dist / SEPARATION_RADIUS)
	# Wander.
	steer += Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * WANDER
	if steer.length() < 0.001:
		return Vector2.ZERO
	return steer.normalized()

static func _enter(a: Dictionary, state: String, rng: RandomNumberGenerator) -> void:
	a["state"] = state
	match state:
		STATE_FEED:  a["state_ticks"] = rng.randi_range(FEED_TICKS.x, FEED_TICKS.y)
		STATE_BROOD: a["state_ticks"] = rng.randi_range(BROOD_TICKS.x, BROOD_TICKS.y)
		_:           a["state_ticks"] = rng.randi_range(ROAM_TICKS.x, ROAM_TICKS.y)

static func _pick_idle(rng: RandomNumberGenerator, type: String = "deer") -> String:
	var c: Dictionary = cfg(type)
	var r: float = rng.randf()
	if r < c["feed_w"]:
		return STATE_FEED
	elif r < c["feed_w"] + c["brood_w"]:
		return STATE_BROOD
	return STATE_ROAM

static func _nearest_threat(pos: Vector2, threats: Array) -> Vector2:
	var best := Vector2.INF
	var best_d: float = THREAT_RADIUS
	for t in threats:
		var tp := Vector2(t.get("x", 0.0), t.get("y", 0.0))
		var d := pos.distance_to(tp)
		if d < best_d:
			best_d = d
			best = tp
	return best

static func _passable(grid, x: float, y: float) -> bool:
	if grid == null:
		return true
	var ix: int = int(round(x))
	var iy: int = int(round(y))
	if not grid.in_bounds(ix, iy):
		return false
	# PASSABLE_FOOT bit (deer travel on foot terrain).
	return (grid.is_passable(ix, iy, 0b00000001)) if grid.has_method("is_passable") else true

static func _maybe_breed(wildlife: Array, sums: Dictionary, rng: RandomNumberGenerator,
		tick_count: int, next_id: int) -> int:
	# One slow breeding check per herd, gated by a per-herd cooldown.
	var last_birth: Dictionary = {}   # herd_id -> tick (stored on any member)
	var adults_by_herd: Dictionary = {}
	var herd_type: Dictionary = {}    # herd_id -> species (newborns inherit it)
	for a in wildlife:
		if not (a is Dictionary and a.get("is_alive", false)):
			continue
		var hid: int = a.get("herd_id", 0)
		if int(a.get("age", 0)) >= ADULT_AGE:
			adults_by_herd[hid] = adults_by_herd.get(hid, 0) + 1
		last_birth[hid] = maxi(last_birth.get(hid, 0), int(a.get("_last_birth", 0)))
		herd_type[hid] = a.get("type", "deer")
	for hid in sums.keys():
		var herd_size: int = sums[hid][2]
		var htype: String = herd_type.get(hid, "deer")
		if herd_size >= int(cfg(htype)["cap"]) or adults_by_herd.get(hid, 0) < 2:
			continue
		if tick_count - last_birth.get(hid, 0) < BREED_INTERVAL:
			continue
		if rng.randf() < 0.5:   # checked rarely (only when cooldown elapsed)
			var cx: float = sums[hid][0] / float(herd_size)
			var cy: float = sums[hid][1] / float(herd_size)
			wildlife.append(make_animal(next_id, hid, cx + rng.randf_range(-1, 1),
				cy + rng.randf_range(-1, 1), false, htype))
			next_id += 1
			# Stamp the birth tick on herd members for the cooldown.
			for a in wildlife:
				if a is Dictionary and a.get("herd_id", -1) == hid:
					a["_last_birth"] = tick_count
	return next_id
