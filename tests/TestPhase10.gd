extends SceneTree
# Phase 10 test suite — Simulation audit fixes (S1–S4 and related).
# Run: godot --headless --script tests/TestPhase10.gd
# Pattern: integer constants for CommandType to avoid compile-time autoload resolution.

const UnitState     = preload("res://simulation/units/UnitState.gd")
const UnitRegistry  = preload("res://simulation/units/UnitRegistry.gd")
const WorldGrid     = preload("res://simulation/world/WorldGrid.gd")
const AIFaction     = preload("res://simulation/ai/AIFaction.gd")
const BuildingState = preload("res://simulation/buildings/BuildingState.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const ResourceTick  = preload("res://simulation/economy/ResourceTick.gd")
const ShireMap      = preload("res://simulation/world/ShireMap.gd")
const PlacementValidator = preload("res://simulation/buildings/PlacementValidator.gd")
const MilestoneSystem = preload("res://simulation/core/MilestoneSystem.gd")
const SaveManager   = preload("res://simulation/persistence/SaveManager.gd")

const CT_DIPLOMACY_RESPONSE = 26

const CT_RECRUIT_UNIT       = 11
const CT_ISSUE_ATTACK_ORDER = 13

var _gs: Node = null
var _cq: Node = null
var _sc: Node = null
var _pass: int = 0
var _fail: int = 0

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_cq = root.get_node_or_null("CommandQueue")
	_sc = root.get_node_or_null("SimulationClock")
	if _gs == null or _cq == null or _sc == null:
		print("FATAL: Autoloads not found")
		quit(1)
		return
	_run_all()
	print("Phase 10 Results: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _run_all() -> void:
	_test_attack_orders()
	_test_training_queue()
	_test_armor_production()
	_test_population_growth()
	_test_medium_fixes()
	_test_keep_diplomacy_save()

func ok(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  PASS: " + label)
	else:
		_fail += 1
		print("  FAIL: " + label)

func _fresh_player(grid_size: int = 60) -> Dictionary:
	_gs.players.clear()
	_gs.ai_factions.clear()
	_gs._grid = WorldGrid.new(grid_size, grid_size)
	_gs._next_building_id = 1
	_gs._next_unit_id = 1
	_sc.current_tick = 0
	_cq.clear()
	_gs.initialize_player(0, "TestLord", 50, 50)
	return _gs.players[0]

# ─── S1: Attack orders ────────────────────────────────────────────────────────

func _test_attack_orders() -> void:
	print("\n--- S1: Attack Orders ---")

	# Adjacent strike: a swordsman next to a weak enemy kills it via attack order.
	var p: Dictionary = _fresh_player(60)
	var fid: int = _gs.add_ai_faction(AIFaction.ARCHETYPE_BANDIT, 55, 50)
	var faction: Dictionary = _gs.ai_factions[fid]
	var target: Dictionary = UnitState.create("armed_peasant", fid, 51, 50, 9001)
	faction["units"] = [target]
	var atk: Dictionary = UnitState.create("swordsman", 0, 50, 50, 1)
	p["units"] = [atk]
	p["total_kills"] = 0

	_cq.enqueue(CT_ISSUE_ATTACK_ORDER,
		{"unit_id": 1, "target_x": 51, "target_y": 50, "target_id": 9001}, 0)
	_sc._advance_tick()
	ok("attack order sets ORDER_ATTACK", p["units"][0].get("order") == UnitState.ORDER_ATTACK)

	for _i in range(120):
		_sc._advance_tick()
	ok("attack order kills adjacent target", not faction["units"][0].get("is_alive", true))
	ok("attack order increments total_kills", int(p.get("total_kills", 0)) >= 1)
	ok("attacker reverts to IDLE after kill", p["units"][0].get("order") == UnitState.ORDER_IDLE)

	# Chase: an out-of-range attacker steps toward its target.
	var p2: Dictionary = _fresh_player(60)
	var fid2: int = _gs.add_ai_faction(AIFaction.ARCHETYPE_BANDIT, 55, 50)
	var faction2: Dictionary = _gs.ai_factions[fid2]
	faction2["units"] = [UnitState.create("armed_peasant", fid2, 53, 50, 9002)]
	var chaser: Dictionary = UnitState.create("swordsman", 0, 50, 50, 1)
	chaser["order"] = UnitState.ORDER_ATTACK
	chaser["target_id"] = 9002
	chaser["target_x"] = 53
	chaser["target_y"] = 50
	p2["units"] = [chaser]
	var start_x: int = chaser["pos_x"]
	# swordsman speed 3 → one step every 80 ticks; tick 80 triggers a step.
	_gs._tick_player_unit_movement(p2, 80)
	ok("out-of-range attacker steps toward target", int(p2["units"][0]["pos_x"]) > start_x)

# ─── S2: Training queue ───────────────────────────────────────────────────────

func _give_barracks(p: Dictionary) -> void:
	p["buildings"] = [BuildingState.create("barracks", 0, 40, 40, 1)]
	p["gold"] = 500

func _test_training_queue() -> void:
	print("\n--- S2: Training Queue ---")

	# Recruited unit with train_ticks > 0 enters ORDER_TRAINING, not deployable.
	var p: Dictionary = _fresh_player(60)
	_give_barracks(p)
	_cq.enqueue(CT_RECRUIT_UNIT, {"unit_type": "armed_peasant"}, 0)
	_sc._advance_tick()
	ok("recruited unit added to army", p.get("units", []).size() == 1)
	ok("recruited unit is in training", p["units"][0].get("order") == UnitState.ORDER_TRAINING)
	ok("training unit is not deployable", not UnitState.is_deployable(p["units"][0]))

	# After train_ticks (60) the unit graduates to IDLE and becomes deployable.
	for _i in range(60):
		_sc._advance_tick()
	ok("unit graduates after train_ticks", p["units"][0].get("order") == UnitState.ORDER_IDLE)
	ok("graduated unit is deployable", UnitState.is_deployable(p["units"][0]))

	# training_rate_bonus (training_speed tech) shortens the required time.
	var p2: Dictionary = _fresh_player(60)
	_give_barracks(p2)
	p2["tech_unlocks"] = ["unit_unlocks", "training_speed"]  # grants training_rate_bonus 0.3
	_cq.enqueue(CT_RECRUIT_UNIT, {"unit_type": "armed_peasant"}, 0)
	_sc._advance_tick()
	# required = round(60 / 1.3) = 46 ticks; advance 46 more (47 total) → graduated.
	for _i in range(46):
		_sc._advance_tick()
	ok("training_rate_bonus speeds training", p2["units"][0].get("order") == UnitState.ORDER_IDLE)

	# Peasants (train_ticks 0) are available immediately (no training queue).
	var p3: Dictionary = _fresh_player(60)
	p3["buildings"] = [BuildingState.create("village_hall", 0, 40, 40, 1)]
	p3["gold"] = 500
	_cq.enqueue(CT_RECRUIT_UNIT, {"unit_type": "peasant"}, 0)
	_sc._advance_tick()
	ok("peasant deploys instantly", p3["units"].size() == 1 and UnitState.is_deployable(p3["units"][0]))

# ─── S3: Armor & crossbow production ──────────────────────────────────────────

func _test_armor_production() -> void:
	print("\n--- S3: Armor & Crossbow Production ---")

	# Registry has the new producers.
	ok("armorer registered", BuildingRegistry.is_valid_type("armorer"))
	ok("tannery registered", BuildingRegistry.is_valid_type("tannery"))
	ok("crossbow_workshop registered", BuildingRegistry.is_valid_type("crossbow_workshop"))

	var p: Dictionary = _fresh_player(60)
	p["resources"]["iron"] = 20
	p["resources"]["leather"] = 5
	p["resources"]["wood"] = 20

	var armorer: Dictionary = {"type": "armorer", "workers": 1, "is_active": true}
	var ch_a: Dictionary = ResourceTick.tick_building(armorer, p, 360)
	ok("armorer produces plate_armor", int(ch_a.get("plate_armor", 0)) == 1)
	ok("armorer consumes iron", int(ch_a.get("iron", 0)) == -2)

	var tannery: Dictionary = {"type": "tannery", "workers": 1, "is_active": true}
	var ch_t: Dictionary = ResourceTick.tick_building(tannery, p, 240)
	ok("tannery produces leather_armor", int(ch_t.get("leather_armor", 0)) == 1)
	ok("tannery consumes leather", int(ch_t.get("leather", 0)) == -1)

	var xbow: Dictionary = {"type": "crossbow_workshop", "workers": 1, "is_active": true}
	var ch_x: Dictionary = ResourceTick.tick_building(xbow, p, 300)
	ok("crossbow_workshop produces crossbows", int(ch_x.get("crossbows", 0)) == 1)

	var pig: Dictionary = {"type": "pig_farm", "workers": 1, "is_active": true, "terrain_yield": 1.0}
	var ch_p: Dictionary = ResourceTick.tick_building(pig, p, 600)
	ok("pig_farm yields leather (domestic source)", int(ch_p.get("leather", 0)) >= 1)

	# End-to-end: produced armory items are deposited into the armory.
	ResourceTick.apply_changes(p, ch_a)
	ok("plate_armor deposited into armory", int(p["armory"].get("plate_armor", 0)) >= 1)

# ─── S4: Population growth ────────────────────────────────────────────────────

func _test_population_growth() -> void:
	print("\n--- S4: Population Growth ---")

	var p: Dictionary = _fresh_player(60)
	p["buildings"] = [
		BuildingState.create("village_hall", 0, 40, 40, 1),
		BuildingState.create("hovel", 0, 45, 45, 2),
	]
	ok("population cap = hall baseline + hovel", _gs._get_population_cap(p) == 58)

	p["population"] = 50
	p["popularity"] = 80.0
	p["food"]["apples"] = 100
	_gs._tick_population_growth(p)
	ok("content, fed village grows", int(p["population"]) > 50)

	p["population"] = 58
	_gs._tick_population_growth(p)
	ok("growth is capped at housing", int(p["population"]) == 58)

	# Unhappy village does not grow.
	var p2: Dictionary = _fresh_player(60)
	p2["buildings"] = [
		BuildingState.create("village_hall", 0, 40, 40, 1),
		BuildingState.create("hovel", 0, 45, 45, 2),
	]
	p2["population"] = 40
	p2["popularity"] = 30.0
	p2["food"]["apples"] = 100
	_gs._tick_population_growth(p2)
	ok("unhappy village does not grow", int(p2["population"]) == 40)

	# Starving village attracts no newcomers (growth-only; no decline here).
	var p3: Dictionary = _fresh_player(60)
	p3["buildings"] = [
		BuildingState.create("village_hall", 0, 40, 40, 1),
		BuildingState.create("hovel", 0, 45, 45, 2),
	]
	p3["population"] = 30
	p3["popularity"] = 60.0
	p3["food"] = {"apples": 0, "bread": 0, "cheese": 0, "meat": 0, "ale": 0}
	_gs._tick_population_growth(p3)
	ok("starving village does not grow", int(p3["population"]) == 30)

# ─── S5/S7/S8/S11/S13 + dead modifiers ────────────────────────────────────────

func _test_medium_fixes() -> void:
	print("\n--- S5/S7/S8/S11/S13 + dead modifiers ---")

	# S8: three_shires milestone fires when the player owns 3+ shires.
	var p_ms: Dictionary = _fresh_player(60)
	p_ms["shire_ids"] = [0, 1, 2]
	var earned: Array = MilestoneSystem.check(p_ms, _gs.world, {}, [])
	ok("three_shires milestone fires at 3 shires", "three_shires" in earned)
	var earned2: Array = MilestoneSystem.check(p_ms, _gs.world, {"three_shires": true}, [])
	ok("three_shires does not re-fire", "three_shires" not in earned2)

	# S11: a second village_hall (unique) is rejected by the placement validator.
	var p_uniq: Dictionary = _fresh_player(60)
	p_uniq["buildings"] = [BuildingState.create("village_hall", 0, 40, 40, 1)]
	p_uniq["shire_id"] = -1  # skip border check
	var res_uniq: Dictionary = PlacementValidator.validate("village_hall", 30, 30, _gs._grid, p_uniq, _gs.world)
	ok("second village_hall rejected (unique)", not res_uniq["ok"])
	ok("rejection code is UNIQUE_EXISTS", res_uniq.get("code") == PlacementValidator.ValidationResult.UNIQUE_EXISTS)

	# S7: only one Captain (hero) may be recruited.
	var p_cap: Dictionary = _fresh_player(60)
	p_cap["buildings"] = [BuildingState.create("barracks", 0, 40, 40, 1)]
	p_cap["tech_unlocks"] = ["advanced_masonry"]
	p_cap["gold"] = 1000
	p_cap["armory"] = {"swords": 4, "plate_armor": 4, "bows": 0, "crossbows": 0, "pikes": 0, "leather_armor": 0}
	_cq.enqueue(CT_RECRUIT_UNIT, {"unit_type": "captain"}, 0)
	_sc._advance_tick()
	var captains_after_first: int = p_cap.get("units", []).size()
	_cq.enqueue(CT_RECRUIT_UNIT, {"unit_type": "captain"}, 0)
	_sc._advance_tick()
	ok("first captain recruited", captains_after_first == 1)
	ok("second captain rejected (hero unique)", p_cap.get("units", []).size() == 1)

	# S5: desertion removes a soldier and a peasant at desertion-risk popularity.
	var p_des: Dictionary = _fresh_player(60)
	p_des["popularity"] = 15.0
	p_des["population"] = 30
	p_des["units"] = [UnitState.create("swordsman", 0, 50, 50, 1)]
	var pop_before: int = p_des["population"]
	_gs._apply_desertion(p_des)
	ok("desertion removes a soldier", p_des["units"].size() == 0)
	ok("desertion costs a peasant", int(p_des["population"]) < pop_before)

	# S13: shire layout varies with the world seed (no longer hardcoded to 42).
	var sm_a := ShireMap.new()
	sm_a.generate_default(200, 200, 8, 111)
	var sm_b := ShireMap.new()
	sm_b.generate_default(200, 200, 8, 222)
	var differs: bool = false
	for i in range(sm_a.shires.size()):
		if sm_a.shires[i].get("capital_x") != sm_b.shires[i].get("capital_x"):
			differs = true
			break
	ok("shire capitals vary with seed", differs)

	# cart_capacity_bonus (transport_logistics) now boosts trading-post income.
	var p_cart: Dictionary = _fresh_player(60)
	p_cart["tech_unlocks"] = ["resource_unlocks", "transport_logistics"]
	var post: Dictionary = {"type": "trading_post", "workers": 1, "is_active": true}
	var ch_cart: Dictionary = ResourceTick.tick_building(post, p_cart, 480)
	ok("cart_capacity_bonus lifts trade income above base 3", int(ch_cart.get("gold", 0)) > 3)

# ─── S6 (keep) / S9 (diplomacy command) / S16 (save migration) ─────────────────

func _test_keep_diplomacy_save() -> void:
	print("\n--- S6 keep / S9 diplomacy / S16 save migration ---")

	# S6: the keep is now a registered, unique, fortified building.
	ok("keep registered", BuildingRegistry.is_valid_type("keep"))
	var keep_defn: Dictionary = BuildingRegistry.lookup("keep")
	ok("keep is fortified (hp >= 1000)", int(keep_defn.get("hp", 0)) >= 1000)
	ok("keep is unique", keep_defn.get("unique", false) == true)

	# S9: a tribute response routed through the command pipeline pays the demand.
	var p: Dictionary = _fresh_player(60)
	p["resources"]["iron"] = 100
	var fid: int = _gs.add_ai_faction(AIFaction.ARCHETYPE_ASHEN_BARONY, 55, 55)
	var faction: Dictionary = _gs.ai_factions[fid]
	faction["tribute_demands"] = [{"player_id": 0, "resource": "iron", "amount": 20, "fulfilled": false}]
	_cq.enqueue(CT_DIPLOMACY_RESPONSE,
		{"faction_id": fid, "accept": true, "demands": {"iron": 20}}, 0)
	_sc._advance_tick()
	ok("diplomacy accept pays tribute via command", int(p["resources"]["iron"]) == 80)
	ok("diplomacy accept marks demand fulfilled", faction["tribute_demands"][0].get("fulfilled", false))

	# Refuse imposes an embargo through the command pipeline.
	var p2: Dictionary = _fresh_player(60)
	var fid2: int = _gs.add_ai_faction(AIFaction.ARCHETYPE_ASHEN_BARONY, 55, 55)
	var faction2: Dictionary = _gs.ai_factions[fid2]
	faction2["tribute_demands"] = [{"player_id": 0, "resource": "iron", "amount": 20, "fulfilled": false}]
	_cq.enqueue(CT_DIPLOMACY_RESPONSE, {"faction_id": fid2, "accept": false}, 0)
	_sc._advance_tick()
	ok("diplomacy refuse embargoes the player", 0 in faction2.get("embargoed_players", []))

	# S16: a pre-Phase-6 (v1) save without unit/armory fields migrates and loads.
	var path: String = "user://test_v1_migration.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"save_version": 1,
		"state": {"players": [{"id": 0, "gold": 200, "population": 50}], },
	}))
	f.close()
	var loaded: Dictionary = SaveManager.load_save(path)
	DirAccess.remove_absolute(path)
	ok("v1 save migrates (non-empty)", not loaded.is_empty())
	ok("v1 migration backfills units array", loaded["players"][0].has("units"))
	ok("v1 migration backfills armory", loaded["players"][0].has("armory"))
	ok("v1 migration backfills ai_factions", loaded.has("ai_factions"))
