extends RefCounted
# Animated villager pawns — the visible little people of the realm. Like wildlife,
# each citizen is a JSON-serializable Dictionary advanced deterministically each
# tick. They idle/wander near home (the campfire once the hall is built); when a
# building is placed unbuilt, EVERY free villager rushes to it. Builders take a
# distinct standing spot around the OUTSIDE of the site, face inward, and hammer —
# build progress accrues per builder present (more builders → faster) and they
# stay until it is finished. They steer around each other and impassable tiles
# (crude local avoidance). State drives the animation.

const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

const STATE_IDLE   = "idle"     # standing about near home
const STATE_WANDER = "wander"   # ambling near home
const STATE_WALK   = "walk"     # heading to a target (tx,ty)
const STATE_BUILD  = "build"    # at a construction site, hammering
const STATE_WORK   = "work"     # loitering at an assigned workplace

const WALK_SPEED: float = 0.05      # tiles/tick — villagers bustle
const ARRIVE_DIST: float = 0.7      # close enough to a standing spot to work
const WANDER_RADIUS: float = 4.0
const BUILD_RATE: float = 1.0       # build-progress added per builder per tick
const MAX_CITIZENS: int = 12
const SEP_RADIUS: float = 0.85      # personal space — pawns push apart within this
const LAND_MOVE: int = 0b00000001   # is_passable move-type bit (foot/land)

const IDLE_TICKS := Vector2i(60, 180)
const WANDER_TICKS := Vector2i(90, 240)

static func make_citizen(id: int, hx: float, hy: float, rng: RandomNumberGenerator) -> Dictionary:
	return {
		"id": id, "role": "peasant", "job": -1, "build_slot": 0,
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
# `grid` (optional) enables obstacle avoidance; pass null in headless tests.
static func tick(citizens: Array, buildings: Array, rng: RandomNumberGenerator,
		_tick_count: int, grid: Object = null) -> void:
	var sites: Array = []
	for b in buildings:
		if is_site(b):
			sites.append(b)

	# Every free villager heads to the nearest unfinished site (all hands on deck).
	# Each is given a distinct standing slot around the site's outside perimeter.
	if not sites.is_empty():
		# Seed slot counters with builders already committed to each job.
		var slot_count: Dictionary = {}
		for c in citizens:
			if c is Dictionary and c.get("role", "") == "builder":
				var j: int = int(c.get("job", -1))
				slot_count[j] = int(slot_count.get(j, 0)) + 1
		for c in citizens:
			if not (c is Dictionary and c.get("is_alive", false)):
				continue
			var st: String = c.get("state", "")
			if st == STATE_IDLE or st == STATE_WANDER:
				var nb := _nearest_site(sites, c["x"], c["y"])
				if not nb.is_empty():
					var jid: int = int(nb.get("id", -1))
					var slot: int = int(slot_count.get(jid, 0))
					slot_count[jid] = slot + 1
					c["role"] = "builder"
					c["job"] = jid
					c["build_slot"] = slot
					c["state"] = STATE_WALK
					var spot := _build_spot(nb, slot)
					c["tx"] = spot.x
					c["ty"] = spot.y

	for c in citizens:
		if c is Dictionary and c.get("is_alive", false):
			_tick_citizen(c, buildings, citizens, rng, grid)

static func _tick_citizen(c: Dictionary, buildings: Array, citizens: Array,
		rng: RandomNumberGenerator, grid: Object) -> void:
	var pos := Vector2(c["x"], c["y"])
	match c.get("state", STATE_IDLE):
		STATE_WALK:
			var tgt := Vector2(c["tx"], c["ty"])
			_step_to(c, tgt, citizens, grid)
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
				# Face inward toward the structure while hammering.
				var ctr := _site_center(b)
				c["facing"] = 1.0 if ctr.x >= c["x"] else -1.0
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
			steer += _separation(c, citizens) * 0.8
			if steer.length() > 0.001:
				steer = steer.normalized()
			var step := steer * WALK_SPEED * 0.6
			if grid == null or _passable(grid, pos + step):
				c["x"] += step.x; c["y"] += step.y
				c["vx"] = step.x; c["vy"] = step.y
			else:
				c["vx"] = 0.0; c["vy"] = 0.0
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

# Move toward tgt with crude local avoidance: separation from neighbours, plus
# deflection around impassable/occupied tiles when a grid is supplied.
static func _step_to(c: Dictionary, tgt: Vector2, citizens: Array, grid: Object) -> void:
	var pos := Vector2(c["x"], c["y"])
	var to := tgt - pos
	if to.length() < 0.001:
		c["vx"] = 0.0; c["vy"] = 0.0
		return
	var dir := to.normalized() + _separation(c, citizens) * 0.6
	if dir.length() > 0.001:
		dir = dir.normalized()
	var step := dir * WALK_SPEED
	if grid != null and not _passable(grid, pos + step):
		# Try fanning the heading out to slip around the obstacle.
		var deflected := false
		for ang in [0.7, -0.7, 1.3, -1.3, 2.0, -2.0]:
			var alt := dir.rotated(ang) * WALK_SPEED
			if _passable(grid, pos + alt):
				step = alt
				deflected = true
				break
		if not deflected:
			step = Vector2.ZERO
	c["vx"] = step.x; c["vy"] = step.y
	c["x"] += step.x; c["y"] += step.y

# Repulsion vector pushing this pawn away from nearby pawns (boids separation).
static func _separation(c: Dictionary, citizens: Array) -> Vector2:
	var push := Vector2.ZERO
	var p := Vector2(c["x"], c["y"])
	var cid: int = int(c.get("id", -1))
	for o in citizens:
		if not (o is Dictionary and o.get("is_alive", false)):
			continue
		if int(o.get("id", -2)) == cid:
			continue
		var d := p - Vector2(o["x"], o["y"])
		var dl := d.length()
		if dl > 0.001 and dl < SEP_RADIUS:
			push += (d / dl) * ((SEP_RADIUS - dl) / SEP_RADIUS)
	return push

# True if the tile under p is walkable (in bounds, passable terrain, no building).
static func _passable(grid: Object, p: Vector2) -> bool:
	var gx := int(round(p.x))
	var gy := int(round(p.y))
	if not grid.in_bounds(gx, gy):
		return false
	if grid.has_method("is_passable") and not grid.is_passable(gx, gy, LAND_MOVE):
		return false
	if grid.has_method("get_building_at") and grid.get_building_at(gx, gy) != 0:
		return false
	return true

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

# Centre of a building's footprint, in grid coords.
static func _site_center(b: Dictionary) -> Vector2:
	var defn: Dictionary = BuildingRegistry.lookup(b.get("type", ""))
	var w: int = defn.get("width", 1)
	var h: int = defn.get("height", 1)
	return Vector2(float(b.get("grid_x", 0)) + (w - 1) * 0.5, float(b.get("grid_y", 0)) + (h - 1) * 0.5)

# A distinct standing spot just OUTSIDE the building, on a ring around it, so
# builders cluster around the perimeter rather than stacking on one tile.
static func _build_spot(b: Dictionary, slot: int) -> Vector2:
	var defn: Dictionary = BuildingRegistry.lookup(b.get("type", ""))
	var w: int = defn.get("width", 1)
	var h: int = defn.get("height", 1)
	var center := Vector2(float(b.get("grid_x", 0)) + (w - 1) * 0.5, float(b.get("grid_y", 0)) + (h - 1) * 0.5)
	var ring: int = maxi(6, 2 * (w + h))           # roughly one slot per perimeter tile
	var radius: float = maxf(w, h) * 0.5 + 0.9     # just beyond the wall
	var ang: float = TAU * float(slot % ring) / float(ring)
	return center + Vector2(cos(ang), sin(ang)) * radius

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
