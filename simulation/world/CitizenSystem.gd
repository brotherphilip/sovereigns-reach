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
const WorkerJobs       = preload("res://simulation/world/WorkerJobs.gd")
const Pathfinder       = preload("res://simulation/pathfinding/Pathfinder.gd")
const SeasonSystem     = preload("res://simulation/world/SeasonSystem.gd")
const WorldGrid        = preload("res://simulation/world/WorldGrid.gd")
const ResourceTick     = preload("res://simulation/economy/ResourceTick.gd")
const StorageSystem    = preload("res://simulation/economy/StorageSystem.gd")
const FoodSystem       = preload("res://simulation/economy/FoodSystem.gd")

# ── Hauler (gather → process → deliver) ─────────────────────────────────────────
# Chain workers physically fetch raw goods from a map node (or a stockpile), process
# them at their building, and haul the output to a store. Output is credited ONLY on
# a completed delivery; a full store or a dead node stalls the worker (it waits).
const PH_SEEK     = "seek"       # walk to source (node / input stockpile / field)
const PH_GATHER   = "gather"     # harvest a node or fetch an input (dwell)
const PH_HAUL_IN  = "haul_in"    # carry the raw load back to the workplace
const PH_PROCESS  = "process"    # work the raw into output (dwell)
const PH_HAUL_OUT = "haul_out"   # carry the output to a store
const PH_WAIT     = "wait"       # store full / no node — pause and retry

const NODE_RADIUS: int = 16       # how far a gatherer ranges for a resource node
const HARVEST_TICKS: int = 90     # dwell felling/digging/picking
const PROCESS_TICKS: int = 70     # dwell working raw into output
const HARVEST_DEPLETE: int = 20   # resource_density removed per harvest
const WAIT_TICKS: int = 60        # pause before retrying a blocked store/node
const HAUL_TIMEOUT: int = 1400    # give up on an unreachable target, re-seek

const STATE_IDLE   = "idle"     # standing about near home
const STATE_WANDER = "wander"   # ambling near home
const STATE_WALK   = "walk"     # heading to a target (tx,ty)
const STATE_BUILD  = "build"    # at a construction site, hammering
const STATE_WORK   = "work"     # at an assigned workplace, doing the job

# How long a worker labours at one spot before tending to another part of the site.
const WORK_TICKS := Vector2i(150, 360)

const WALK_SPEED: float = 0.05      # tiles/tick — villagers bustle
const ARRIVE_DIST: float = 0.7      # close enough to a standing spot to work
# Stuck recovery: if a walking pawn fails to get STUCK_EPS tiles closer to its
# target for STUCK_TIMEOUT ticks, it re-targets a reachable spot or abandons the job
# (so a builder can never freeze forever against an unreachable site). ~2 game-days.
const STUCK_TIMEOUT: int = 480
const STUCK_EPS: float = 0.5
const WANDER_RADIUS: float = 4.0
const BUILD_RATE: float = 1.0       # build-progress added per builder per tick
const MAX_CITIZENS: int = 40
const SEP_RADIUS: float = 0.85      # personal space — pawns push apart within this
const LAND_MOVE: int = 0b00000001   # is_passable move-type bit (foot/land)

const IDLE_TICKS := Vector2i(60, 180)
const WANDER_TICKS := Vector2i(90, 240)

# Names for villager profiles (flavour).
const MALE_NAMES: Array = ["Aldric", "Bran", "Cedric", "Dunstan", "Edmund", "Garrick", "Hew", "Osric", "Rowan", "Tomas", "Wulf", "Godwin"]
const FEMALE_NAMES: Array = ["Ada", "Bryn", "Cwen", "Edith", "Freya", "Gisela", "Hild", "Maud", "Rowena", "Sela", "Wynn", "Elga"]
# Hair palette (inherited / random). Old age greys these.
const HAIR_COLORS: Array = [
	Color(0.10, 0.08, 0.07), Color(0.22, 0.14, 0.08), Color(0.38, 0.24, 0.12),
	Color(0.55, 0.40, 0.18), Color(0.74, 0.58, 0.28), Color(0.42, 0.20, 0.10),
]

# A villager. Defaults to a randomly-profiled WORKING-AGE adult (initial settlers);
# PeopleSystem passes explicit profile fields for new-born babies.
static func make_citizen(id: int, hx: float, hy: float, rng: RandomNumberGenerator,
		day: int = 0, profile: Dictionary = {}) -> Dictionary:
	var sex: String = profile.get("sex", "m" if rng.randf() < 0.5 else "f")
	# Born so they're working-age (6–9 game-yr) at the given day, unless told otherwise.
	var born_day: int = profile.get("born_day", day - rng.randi_range(288, 432))
	return {
		"id": id, "role": "peasant", "job": -1, "build_slot": 0,
		"job_type": "", "work_anim": "", "work_slot": 0,
		"x": hx + rng.randf_range(-3, 3), "y": hy + rng.randf_range(-3, 3),
		"vx": 0.0, "vy": 0.0, "hx": hx, "hy": hy,
		"state": STATE_IDLE, "state_ticks": rng.randi_range(IDLE_TICKS.x, IDLE_TICKS.y),
		"tx": hx, "ty": hy, "facing": 1.0, "anim": 0.0, "is_alive": true,
		# ── Person profile ──
		"sex": sex,
		"born_day": born_day,
		"stage": profile.get("stage", "adult"),
		"skin": profile.get("skin", rng.randf()),                       # 0 dark-brown … 1 fair
		"hair_color": profile.get("hair_color", HAIR_COLORS[rng.randi_range(0, HAIR_COLORS.size() - 1)]),
		"hair_style": profile.get("hair_style", rng.randi_range(0, 2)),
		"partner_id": profile.get("partner_id", -1),
		"mother_id": profile.get("mother_id", -1),
		"father_id": profile.get("father_id", -1),
		"pregnant_until": -1,
		"name": profile.get("name", (FEMALE_NAMES if sex == "f" else MALE_NAMES)[rng.randi_range(0, 11)]),
	}

static func spawn(citizens: Array, count: int, hx: float, hy: float,
		rng: RandomNumberGenerator, next_id: int, day: int = 0) -> int:
	for _i in range(count):
		citizens.append(make_citizen(next_id, hx, hy, rng, day))
		next_id += 1
	return next_id

# A building is a live construction site while it is not yet built.
static func is_site(b: Dictionary) -> bool:
	return b is Dictionary and b.has("build_required") and not b.get("built", true)

# Only working-age adults (ADULT/MIDLIFE) take jobs; children and elders don't toil.
# `stage` is refreshed each game-day by PeopleSystem; defaults to adult for legacy pawns.
static func _is_working_age(c: Dictionary) -> bool:
	var s: String = c.get("stage", "adult")
	return s == "adult" or s == "midlife"

# Advances all citizens one tick; accrues build progress on sites being worked and
# drives the hauler economy. `player` may be the player Dictionary (enables the
# gather→deliver economy) or just a buildings Array (movement only, for tests).
# `grid` (optional) enables obstacle avoidance; pass null in headless tests.
# Returns the list of tiles whose terrain changed this tick (felled forests, spent
# ore/rock) so the caller can repaint them (GameState emits EventBus.terrain_painted).
static func tick(citizens: Array, player, rng: RandomNumberGenerator,
		_tick_count: int, grid: Object = null, farm_mult: float = 1.0) -> Array:
	var pdict: Dictionary = player if player is Dictionary else {"buildings": player}
	# Ensure the economy sub-dicts exist so the hauler can read/credit without crashing.
	if not pdict.has("resources"): pdict["resources"] = {}
	if not pdict.has("food"): pdict["food"] = {}
	if not pdict.has("armory"): pdict["armory"] = {}
	var buildings: Array = pdict.get("buildings", [])
	var changed: Array = []
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
			if (st == STATE_IDLE or st == STATE_WANDER) and _is_working_age(c):
				var nb := _nearest_site(sites, c["x"], c["y"])
				if not nb.is_empty():
					var jid: int = int(nb.get("id", -1))
					var slot: int = int(slot_count.get(jid, 0))
					slot_count[jid] = slot + 1
					c["role"] = "builder"
					c["job"] = jid
					c["build_slot"] = slot
					c["state"] = STATE_WALK
					c["stuck_ticks"] = 0
					c.erase("best_dist")
					var spot := _reachable_spot(nb, slot, c, grid, false, null)
					c["tx"] = spot.x
					c["ty"] = spot.y

	# Staff built workplaces from the available stock: idle villagers become
	# job-workers (woodcutters, reapers, smiths…) up to each building's assigned
	# worker count, and surplus workers are released back to villagers.
	_reconcile_workers(citizens, buildings, rng, grid)

	var season: int = SeasonSystem.season_at_tick(_tick_count)
	for c in citizens:
		if c is Dictionary and c.get("is_alive", false):
			_tick_citizen(c, buildings, citizens, rng, grid, season, pdict, farm_mult, changed)
	return changed

# Match worker pawns to each built building's assigned `workers` count. Pulls idle
# villagers into jobs; releases extras and orphans (building gone / workers=0).
static func _reconcile_workers(citizens: Array, buildings: Array, rng: RandomNumberGenerator, grid: Object = null) -> void:
	var desired: Dictionary = {}   # building_id -> worker count
	var bmap: Dictionary = {}      # building_id -> building dict
	for b in buildings:
		if not (b is Dictionary) or not b.get("built", true) or not b.get("is_active", true):
			continue
		var w: int = int(b.get("workers", 0))
		if w <= 0 or not WorkerJobs.employs_workers(b.get("type", "")):
			continue
		var bid: int = int(b.get("id", -1))
		desired[bid] = w
		bmap[bid] = b

	# Keep up to `desired` workers per building; release the rest.
	var assigned: Dictionary = {}  # building_id -> count kept
	for c in citizens:
		if not (c is Dictionary and c.get("is_alive", false)) or c.get("role", "") != "worker":
			continue
		var jb: int = int(c.get("job", -1))
		var keep: int = int(assigned.get(jb, 0))
		# Release surplus, orphaned, OR aged-out workers (the young and old don't toil).
		if not desired.has(jb) or keep >= int(desired[jb]) or not _is_working_age(c):
			_release_worker(c, grid)
		else:
			assigned[jb] = keep + 1

	# Fill shortfalls from idle/wandering villagers.
	for bid in desired:
		var need: int = int(desired[bid]) - int(assigned.get(bid, 0))
		if need <= 0:
			continue
		var b: Dictionary = bmap[bid]
		var style: Dictionary = WorkerJobs.for_building(b.get("type", ""))
		var slot: int = int(assigned.get(bid, 0))
		for c in citizens:
			if need <= 0:
				break
			if not (c is Dictionary and c.get("is_alive", false)) or c.get("role", "") != "peasant":
				continue
			if not _is_working_age(c):
				continue   # only working-age adults take jobs
			var st: String = c.get("state", "")
			if st != STATE_IDLE and st != STATE_WANDER:
				continue
			c["role"] = "worker"
			c["job"] = bid
			c["job_type"] = style.get("job", "Laborer")
			c["work_anim"] = style.get("anim", "carry")
			c["work_slot"] = slot
			c["stuck_ticks"] = 0
			c.erase("best_dist")
			var spot := _reachable_spot(b, slot, c, grid, true, rng)
			c["tx"] = spot.x
			c["ty"] = spot.y
			c["state"] = STATE_WALK
			slot += 1
			need -= 1

static func _release_worker(c: Dictionary, grid: Object = null) -> void:
	c["role"] = "peasant"
	c["job"] = -1
	c["job_type"] = ""
	c["work_anim"] = ""
	c["state"] = STATE_WALK
	c["path"] = []
	var home := _snap_to_free(grid, Vector2(c.get("hx", c.get("x", 0.0)), c.get("hy", c.get("y", 0.0))))
	c["tx"] = home.x
	c["ty"] = home.y

# ── Hauler economy (gather → process → deliver) ─────────────────────────────────

# When a builder finishes, hand it the nearest remaining site so it flows job→job
# instead of trekking home. Returns false if no sites remain.
static func _assign_next_site(c: Dictionary, buildings: Array, grid: Object) -> bool:
	var sites: Array = []
	for b in buildings:
		if is_site(b):
			sites.append(b)
	if sites.is_empty():
		return false
	var nb := _nearest_site(sites, c.get("x", 0.0), c.get("y", 0.0))
	if nb.is_empty():
		return false
	c["role"] = "builder"
	c["job"] = int(nb.get("id", -1))
	c["state"] = STATE_WALK
	c["path"] = []
	c["stuck_ticks"] = 0
	c.erase("best_dist")
	var spot := _reachable_spot(nb, int(c.get("build_slot", 0)), c, grid, false, null)
	c["tx"] = spot.x
	c["ty"] = spot.y
	return true

# Source of a chain building's raw materials: a map node, its own field, or a fetched
# input from a stockpile.
static func _chain_source(btype: String) -> String:
	if btype in ["woodcutter_camp", "stone_quarry", "iron_mine", "pitch_rig"]:
		return "node"
	if btype in ["apple_orchard", "wheat_farm", "hops_farm", "pig_farm", "dairy_farm"]:
		return "field"
	return "fetch"

static func _node_terrain(btype: String) -> int:
	match btype:
		"woodcutter_camp": return WorldGrid.Terrain.FOREST
		"stone_quarry":    return WorldGrid.Terrain.ROCK
		"iron_mine":       return WorldGrid.Terrain.ORE_VEIN
		"pitch_rig":       return WorldGrid.Terrain.MARSH
	return -1

static func _arrived(c: Dictionary) -> bool:
	return Vector2(c["x"], c["y"]).distance_to(Vector2(c["tx"], c["ty"])) <= ARRIVE_DIST

# The hauler state machine for ONE chain worker. Output is credited only at DEPOSIT.
static func _tick_hauler(c: Dictionary, wb: Dictionary, buildings: Array, citizens: Array,
		grid: Object, rng: RandomNumberGenerator, season: int, player: Dictionary,
		farm_mult: float, changed: Array) -> void:
	var btype: String = wb.get("type", "")
	var job_anim: String = WorkerJobs.for_building(btype).get("anim", "carry")
	match c.get("work_phase", PH_SEEK):
		PH_SEEK:
			if not bool(c.get("src_set", false)):
				if not _hauler_pick_source(c, wb, buildings, grid, rng, season, player):
					c["work_phase"] = PH_WAIT
					c["phase_ticks"] = WAIT_TICKS
					return
				c["src_set"] = true
				c["haul_ticks"] = 0
			_follow_path(c, Vector2(c["tx"], c["ty"]), citizens, grid)
			c["haul_ticks"] = int(c.get("haul_ticks", 0)) + 1
			if _arrived(c):
				c["work_phase"] = PH_GATHER
				c["phase_ticks"] = HARVEST_TICKS
			elif int(c["haul_ticks"]) > HAUL_TIMEOUT:
				c["src_set"] = false   # unreachable — pick another source
		PH_GATHER:
			c["vx"] = 0.0; c["vy"] = 0.0
			c["work_anim"] = job_anim
			c["phase_ticks"] = int(c.get("phase_ticks", 0)) - 1
			if int(c["phase_ticks"]) <= 0:
				if int(c.get("node_x", -1)) >= 0 and grid != null:
					var nx: int = int(c["node_x"]); var ny: int = int(c["node_y"])
					var dens: int = grid.get_resource_density(nx, ny) - HARVEST_DEPLETE
					grid.set_resource_density(nx, ny, maxi(0, dens))
					if dens <= 0:
						grid.set_terrain(nx, ny, WorldGrid.Terrain.GRASS)
						changed.append(Vector2i(nx, ny))
				elif _chain_source(btype) == "fetch":
					if not _consume_inputs(wb, player):
						c["work_phase"] = PH_WAIT; c["phase_ticks"] = WAIT_TICKS
						return
				c["carry"] = "raw"
				var spot := _work_spot(wb, int(c.get("work_slot", 0)), rng, grid)
				c["tx"] = spot.x; c["ty"] = spot.y; c["ptx"] = -99999
				c["work_phase"] = PH_HAUL_IN
				c["haul_ticks"] = 0
		PH_HAUL_IN:
			c["work_anim"] = "carry"
			_follow_path(c, Vector2(c["tx"], c["ty"]), citizens, grid)
			c["haul_ticks"] = int(c.get("haul_ticks", 0)) + 1
			if _arrived(c) or int(c["haul_ticks"]) > HAUL_TIMEOUT:
				c["work_phase"] = PH_PROCESS
				c["phase_ticks"] = PROCESS_TICKS
		PH_PROCESS:
			c["vx"] = 0.0; c["vy"] = 0.0
			c["work_anim"] = job_anim
			c["phase_ticks"] = int(c.get("phase_ticks", 0)) - 1
			if int(c["phase_ticks"]) <= 0:
				var outputs := ResourceTick.per_worker_output(wb, player, season, farm_mult)
				if outputs.is_empty():
					c["carry"] = ""
					c["work_phase"] = PH_SEEK; c["src_set"] = false
					return
				var primary: String = String(outputs.keys()[0])
				c["carry"] = primary
				var store := _nearest_building_of(buildings, _store_types(StorageSystem.store_for(primary)), Vector2(c["x"], c["y"]))
				var t: Vector2 = _work_spot(store, int(c.get("work_slot", 0)), rng, grid) if not store.is_empty() else _work_spot(wb, 0, rng, grid)
				c["tx"] = t.x; c["ty"] = t.y; c["ptx"] = -99999
				c["work_phase"] = PH_HAUL_OUT
				c["haul_ticks"] = 0
		PH_HAUL_OUT:
			c["work_anim"] = "carry"
			_follow_path(c, Vector2(c["tx"], c["ty"]), citizens, grid)
			c["haul_ticks"] = int(c.get("haul_ticks", 0)) + 1
			if _arrived(c) or int(c["haul_ticks"]) > HAUL_TIMEOUT:
				if _hauler_deposit(c, wb, player, season, farm_mult):
					c["work_phase"] = PH_SEEK; c["src_set"] = false
				else:
					c["work_phase"] = PH_WAIT; c["phase_ticks"] = WAIT_TICKS   # store full
		PH_WAIT:
			c["vx"] = 0.0; c["vy"] = 0.0
			c["phase_ticks"] = int(c.get("phase_ticks", 0)) - 1
			if int(c["phase_ticks"]) <= 0:
				var carry: String = String(c.get("carry", ""))
				if carry != "" and carry != "raw":
					c["work_phase"] = PH_HAUL_OUT; c["ptx"] = -99999; c["haul_ticks"] = 0   # retry deposit
				else:
					c["work_phase"] = PH_SEEK; c["src_set"] = false
		_:
			c["work_phase"] = PH_SEEK; c["src_set"] = false

# Pick this trip's source; sets c.tx/ty (+ node_x/y). False → nothing to do (wait/tend).
static func _hauler_pick_source(c: Dictionary, wb: Dictionary, buildings: Array,
		grid: Object, rng: RandomNumberGenerator, season: int, player: Dictionary) -> bool:
	var btype: String = wb.get("type", "")
	c["node_x"] = -1
	var src := _chain_source(btype)
	if src == "field":
		# Always work the field — off-season the trip simply yields nothing at PROCESS,
		# so the worker tends the rows rather than freezing at the edge.
		var f := _field_node(wb, int(c.get("work_slot", 0)) + 1, rng, grid)
		c["tx"] = f.x; c["ty"] = f.y; c["ptx"] = -99999
		return true
	elif src == "node":
		if grid == null:
			return false
		var node := _find_node(wb, _node_terrain(btype), grid)
		if node.x < 0:
			return false
		c["node_x"] = int(node.x); c["node_y"] = int(node.y)
		var stand := _snap_to_free(grid, node)
		c["tx"] = stand.x; c["ty"] = stand.y; c["ptx"] = -99999
		return true
	else:  # fetch (processor)
		if not _has_inputs(wb, player):
			return false
		var store := _nearest_building_of(buildings, ["stockpile", "village_hall", "keep"], Vector2(c["x"], c["y"]))
		var t: Vector2 = _work_spot(store, 0, rng, grid) if not store.is_empty() else _work_spot(wb, 0, rng, grid)
		c["tx"] = t.x; c["ty"] = t.y; c["ptx"] = -99999
		return true

# Nearest harvestable node tile of `terrain` within NODE_RADIUS of the building.
static func _find_node(wb: Dictionary, terrain: int, grid: Object) -> Vector2:
	if terrain < 0 or grid == null:
		return Vector2(-1, -1)
	var center := _site_center(wb)
	var cx: int = int(round(center.x)); var cy: int = int(round(center.y))
	for r in range(1, NODE_RADIUS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var x: int = cx + dx; var y: int = cy + dy
				if grid.in_bounds(x, y) and grid.get_terrain(x, y) == terrain and grid.get_resource_density(x, y) > 0:
					return Vector2(x, y)
	return Vector2(-1, -1)

static func _nearest_building_of(buildings: Array, types: Array, from: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for b in buildings:
		if not (b is Dictionary) or not b.get("built", true) or not b.get("is_active", true):
			continue
		if b.get("type", "") not in types:
			continue
		var d := from.distance_to(_site_center(b))
		if d < best_d:
			best_d = d
			best = b
	return best

static func _store_types(kind: String) -> Array:
	match kind:
		"granary": return ["granary", "village_hall", "keep"]
		"armory":  return ["armory", "village_hall", "keep"]
	return ["stockpile", "village_hall", "keep"]

static func _has_inputs(wb: Dictionary, player: Dictionary) -> bool:
	var inputs: Dictionary = ResourceTick.PRODUCTION_INPUTS.get(wb.get("type", ""), {})
	var res: Dictionary = player.get("resources", {})
	for r in inputs:
		if int(res.get(r, 0)) < int(inputs[r]):
			return false
	return true

static func _consume_inputs(wb: Dictionary, player: Dictionary) -> bool:
	if not _has_inputs(wb, player):
		return false
	var inputs: Dictionary = ResourceTick.PRODUCTION_INPUTS.get(wb.get("type", ""), {})
	for r in inputs:
		player["resources"][r] = int(player["resources"].get(r, 0)) - int(inputs[r])
	return true

static func _granary_room(player: Dictionary) -> int:
	return maxi(0, FoodSystem.get_granary_capacity(player) - FoodSystem.get_total_food(player))

# Credit a finished delivery. False → primary store full (the worker waits).
static func _hauler_deposit(c: Dictionary, wb: Dictionary, player: Dictionary, season: int, farm_mult: float) -> bool:
	var outputs := ResourceTick.per_worker_output(wb, player, season, farm_mult)
	if outputs.is_empty():
		c["carry"] = ""
		return true
	var primary: String = String(c.get("carry", ""))
	if primary == "" or primary == "raw" or not outputs.has(primary):
		primary = String(outputs.keys()[0])
	var kind := StorageSystem.store_for(primary)
	if kind == "stockpile" and StorageSystem.room(player) <= 0:
		return false
	if kind == "granary" and _granary_room(player) <= 0:
		return false
	for g in outputs:
		var amt: int = int(outputs[g])
		var k := StorageSystem.store_for(g)
		if k == "stockpile":
			amt = mini(amt, StorageSystem.room(player))
			if amt > 0:
				player["resources"][g] = int(player.get("resources", {}).get(g, 0)) + amt
		elif k == "granary":
			amt = mini(amt, _granary_room(player))
			if amt > 0:
				player["food"][g] = int(player.get("food", {}).get(g, 0)) + amt
		else:
			player["armory"][g] = int(player.get("armory", {}).get(g, 0)) + amt
	c["carry"] = ""
	return true

static func _tick_citizen(c: Dictionary, buildings: Array, citizens: Array,
		rng: RandomNumberGenerator, grid: Object, season: int = 0,
		player: Dictionary = {}, farm_mult: float = 1.0, changed: Array = []) -> void:
	# Safety net: if a pawn somehow ends up standing inside a building or on
	# impassable terrain (a building raised on top of it, a bad push), pop it out
	# to the nearest free tile so it can never get trapped in/on a structure.
	if grid != null and not _tile_free(grid, int(round(c["x"])), int(round(c["y"]))):
		var free := _snap_to_free(grid, Vector2(c["x"], c["y"]))
		c["x"] = free.x
		c["y"] = free.y
		c["vx"] = 0.0
		c["vy"] = 0.0
	var pos := Vector2(c["x"], c["y"])
	match c.get("state", STATE_IDLE):
		STATE_WALK:
			var tgt := Vector2(c["tx"], c["ty"])
			_follow_path(c, tgt, citizens, grid)
			var d := Vector2(c["x"], c["y"]).distance_to(tgt)
			if d <= ARRIVE_DIST:
				c["stuck_ticks"] = 0
				c.erase("best_dist")
				var b := _find(buildings, c.get("job", -1))
				if c.get("role", "") == "builder" and not b.is_empty() and is_site(b):
					c["state"] = STATE_BUILD
				elif c.get("role", "") == "worker" and not b.is_empty() and b.get("built", true):
					c["state"] = STATE_WORK
					c["state_ticks"] = rng.randi_range(WORK_TICKS.x, WORK_TICKS.y)
					if ResourceTick.is_chain(b.get("type", "")):
						c["work_phase"] = PH_SEEK
						c["src_set"] = false
						c["carry"] = ""
				else:
					_go_home(c, rng, grid)
			else:
				_track_stuck(c, d, buildings, rng, grid)
		STATE_BUILD:
			c["vx"] = 0.0; c["vy"] = 0.0
			var b := _find(buildings, c.get("job", -1))
			if b.is_empty() or not is_site(b):
				# Finished (or removed): flow straight to the next site if one remains,
				# rather than trekking all the way home and back.
				if not _assign_next_site(c, buildings, grid):
					_go_home(c, rng, grid)
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
			var wb := _find(buildings, c.get("job", -1))
			if c.get("role", "") != "worker" or wb.is_empty() or not wb.get("built", true):
				_go_home(c, rng, grid)   # released, demolished, or reverted
			elif ResourceTick.is_chain(wb.get("type", "")):
				# Production buildings: physically gather → process → deliver.
				_tick_hauler(c, wb, buildings, citizens, grid, rng, season, player, farm_mult, changed)
			else:
				# Service buildings (market/inn/church/granary…): stand and toil; the view
				# animates the job. Periodically shuffle so workers don't stand frozen.
				var ctr := _site_center(wb)
				c["facing"] = 1.0 if ctr.x >= c["x"] else -1.0
				c["state_ticks"] = int(c.get("state_ticks", 0)) - 1
				if c["state_ticks"] <= 0:
					var spot := _work_spot(wb, int(c.get("work_slot", 0)) + rng.randi_range(0, 5), rng, grid)
					c["tx"] = spot.x
					c["ty"] = spot.y
					c["state"] = STATE_WALK
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

# Walk toward a target by following an A* path that ROUTES AROUND buildings, so
# pawns never get wedged against walls in a dense town. The path is cached and
# only recomputed when the target tile changes or the pawn strays off it. Falls
# back to crude steering when there's no grid (headless tests) or no path.
static func _follow_path(c: Dictionary, tgt: Vector2, citizens: Array, grid: Object) -> void:
	if grid == null:
		_step_to(c, tgt, citizens, grid)
		return
	var tix: int = int(round(tgt.x))
	var tiy: int = int(round(tgt.y))
	var path: Array = c.get("path", [])
	var stale: bool = int(c.get("ptx", -99999)) != tix or int(c.get("pty", -99999)) != tiy
	if not stale and not path.is_empty():
		# Recompute if we've been knocked off the next waypoint.
		if Vector2(c["x"], c["y"]).distance_to(Vector2(path[0][0], path[0][1])) > 2.5:
			stale = true
	if stale:
		path = Pathfinder.find_path(grid, int(round(c["x"])), int(round(c["y"])), tix, tiy, LAND_MOVE, true)
		c["path"] = path
		c["ptx"] = tix
		c["pty"] = tiy
	if path.is_empty():
		_step_to(c, tgt, citizens, grid)   # adjacent, already there, or unreachable
		return
	var wp := Vector2(path[0][0], path[0][1])
	_step_to(c, wp, citizens, grid)
	if Vector2(c["x"], c["y"]).distance_to(wp) <= 0.55:
		path.remove_at(0)
		c["path"] = path

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
	# Terrain scales pace: villagers stride twice as fast on a path/road and slow in
	# forest/water (mirrors the military _terrain_factor).
	var spd: float = _walk_speed(grid, pos)
	var step := dir * spd
	if grid != null and not _passable(grid, pos + step):
		# Try fanning the heading out to slip around the obstacle.
		var deflected := false
		for ang in [0.7, -0.7, 1.3, -1.3, 2.0, -2.0]:
			var alt := dir.rotated(ang) * spd
			if _passable(grid, pos + alt):
				step = alt
				deflected = true
				break
		if not deflected:
			step = Vector2.ZERO
	c["vx"] = step.x; c["vy"] = step.y
	c["x"] += step.x; c["y"] += step.y

# Walk speed at a tile: base / terrain-cost, so a ROAD (cost 0.5) is 2× faster.
static func _walk_speed(grid: Object, pos: Vector2) -> float:
	if grid == null or not grid.has_method("get_move_cost"):
		return WALK_SPEED
	var cost: float = clampf(grid.get_move_cost(int(round(pos.x)), int(round(pos.y))), 0.4, 4.0)
	return WALK_SPEED / cost

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
		return grid.has_method("is_field_at") and grid.is_field_at(gx, gy)
	return true

# A spot for a worker to toil at. Field buildings (orchards/farms) are walkable, so
# the worker stands AMONG the rows/trees; solid buildings keep workers just outside.
# Slots spread workers out; small jitter lets them tend different parts.
static func _work_spot(b: Dictionary, slot: int, rng: RandomNumberGenerator, grid: Object = null) -> Vector2:
	var defn: Dictionary = BuildingRegistry.lookup(b.get("type", ""))
	if defn.get("field", false):
		return _field_node(b, slot, rng, grid)
	var w: int = defn.get("width", 1)
	var h: int = defn.get("height", 1)
	var center := Vector2(float(b.get("grid_x", 0)) + (w - 1) * 0.5, float(b.get("grid_y", 0)) + (h - 1) * 0.5)
	var ring: int = maxi(4, 2 * (w + h))
	# Sit just OUTSIDE the footprint (never on a building tile) and snap to the
	# nearest walkable, unbuilt tile so workers don't end up stuck on the wall.
	var radius: float = maxf(w, h) * 0.5 + 1.1
	var ang: float = TAU * float(slot % ring) / float(ring) + rng.randf_range(-0.25, 0.25)
	var ideal := center + Vector2(cos(ang), sin(ang)) * radius
	return _snap_to_free(grid, ideal)

# A standing spot AMONG the rows/trees of a walkable field building. Spreads workers
# across the interior footprint tiles, with jitter so they tend different rows.
static func _field_node(b: Dictionary, slot: int, rng: RandomNumberGenerator, grid: Object = null) -> Vector2:
	var defn: Dictionary = BuildingRegistry.lookup(b.get("type", ""))
	var w: int = maxi(1, defn.get("width", 1))
	var h: int = maxi(1, defn.get("height", 1))
	var idx: int = slot % (w * h)
	var gx: float = float(b.get("grid_x", 0)) + float(idx % w)
	var gy: float = float(b.get("grid_y", 0)) + float(idx / w)
	if rng != null:
		gx += rng.randf_range(-0.3, 0.3)
		gy += rng.randf_range(-0.3, 0.3)
	return _snap_to_free(grid, Vector2(gx, gy))

static func _go_home(c: Dictionary, rng: RandomNumberGenerator, grid: Object = null) -> void:
	c["role"] = "peasant"
	c["job"] = -1
	c["job_type"] = ""
	c["work_anim"] = ""
	c["state"] = STATE_WALK
	c["path"] = []
	# Snap the home target to a free tile so a campfire ring spot on the hall
	# doesn't leave the pawn pathing into a wall.
	var home := _snap_to_free(grid, Vector2(c["hx"], c["hy"]))
	c["tx"] = home.x; c["ty"] = home.y
	# Arrive-home is handled by the WALK case → falls back to idle there.
	if Vector2(c["x"], c["y"]).distance_to(home) <= ARRIVE_DIST:
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
static func _build_spot(b: Dictionary, slot: int, grid: Object = null) -> Vector2:
	var defn: Dictionary = BuildingRegistry.lookup(b.get("type", ""))
	var w: int = defn.get("width", 1)
	var h: int = defn.get("height", 1)
	var center := Vector2(float(b.get("grid_x", 0)) + (w - 1) * 0.5, float(b.get("grid_y", 0)) + (h - 1) * 0.5)
	var ring: int = maxi(6, 2 * (w + h))           # roughly one slot per perimeter tile
	var radius: float = maxf(w, h) * 0.5 + 1.1     # just beyond the wall
	var ang: float = TAU * float(slot % ring) / float(ring)
	var ideal := center + Vector2(cos(ang), sin(ang)) * radius
	return _snap_to_free(grid, ideal)

# A walking pawn that stops making progress toward its target recovers here: first by
# re-targeting a reachable standing spot near its job, and failing that by abandoning
# the job and heading home (which frees the slot for another pawn). This guarantees a
# builder/worker can never freeze forever against an unreachable site.
static func _track_stuck(c: Dictionary, dist: float, buildings: Array,
		rng: RandomNumberGenerator, grid: Object) -> void:
	var best: float = float(c.get("best_dist", 1.0e9))
	if dist < best - STUCK_EPS:
		c["best_dist"] = dist        # made progress — reset the patience clock
		c["stuck_ticks"] = 0
		return
	var st: int = int(c.get("stuck_ticks", 0)) + 1
	c["stuck_ticks"] = st
	if st < STUCK_TIMEOUT:
		return
	# Given up on the current route: reset tracking and try to recover.
	c["stuck_ticks"] = 0
	c.erase("best_dist")
	c["path"] = []
	c["ptx"] = -99999    # force a fresh path next tick
	var b := _find(buildings, c.get("job", -1))
	if not b.is_empty():
		var is_work: bool = c.get("role", "") == "worker"
		var slot: int = int(c.get("work_slot", 0)) if is_work else int(c.get("build_slot", 0))
		var spot := _reachable_spot(b, slot, c, grid, is_work, rng)
		if _is_reachable(c, int(round(spot.x)), int(round(spot.y)), grid):
			c["tx"] = spot.x
			c["ty"] = spot.y
			return
	# Nothing near the job can be reached (walled-in site) — release it and go home.
	_go_home(c, rng, grid)

# A standing spot near building `b` the pawn can actually path to from where it stands.
# Tries the preferred slot then a few neighbours around the perimeter ring; returns the
# first reachable one, or the nominal spot as a best-effort fallback (the stuck timer
# then releases the pawn). With no grid (headless tests) returns the nominal spot.
static func _reachable_spot(b: Dictionary, slot: int, c: Dictionary, grid: Object,
		is_work: bool, rng: RandomNumberGenerator) -> Vector2:
	var nominal: Vector2 = _work_spot(b, slot, rng, grid) if is_work else _build_spot(b, slot, grid)
	if grid == null:
		return nominal
	for off in range(0, 8):
		var spot: Vector2 = _work_spot(b, slot + off, rng, grid) if is_work else _build_spot(b, slot + off, grid)
		if _is_reachable(c, int(round(spot.x)), int(round(spot.y)), grid):
			return spot
	return nominal

# True if the pawn can stand-or-path to tile (gx,gy). No grid → assume reachable.
static func _is_reachable(c: Dictionary, gx: int, gy: int, grid: Object) -> bool:
	if grid == null:
		return true
	var cx: int = int(round(c.get("x", 0.0)))
	var cy: int = int(round(c.get("y", 0.0)))
	if cx == gx and cy == gy:
		return true
	return not Pathfinder.find_path(grid, cx, cy, gx, gy, LAND_MOVE, true).is_empty()

# Snap a desired position to the nearest in-bounds, walkable, unbuilt tile so a
# pawn never gets a standing target inside a building or on impassable terrain.
static func _snap_to_free(grid: Object, p: Vector2) -> Vector2:
	if grid == null:
		return p
	var ix: int = int(round(p.x))
	var iy: int = int(round(p.y))
	for r in range(0, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				if _tile_free(grid, ix + dx, iy + dy):
					return Vector2(ix + dx, iy + dy)
	return p

static func _tile_free(grid: Object, x: int, y: int) -> bool:
	if not grid.in_bounds(x, y):
		return false
	if grid.has_method("is_passable") and not grid.is_passable(x, y, LAND_MOVE):
		return false
	if grid.has_method("get_building_at") and grid.get_building_at(x, y) != 0:
		return grid.has_method("is_field_at") and grid.is_field_at(x, y)
	return true

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
