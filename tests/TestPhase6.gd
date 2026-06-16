extends SceneTree
# Phase 6 test suite — AI & Entities
# Run: godot --headless --script tests/TestPhase6.gd
# Pattern: integer constants for CommandType to avoid compile-time autoload resolution.

const UnitRegistry  = preload("res://simulation/units/UnitRegistry.gd")
const UnitState     = preload("res://simulation/units/UnitState.gd")
const Pathfinder    = preload("res://simulation/pathfinding/Pathfinder.gd")
const WorldGrid     = preload("res://simulation/world/WorldGrid.gd")
const CombatSystem  = preload("res://simulation/combat/CombatSystem.gd")
const AIFaction     = preload("res://simulation/ai/AIFaction.gd")
const BanditKing    = preload("res://simulation/ai/BanditKing.gd")
const MerchantPrince = preload("res://simulation/ai/MerchantPrince.gd")
const Ironhand      = preload("res://simulation/ai/Ironhand.gd")
const AshenBarony   = preload("res://simulation/ai/AshenBarony.gd")
const DiplomacySystem = preload("res://simulation/ai/DiplomacySystem.gd")

# CommandType integer constants (avoids compile-time autoload resolution)
const CT_RECRUIT_UNIT      = 11
const CT_ISSUE_MOVE_ORDER  = 12
const CT_ISSUE_ATTACK_ORDER = 13
const CT_DISBAND_UNIT      = 15

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
	print("Phase 6 Results: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _run_all() -> void:
	_test_unit_registry()
	_test_unit_state()
	_test_pathfinder()
	_test_combat_system()
	_test_ai_factions()
	_test_gamestate_integration()

# ─── helpers ────────────────────────────────────────────────────────────────

func ok(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  PASS: " + label)
	else:
		_fail += 1
		print("  FAIL: " + label)

func _fresh_player() -> Dictionary:
	_gs.players.clear()
	_gs._grid = null
	_gs._next_building_id = 1
	_gs._next_unit_id = 1
	_sc.current_tick = 0
	_cq.clear()
	_gs.initialize_player(0, "TestLord", 50, 50)
	return _gs.players[0]

# ─── UnitRegistry tests (15) ────────────────────────────────────────────────

func _test_unit_registry() -> void:
	print("\n--- UnitRegistry ---")

	# 1. All expected unit types exist
	var required_types := ["peasant","scout","monk","merchant","settler",
		"armed_peasant","archer","ladderman","tunneler","militia",
		"crossbowman","pikeman","swordsman","captain","halberdier",
		"battering_ram","catapult","trebuchet","siege_tower","mantlet"]
	var all_exist := true
	for t in required_types:
		if not UnitRegistry.is_valid(t):
			all_exist = false
	ok("all 20 unit types defined", all_exist)

	# 2. armed_peasant: no armor, melee
	var ap := UnitRegistry.lookup("armed_peasant")
	ok("armed_peasant armor_type=none", ap.get("armor_type") == UnitRegistry.ARMOR_NONE)
	ok("armed_peasant attack_type=melee", ap.get("attack_type") == UnitRegistry.ATTACK_MELEE)

	# 3. archer: ranged pierce
	var archer := UnitRegistry.lookup("archer")
	ok("archer range>0", archer.get("range", 0) > 0)
	ok("archer attack_type=pierce", archer.get("attack_type") == UnitRegistry.ATTACK_PIERCE)

	# 4. swordsman: heavy armor, high attack
	var sw := UnitRegistry.lookup("swordsman")
	ok("swordsman armor_type=heavy", sw.get("armor_type") == UnitRegistry.ARMOR_HEAVY)
	ok("swordsman attack > 15", sw.get("attack", 0) > 15)

	# 5. battering_ram: siege attack, heavy armor, immune_to_arrows
	var ram := UnitRegistry.lookup("battering_ram")
	ok("battering_ram attack_type=siege", ram.get("attack_type") == UnitRegistry.ATTACK_SIEGE)
	ok("battering_ram immune_to_arrows", ram.get("immune_to_arrows", false) == true)
	ok("battering_ram target_priority=gatehouse", ram.get("target_priority", "") == "gatehouse")

	# 6. captain: morale_buff > 0, is_hero
	var cap := UnitRegistry.lookup("captain")
	ok("captain morale_buff>0", cap.get("morale_buff", 0) > 0)
	ok("captain is_hero=true", cap.get("is_hero", false) == true)

	# 7. trebuchet: target_priority=great_tower
	var treb := UnitRegistry.lookup("trebuchet")
	ok("trebuchet target_priority=great_tower", treb.get("target_priority", "") == "great_tower")

	# 8. halberdier: anti_armor_bonus present
	var halb := UnitRegistry.lookup("halberdier")
	ok("halberdier has anti_armor_bonus", halb.get("anti_armor_bonus", 0.0) > 0.0)

# ─── UnitState tests (12) ───────────────────────────────────────────────────

func _test_unit_state() -> void:
	print("\n--- UnitState ---")

	# 1. create returns correct fields
	var u: Dictionary = UnitState.create("archer", 0, 10, 20, 42)
	ok("create: id=42", int(u.get("id", -1)) == 42)
	ok("create: type=archer", u.get("type") == "archer")
	ok("create: hp=max_hp", int(u.get("hp", 0)) == int(u.get("max_hp", 0)))
	ok("create: is_alive=true", u.get("is_alive") == true)
	ok("create: pos_x=10", int(u.get("pos_x", 0)) == 10)
	ok("create: order=idle", u.get("order") == UnitState.ORDER_IDLE)

	# 2. apply_damage reduces hp
	var u2: Dictionary = UnitState.create("swordsman", 0, 0, 0, 1)
	var res: Dictionary = UnitState.apply_damage(u2, 10, UnitRegistry.ATTACK_MELEE)
	ok("apply_damage: reduces hp", int(u2.get("hp", 0)) < int(u2.get("max_hp", 0)))
	ok("apply_damage: returns damage>0", res.get("damage", 0) > 0)

	# 3. apply_damage kills when hp reaches 0
	var u3: Dictionary = UnitState.create("armed_peasant", 0, 0, 0, 2)
	UnitState.apply_damage(u3, 999, UnitRegistry.ATTACK_MELEE)
	ok("apply_damage: kills unit at 0 hp", u3.get("is_alive") == false)

	# 4. pierce vs none does 1.5x multiplier (more damage than melee vs none)
	var undef: Dictionary = UnitState.create("armed_peasant", 0, 0, 0, 3)
	var hp_before_p: int = undef.get("hp", 0)
	UnitState.apply_damage(undef, 5, UnitRegistry.ATTACK_PIERCE)
	var pierce_dmg: int = hp_before_p - int(undef.get("hp", 0))
	var udef2: Dictionary = UnitState.create("armed_peasant", 0, 0, 0, 4)
	var hp_before_m: int = udef2.get("hp", 0)
	UnitState.apply_damage(udef2, 5, UnitRegistry.ATTACK_MELEE)
	var melee_dmg: int = hp_before_m - int(udef2.get("hp", 0))
	ok("pierce does more than melee vs unarmored", pierce_dmg > melee_dmg)

	# 5. is_ranged
	var ra := UnitState.create("archer", 0, 0, 0, 5)
	var rp := UnitState.create("pikeman", 0, 0, 0, 6)
	ok("archer is_ranged=true", UnitState.is_ranged(ra) == true)
	ok("pikeman is_ranged=false", UnitState.is_ranged(rp) == false)

# ─── Pathfinder tests (12) ──────────────────────────────────────────────────

func _test_pathfinder() -> void:
	print("\n--- Pathfinder ---")

	# Build a small all-grass grid for basic tests
	var flat_5x5 := _make_flat_grid(5, 5, 0)  # terrain 0 = GRASS

	# 1. Same start and end returns []
	var p0 := Pathfinder.find_path_dict(flat_5x5, 2, 2, 2, 2, Pathfinder.PASS_FOOT)
	ok("same start/end returns []", p0.size() == 0)

	# 2. Adjacent tile path has length 1
	var p1 := Pathfinder.find_path_dict(flat_5x5, 0, 0, 1, 0, Pathfinder.PASS_FOOT)
	ok("adjacent path length=1", p1.size() == 1)
	ok("adjacent path reaches goal", p1[0][0] == 1 and p1[0][1] == 0)

	# 3. Straight 4-tile path
	var p2 := Pathfinder.find_path_dict(flat_5x5, 0, 0, 4, 0, Pathfinder.PASS_FOOT)
	ok("4-tile straight path length=4", p2.size() == 4)
	ok("last step is goal", p2[p2.size()-1][0] == 4 and p2[p2.size()-1][1] == 0)

	# 4. Path around an impassable mountain obstacle (terrain 2 = MOUNTAIN).
	# Mountain at x=2 for rows y=1..3; row y=0 is grass (gap to route through).
	# (Rivers are now wadeable-but-slow, so mountains are the hard blockers.)
	var grid_obs := _make_flat_grid(5, 4, 0)
	for ry in range(1, 4):
		grid_obs["tiles"][ry][2] = 2
	# Path from (0,2) to (4,2) — must detour via y=0
	var p3 := Pathfinder.find_path_dict(grid_obs, 0, 2, 4, 2, Pathfinder.PASS_FOOT)
	ok("path exists around mountain", p3.size() > 0)
	# Verify no step passes through the blocked mountain tiles (y=1..3, x=2)
	var avoids_obstacle := true
	for step in p3:
		if step[0] == 2 and step[1] >= 1 and step[1] <= 3:
			avoids_obstacle = false
	ok("path avoids impassable mountain tiles", avoids_obstacle)

	# 5. Fully blocked (surrounded by mountains) returns []
	var grid_blocked := _make_flat_grid(3, 3, 2)  # all mountain
	grid_blocked["tiles"][1][1] = 0               # only center is grass
	var p4 := Pathfinder.find_path_dict(grid_blocked, 1, 1, 0, 0, Pathfinder.PASS_FOOT)
	ok("fully blocked target returns []", p4.size() == 0)

	# 6. Road tile prefers shorter cost path
	# 5-tile road at y=0, grass detour at y=1
	var grid_road := _make_flat_grid(6, 2, 0)
	for rx in range(6):
		grid_road["tiles"][0][rx] = 9   # ROAD
	var p5_road := Pathfinder.find_path_dict(grid_road, 0, 0, 5, 0, Pathfinder.PASS_FOOT)
	# Should stay on y=0 road (cost 0.5 each) rather than detour through grass (1.0)
	var stays_on_road := true
	for step in p5_road:
		if step[1] != 0:
			stays_on_road = false
	ok("path prefers road tiles (lower cost)", stays_on_road)

	# 7. Cavalry mask cannot pass forest (terrain 1)
	var grid_forest := _make_flat_grid(3, 3, 0)
	grid_forest["tiles"][1][1] = 1   # forest in middle
	# Test passability directly
	ok("cavalry cannot pass forest tile (mask check)",
		not _dict_passable(grid_forest, 1, 1, Pathfinder.PASS_CAVALRY))
	ok("foot can pass forest tile (mask check)",
		_dict_passable(grid_forest, 1, 1, Pathfinder.PASS_FOOT))

# ─── CombatSystem tests (14) ────────────────────────────────────────────────

func _test_combat_system() -> void:
	print("\n--- CombatSystem ---")

	# 1. melee vs heavy armor is reduced (0.5x mult)
	var attacker: Dictionary = UnitState.create("armed_peasant", 0, 0, 0, 1)
	var defender: Dictionary = UnitState.create("pikeman", 1, 0, 0, 2)
	var def_hp_before: int = defender.get("hp", 0)
	var res1: Dictionary = CombatSystem.calculate_damage(attacker, defender)
	ok("melee vs heavy: damage reduced", int(defender.get("hp", 0)) < def_hp_before)
	ok("calculate_damage returns damage field", res1.has("damage"))

	# 2. pierce vs unarmored is +50% multiplier
	var archer_unit: Dictionary = UnitState.create("archer", 0, 0, 0, 3)
	var peasant: Dictionary = UnitState.create("armed_peasant", 1, 0, 0, 4)
	var peasant_hp_before: int = peasant.get("hp", 0)
	var res2: Dictionary = CombatSystem.calculate_damage(archer_unit, peasant)
	var dmg_pierce_no_armor: int = peasant_hp_before - int(peasant.get("hp", 0))

	var archer2: Dictionary = UnitState.create("archer", 0, 0, 0, 5)
	var pikeman2: Dictionary = UnitState.create("pikeman", 1, 0, 0, 6)
	var pike_hp_before: int = pikeman2.get("hp", 0)
	CombatSystem.calculate_damage(archer2, pikeman2)
	var dmg_pierce_heavy_armor: int = pike_hp_before - int(pikeman2.get("hp", 0))
	ok("pierce vs unarmored > pierce vs heavy", dmg_pierce_no_armor > dmg_pierce_heavy_armor)

	# 3. siege vs structure (3x mult) vs siege vs heavy (1x)
	var ram: Dictionary = UnitState.create("battering_ram", 0, 0, 0, 7)
	var wall_target: Dictionary = {"id": 99, "type": "stone_wall", "hp": 1000, "max_hp": 1000,
		"attack": 0, "defense": 0, "armor_type": UnitRegistry.ARMOR_STRUCTURE,
		"attack_type": UnitRegistry.ATTACK_NONE, "is_alive": true, "order": "idle"}
	var wall_hp_before: int = wall_target["hp"]
	var res3: Dictionary = CombatSystem.calculate_damage(ram, wall_target)
	var wall_dmg: int = wall_hp_before - int(wall_target["hp"])

	var ram2: Dictionary = UnitState.create("battering_ram", 0, 0, 0, 8)
	var heavy_target: Dictionary = UnitState.create("pikeman", 1, 0, 0, 9)
	var heavy_hp_before: int = heavy_target.get("hp", 0)
	CombatSystem.calculate_damage(ram2, heavy_target)
	var heavy_dmg: int = heavy_hp_before - int(heavy_target.get("hp", 0))
	ok("siege vs structure > siege vs heavy", wall_dmg > heavy_dmg)

	# 4. arrows cannot damage battering_ram (immune_to_arrows)
	var archer3: Dictionary = UnitState.create("archer", 0, 0, 0, 10)
	var ram3: Dictionary = UnitState.create("battering_ram", 1, 0, 0, 11)
	var ram_hp_before: int = ram3.get("hp", 0)
	CombatSystem.calculate_damage(archer3, ram3)
	ok("pierce attack does 0 to battering_ram", int(ram3.get("hp", 0)) == ram_hp_before)

	# 5. captain morale buff
	var army_with_captain: Array = [
		UnitState.create("captain", 0, 0, 0, 20),
		UnitState.create("swordsman", 0, 0, 0, 21),
	]
	var army_no_captain: Array = [
		UnitState.create("swordsman", 0, 0, 0, 22),
	]
	ok("captain morale buff > 0", CombatSystem.get_morale_attack_bonus(army_with_captain) > 0)
	ok("no captain: morale buff = 0", CombatSystem.get_morale_attack_bonus(army_no_captain) == 0)

	# 6. resolve_combat: larger army causes more casualties on smaller
	var big_army: Array = []
	var small_army: Array = []
	for i in range(10):
		big_army.append(UnitState.create("swordsman", 0, 0, 0, 100 + i))
	for i in range(2):
		small_army.append(UnitState.create("armed_peasant", 1, 0, 0, 200 + i))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var combat_result := CombatSystem.resolve_combat(big_army, small_army, rng)
	ok("bigger army kills more of smaller", combat_result.get("defender_casualties", 0) >= combat_result.get("attacker_casualties", 0))

	# 7. siege priority: ram targets gatehouse, trebuchet targets great_tower
	ok("ram siege_priority=gatehouse", CombatSystem.get_siege_priority("battering_ram") == "gatehouse")
	ok("trebuchet siege_priority=great_tower", CombatSystem.get_siege_priority("trebuchet") == "great_tower")

	# 8. halberdier anti-armor bonus increases damage vs a zero-defense heavy target
	# Use a custom heavy-armored defender with defense=0 so the mult difference shows
	var halb: Dictionary = UnitState.create("halberdier", 0, 0, 0, 50)
	var heavy_dummy: Dictionary = {"id": 55, "type": "pikeman", "hp": 200, "max_hp": 200,
		"attack": 0, "defense": 0, "armor_type": UnitRegistry.ARMOR_HEAVY,
		"attack_type": UnitRegistry.ATTACK_NONE, "is_alive": true, "order": "idle"}
	var hd_hp: int = heavy_dummy["hp"]
	CombatSystem.calculate_damage(halb, heavy_dummy)
	var halb_dmg: int = hd_hp - int(heavy_dummy["hp"])
	var plain_melee: Dictionary = UnitState.create("militia", 0, 0, 0, 52)
	var heavy_dummy2: Dictionary = {"id": 56, "type": "pikeman", "hp": 200, "max_hp": 200,
		"attack": 0, "defense": 0, "armor_type": UnitRegistry.ARMOR_HEAVY,
		"attack_type": UnitRegistry.ATTACK_NONE, "is_alive": true, "order": "idle"}
	var hd2_hp: int = heavy_dummy2["hp"]
	CombatSystem.calculate_damage(plain_melee, heavy_dummy2)
	var militia_dmg: int = hd2_hp - int(heavy_dummy2["hp"])
	ok("halberdier anti-armor bonus increases dmg vs heavy", halb_dmg > militia_dmg)

# ─── AI Faction tests (18) ──────────────────────────────────────────────────

func _test_ai_factions() -> void:
	print("\n--- AI Factions ---")

	# 1. make_faction base fields
	var f := AIFaction.make_faction(0, "TestFaction", AIFaction.ARCHETYPE_BANDIT, 50, 50)
	ok("make_faction: id=0", f.get("id") == 0)
	ok("make_faction: is_alive=true", f.get("is_alive") == true)
	ok("make_faction: has units array", f.has("units"))
	ok("make_faction: has resources dict", f.has("resources"))

	# 2. BanditKing archetype
	var bk := BanditKing.make(0, 30, 30)
	ok("BanditKing archetype correct", bk.get("archetype") == AIFaction.ARCHETYPE_BANDIT)
	ok("BanditKing starts with wood, little gold", bk["resources"].get("wood", 0) > 200)
	ok("BanditKing stone=0 (ignores stone mining)", bk["resources"].get("stone", 0) == 0)

	# 3. MerchantPrince archetype
	var mp := MerchantPrince.make(1, 60, 60)
	ok("MerchantPrince archetype correct", mp.get("archetype") == AIFaction.ARCHETYPE_MERCHANT)
	ok("MerchantPrince starts with large gold", mp.get("gold", 0) >= 1000)

	# 4. Ironhand archetype
	var ih := Ironhand.make(2, 70, 70)
	ok("Ironhand archetype correct", ih.get("archetype") == AIFaction.ARCHETYPE_IRONHAND)
	ok("Ironhand has high iron stockpile", ih["resources"].get("iron", 0) >= 100)
	ok("Ironhand has siege_engines tech", "siege_engines" in ih.get("tech_unlocks", []))

	# 5. AshenBarony archetype
	var ab := AshenBarony.make(3, 80, 80)
	ok("AshenBarony archetype correct", ab.get("archetype") == AIFaction.ARCHETYPE_ASHEN_BARONY)
	ok("AshenBarony capital_name=Highwatch", ab.get("capital_name") == "Highwatch")
	ok("AshenBarony supply_lines_active=true", ab.get("supply_lines_active") == true)
	ok("cut_supply_lines disables them", _test_cut_supply(ab))

	# 6. AIFaction.tick increments days_alive at day boundary
	var f2 := AIFaction.make_faction(5, "T", AIFaction.ARCHETYPE_BANDIT, 0, 0)
	AIFaction.tick(f2, {}, 240)  # tick=240 (first day boundary)
	ok("tick: days_alive increments", f2.get("days_alive") == 1)

	# 7. AIFaction recruit_unit reduces gold
	var f3 := AIFaction.make_faction(6, "T", AIFaction.ARCHETYPE_BANDIT, 0, 0)
	f3["gold"] = 100
	var gold_before: int = f3["gold"]
	AIFaction.recruit_unit(f3, "armed_peasant", 1)
	ok("recruit_unit deducts gold", int(f3["gold"]) < gold_before)
	ok("recruit_unit adds to units array", f3["units"].size() == 1)

	# 8. should_attack respects threshold
	var bk2 := BanditKing.make(7, 0, 0)
	bk2["threat_level"] = 5.0   # below bandit threshold (15)
	var player_stub := [{"id": 0, "is_alive": true, "keep_x": 10, "keep_y": 10, "military_strength": 0, "prestige": 0}]
	var att := AIFaction.should_attack(bk2, player_stub)
	ok("below threshold: should_attack=false", att.get("attack") == false)

	# 8b. Diplomacy depth: paying tribute buys a peace window; refusing nurses grievance.
	var dipf := BanditKing.make(9, 0, 0)
	dipf["days_alive"] = AIFaction.PLAYER_GRACE_DAYS + 5   # past the King's Peace
	dipf["threat_level"] = 80.0                            # well over the bandit threshold
	var now := 100 * 240
	ok("aggressive faction would attack absent diplomacy",
		AIFaction.should_attack(dipf, player_stub, now).get("attack") == true)
	DiplomacySystem.accept({"id": 0, "gold": 100, "resources": {}, "food": {}}, {"gold": 10}, dipf, now)
	ok("paying tribute buys peace (no siege during the window)",
		AIFaction.should_attack(dipf, player_stub, now + 240).get("attack") == false)
	ok("the bought peace eventually expires",
		AIFaction.should_attack(dipf, player_stub, now + AIFaction.TRIBUTE_PEACE_DAYS * 240 + 240).get("attack") == true)
	var dipf2 := BanditKing.make(10, 0, 0)
	var g0: float = dipf2.get("grievance", 0.0)
	DiplomacySystem.refuse({"id": 0, "popularity": 50.0}, dipf2)
	ok("refusing tribute nurses a persistent grievance", dipf2.get("grievance", 0.0) > g0)

	# 9. Ashen tribute demands after 14+ game-days
	var ab2: Dictionary = AshenBarony.make(8, 0, 0)
	var player_stub2 := [{"id": 0, "is_alive": true, "keep_x": 5, "keep_y": 5}]
	for tday in range(1, 16):
		AshenBarony.tick(ab2, player_stub2, {}, tday * 240)
	var demands: Array = AIFaction.get_pending_demands(ab2, 0)
	ok("AshenBarony sends tribute demands after 14 days", demands.size() > 0)

# ─── GameState integration tests (10) ───────────────────────────────────────

func _test_gamestate_integration() -> void:
	print("\n--- GameState Integration ---")

	# 1. add_ai_faction registers in ai_factions
	_gs.ai_factions.clear()
	var fid: int = _gs.add_ai_faction(AIFaction.ARCHETYPE_BANDIT, 10, 10)
	ok("add_ai_faction: returns valid id", fid == 0)
	ok("add_ai_faction: ai_factions.size=1", _gs.ai_factions.size() == 1)
	ok("add_ai_faction: correct archetype", _gs.ai_factions[0].get("archetype") == AIFaction.ARCHETYPE_BANDIT)

	# 2. All four archetypes can be added
	_gs.ai_factions.clear()
	_gs.add_ai_faction(AIFaction.ARCHETYPE_BANDIT, 10, 10)
	_gs.add_ai_faction(AIFaction.ARCHETYPE_MERCHANT, 20, 20)
	_gs.add_ai_faction(AIFaction.ARCHETYPE_IRONHAND, 30, 30)
	_gs.add_ai_faction(AIFaction.ARCHETYPE_ASHEN_BARONY, 40, 40)
	ok("four archetypes added", _gs.ai_factions.size() == 4)

	# 2b. get_faction_display_name resolves id→name so notifications never show raw ids
	_gs.ai_factions.clear()
	_gs.ai_factions.append({"id": 7, "name": "The Ashen Barony", "is_alive": true})
	ok("faction name resolves by id", _gs.get_faction_display_name(7) == "The Ashen Barony")
	ok("unknown faction id falls back to a title (never a raw number)", _gs.get_faction_display_name(999) == "A rival lord")
	_gs.ai_factions.clear()

	# 2c. is_siege_ready: a prepared realm (defences + garrison) earns the lighter siege penalty
	var undef := {"buildings": [{"type": "village_hall", "built": true}], "units": []}
	ok("no defences -> not siege-ready", not _gs.is_siege_ready(undef))
	var walled := {"buildings": [
		{"type": "stone_wall", "built": true}, {"type": "lookout_tower", "built": true},
		{"type": "gatehouse", "built": true}], "units": []}
	ok("walls+tower+gatehouse -> siege-ready", _gs.is_siege_ready(walled))
	var garrisoned := {"buildings": [], "units": [
		{"is_alive": true}, {"is_alive": true}, {"is_alive": true}]}
	ok("a standing garrison -> siege-ready", _gs.is_siege_ready(garrisoned))
	var dead_garrison := {"buildings": [], "units": [
		{"is_alive": false}, {"is_alive": false}, {"is_alive": false}]}
	ok("a fallen garrison does not count", not _gs.is_siege_ready(dead_garrison))

	# 2d. has_stalled_construction: a site pending + every villager locked in a job = stalled
	var site_player := {"buildings": [
		{"type": "church", "built": false, "build_required": 100.0}]}
	_gs.citizens = [
		{"is_alive": true, "role": "worker", "state": "work", "stage": "adult"},
		{"is_alive": true, "role": "worker", "state": "work", "stage": "adult"}]
	ok("pending site + all villagers working -> stalled", _gs.has_stalled_construction(site_player))
	# An idle working-age villager could be tasked -> not stalled
	_gs.citizens.append({"is_alive": true, "role": "", "state": "idle", "stage": "adult"})
	ok("an idle villager clears the stall", not _gs.has_stalled_construction(site_player))
	# A builder already on the job -> not stalled
	_gs.citizens = [{"is_alive": true, "role": "builder", "state": "build", "stage": "adult"}]
	ok("an active builder is not a stall", not _gs.has_stalled_construction(site_player))
	# No sites at all -> never stalled, even with everyone working
	_gs.citizens = [{"is_alive": true, "role": "worker", "state": "work", "stage": "adult"}]
	ok("no construction -> not stalled", not _gs.has_stalled_construction({"buildings": [{"type": "church", "built": true}]}))
	_gs.citizens = []

	# 3. RECRUIT_UNIT command (player has no barracks → should fail)
	var p: Dictionary = _fresh_player()
	_cq.enqueue(CT_RECRUIT_UNIT, {"unit_type": "armed_peasant"}, 0)
	_sc._advance_tick()
	ok("recruit without barracks fails", p.get("units", []).size() == 0)

	# 4. RECRUIT_UNIT command: place barracks first (no grid so validator skips)
	p["buildings"].append({
		"id": 1, "type": "barracks", "is_active": true,
		"grid_x": 0, "grid_y": 0, "workers": 1, "owner_id": 0,
	})
	p["gold"] = 200
	_cq.clear()
	_cq.enqueue(CT_RECRUIT_UNIT, {"unit_type": "armed_peasant"}, 0)
	_sc._advance_tick()
	ok("recruit armed_peasant with barracks succeeds", p.get("units", []).size() == 1)
	ok("gold deducted for recruitment", int(p.get("gold", 200)) < 200)

	# 5. ISSUE_MOVE_ORDER changes unit order
	# A real grid is required so pathfinding produces a non-empty path; without
	# one the movement tick would immediately clear the order back to IDLE.
	_gs._grid = WorldGrid.new(120, 120)  # all-grass, fully passable
	# The recruit above starts in the barracks training queue; graduate it so it
	# is deployable and can accept a move order.
	p["units"][0]["order"] = UnitState.ORDER_IDLE
	var uid: int = p["units"][0].get("id", -1)
	_cq.enqueue(CT_ISSUE_MOVE_ORDER, {"unit_id": uid, "target_x": 99, "target_y": 99}, 0)
	_sc._advance_tick()
	ok("move order changes unit order field", p["units"][0].get("order") == UnitState.ORDER_MOVE)
	ok("move order sets target_x=99", int(p["units"][0].get("target_x", 0)) == 99)

	# 6. DISBAND_UNIT removes unit from array
	_cq.enqueue(CT_DISBAND_UNIT, {"unit_id": uid}, 0)
	_sc._advance_tick()
	ok("disband removes unit", p.get("units", []).size() == 0)

	# 7. Serialization includes next_unit_id
	_gs._next_unit_id = 42
	var ser: Dictionary = _gs.serialize()
	ok("serialize includes next_unit_id", int(ser.get("next_unit_id", 0)) == 42)
	_gs.deserialize(ser)
	ok("deserialize restores next_unit_id", _gs._next_unit_id == 42)

# ─── Helpers ─────────────────────────────────────────────────────────────────

func _make_flat_grid(w: int, h: int, terrain: int) -> Dictionary:
	var tiles: Array = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			row.append(terrain)
		tiles.append(row)
	return {"width": w, "height": h, "tiles": tiles}

func _dict_passable(grid_dict: Dictionary, x: int, y: int, mask: int) -> bool:
	var tiles: Array = grid_dict.get("tiles", [])
	if y < 0 or y >= tiles.size():
		return false
	var row: Array = tiles[y]
	if x < 0 or x >= row.size():
		return false
	var terrain: int = row[x]
	# mirror Pathfinder's passability table
	const PASS: Dictionary = {
		0: 0b00001111, 1: 0b00000001, 2: 0b00000001, 3: 0,
		4: 0b00000001, 5: 0b00000001, 6: 0b00000001, 7: 0b00001111,
		8: 0b00000111, 9: 0b00001111, 10: 0b00000011
	}
	return (PASS.get(terrain, 0) & mask) != 0

func _test_cut_supply(ab: Dictionary) -> bool:
	AshenBarony.cut_supply_lines(ab)
	return not ab.get("supply_lines_active", true)
