extends SceneTree
# Proof harness for the physical hauling economy: a gatherer must walk to a node, fell
# it (depleting the map), carry to its building, process, and DELIVER to a stockpile
# before any resource is credited; production stops when storage is full; a processor
# consumes a stockpiled input. Run: godot --headless --script tests/TestEconomy.gd

const CitizenSystem    = preload("res://simulation/world/CitizenSystem.gd")
const StorageSystem    = preload("res://simulation/economy/StorageSystem.gd")
const ResourceTick     = preload("res://simulation/economy/ResourceTick.gd")
const WorldGrid        = preload("res://simulation/world/WorldGrid.gd")
const BuildingState    = preload("res://simulation/buildings/BuildingState.gd")

var _pass := 0
var _fail := 0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 11
	_test_storage_capacity()
	_test_woodcutter_chain()
	_test_stop_when_full()
	_test_processor_chain()
	print("\n=== Economy Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _bld(btype: String, gx: int, gy: int, workers: int) -> Dictionary:
	var b := BuildingState.create(btype, 0, gx, gy, _rng.randi())
	b["built"] = true
	b["workers"] = workers
	return b

func _player(buildings: Array) -> Dictionary:
	return {"buildings": buildings, "resources": {}, "food": {}, "armory": {},
		"tech_unlocks": [], "active_edicts": [], "population": 20}

func _register(grid: WorldGrid, b: Dictionary) -> void:
	var defn := ResourceTick.PRODUCTION_OUTPUTS  # just to keep ResourceTick referenced
	grid.set_building_at(b["grid_x"], b["grid_y"], b["id"])

func _run(citizens: Array, player: Dictionary, grid: WorldGrid, n: int) -> void:
	for i in range(n):
		CitizenSystem.tick(citizens, player, _rng, i, grid, 1.0)

func _citizens(n: int, cx: float, cy: float) -> Array:
	var arr: Array = []
	CitizenSystem.spawn(arr, n, cx, cy, _rng, 1)
	return arr

# ── 1. Capacity math ────────────────────────────────────────────────────────────

func _test_storage_capacity() -> void:
	print("\n[Storage capacity]")
	var p := _player([])
	ok("base capacity with no stockpile == RAW_BASE", StorageSystem.get_capacity(p) == StorageSystem.RAW_BASE)
	p["buildings"].append(_bld("stockpile", 5, 5, 0))
	ok("a stockpile adds its capacity", StorageSystem.get_capacity(p) == StorageSystem.RAW_BASE + 100)
	p["resources"]["wood"] = 30
	ok("room = capacity - stored", StorageSystem.room(p) == StorageSystem.get_capacity(p) - 30)
	ok("wood routes to the stockpile", StorageSystem.store_for("wood") == "stockpile")
	ok("apples route to the granary", StorageSystem.store_for("apples") == "granary")
	ok("swords route to the armory", StorageSystem.store_for("swords") == "armory")

# ── 2. Woodcutter: gather a forest node → deliver wood (credited only on delivery) ──

func _test_woodcutter_chain() -> void:
	print("\n[Woodcutter gathers → processes → delivers]")
	var grid := WorldGrid.new(60, 60)
	var wc := _bld("woodcutter_camp", 30, 30, 2)
	var sp := _bld("stockpile", 27, 30, 0)
	_register(grid, wc); _register(grid, sp)
	# A small wood near the camp.
	var forest: Array = []
	for d in [Vector2i(34, 30), Vector2i(35, 30), Vector2i(34, 31), Vector2i(35, 31), Vector2i(33, 29)]:
		grid.set_terrain(d.x, d.y, WorldGrid.Terrain.FOREST)
		grid.set_resource_density(d.x, d.y, 200)
		forest.append(d)
	var initial_density := 0
	for d in forest:
		initial_density += grid.get_resource_density(d.x, d.y)
	var player := _player([wc, sp])
	var citizens := _citizens(6, 30.0, 30.0)

	_run(citizens, player, grid, 120)
	ok("no wood yet — nothing delivered after 120 ticks", int(player["resources"].get("wood", 0)) == 0)

	_run(citizens, player, grid, 2400)
	ok("wood was delivered to storage", int(player["resources"].get("wood", 0)) > 0)

	var after_density := 0
	for d in forest:
		after_density += grid.get_resource_density(d.x, d.y)
	ok("the forest was depleted by harvesting", after_density < initial_density)

# ── 3. Production halts when storage is full ─────────────────────────────────────

func _test_stop_when_full() -> void:
	print("\n[Stop-when-full]")
	var grid := WorldGrid.new(60, 60)
	var wc := _bld("woodcutter_camp", 30, 30, 2)
	_register(grid, wc)
	for d in [Vector2i(33, 30), Vector2i(34, 30), Vector2i(33, 31)]:
		grid.set_terrain(d.x, d.y, WorldGrid.Terrain.FOREST)
		grid.set_resource_density(d.x, d.y, 200)
	var player := _player([wc])    # no stockpile → capacity == RAW_BASE
	var cap := StorageSystem.get_capacity(player)
	player["resources"]["wood"] = cap   # already full
	var citizens := _citizens(6, 30.0, 30.0)
	_run(citizens, player, grid, 2000)
	ok("full storage never exceeds capacity", int(player["resources"].get("wood", 0)) <= cap)
	ok("nothing was added while full", int(player["resources"].get("wood", 0)) == cap)

# ── 4. Processor: fetch wheat from storage → deliver flour ───────────────────────

func _test_processor_chain() -> void:
	print("\n[Mill consumes wheat → delivers flour]")
	var grid := WorldGrid.new(60, 60)
	var mill := _bld("mill", 30, 30, 2)
	var sp := _bld("stockpile", 27, 30, 0)
	_register(grid, mill); _register(grid, sp)
	var player := _player([mill, sp])
	player["resources"]["wheat"] = 12
	player["resources"]["flour"] = 0
	var citizens := _citizens(6, 30.0, 30.0)
	_run(citizens, player, grid, 2600)
	ok("flour was produced and delivered", int(player["resources"].get("flour", 0)) > 0)
	ok("wheat was consumed", int(player["resources"].get("wheat", 0)) < 12)
