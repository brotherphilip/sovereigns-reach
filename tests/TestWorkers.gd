extends SceneTree
# Proof harness for the building-worker system: workers are drawn from the visible
# citizen stock, walk to their building, take the right job, work (tend), and are
# released when unassigned. Run: godot --headless --script tests/TestWorkers.gd

const CitizenSystem    = preload("res://simulation/world/CitizenSystem.gd")
const WorkerJobs       = preload("res://simulation/world/WorkerJobs.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const WorldGrid        = preload("res://simulation/world/WorldGrid.gd")

var _pass := 0
var _fail := 0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 7
	_test_mapping_coverage()
	_test_assign_pulls_idle_citizens()
	_test_release_when_unassigned()
	_test_release_when_demolished()
	_test_non_worker_building_takes_none()
	_test_reachability_helpers()
	_test_builder_reaches_open_site()
	_test_builder_recovers_from_unreachable_site()
	_test_orchardist_toils_inside_the_orchard()
	_test_builder_chains_between_sites()
	print("\n=== Worker Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _building(btype: String, bid: int, gx: int, gy: int, workers: int) -> Dictionary:
	return {"id": bid, "type": btype, "grid_x": gx, "grid_y": gy,
		"built": true, "is_active": true,
		"max_workers": BuildingRegistry.lookup(btype).get("max_workers", 0),
		"workers": workers}

func _citizens(n: int, cx: float, cy: float) -> Array:
	var arr: Array = []
	CitizenSystem.spawn(arr, n, cx, cy, _rng, 1)
	return arr

func _count_workers(citizens: Array, bid: int) -> int:
	var n := 0
	for c in citizens:
		if c.get("role", "") == "worker" and int(c.get("job", -1)) == bid:
			n += 1
	return n

func _count_in_state(citizens: Array, role: String, state: String) -> int:
	var n := 0
	for c in citizens:
		if c.get("role", "") == role and c.get("state", "") == state:
			n += 1
	return n

func _run(citizens: Array, buildings: Array, n: int) -> void:
	for i in range(n):
		CitizenSystem.tick(citizens, buildings, _rng, i, null)

# ── 1. Every worker-employing building maps to a job ────────────────────────────

func _test_mapping_coverage() -> void:
	print("\n[Job mapping coverage]")
	var missing: Array = []
	for btype in BuildingRegistry.BUILDINGS:
		if BuildingRegistry.BUILDINGS[btype].get("max_workers", 0) > 0:
			if not WorkerJobs.employs_workers(btype):
				missing.append(btype)
	ok("every building with workers has a job (%d mapped)" % WorkerJobs.JOBS.size(), missing.is_empty())
	if not missing.is_empty():
		print("    missing: %s" % str(missing))

# ── 2. Assigning workers pulls idle villagers, who walk over and work ───────────

func _test_assign_pulls_idle_citizens() -> void:
	print("\n[Assign pulls idle citizens → walk → work]")
	var orchard := _building("apple_orchard", 1, 50, 50, 2)
	var buildings := [orchard]
	var citizens := _citizens(6, 50.0, 50.0)
	_run(citizens, buildings, 3)
	ok("2 villagers became orchard workers", _count_workers(citizens, 1) == 2)
	var jt_ok := true
	for c in citizens:
		if c.get("role", "") == "worker" and c.get("job_type", "") != "Orchardist":
			jt_ok = false
	ok("workers took the Orchardist job", jt_ok)
	_run(citizens, buildings, 250)
	ok("workers reached the workplace (≥1 in WORK)", _count_in_state(citizens, "worker", "work") >= 1)
	ok("the rest of the stock stayed villagers", citizens.size() == 6 and _count_workers(citizens, 1) == 2)

# ── 3. Lowering the worker count releases them back to villagers ─────────────────

func _test_release_when_unassigned() -> void:
	print("\n[Release when unassigned]")
	var mine := _building("iron_mine", 2, 60, 60, 3)
	var buildings := [mine]
	var citizens := _citizens(8, 60.0, 60.0)
	_run(citizens, buildings, 60)
	ok("3 miners assigned", _count_workers(citizens, 2) == 3)
	mine["workers"] = 1
	_run(citizens, buildings, 5)
	ok("surplus miners released (down to 1)", _count_workers(citizens, 2) == 1)

# ── 4. Demolishing the building frees its workers ───────────────────────────────

func _test_release_when_demolished() -> void:
	print("\n[Release when building removed]")
	var smithy := _building("blacksmith", 3, 40, 40, 1)
	var buildings := [smithy]
	var citizens := _citizens(4, 40.0, 40.0)
	_run(citizens, buildings, 60)
	ok("blacksmith staffed", _count_workers(citizens, 3) == 1)
	buildings.clear()  # demolished
	_run(citizens, buildings, 5)
	var any_worker := false
	for c in citizens:
		if c.get("role", "") == "worker":
			any_worker = true
	ok("worker released after demolition", not any_worker)

# ── 5. Buildings that employ nobody pull no workers ─────────────────────────────

func _test_non_worker_building_takes_none() -> void:
	print("\n[Non-worker building employs nobody]")
	var hovel := _building("hovel", 4, 30, 30, 0)
	var buildings := [hovel]
	var citizens := _citizens(4, 30.0, 30.0)
	_run(citizens, buildings, 30)
	ok("hovel pulled no workers", _count_workers(citizens, 4) == 0)

# ── 6. Stuck recovery: builders never freeze against an unreachable site ────────

# A construction site (unbuilt) registered on the grid footprint.
func _site(btype: String, bid: int, gx: int, gy: int) -> Dictionary:
	return {"id": bid, "type": btype, "grid_x": gx, "grid_y": gy,
		"built": false, "build_required": 40.0, "build_progress": 0.0}

func _open_grid(w: int, h: int) -> WorldGrid:
	return WorldGrid.new(w, h)   # _init fills GRASS (0) everywhere

func _seal_room(grid: WorldGrid, x0: int, y0: int, x1: int, y1: int) -> void:
	# Build an unbroken MOUNTAIN (impassable) ring so the interior is disconnected.
	for x in range(x0, x1 + 1):
		grid.set_terrain(x, y0, WorldGrid.Terrain.MOUNTAIN)
		grid.set_terrain(x, y1, WorldGrid.Terrain.MOUNTAIN)
	for y in range(y0, y1 + 1):
		grid.set_terrain(x0, y, WorldGrid.Terrain.MOUNTAIN)
		grid.set_terrain(x1, y, WorldGrid.Terrain.MOUNTAIN)

func _one(citizens: Array) -> Dictionary:
	return citizens[0]

func _test_reachability_helpers() -> void:
	print("\n[Reachability helpers]")
	var grid := _open_grid(40, 40)
	_seal_room(grid, 27, 27, 33, 33)              # interior 28..32 disconnected
	var c := {"x": 5.0, "y": 5.0}
	ok("open adjacent tile is reachable", CitizenSystem._is_reachable(c, 6, 5, grid))
	ok("tile inside a sealed room is unreachable", not CitizenSystem._is_reachable(c, 30, 30, grid))
	ok("no-grid always reachable", CitizenSystem._is_reachable(c, 999, 999, null))

func _test_builder_reaches_open_site() -> void:
	print("\n[Builder reaches an open site and builds]")
	var grid := _open_grid(40, 40)
	var site := _site("hovel", 9, 20, 20)
	grid.set_building_at(20, 20, 9)
	var buildings := [site]
	var citizens := _citizens(1, 16.0, 16.0)
	for i in range(700):
		CitizenSystem.tick(citizens, buildings, _rng, i, grid)
		if site.get("built", false):
			break
	ok("reachable site got built", site.get("built", false))

func _test_builder_recovers_from_unreachable_site() -> void:
	print("\n[Builder recovers from an unreachable site]")
	var grid := _open_grid(40, 40)
	_seal_room(grid, 27, 27, 33, 33)
	var site := _site("hovel", 11, 30, 30)         # sealed inside the room
	grid.set_building_at(30, 30, 11)
	var buildings := [site]
	# Spawn one villager just outside the west wall so it reaches the wall quickly and
	# then plateaus (rather than spending the whole window legitimately travelling).
	var citizens := [CitizenSystem.make_citizen(1, 25.0, 30.0, _rng)]
	citizens[0]["x"] = 25.0; citizens[0]["y"] = 30.0
	citizens[0]["hx"] = 25.0; citizens[0]["hy"] = 30.0
	var c := _one(citizens)
	var became_builder := false
	var released := false
	# A bit more than the stuck timeout so the recovery ladder fires.
	for i in range(CitizenSystem.STUCK_TIMEOUT + 160):
		CitizenSystem.tick(citizens, buildings, _rng, i, grid)
		if c.get("role", "") == "builder":
			became_builder = true
		elif became_builder and c.get("role", "") == "peasant":
			released = true
	ok("villager was pulled into building the site", became_builder)
	ok("stuck builder was released (never permanently frozen)", released)
	ok("the unreachable site never completed", not site.get("built", false))

# ── 7. Field believability: the orchardist toils AMONG the trees, not outside ───

func _test_orchardist_toils_inside_the_orchard() -> void:
	print("\n[Orchardist toils inside the orchard]")
	var grid := _open_grid(40, 40)
	var orchard := _building("apple_orchard", 21, 20, 20, 1)
	for dy in range(2):
		for dx in range(2):
			grid.set_building_at(20 + dx, 20 + dy, 21)
			grid.set_field_at(20 + dx, 20 + dy, true)   # walkable field rows
	var buildings := [orchard]
	var citizens := _citizens(4, 16.0, 16.0)
	var inside := false
	for i in range(800):
		CitizenSystem.tick(citizens, buildings, _rng, i, grid)
		for c in citizens:
			if c.get("role", "") == "worker" and c.get("state", "") == "work":
				if grid.is_field_at(int(round(c["x"])), int(round(c["y"]))):
					inside = true
		if inside:
			break
	ok("an orchardist stood among the orchard's trees (on a field tile)", inside)

# ── 8. Builders flow site→site without trekking home ────────────────────────────

func _test_builder_chains_between_sites() -> void:
	print("\n[Builder chains between sites]")
	var grid := _open_grid(60, 60)
	var site_a := _site("hovel", 31, 30, 30)
	var site_b := _site("hovel", 32, 44, 30)
	grid.set_building_at(30, 30, 31)
	grid.set_building_at(44, 30, 32)
	var buildings := [site_a, site_b]
	var citizens := [CitizenSystem.make_citizen(1, 28.0, 30.0, _rng)]
	citizens[0]["x"] = 28.0; citizens[0]["y"] = 30.0
	citizens[0]["hx"] = 28.0; citizens[0]["hy"] = 30.0
	var c := _one(citizens)
	var went_home := false
	var chained := false
	for i in range(4000):
		CitizenSystem.tick(citizens, buildings, _rng, i, grid)
		# A finishes first (nearer); the builder must then target B directly.
		if site_a.get("built", false):
			if c.get("role", "") == "peasant":
				went_home = true
			if c.get("role", "") == "builder" and int(c.get("job", -1)) == 32:
				chained = true
		if site_b.get("built", false):
			break
	ok("the first site was built", site_a.get("built", false))
	ok("builder chained straight to the second site (no home detour)", chained and not went_home)
	ok("both sites were built", site_a.get("built", false) and site_b.get("built", false))
