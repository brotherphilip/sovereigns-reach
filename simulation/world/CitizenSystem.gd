extends RefCounted
# Animated villager pawns — the visible little people of the realm. Like wildlife,
# each citizen is a JSON-serializable Dictionary advanced deterministically each
# tick. They idle/wander near the keep; when a building is placed unbuilt, EVERY
# free villager rushes to the nearest construction site and hammers it — build
# progress accrues per builder present (more builders → faster) and they stay
# until it is finished. State drives the animation.

const STATE_IDLE   = "idle"     # standing about near home
const STATE_WANDER = "wander"   # ambling near home
const STATE_WALK   = "walk"     # heading to a target (tx,ty)
const STATE_BUILD  = "build"    # at a construction site, hammering
const STATE_WORK   = "work"     # loitering at an assigned workplace

const WALK_SPEED: float = 0.05      # tiles/tick — villagers bustle
const ARRIVE_DIST: float = 1.2      # close enough to a site to work it
const WANDER_RADIUS: float = 4.0
const BUILD_RATE: float = 1.0       # build-progress added per builder per tick
const MAX_CITIZENS: int = 12

const IDLE_TICKS := Vector2i(60, 180)
const WANDER_TICKS := Vector2i(90, 240)

static func make_citizen(id: int, hx: float, hy: float, rng: RandomNumberGenerator) -> Dictionary:
	return {
		"id": id, "role": "peasant", "job": -1,
		"x": hx + rng.randf_range(-3, 3), "y": hy + rng.randf_range(-3, 3),
		"vx": 0.0, "vy": 0.0, "hx": hx, "hy": hy,
		"state": STATE_IDLE, "state_ticks": rng.randi_range(IDLE_TICKS.x, IDLE_TICKS.y),
		"tx": hx, "ty": hy, "facing": 1.0, "anim": 0.0, "is_alive": true,
	}

static func spawn(citizens: Array, count: int, hx: float, hy: float,
		rng: RandomNumberGenerator, next_id: int) -> int:
	for _i in range(mini(count, MAX_CITIZENS)):
		citizens.append(make_citizen(next_id, hx, hy, rng))
		next_id += 1
	return next_id

# A building is a live construction site while it is not yet built.
static func is_site(b: Dictionary) -> bool:
	return b is Dictionary and b.has("build_required") and not b.get("built", true)

# Advances all citizens one tick; accrues build progress on sites being worked.
static func tick(citizens: Array, buildings: Array, rng: RandomNumberGenerator, _tick_count: int) -> void:
	var sites: Array = []
	for b in buildings:
		if is_site(b):
			sites.append(b)

	# Every free villager heads to the nearest unfinished site (all hands on deck).
	if not sites.is_empty():
		for c in citizens:
			if not (c is Dictionary and c.get("is_alive", false)):
				continue
			var st: String = c.get("state", "")
			if st == STATE_IDLE or st == STATE_WANDER:
				var nb := _nearest_site(sites, c["x"], c["y"])
				if not nb.is_empty():
					c["role"] = "builder"
					c["job"] = nb.get("id", -1)
					c["state"] = STATE_WALK
					c["tx"] = float(nb.get("grid_x", 0))
					c["ty"] = float(nb.get("grid_y", 0))

	for c in citizens:
		if c is Dictionary and c.get("is_alive", false):
			_tick_citizen(c, buildings, rng)

static func _tick_citizen(c: Dictionary, buildings: Array, rng: RandomNumberGenerator) -> void:
	var pos := Vector2(c["x"], c["y"])
	match c.get("state", STATE_IDLE):
		STATE_WALK:
			var tgt := Vector2(c["tx"], c["ty"])
			_step_to(c, tgt)
			if pos.distance_to(tgt) <= ARRIVE_DIST:
				var b := _find(buildings, c.get("job", -1))
				if c.get("role", "") == "builder" and not b.is_empty() and is_site(b):
					c["state"] = STATE_BUILD
				else:
					_go_home(c, rng)
		STATE_BUILD:
			c["vx"] = 0.0; c["vy"] = 0.0
			var b := _find(buildings, c.get("job", -1))
			if b.is_empty() or not is_site(b):
				_go_home(c, rng)   # finished or removed
			else:
				# This builder's labour raises the structure.
				b["build_progress"] = float(b.get("build_progress", 0.0)) + BUILD_RATE
				if b["build_progress"] >= float(b.get("build_required", 1.0)):
					b["built"] = true
		STATE_WORK:
			c["vx"] = 0.0; c["vy"] = 0.0
			c["state_ticks"] = int(c.get("state_ticks", 0)) - 1
			if c["state_ticks"] <= 0:
				_go_home(c, rng)
		STATE_WANDER:
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

static func _go_home(c: Dictionary, rng: RandomNumberGenerator) -> void:
	c["role"] = "peasant"
	c["job"] = -1
	c["state"] = STATE_WALK
	c["tx"] = c["hx"]; c["ty"] = c["hy"]
	# Arrive-home is handled by the WALK case → falls back to idle there.
	if Vector2(c["x"], c["y"]).distance_to(Vector2(c["hx"], c["hy"])) <= ARRIVE_DIST:
		c["state"] = STATE_IDLE
		c["state_ticks"] = rng.randi_range(IDLE_TICKS.x, IDLE_TICKS.y)

static func _find(buildings: Array, bid: int) -> Dictionary:
	for b in buildings:
		if b is Dictionary and b.get("id", -1) == bid:
			return b
	return {}

static func _nearest_site(sites: Array, x: float, y: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	var p := Vector2(x, y)
	for b in sites:
		var d := p.distance_to(Vector2(b.get("grid_x", 0), b.get("grid_y", 0)))
		if d < best_d:
			best_d = d
			best = b
	return best
