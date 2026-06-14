extends RefCounted
# Animated villager pawns — the visible little people of the realm. Like wildlife,
# each citizen is a JSON-serializable Dictionary advanced deterministically each
# tick. They idle/wander near the keep; when a building is placed, an idle citizen
# becomes a BUILDER, walks to the site and constructs it (the building carries a
# build timer); finished, the builder ambles home. State drives the animation.

const STATE_IDLE   = "idle"     # standing about near home
const STATE_WANDER = "wander"   # ambling near home
const STATE_WALK   = "walk"     # heading to a target (tx,ty)
const STATE_BUILD  = "build"    # at a construction site, hammering
const STATE_WORK   = "work"     # loitering at an assigned workplace

const WALK_SPEED: float = 0.05      # tiles/tick — villagers bustle
const ARRIVE_DIST: float = 0.7      # close enough to a target
const WANDER_RADIUS: float = 4.0    # how far they stray from home
const BUILD_TIME: int = 240         # ticks to raise a building (~12s)
const MAX_CITIZENS: int = 12        # visible pawns cap (perf)

const IDLE_TICKS := Vector2i(60, 180)
const WANDER_TICKS := Vector2i(90, 240)

static func make_citizen(id: int, hx: float, hy: float, rng: RandomNumberGenerator) -> Dictionary:
	return {
		"id": id, "role": "peasant", "job": -1,
		"x": hx + rng.randf_range(-3, 3), "y": hy + rng.randf_range(-3, 3),
		"vx": 0.0, "vy": 0.0,
		"hx": hx, "hy": hy,
		"state": STATE_IDLE, "state_ticks": rng.randi_range(IDLE_TICKS.x, IDLE_TICKS.y),
		"tx": hx, "ty": hy, "facing": 1.0, "anim": 0.0, "is_alive": true,
	}

static func spawn(citizens: Array, count: int, hx: float, hy: float,
		rng: RandomNumberGenerator, next_id: int) -> int:
	for _i in range(mini(count, MAX_CITIZENS)):
		citizens.append(make_citizen(next_id, hx, hy, rng))
		next_id += 1
	return next_id

# Advances all citizens one tick. `buildings` is the player's building list (read
# for construction sites; build_progress is updated in place). tick_count drives
# the per-building construction timer (construction_until).
static func tick(citizens: Array, buildings: Array, rng: RandomNumberGenerator, tick_count: int) -> void:
	# Dispatch a builder to any site still under construction without one.
	for b in buildings:
		if not (b is Dictionary):
			continue
		if int(b.get("construction_until", 0)) <= tick_count:
			continue   # already built (or never under construction)
		var bid: int = b.get("id", -1)
		if _has_builder(citizens, bid):
			continue
		var c := _nearest_idle(citizens, float(b.get("grid_x", 0)), float(b.get("grid_y", 0)))
		if not c.is_empty():
			c["role"] = "builder"
			c["job"] = bid
			c["state"] = STATE_WALK
			c["tx"] = float(b.get("grid_x", 0))
			c["ty"] = float(b.get("grid_y", 0))

	for c in citizens:
		if not (c is Dictionary and c.get("is_alive", false)):
			continue
		_tick_citizen(c, buildings, rng, tick_count)

static func _tick_citizen(c: Dictionary, buildings: Array, rng: RandomNumberGenerator, tick_count: int) -> void:
	var pos := Vector2(c["x"], c["y"])
	match c.get("state", STATE_IDLE):
		STATE_WALK:
			var tgt := Vector2(c["tx"], c["ty"])
			_step_to(c, tgt)
			if pos.distance_to(tgt) <= ARRIVE_DIST:
				if c.get("role", "") == "builder" and _site_active(buildings, c.get("job", -1), tick_count):
					c["state"] = STATE_BUILD
				else:
					_go_home_idle(c, rng)
		STATE_BUILD:
			c["vx"] = 0.0; c["vy"] = 0.0
			if not _site_active(buildings, c.get("job", -1), tick_count):
				# Construction finished (or building gone) — head home.
				c["role"] = "peasant"
				c["job"] = -1
				c["state"] = STATE_WALK
				c["tx"] = c["hx"]; c["ty"] = c["hy"]
		STATE_WORK:
			c["vx"] = 0.0; c["vy"] = 0.0
			c["state_ticks"] = int(c.get("state_ticks", 0)) - 1
			if c["state_ticks"] <= 0:
				_go_home_idle(c, rng)
		STATE_WANDER:
			# Amble around home.
			var to_home := Vector2(c["hx"], c["hy"]) - pos
			var steer := to_home * 0.05 + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			if to_home.length() > WANDER_RADIUS:
				steer = to_home.normalized()
			if steer.length() > 0.001:
				steer = steer.normalized()
			c["vx"] = steer.x * WALK_SPEED * 0.6
			c["vy"] = steer.y * WALK_SPEED * 0.6
			c["x"] += c["vx"]; c["y"] += c["vy"]
			c["state_ticks"] = int(c.get("state_ticks", 0)) - 1
			if c["state_ticks"] <= 0:
				c["state"] = STATE_IDLE
				c["state_ticks"] = rng.randi_range(IDLE_TICKS.x, IDLE_TICKS.y)
		_:  # IDLE
			c["vx"] = 0.0; c["vy"] = 0.0
			c["state_ticks"] = int(c.get("state_ticks", 0)) - 1
			if c["state_ticks"] <= 0:
				c["state"] = STATE_WANDER
				c["state_ticks"] = rng.randi_range(WANDER_TICKS.x, WANDER_TICKS.y)

	if absf(c.get("vx", 0.0)) > 0.001:
		c["facing"] = 1.0 if c["vx"] > 0.0 else -1.0
	c["anim"] = fposmod(c.get("anim", 0.0) + 0.15, TAU)

static func _step_to(c: Dictionary, tgt: Vector2) -> void:
	var d := tgt - Vector2(c["x"], c["y"])
	if d.length() < 0.001:
		c["vx"] = 0.0; c["vy"] = 0.0
		return
	d = d.normalized() * WALK_SPEED
	c["vx"] = d.x; c["vy"] = d.y
	c["x"] += d.x; c["y"] += d.y

static func _go_home_idle(c: Dictionary, rng: RandomNumberGenerator) -> void:
	c["role"] = "peasant"
	c["job"] = -1
	c["state"] = STATE_IDLE
	c["state_ticks"] = rng.randi_range(IDLE_TICKS.x, IDLE_TICKS.y)

static func _site_active(buildings: Array, bid: int, tick_count: int) -> bool:
	for b in buildings:
		if b is Dictionary and b.get("id", -1) == bid:
			return int(b.get("construction_until", 0)) > tick_count
	return false

static func _has_builder(citizens: Array, bid: int) -> bool:
	for c in citizens:
		if c is Dictionary and c.get("role", "") == "builder" and c.get("job", -1) == bid:
			return true
	return false

static func _nearest_idle(citizens: Array, x: float, y: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	var p := Vector2(x, y)
	for c in citizens:
		if not (c is Dictionary and c.get("is_alive", false)):
			continue
		if c.get("role", "") == "builder":
			continue
		var st: String = c.get("state", "")
		if st != STATE_IDLE and st != STATE_WANDER:
			continue
		var d := p.distance_to(Vector2(c["x"], c["y"]))
		if d < best_d:
			best_d = d
			best = c
	return best
