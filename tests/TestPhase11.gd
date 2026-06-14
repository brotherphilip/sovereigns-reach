extends SceneTree
# Phase 11 test suite — Faith & Religion system (GDD §3.3).
# Run: godot --headless --script tests/TestPhase11.gd

const ReligionSystem = preload("res://simulation/economy/ReligionSystem.gd")
const BuildingState  = preload("res://simulation/buildings/BuildingState.gd")
const UnitState      = preload("res://simulation/units/UnitState.gd")
const HUDController   = preload("res://view/hud/HUDController.gd")

var _gs: Node = null
var _sc: Node = null
var _pass: int = 0
var _fail: int = 0

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_sc = root.get_node_or_null("SimulationClock")
	if _gs == null or _sc == null:
		print("FATAL: autoloads missing"); quit(1); return
	_run()
	print("Phase 11 Results: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: " + label)
	else: _fail += 1; print("  FAIL: " + label)

func _church(workers: int = 2) -> Dictionary:
	var b := BuildingState.create("church", 0, 10, 10, 1)
	b["workers"] = workers
	return b

func _cathedral(workers: int = 4) -> Dictionary:
	var b := BuildingState.create("cathedral", 0, 20, 20, 2)
	b["workers"] = workers
	return b

func _run() -> void:
	print("\n--- Coverage ---")
	var p := {"buildings": [_church(), BuildingState.create("hovel", 0, 1, 1, 3),
		BuildingState.create("hovel", 0, 2, 2, 4), BuildingState.create("hovel", 0, 3, 3, 5)]}
	# 1 church radius 12 → 12/4 = 3 coverage units; 3 hovels → 3/3 = 1.0
	ok("full coverage with church + 3 hovels", absf(ReligionSystem.compute_religion_coverage(p) - 1.0) < 0.001)
	var p2 := {"buildings": [_church()]}
	for i in range(12):
		p2["buildings"].append(BuildingState.create("hovel", 0, i, 0, 100 + i))
	# 3 / 12 = 0.25
	ok("partial coverage scales with hovels", absf(ReligionSystem.compute_religion_coverage(p2) - 0.25) < 0.01)
	ok("no holy buildings → zero coverage",
		ReligionSystem.compute_religion_coverage({"buildings": [BuildingState.create("hovel",0,0,0,1)]}) == 0.0)

	print("\n--- Faith capacity ---")
	ok("church cap = 30", ReligionSystem.faith_capacity({"buildings": [_church()]}) == 30.0)
	ok("church + cathedral cap = 110",
		ReligionSystem.faith_capacity({"buildings": [_church(), _cathedral()]}) == 110.0)

	print("\n--- Faith generation ---")
	var pf := {"buildings": [_church(), BuildingState.create("hovel",0,1,1,3),
		BuildingState.create("hovel",0,2,2,4), BuildingState.create("hovel",0,3,3,5)], "units": []}
	var gain_no_monk: float = ReligionSystem.daily_faith_gain(pf)
	ok("staffed church generates faith", gain_no_monk > 0.0)
	pf["units"] = [UnitState.create("monk", 0, 5, 5, 1)]
	ok("monks increase faith generation", ReligionSystem.daily_faith_gain(pf) > gain_no_monk)
	# A church with no congregation (no hovels) still has coverage 0 → reduced yield.
	var pf2 := {"buildings": [_church()], "units": []}
	ok("faithless church yields less than full congregation",
		ReligionSystem.daily_faith_gain(pf2) < gain_no_monk)

	print("\n--- Blessing ---")
	var pb := {"buildings": [_cathedral()], "units": [], "faith": ReligionSystem.BLESSING_THRESHOLD}
	var r := ReligionSystem.tick_faith(pb, 100)
	ok("blessing bestowed at threshold", r.get("blessing", false))
	ok("blessing spends the threshold faith", float(pb["faith"]) < ReligionSystem.BLESSING_THRESHOLD)
	ok("blessing sets protection window", int(pb["blessing_until"]) > 100)
	ok("blessing active during window", ReligionSystem.is_blessing_active(pb, 200))
	ok("blessing expires after window", not ReligionSystem.is_blessing_active(pb, 100000))
	# Below threshold: faith accrues, no blessing.
	var pb2 := {"buildings": [_church()], "units": [], "faith": 0.0}
	var r2 := ReligionSystem.tick_faith(pb2, 0)
	ok("faith accrues below threshold", float(pb2["faith"]) > 0.0 and not r2.get("blessing", false))
	ok("faith never exceeds cap", float(pb2["faith"]) <= float(pb2["faith_cap"]))

	print("\n--- HUD exposure ---")
	var hud := HUDController.get_hud_data(
		{"faith": 25.0, "faith_cap": 80.0, "blessing_until": 500}, {"current": 0}, 100)
	ok("HUD exposes faith", absf(float(hud.get("faith", -1)) - 25.0) < 0.001)
	ok("HUD exposes faith_cap", absf(float(hud.get("faith_cap", -1)) - 80.0) < 0.001)
	ok("HUD reports active blessing", hud.get("blessing_active", false) == true)

	print("\n--- GameState integration (1 game-day) ---")
	_gs.players.clear()
	_gs._grid = null
	_sc.current_tick = 0
	_gs.initialize_player(0, "Devout", 100, 100)
	var pl: Dictionary = _gs.players[0]
	pl["buildings"] = [_church(), BuildingState.create("hovel",0,1,1,9),
		BuildingState.create("hovel",0,2,2,10), BuildingState.create("hovel",0,3,3,11)]
	pl["food"]["apples"] = 9999
	pl["faith"] = 0.0
	for _i in range(240):
		_sc._advance_tick()
	ok("faith accrues through the live day-boundary tick", float(_gs.players[0].get("faith", 0.0)) > 0.0)
	ok("religion coverage updated live", float(_gs.players[0].get("religion_coverage", 0.0)) > 0.0)
