extends SceneTree
# Phase 12 test suite — Public Health & Disease (GDD §3.5.3).
# Run: godot --headless --script tests/TestPhase12.gd

const DiseaseSystem  = preload("res://simulation/economy/DiseaseSystem.gd")
const BuildingState  = preload("res://simulation/buildings/BuildingState.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const HUDController   = preload("res://view/hud/HUDController.gd")
const WeatherSystem  = preload("res://simulation/world/WeatherSystem.gd")

var _pass: int = 0
var _fail: int = 0

func _init() -> void:
	await process_frame
	_run()
	print("Phase 12 Results: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: " + label)
	else: _fail += 1; print("  FAIL: " + label)

func _player(hovels: int, apoth: int = 0, wells: int = 0) -> Dictionary:
	var b: Array = []
	for i in range(hovels):
		b.append(BuildingState.create("hovel", 0, i, 0, 100 + i))
	for j in range(apoth):
		var a := BuildingState.create("apothecary", 0, j, 5, 200 + j); a["workers"] = 1
		b.append(a)
	for k in range(wells):
		b.append(BuildingState.create("well", 0, k, 9, 300 + k))
	return {"buildings": b, "population": 50, "food": {"apples": 10, "bread": 10, "cheese": 10, "meat": 10}}

func _run() -> void:
	print("\n--- Well building ---")
	ok("well registered", BuildingRegistry.is_valid_type("well"))
	ok("well needs no workers", BuildingRegistry.lookup("well").get("max_workers", -1) == 0)

	print("\n--- Coverage ---")
	ok("apothecary coverage 1/8 = 0.75",
		absf(DiseaseSystem.compute_apothecary_coverage(_player(8, 1)) - 0.75) < 0.01)
	ok("well coverage (no staff) 1/8 = 0.75",
		absf(DiseaseSystem.compute_well_coverage(_player(8, 0, 1)) - 0.75) < 0.01)
	# 12 hovels: 1 apoth → 0.5; 1 well → 0.5; sanitation = 0.5 + 0.5*0.5 = 0.75
	ok("sanitation combines apothecary + half well",
		absf(DiseaseSystem.sanitation_coverage(_player(12, 1, 1)) - 0.75) < 0.01)

	print("\n--- Health ---")
	var healthy := _player(8, 2)  # full sanitation, good food
	ok("well-sanitised realm is healthy", DiseaseSystem.compute_health(healthy, {"current": 0}) >= 95.0)
	var h_winter := DiseaseSystem.compute_health(healthy, {"current": WeatherSystem.WeatherType.SNOW})
	ok("winter lowers health", h_winter < DiseaseSystem.compute_health(healthy, {"current": 0}))
	var starving := _player(8, 2); starving["food"] = {"apples": 1}  # variety < 2
	ok("malnutrition lowers health",
		DiseaseSystem.compute_health(starving, {"current": 0}) < DiseaseSystem.compute_health(healthy, {"current": 0}))

	print("\n--- Crowding risk ---")
	ok("crowded + no sanitation = risk", DiseaseSystem.is_crowding_risk(_player(8)))
	ok("crowded + apothecaries = safe", not DiseaseSystem.is_crowding_risk(_player(8, 2)))
	ok("few hovels = no risk", not DiseaseSystem.is_crowding_risk(_player(3)))
	ok("wells alone can avert crowding risk", not DiseaseSystem.is_crowding_risk(_player(6, 0, 1)))

	print("\n--- Disease severity dynamics ---")
	var rng := RandomNumberGenerator.new()
	var sick := _player(8)            # no sanitation
	sick["disease_severity"] = 25.0
	sick["disease_active"] = true
	var pop0: int = sick["population"]
	DiseaseSystem.tick(sick, rng, 240)
	ok("plague kills peasants", int(sick["population"]) < pop0)
	ok("plague spreads without sanitation", float(sick["disease_severity"]) > 25.0)
	ok("plague stays active while severe", sick.get("disease_active", false))

	var cured := _player(8, 2)        # full apothecary coverage
	cured["disease_severity"] = 25.0
	cured["disease_active"] = true
	DiseaseSystem.tick(cured, rng, 240)
	ok("apothecary care cures the plague", not cured.get("disease_active", true))
	ok("cured severity is zero", float(cured["disease_severity"]) == 0.0)

	# Deaths scale with severity.
	var mild := _player(8); mild["disease_severity"] = 10.0; mild["disease_active"] = true
	var severe := _player(8); severe["disease_severity"] = 90.0; severe["disease_active"] = true
	var mp: int = mild["population"]; var sp: int = severe["population"]
	DiseaseSystem.tick(mild, rng, 240)
	DiseaseSystem.tick(severe, rng, 240)
	ok("severe plague kills more than mild", (sp - int(severe["population"])) > (mp - int(mild["population"])))

	ok("health stored on player after tick", float(mild.get("health", -1.0)) >= 0.0)
	ok("no disease tick mid-day", DiseaseSystem.tick(_player(8), rng, 120).is_empty())

	print("\n--- HUD exposure ---")
	var hud := HUDController.get_hud_data(
		{"health": 72.0, "disease_active": true, "disease_severity": 40.0}, {"current": 0}, 100)
	ok("HUD exposes health", absf(float(hud.get("health", -1)) - 72.0) < 0.01)
	ok("HUD exposes disease_severity", absf(float(hud.get("disease_severity", -1)) - 40.0) < 0.01)
	ok("HUD exposes disease_active", hud.get("disease_active", false) == true)
