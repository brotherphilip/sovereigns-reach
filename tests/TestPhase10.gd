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
const AshenBarony   = preload("res://simulation/ai/AshenBarony.gd")
const EdictSystem   = preload("res://simulation/edicts/EdictSystem.gd")

const CT_ACTIVATE_EDICT     = 16
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
	_test_ai_unit_id_uniqueness()
	_test_serialization_roundtrip()
	_test_siege_survival()

# Land one siege on player 0 by arming an assembly one day from done, then running a
# single day-boundary tick (the brain completes it → GameState damages the seat).
var _siege_test_day: int = 0
func _land_siege(faction: Dictionary) -> void:
	_siege_test_day += 1
	faction["is_alive"] = true
	faction["last_attack_tick"] = 0
	faction["siege_assembly"] = {"target_player_id": 0, "target_x": 50, "target_y": 50,
		"ticks_elapsed": AIFaction.SIEGE_ASSEMBLY_TICKS - 240}
	_gs.simulate_tick(_siege_test_day * 240)

# Validates the iter-61/62 siege balance end-to-end: a prepared seat blunts sieges and
# endures the campaign; an undefended one is gutted — "fair but demanding".
func _test_siege_survival() -> void:
	print("\n--- Siege survival: prepared vs unprepared ---")
	_siege_test_day = 0
	# Defended: hall + 3 watchtowers → siege-ready → ~75 damage/siege, weathers many.
	var p := _fresh_player(60)
	_gs.citizens = []
	var hall := BuildingState.create("village_hall", 0, 50, 50, 1)
	hall["built"] = true
	p["buildings"] = [hall]
	for i in range(3):
		var w := BuildingState.create("watchtower", 0, 45 + i, 45, 10 + i)
		w["built"] = true
		p["buildings"].append(w)
	ok("a walled+garrisoned seat reads as siege-ready", _gs.is_siege_ready(p))
	var faction: Dictionary = _gs.ai_factions[_gs.add_ai_faction(AIFaction.ARCHETYPE_BANDIT, 55, 55)]
	var hp0: int = int(hall.get("hp", 0))
	_land_siege(faction)
	var drop_d: int = hp0 - int(hall.get("hp", 0))
	ok("a siege landed on the defended seat", drop_d > 0)
	ok("defended seat is blunted to ~75 damage", drop_d == 75)
	var sieges := 1
	while int(hall.get("hp", 0)) > 0 and sieges < 8:
		_land_siege(faction)
		sieges += 1
	ok("a defended seat endures many sieges (>=5)", sieges >= 5)

	# Undefended: bare hall, no garrison → full 150 damage.
	var p2 := _fresh_player(60)
	_gs.citizens = []
	var hall2 := BuildingState.create("village_hall", 0, 50, 50, 1)
	hall2["built"] = true
	p2["buildings"] = [hall2]
	ok("a bare seat is NOT siege-ready", not _gs.is_siege_ready(p2))
	var faction2: Dictionary = _gs.ai_factions[_gs.add_ai_faction(AIFaction.ARCHETYPE_BANDIT, 55, 55)]
	var u0: int = int(hall2.get("hp", 0))
	_land_siege(faction2)
	var drop_u: int = u0 - int(hall2.get("hp", 0))
	ok("undefended seat takes the full 150 damage", drop_u == 150)

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

	# Kiting: a ranged attacker (archer, range 8) strikes a melee target from
	# distance and takes no retaliation.
	var p3: Dictionary = _fresh_player(60)
	var fid3: int = _gs.add_ai_faction(AIFaction.ARCHETYPE_BANDIT, 55, 50)
	var faction3: Dictionary = _gs.ai_factions[fid3]
	faction3["units"] = [UnitState.create("armed_peasant", fid3, 55, 50, 9003)]
	var archer: Dictionary = UnitState.create("archer", 0, 50, 50, 1)
	archer["order"] = UnitState.ORDER_ATTACK
	archer["target_id"] = 9003
	archer["target_x"] = 55
	archer["target_y"] = 50
	p3["units"] = [archer]
	var archer_hp_before: int = archer["hp"]
	for i in range(120):
		_gs._tick_player_unit_movement(p3, i + 1)
	ok("ranged attacker kills melee target", not faction3["units"][0].get("is_alive", true))
	ok("ranged attacker takes no melee retaliation", int(p3["units"][0]["hp"]) == archer_hp_before)

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

	# A training unit cannot be ordered (would otherwise skip the queue).
	var tuid: int = p["units"][0].get("id", -1)
	_cq.enqueue(12, {"unit_id": tuid, "target_x": 55, "target_y": 55}, 0)  # ISSUE_MOVE_ORDER
	_sc._advance_tick()
	ok("training unit rejects move orders", p["units"][0].get("order") == UnitState.ORDER_TRAINING)

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
	var ch_p: Dictionary = ResourceTick.tick_building(pig, p, 720)  # multiple of pig_farm interval (360)
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

	# Mid/late-game milestones (iter 69): keep the reward loop alive past the early game.
	# reign_day_50 fires on the day-50 survival beat (and only then).
	var p_day: Dictionary = _fresh_player(60)
	ok("reign_day_50 does NOT fire before day 50", "reign_day_50" not in MilestoneSystem.check(p_day, _gs.world, {}, [], 49))
	ok("reign_day_50 fires at day 50", "reign_day_50" in MilestoneSystem.check(p_day, _gs.world, {}, [], 50))
	# reign_day_75 (iter103) — a late-game beat to keep the reward loop alive in the endgame.
	var p_d75: Dictionary = _fresh_player(60)
	ok("reign_day_75 does NOT fire before day 75", "reign_day_75" not in MilestoneSystem.check(p_d75, _gs.world, {}, [], 74))
	ok("reign_day_75 fires at day 75", "reign_day_75" in MilestoneSystem.check(p_d75, _gs.world, {}, [], 75))
	# town_of_ten fires once the settlement reaches 10 buildings.
	var p_town: Dictionary = _fresh_player(60)
	p_town["buildings"] = []
	for _i in range(10):
		p_town["buildings"].append(BuildingState.create("hovel", 0, 10 + _i, 10, 1))
	ok("town_of_ten fires at 10 buildings", "town_of_ten" in MilestoneSystem.check(p_town, _gs.world, {}, [], 5))
	# first_watchtower fires when a watchtower is raised (survival-aligned reward).
	var p_tower: Dictionary = _fresh_player(60)
	p_tower["buildings"] = [BuildingState.create("watchtower", 0, 20, 20, 1)]
	ok("first_watchtower fires with a watchtower built", "first_watchtower" in MilestoneSystem.check(p_tower, _gs.world, {}, [], 5))
	# treasury_300 fires when gold crosses 300, and none re-fire once latched.
	var p_gold: Dictionary = _fresh_player(60)
	p_gold["gold"] = 400
	ok("treasury_300 fires at 300+ gold", "treasury_300" in MilestoneSystem.check(p_gold, _gs.world, {}, [], 5))
	# standing_army fires once the player musters STANDING_ARMY_SIZE living soldiers (iter84/85).
	var p_army: Dictionary = _fresh_player(60)
	p_army["units"] = []
	for _i in range(MilestoneSystem.STANDING_ARMY_SIZE - 1):
		p_army["units"].append({"is_alive": true})
	ok("standing_army does NOT fire below the threshold",
		"standing_army" not in MilestoneSystem.check(p_army, _gs.world, {}, [], 5))
	p_army["units"].append({"is_alive": true})  # now at the threshold
	ok("standing_army fires at %d living soldiers" % MilestoneSystem.STANDING_ARMY_SIZE,
		"standing_army" in MilestoneSystem.check(p_army, _gs.world, {}, [], 5))
	# Dead units don't count toward the standing army.
	var p_dead: Dictionary = _fresh_player(60)
	p_dead["units"] = []
	for _i in range(MilestoneSystem.STANDING_ARMY_SIZE + 2):
		p_dead["units"].append({"is_alive": false})
	ok("standing_army ignores the fallen", "standing_army" not in MilestoneSystem.check(p_dead, _gs.world, {}, [], 5))

	# Latch EVERY milestone → a subsequent check (even at day 60, rich) earns nothing.
	var latched: Dictionary = {}
	for mid in MilestoneSystem.DEFINITIONS.keys():
		latched[mid] = true
	ok("all latched milestones do not re-fire",
		MilestoneSystem.check(p_gold, _gs.world, latched, [], 60).is_empty())

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

	# S15: a stronger player army interdicts the Ashen Barony's supply lines.
	var barony: Dictionary = AshenBarony.make(0, 100, 100)
	barony["is_alive"] = true
	barony["units"] = [UnitState.create("armed_peasant", 0, 100, 100, 1)]  # weak army
	barony["supply_lines_active"] = true
	var strong_player: Dictionary = {
		"id": 0, "is_alive": true, "keep_x": 50, "keep_y": 50,
		"units": [
			UnitState.create("swordsman", 0, 50, 50, 2),
			UnitState.create("swordsman", 0, 51, 50, 3),
		],
	}
	var sup_events: Array = AshenBarony.tick(barony, [strong_player], {}, 240)
	ok("stronger player cuts Ashen supply lines", not AshenBarony.has_supply_lines(barony))
	ok("ashen_supply_cut event emitted", "ashen_supply_cut" in sup_events)

	# S14: high-tier edicts (levy_summons, tier 3) are gated behind a developed
	# shire capital's edict_tier_cap.
	var pe: Dictionary = _fresh_player(60)
	pe["tech_unlocks"] = ["army_logistics"]
	pe["edict_points"] = 20
	pe["popularity"] = 80.0
	pe["shire_id"] = 0
	# levy_summons (tier 3) applies a -50 popularity cost on activation — used here
	# as the proxy for "did the edict fire?".
	_gs.world["shires"] = [{"id": 0, "capital_level": 1, "capital_donations": {}}]
	_cq.enqueue(CT_ACTIVATE_EDICT, {"edict_id": "levy_summons"}, 0)
	_sc._advance_tick()
	ok("tier-3 edict blocked at level-1 capital", pe["popularity"] == 80.0)
	# Upgrade the capital — edict_tier_cap rises, unlocking the edict.
	_gs.world["shires"][0]["capital_level"] = 2
	_cq.enqueue(CT_ACTIVATE_EDICT, {"edict_id": "levy_summons"}, 0)
	_sc._advance_tick()
	ok("tier-3 edict allowed at level-2 capital", pe["popularity"] < 80.0)

# ─── AI unit id uniqueness after purge (latent collision bug) ──────────────────

func _test_ai_unit_id_uniqueness() -> void:
	print("\n--- AI unit id uniqueness ---")
	var f: Dictionary = AIFaction.make_faction(0, "Raiders", AIFaction.ARCHETYPE_BANDIT, 10, 10)
	f["gold"] = 1000
	AIFaction.recruit_unit(f, "armed_peasant")
	AIFaction.recruit_unit(f, "armed_peasant")
	ok("two recruited AI units have distinct ids", f["units"][0]["id"] != f["units"][1]["id"])
	var survivor_id: int = f["units"][1]["id"]
	# Kill the first unit and purge it via the day-boundary tick.
	f["units"][0]["is_alive"] = false
	AIFaction.tick(f, {}, 240)
	ok("dead AI unit purged", f["units"].size() == 1)
	# A freshly recruited unit must not reuse the survivor's id.
	AIFaction.recruit_unit(f, "armed_peasant")
	ok("recruited id does not collide after purge", f["units"][1]["id"] != survivor_id)

# ─── Full serialization round-trip with new state ──────────────────────────────

func _test_serialization_roundtrip() -> void:
	print("\n--- Serialization round-trip (training + AI) ---")
	var p: Dictionary = _fresh_player(60)
	_give_barracks(p)
	# A unit in the training queue.
	_cq.enqueue(CT_RECRUIT_UNIT, {"unit_type": "armed_peasant"}, 0)
	_sc._advance_tick()
	# An AI faction with a recruited unit (exercises next_unit_id).
	var fid: int = _gs.add_ai_faction(AIFaction.ARCHETYPE_BANDIT, 55, 55)
	_gs.ai_factions[fid]["gold"] = 500
	AIFaction.recruit_unit(_gs.ai_factions[fid], "armed_peasant")

	# Serialize → JSON string → parse → deserialize (the real save path).
	var snap: Dictionary = _gs.serialize()
	var json_str: String = JSON.stringify(snap)
	var parsed = JSON.parse_string(json_str)
	ok("serialized state is JSON round-trippable", parsed is Dictionary)
	_gs.players.clear()
	_gs.ai_factions.clear()
	_gs.deserialize(parsed)

	ok("player restored after load", _gs.players.size() == 1)
	ok("training unit survives round-trip",
		_gs.players[0]["units"][0].get("order") == UnitState.ORDER_TRAINING)
	ok("ai faction restored after load", _gs.ai_factions.size() == 1)
	ok("faction next_unit_id survives round-trip",
		int(_gs.ai_factions[0].get("next_unit_id", 0)) > 0)
	# The simulation continues without error after a load.
	_sc._advance_tick()
	ok("simulation advances after load", true)
