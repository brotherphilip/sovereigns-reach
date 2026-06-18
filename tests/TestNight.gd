extends SceneTree
# Proof harness for the night sleep cycle: once it's dark, idle villagers must walk to
# their allotted home's door and step INSIDE to sleep (STATE_INSIDE, not drawn) — they
# must NOT pace the wall forever. Regression guard for the bug where the STATE_WALK
# arrival handler called _go_home (re-targeting the home centre) instead of going inside,
# leaving pawns oscillating at the doorstep all night.
# Run: godot --headless --script tests/TestNight.gd

const CitizenSystem    = preload("res://simulation/world/CitizenSystem.gd")
const SeasonSystem     = preload("res://simulation/world/SeasonSystem.gd")
const WorldGrid        = preload("res://simulation/world/WorldGrid.gd")
const BuildingState    = preload("res://simulation/buildings/BuildingState.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

var _pass := 0
var _fail := 0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 7
	_test_is_night_window()
	_test_villagers_go_inside_at_night()
	_test_villagers_come_out_by_day()
	print("\n=== Night Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _bld(btype: String, gx: int, gy: int) -> Dictionary:
	var b := BuildingState.create(btype, 0, gx, gy, _rng.randi())
	b["built"] = true
	return b

func _register(grid: WorldGrid, b: Dictionary) -> void:
	var defn := BuildingRegistry.lookup(b["type"])
	var w: int = defn.get("width", 1)
	var h: int = defn.get("height", 1)
	for dy in range(h):
		for dx in range(w):
			grid.set_building_at(b["grid_x"] + dx, b["grid_y"] + dy, b["id"])

func _player(buildings: Array) -> Dictionary:
	return {"buildings": buildings, "resources": {}, "food": {}, "armory": {},
		"tech_unlocks": [], "active_edicts": [], "population": 6}

# A deep-night tick (≈ midnight) so SeasonSystem.is_night() is true throughout the run.
func _night_tick() -> int:
	return SeasonSystem.DAY_NIGHT_TICKS / 2   # f = 0.5 → night_factor = 1.0

func _count_inside(citizens: Array) -> int:
	var n := 0
	for c in citizens:
		if c is Dictionary and c.get("state", "") == CitizenSystem.STATE_INSIDE:
			n += 1
	return n

func _test_is_night_window() -> void:
	print("\n[Night window]")
	ok("midnight tick reads as night", SeasonSystem.is_night(_night_tick()))
	ok("noon tick reads as day", not SeasonSystem.is_night(0))

func _test_villagers_go_inside_at_night() -> void:
	print("\n[Villagers retire indoors after dark]")
	var grid := WorldGrid.new(60, 60)
	var home := _bld("hovel", 30, 30)
	_register(grid, home)
	var player := _player([home])
	var citizens: Array = []
	CitizenSystem.spawn(citizens, 6, 31.0, 33.0, _rng, 1)
	# Drive a stretch of night (constant night tick) — long enough to walk to the door
	# and step inside. day_night = true enables the night branch.
	var nt := _night_tick()
	for _i in range(3000):
		CitizenSystem.tick(citizens, player, _rng, nt, grid, 1.0, true)
	var inside := _count_inside(citizens)
	ok("all 6 villagers are asleep indoors at night (got %d/6)" % inside, inside == 6)

func _test_villagers_come_out_by_day() -> void:
	print("\n[Villagers rise at dawn]")
	var grid := WorldGrid.new(60, 60)
	var home := _bld("hovel", 30, 30)
	_register(grid, home)
	var player := _player([home])
	var citizens: Array = []
	CitizenSystem.spawn(citizens, 4, 31.0, 33.0, _rng, 1)
	var nt := _night_tick()
	for _i in range(3000):
		CitizenSystem.tick(citizens, player, _rng, nt, grid, 1.0, true)
	ok("indoors at night", _count_inside(citizens) == 4)
	# Now switch to a daytime tick: they must step back out (no longer inside).
	for _i in range(400):
		CitizenSystem.tick(citizens, player, _rng, 0, grid, 1.0, true)
	ok("back outdoors by day (none left inside)", _count_inside(citizens) == 0)
