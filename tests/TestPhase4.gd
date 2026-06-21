extends SceneTree
# Phase 4 test suite — FoodSystem, AleSystem, ReligionSystem, TaxSystem,
#                       DiseaseSystem, MarketSystem, and GameState economy integration.
# Run: godot --headless --script tests/TestPhase4.gd

const FoodSystem     = preload("res://simulation/economy/FoodSystem.gd")
const AleSystem      = preload("res://simulation/economy/AleSystem.gd")
const ReligionSystem = preload("res://simulation/economy/ReligionSystem.gd")
const TaxSystem      = preload("res://simulation/economy/TaxSystem.gd")
const DiseaseSystem  = preload("res://simulation/economy/DiseaseSystem.gd")
const MarketSystem   = preload("res://simulation/economy/MarketSystem.gd")
const PopularityEngine = preload("res://simulation/economy/PopularityEngine.gd")
const BuildingState  = preload("res://simulation/buildings/BuildingState.gd")

# Mirror CommandType enum values to avoid compile-time autoload resolution (same pattern as TestPhase3)
const CT_BUY_RESOURCE  = 5   # CommandQueue.CommandType.BUY_RESOURCE
const CT_SELL_RESOURCE = 6   # CommandQueue.CommandType.SELL_RESOURCE

var _gs = null
var _cq = null
var _sc = null

var _pass: int = 0
var _fail: int = 0
var _errors: Array = []

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_cq = root.get_node_or_null("CommandQueue")
	_sc = root.get_node_or_null("SimulationClock")
	if not (_gs and _cq and _sc):
		print("FATAL: Autoloads not found — gs=%s cq=%s sc=%s" % [str(_gs), str(_cq), str(_sc)])
		quit(1)
		return
	run_all()
	print("\n=== Phase 4 Results: %d passed, %d failed ===" % [_pass, _fail])
	for e in _errors:
		print("  FAIL: ", e)
	quit(1 if _fail > 0 else 0)

func run_all() -> void:
	print("--- FoodSystem ---")
	test_food_total_food()
	test_food_granary_capacity_no_granary()
	test_food_granary_capacity_with_granary()
	test_food_tick_consumes_by_ration()
	test_food_tick_starvation_on_zero_ration()
	test_food_tick_shortage_when_low_stock()
	test_food_consumption_order()
	test_food_variety_count()
	test_food_granary_cap_spills_excess()
	test_food_no_tick_mid_day()

	print("--- AleSystem ---")
	test_ale_coverage_no_inn()
	test_ale_coverage_one_inn_two_hovels()
	test_ale_coverage_multiple_inns()
	test_ale_tick_updates_inn_coverage()
	test_ale_tick_consumes_ale_at_day_boundary()
	test_ale_no_worker_inn_not_counted()
	test_ale_no_consumption_mid_day()

	print("--- ReligionSystem ---")
	test_religion_coverage_no_church()
	test_religion_coverage_one_church()
	test_religion_coverage_cathedral()
	test_religion_tick_updates_player()
	test_religion_coverage_to_delta()

	print("--- TaxSystem ---")
	test_tax_zero_rate_no_gold()
	test_tax_positive_rate_earns_gold()
	test_tax_negative_rate_costs_gold()
	test_tax_no_tick_mid_day()
	test_tax_shire_modifier_applied()
	test_tax_gold_floor_zero()

	print("--- DiseaseSystem ---")
	test_disease_no_crowding_low_hovels()
	test_disease_crowding_risk_no_apothecary()
	test_disease_apothecary_coverage_prevents_risk()
	test_disease_active_kills_peasants()
	test_disease_cure_by_high_coverage()
	test_disease_no_tick_mid_day()

	print("--- MarketSystem ---")
	test_market_initialize_prices()
	test_market_buy_price_higher_than_sell()
	test_market_buy_requires_market_building()
	test_market_buy_deducts_gold()
	test_market_buy_adds_resource()
	test_market_buy_fails_no_gold()
	test_market_sell_requires_market_building()
	test_market_sell_earns_gold()
	test_market_sell_deducts_resource()
	test_market_sell_fails_insufficient_stock()
	test_market_price_fluctuation()

	print("--- GameState Phase 4 integration ---")
	test_gs_tax_from_taxis_system()
	test_gs_ale_coverage_updates_on_tick()
	test_gs_religion_coverage_updates_on_tick()
	test_gs_buy_resource_via_command()
	test_gs_sell_resource_via_command()
	test_gs_disease_event_reduces_popularity()

# ============ FoodSystem ============

func _make_player_with_food(apples: int = 50, bread: int = 0, ale: int = 0, pop: int = 10) -> Dictionary:
	return {
		"id": 0, "population": pop,
		"food_ration": 2, "ale_ration": 1,
		"food": {"apples": apples, "cheese": 0, "meat": 0, "bread": bread, "ale": ale},
		"resources": {"wood": 0, "stone": 0, "iron": 0, "pitch": 0, "hops": 0, "wheat": 0, "flour": 0, "leather": 0},
		"buildings": [],
	}

func test_food_total_food() -> void:
	var p = _make_player_with_food(30, 20)
	expect("total food = apples+bread", FoodSystem.get_total_food(p) == 50)

func test_food_granary_capacity_no_granary() -> void:
	var p = _make_player_with_food()
	expect("no granary returns default 200", FoodSystem.get_granary_capacity(p) == 200)

func test_food_granary_capacity_with_granary() -> void:
	var p = _make_player_with_food()
	var gran = BuildingState.create("granary", 0, 5, 5, 1)
	p["buildings"] = [gran]
	expect("granary contributes storage_max", FoodSystem.get_granary_capacity(p) == gran.get("storage_max", 0))

func test_food_tick_consumes_by_ration() -> void:
	var p = _make_player_with_food(1000, 0, 0, 10)
	p["food_ration"] = 2  # Normal ration: 1.0 food/person/day
	var result = FoodSystem.tick(p, 240)  # day 1 boundary
	expect("normal ration consumes 10 food", result.get("food_consumed", 0) == 10)

func test_food_tick_starvation_on_zero_ration() -> void:
	var p = _make_player_with_food(100, 0, 0, 10)
	p["food_ration"] = 0
	var result = FoodSystem.tick(p, 240)
	expect("zero ration sets starving flag", result.get("starving", false) == true)
	expect("zero ration consumes no food", result.get("food_consumed", -1) == 0)

func test_food_tick_shortage_when_low_stock() -> void:
	var p = _make_player_with_food(3, 0, 0, 10)  # Only 3 apples for 10 pop, need 10
	p["food_ration"] = 2
	var result = FoodSystem.tick(p, 240)
	expect("shortage detected when stock low", result.get("food_shortage", 0) > 0)
	expect("starving=true when shortage", result.get("starving", false) == true)

func test_food_consumption_order() -> void:
	# Apples consumed before meat (order: apples, bread, cheese, meat)
	var p = _make_player_with_food(5, 0, 0, 10)
	p["food"]["meat"] = 100
	p["food_ration"] = 2  # consumes 10
	FoodSystem.tick(p, 240)
	# Should consume apples first, then start on bread (which is 0), then cheese (0), then meat
	expect("apples consumed first", p["food"]["apples"] == 0)
	expect("meat only consumed after apples exhausted", p["food"]["meat"] < 100)

func test_food_variety_count() -> void:
	var p = _make_player_with_food(10, 5)
	p["food"]["meat"] = 0
	expect("variety count = 2 (apples+bread)", FoodSystem.get_food_variety_count(p) == 2)

func test_food_granary_cap_spills_excess() -> void:
	var p = _make_player_with_food(500, 0, 0, 10)
	# No granary → default cap = 200, but we have 500 apples
	FoodSystem.apply_granary_cap(p)
	expect("food capped at granary capacity", FoodSystem.get_total_food(p) == 200)

func test_food_no_tick_mid_day() -> void:
	var p = _make_player_with_food(100)
	var result = FoodSystem.tick(p, 120)  # mid-day tick, not boundary
	expect("no consumption mid-day", result.is_empty())

# ============ AleSystem ============

func _make_player_with_ale_buildings(inn_count: int, hovel_count: int, ale: int = 100) -> Dictionary:
	var p = _make_player_with_food(50, 0, ale)
	var buildings: Array = []
	for i in range(inn_count):
		var inn = BuildingState.create("inn", 0, i * 3, 5, i + 10)
		inn["workers"] = 1
		buildings.append(inn)
	for j in range(hovel_count):
		buildings.append(BuildingState.create("hovel", 0, j * 2, 10, j + 20))
	p["buildings"] = buildings
	return p

func test_ale_coverage_no_inn() -> void:
	var p = _make_player_with_ale_buildings(0, 5)
	expect("0 inns = 0.0 coverage", AleSystem.compute_inn_coverage(p) == 0.0)

func test_ale_coverage_one_inn_two_hovels() -> void:
	var p = _make_player_with_ale_buildings(1, 2)
	var cov = AleSystem.compute_inn_coverage(p)
	# 1 inn × 4 / 2 hovels = 2.0, clamped to 1.0
	expect("1 inn 2 hovels = 1.0 coverage", cov == 1.0)

func test_ale_coverage_multiple_inns() -> void:
	var p = _make_player_with_ale_buildings(2, 10)
	var cov = AleSystem.compute_inn_coverage(p)
	# 2 × 4 / 10 = 0.8
	expect("2 inns 10 hovels = 0.8 coverage", absf(cov - 0.8) < 0.01)

func test_ale_tick_updates_inn_coverage() -> void:
	var p = _make_player_with_ale_buildings(1, 2)
	p.erase("inn_coverage")
	AleSystem.tick(p, 100)  # mid-day tick
	expect("tick updates inn_coverage field", p.has("inn_coverage"))
	expect("inn_coverage = 1.0 after tick", absf(p.get("inn_coverage", 0.0) - 1.0) < 0.01)

func test_ale_tick_consumes_ale_at_day_boundary() -> void:
	var p = _make_player_with_ale_buildings(1, 2, 50)
	p["ale_ration"] = 2  # ration mult = 1.0, so 1 inn × 1.0 = 1 ale/day
	AleSystem.tick(p, 240)
	expect("ale consumed at day boundary", p["food"]["ale"] == 49)

func test_ale_no_worker_inn_not_counted() -> void:
	var p = _make_player_with_ale_buildings(1, 2)
	p["buildings"][0]["workers"] = 0  # destaff the inn
	var cov = AleSystem.compute_inn_coverage(p)
	expect("unstaffed inn contributes 0 coverage", cov == 0.0)

func test_ale_no_consumption_mid_day() -> void:
	var p = _make_player_with_ale_buildings(1, 2, 50)
	var result = AleSystem.tick(p, 100)
	expect("no ale consumed mid-day", result.is_empty())

# ============ ReligionSystem ============

func _make_player_with_religion_buildings(church_count: int, cathedral_count: int, hovel_count: int) -> Dictionary:
	var p = _make_player_with_food(50)
	p["tech_unlocks"] = ["monastic_orders"]
	var buildings: Array = []
	for i in range(church_count):
		var b = BuildingState.create("church", 0, i * 3, 5, i + 30)
		buildings.append(b)
	for j in range(cathedral_count):
		var b = BuildingState.create("cathedral", 0, j * 5, 15, j + 40)
		buildings.append(b)
	for k in range(hovel_count):
		buildings.append(BuildingState.create("hovel", 0, k * 2, 20, k + 50))
	p["buildings"] = buildings
	return p

func test_religion_coverage_no_church() -> void:
	var p = _make_player_with_religion_buildings(0, 0, 5)
	expect("no church = 0.0 coverage", ReligionSystem.compute_religion_coverage(p) == 0.0)

func test_religion_coverage_one_church() -> void:
	var p = _make_player_with_religion_buildings(1, 0, 1)
	var cov = ReligionSystem.compute_religion_coverage(p)
	# church radius=12, tiles_per_hovel=4: 12/4 = 3.0, clamped to 1.0 for 1 hovel
	expect("church with 1 hovel = 1.0 coverage", cov == 1.0)

func test_religion_coverage_cathedral() -> void:
	var p = _make_player_with_religion_buildings(0, 1, 6)
	var cov = ReligionSystem.compute_religion_coverage(p)
	# cathedral radius=30, tiles_per_hovel=4: 30/4=7.5, for 6 hovels = 7.5/6=1.25 clamped to 1.0
	expect("cathedral with 6 hovels = 1.0 coverage", cov == 1.0)

func test_religion_tick_updates_player() -> void:
	var p = _make_player_with_religion_buildings(1, 0, 2)
	p.erase("religion_coverage")
	ReligionSystem.tick(p)
	expect("tick sets religion_coverage field", p.has("religion_coverage"))
	expect("religion_coverage > 0 after tick", p.get("religion_coverage", 0.0) > 0.0)

func test_religion_coverage_to_delta() -> void:
	var delta_full = ReligionSystem.coverage_to_popularity_delta(1.0)
	var delta_none = ReligionSystem.coverage_to_popularity_delta(0.0)
	expect("full coverage = MAX_RELIGION_DELTA", absf(delta_full - 10.0) < 0.01)
	expect("zero coverage = 0.0 delta", delta_none == 0.0)

# ============ TaxSystem ============

func _make_tax_player(tax_rate: int = 1, pop: int = 100, gold: int = 0) -> Dictionary:
	return {
		"id": 0, "population": pop, "gold": gold,
		"tax_rate": tax_rate, "shire_id": -1,
	}

func test_tax_zero_rate_no_gold() -> void:
	var p = _make_tax_player(0)
	var result = TaxSystem.tick(p, {}, 240)
	expect("zero tax rate returns empty", result.is_empty())

func test_tax_positive_rate_earns_gold() -> void:
	var p = _make_tax_player(2, 100, 0)  # tax_rate=2, pop=100
	TaxSystem.tick(p, {}, 240)
	# gold_per_peasant = 2 * 0.5 = 1.0, delta = 100
	expect("tax rate 2 earns 100 gold from 100 pop", p["gold"] == 100)

func test_tax_negative_rate_costs_gold() -> void:
	var p = _make_tax_player(-1, 100, 200)  # bribe: rate=-1, starts with 200 gold
	TaxSystem.tick(p, {}, 240)
	# gold_per_peasant = 1 * 0.5 = 0.5, delta = 50, negative
	expect("bribe at rate -1 costs 50 gold from 100 pop", p["gold"] == 150)

func test_tax_no_tick_mid_day() -> void:
	var p = _make_tax_player(1, 100, 0)
	var result = TaxSystem.tick(p, {}, 120)
	expect("no tax mid-day", result.is_empty())

func test_tax_shire_modifier_applied() -> void:
	var p = _make_tax_player(1, 100, 0)
	p["shire_id"] = 0
	var world = {
		"shires": [{"id": 0, "capital_x": 50, "capital_y": 50,
		             "influence_radius": 30, "tax_rate_modifier": 0.5}]
	}
	TaxSystem.tick(p, world, 240)
	# base = 50 gold (rate 1, 100 pop, 0.5/person), modifier +50% → 75
	expect("shire modifier increases tax income", p["gold"] == 75)

func test_tax_gold_floor_zero() -> void:
	var p = _make_tax_player(-3, 100, 10)  # heavy bribe with only 10 gold
	TaxSystem.tick(p, {}, 240)
	expect("gold never goes below 0", p["gold"] >= 0)

# ============ DiseaseSystem ============

func _make_crowded_player(hovel_count: int, apothecary_count: int = 0) -> Dictionary:
	var p = _make_player_with_food(50, 0, 0, 100)
	var buildings: Array = []
	for i in range(hovel_count):
		buildings.append(BuildingState.create("hovel", 0, i * 2, 5, i + 60))
	for j in range(apothecary_count):
		var apo = BuildingState.create("apothecary", 0, j * 3, 15, j + 70)
		apo["workers"] = 1
		buildings.append(apo)
	p["buildings"] = buildings
	return p

func test_disease_no_crowding_low_hovels() -> void:
	var p = _make_crowded_player(3)  # Below threshold of 5
	expect("few hovels not crowding risk", DiseaseSystem.is_crowding_risk(p) == false)

func test_disease_crowding_risk_no_apothecary() -> void:
	var p = _make_crowded_player(8)  # Above threshold, no apothecary
	expect("8 hovels without apothecary = crowding risk", DiseaseSystem.is_crowding_risk(p) == true)

func test_disease_apothecary_coverage_prevents_risk() -> void:
	var p = _make_crowded_player(8, 3)  # 3 apothecaries covering 8 hovels
	expect("3 apothecaries covering 8 hovels not risk", DiseaseSystem.is_crowding_risk(p) == false)

func test_disease_active_kills_peasants() -> void:
	var p = _make_crowded_player(8)
	p["disease_active"] = true
	var pop_before: int = p["population"]
	var rng = RandomNumberGenerator.new()
	DiseaseSystem.tick(p, rng, 240)
	expect("disease kills peasants per day", p["population"] < pop_before)

func test_disease_cure_by_high_coverage() -> void:
	var p = _make_crowded_player(8, 10)  # Very high apothecary coverage
	p["disease_active"] = true
	var rng = RandomNumberGenerator.new()
	DiseaseSystem.tick(p, rng, 240)
	expect("high apothecary coverage cures disease", p.get("disease_active", true) == false)

func test_disease_no_tick_mid_day() -> void:
	var p = _make_crowded_player(8)
	var rng = RandomNumberGenerator.new()
	var events = DiseaseSystem.tick(p, rng, 120)
	expect("no disease tick mid-day", events.is_empty())

# ============ MarketSystem ============

func _make_market_player(gold: int = 500, wood: int = 50) -> Dictionary:
	var p = _make_player_with_food(50, 0, 0, 10)
	p["gold"] = gold
	p["resources"]["wood"] = wood
	# Add a market building
	var market = BuildingState.create("market", 0, 5, 5, 80)
	p["buildings"] = [market]
	return p

func test_market_initialize_prices() -> void:
	var world: Dictionary = {}
	MarketSystem.initialize_prices(world)
	expect("world gets market_prices", world.has("market_prices"))
	expect("wood has a base price", world["market_prices"].get("wood", 0) > 0)

func test_market_buy_price_higher_than_sell() -> void:
	var world: Dictionary = {}
	MarketSystem.initialize_prices(world)
	var buy = MarketSystem.get_buy_price("wood", world)
	var sell = MarketSystem.get_sell_price("wood", world)
	expect("buy price > sell price", buy > sell)

func test_market_buy_requires_market_building() -> void:
	var p = _make_market_player()
	p["buildings"] = []  # No market
	var world: Dictionary = {}
	MarketSystem.initialize_prices(world)
	var result = MarketSystem.buy(p, "wood", 10, world)
	expect("buy without market fails", result["ok"] == false)

func test_market_buy_deducts_gold() -> void:
	var p = _make_market_player(500)
	var world: Dictionary = {}
	MarketSystem.initialize_prices(world)
	var cost = MarketSystem.get_buy_price("wood", world) * 10
	MarketSystem.buy(p, "wood", 10, world)
	expect("buy deducts gold", p["gold"] == 500 - cost)

func test_market_buy_adds_resource() -> void:
	var p = _make_market_player(500, 0)
	var world: Dictionary = {}
	MarketSystem.initialize_prices(world)
	MarketSystem.buy(p, "wood", 10, world)
	expect("buy adds wood to resources", p["resources"]["wood"] == 10)

func test_market_buy_fails_no_gold() -> void:
	var p = _make_market_player(0)
	var world: Dictionary = {}
	MarketSystem.initialize_prices(world)
	var result = MarketSystem.buy(p, "wood", 10, world)
	expect("buy fails with no gold", result["ok"] == false)

func test_market_sell_requires_market_building() -> void:
	var p = _make_market_player()
	p["buildings"] = []  # No market
	var world: Dictionary = {}
	MarketSystem.initialize_prices(world)
	var result = MarketSystem.sell(p, "wood", 10, world)
	expect("sell without market fails", result["ok"] == false)

func test_market_sell_earns_gold() -> void:
	var p = _make_market_player(0, 50)
	var world: Dictionary = {}
	MarketSystem.initialize_prices(world)
	var earned_per = MarketSystem.get_sell_price("wood", world)
	MarketSystem.sell(p, "wood", 10, world)
	expect("sell earns gold", p["gold"] == earned_per * 10)

func test_market_sell_deducts_resource() -> void:
	var p = _make_market_player(0, 50)
	var world: Dictionary = {}
	MarketSystem.initialize_prices(world)
	MarketSystem.sell(p, "wood", 10, world)
	expect("sell deducts wood", p["resources"]["wood"] == 40)

func test_market_sell_fails_insufficient_stock() -> void:
	var p = _make_market_player(0, 5)  # Only 5 wood
	var world: Dictionary = {}
	MarketSystem.initialize_prices(world)
	var result = MarketSystem.sell(p, "wood", 10, world)
	expect("sell fails when insufficient stock", result["ok"] == false)

func test_market_price_fluctuation() -> void:
	var world: Dictionary = {}
	MarketSystem.initialize_prices(world)
	var base_price: int = world["market_prices"]["wood"]
	var rng = RandomNumberGenerator.new()
	# Tick 2400 = 10 game-days, should fluctuate prices
	MarketSystem.tick_prices(world, rng, 2400)
	# Price should still be > 0 but may have changed
	expect("wood price still positive after fluctuation", world["market_prices"]["wood"] > 0)

# ============ GameState Phase 4 integration ============

func _init_gs_player() -> void:
	_gs.players.clear()
	_gs.initialize_player(0, "TestLord", 100, 100)
	_gs._grid = null
	_gs._next_building_id = 1
	_sc.current_tick = 0  # reset so 240 advances always hits the first day boundary
	_cq.clear()
	# Initialize market prices in world
	if not _gs.world.has("market_prices"):
		MarketSystem.initialize_prices(_gs.world)

func test_gs_tax_from_taxis_system() -> void:
	_init_gs_player()
	_gs.players[0]["tax_rate"] = 2
	_gs.players[0]["population"] = 100
	_gs.players[0]["gold"] = 0
	_gs.players[0]["shire_id"] = -1
	# Advance to day boundary (tick 240)
	_sc.set_speed(1)
	for _i in range(240):
		_sc._advance_tick()
	_sc.set_speed(0)
	expect("TaxSystem collects gold at day boundary", _gs.players[0]["gold"] > 0)

func test_gs_ale_coverage_updates_on_tick() -> void:
	_init_gs_player()
	var inn = BuildingState.create("inn", 0, 10, 10, 1)
	inn["workers"] = 1
	var hovel = BuildingState.create("hovel", 0, 12, 12, 2)
	_gs.players[0]["buildings"] = [inn, hovel]
	_sc.set_speed(1)
	_sc._advance_tick()
	_sc.set_speed(0)
	var cov = _gs.players[0].get("inn_coverage", 0.0)
	expect("inn_coverage updated in GameState tick", cov > 0.0)

func test_gs_religion_coverage_updates_on_tick() -> void:
	_init_gs_player()
	var church = BuildingState.create("church", 0, 10, 10, 1)
	var hovel = BuildingState.create("hovel", 0, 12, 12, 2)
	_gs.players[0]["buildings"] = [church, hovel]
	_sc.set_speed(1)
	_sc._advance_tick()
	_sc.set_speed(0)
	var cov = _gs.players[0].get("religion_coverage", 0.0)
	expect("religion_coverage updated in GameState tick", cov > 0.0)

func test_gs_buy_resource_via_command() -> void:
	_init_gs_player()
	_gs.players[0]["gold"] = 500
	var market = BuildingState.create("market", 0, 15, 15, 3)
	_gs.players[0]["buildings"] = [market]
	_gs.world["market_prices"] = {"wood": 3}
	var wood_before = _gs.players[0]["resources"]["wood"]
	_cq.enqueue(CT_BUY_RESOURCE, {"resource": "wood", "amount": 10}, 0)
	_sc.set_speed(1)
	_sc._advance_tick()
	_sc.set_speed(0)
	expect("buy_resource adds wood", _gs.players[0]["resources"]["wood"] > wood_before)
	expect("buy_resource deducts gold", _gs.players[0]["gold"] < 500)

func test_gs_sell_resource_via_command() -> void:
	_init_gs_player()
	_gs.players[0]["resources"]["wood"] = 100
	var market = BuildingState.create("market", 0, 15, 15, 3)
	_gs.players[0]["buildings"] = [market]
	_gs.world["market_prices"] = {"wood": 3}
	_cq.enqueue(CT_SELL_RESOURCE, {"resource": "wood", "amount": 10}, 0)
	_sc.set_speed(1)
	_sc._advance_tick()
	_sc.set_speed(0)
	expect("sell_resource deducts wood", _gs.players[0]["resources"]["wood"] == 90)
	expect("sell_resource earns gold", _gs.players[0]["gold"] > 200)  # Started at 200

func test_gs_disease_event_reduces_popularity() -> void:
	# A/B isolation: disease must leave the realm LESS popular than the SAME realm without it.
	# (Asserting an absolute drop below 80 was non-isolating — the baseline food-variety bonus,
	# which grew when the starting larder gained a bread reserve, can fully offset the −10 disease
	# penalty and net to zero. Comparing diseased vs healthy isolates the disease term regardless
	# of how the surrounding food/tax model is tuned.)
	var healthy_pop: float = _run_day_popularity(false)
	var sick_pop: float = _run_day_popularity(true)
	expect("disease lowers popularity vs an otherwise-identical healthy realm", sick_pop < healthy_pop)

# Runs one game-day for a fixed realm (optionally diseased) and returns its end-of-day popularity.
func _run_day_popularity(diseased: bool) -> float:
	_init_gs_player()
	_gs.players[0]["disease_active"] = diseased
	_gs.players[0]["popularity"] = 80.0
	_gs.players[0]["tax_rate"] = 0
	_gs.players[0]["food_ration"] = 2
	_gs.players[0]["ale_ration"] = 1
	_gs.players[0]["food"]["apples"] = 9999
	_gs.players[0]["inn_coverage"] = 0.0
	_gs.players[0]["religion_coverage"] = 0.0
	_gs.players[0]["shire_id"] = -1
	_sc.set_speed(1)
	for _i in range(240):
		_sc._advance_tick()
	_sc.set_speed(0)
	return _gs.players[0].get("popularity", 80.0)

# ============ Assertion helpers ============

func expect(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  PASS: ", label)
	else:
		_fail += 1
		_errors.append(label)
		print("  FAIL: ", label)
