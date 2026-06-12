extends SceneTree
# Phase 5 test suite — SaveManager, TechTree, PrestigeSystem, CapitalSystem, EdictSystem,
#                       and GameState Phase 5 integration.
# Run: godot --headless --script tests/TestPhase5.gd

const SaveManager    = preload("res://simulation/persistence/SaveManager.gd")
const TechTree       = preload("res://simulation/tech/TechTree.gd")
const PrestigeSystem = preload("res://simulation/tech/PrestigeSystem.gd")
const CapitalSystem  = preload("res://simulation/world/CapitalSystem.gd")
const EdictSystem    = preload("res://simulation/edicts/EdictSystem.gd")
const BuildingState  = preload("res://simulation/buildings/BuildingState.gd")

# Mirror CommandType enum values to avoid compile-time autoload resolution
const CT_ACTIVATE_EDICT     = 16  # CommandQueue.CommandType.ACTIVATE_EDICT
const CT_DONATE_TO_CAPITAL  = 3   # CommandQueue.CommandType.DONATE_TO_CAPITAL

var _gs = null
var _cq = null
var _sc = null

var _pass: int = 0
var _fail: int = 0
var _errors: Array = []

const TEST_SAVE_PATH: String = "user://test_phase5_save.json"

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
	# Clean up test save file
	if SaveManager.save_exists(TEST_SAVE_PATH):
		SaveManager.delete_save(TEST_SAVE_PATH)
	print("\n=== Phase 5 Results: %d passed, %d failed ===" % [_pass, _fail])
	for e in _errors:
		print("  FAIL: ", e)
	quit(1 if _fail > 0 else 0)

func run_all() -> void:
	print("--- SaveManager ---")
	test_save_writes_file()
	test_save_load_roundtrip()
	test_load_nonexistent_returns_empty()
	test_load_corrupt_returns_empty()
	test_load_wrong_version_returns_empty()
	test_save_exists()
	test_delete_save()
	test_get_metadata_valid()
	test_get_metadata_invalid()

	print("--- TechTree ---")
	test_tech_lookup_valid()
	test_tech_lookup_invalid()
	test_tech_is_unlocked_false()
	test_tech_is_unlocked_true()
	test_tech_can_research_missing_prereq()
	test_tech_can_research_insufficient_prestige()
	test_tech_can_research_already_unlocked()
	test_tech_can_research_ok()
	test_tech_research_deducts_prestige()
	test_tech_research_adds_to_unlocks()
	test_tech_research_returns_buildings()
	test_tech_research_fails_prereq()
	test_tech_get_researchable_empty()
	test_tech_get_researchable_after_unlock()
	test_tech_get_branch_returns_subset()
	test_tech_get_all_modifiers_empty()
	test_tech_get_all_modifiers_stacks()

	print("--- PrestigeSystem ---")
	test_prestige_tick_no_day_boundary()
	test_prestige_tick_generates_at_day_boundary()
	test_prestige_starvation_halts_generation()
	test_prestige_food_variety_increases_gain()
	test_prestige_popularity_multiplier_low()
	test_prestige_popularity_multiplier_high()
	test_prestige_capital_multiplier()
	test_prestige_spend_succeeds()
	test_prestige_spend_fails_insufficient()
	test_prestige_can_afford()
	test_prestige_defeat_loss()

	print("--- CapitalSystem ---")
	test_capital_ensure_fields()
	test_capital_record_donation()
	test_capital_total_donated()
	test_capital_player_donations()
	test_capital_can_upgrade_no_donations()
	test_capital_can_upgrade_sufficient_donations()
	test_capital_upgrade_increases_level()
	test_capital_upgrade_resets_donations()
	test_capital_upgrade_max_level()
	test_capital_buffs_level_0()
	test_capital_buffs_level_3()
	test_capital_prestige_multiplier()
	test_capital_edict_tier_cap()

	print("--- EdictSystem ---")
	test_edict_lookup_valid()
	test_edict_lookup_invalid()
	test_edict_is_active_false()
	test_edict_can_activate_no_tech()
	test_edict_can_activate_no_points()
	test_edict_can_activate_ok()
	test_edict_activate_deducts_points()
	test_edict_activate_adds_to_active()
	test_edict_activate_duplicate_fails()
	test_edict_cooldown_after_active_edict()
	test_edict_tick_expires_active()
	test_edict_get_modifiers_empty()
	test_edict_get_modifiers_stacks()
	test_edict_levy_summons_instant_effects()
	test_edict_festival_triggers_event()

	print("--- GameState Phase 5 integration ---")
	test_gs_prestige_generated_at_day_boundary()
	test_gs_tech_tree_unlocks_buildings()
	test_gs_activate_edict_via_command()
	test_gs_donate_to_capital_via_command()
	test_gs_save_load_roundtrip()

# ============ SaveManager ============

func _make_test_state() -> Dictionary:
	return {
		"version": 1,
		"players": [{"id": 0, "gold": 100}],
		"world": {"map_seed": 12345},
	}

func test_save_writes_file() -> void:
	SaveManager.delete_save(TEST_SAVE_PATH)
	var ok = SaveManager.save(_make_test_state(), TEST_SAVE_PATH)
	expect("save returns true", ok == true)
	expect("file exists after save", SaveManager.save_exists(TEST_SAVE_PATH))

func test_save_load_roundtrip() -> void:
	var state = _make_test_state()
	SaveManager.save(state, TEST_SAVE_PATH)
	var loaded = SaveManager.load_save(TEST_SAVE_PATH)
	expect("loaded state not empty", not loaded.is_empty())
	expect("players array preserved", loaded.get("players", []).size() == 1)
	expect("gold preserved", loaded.get("players", [{}])[0].get("gold", -1) == 100)

func test_load_nonexistent_returns_empty() -> void:
	var loaded = SaveManager.load_save("user://does_not_exist_xyz.json")
	expect("missing file returns empty", loaded.is_empty())

func test_load_corrupt_returns_empty() -> void:
	var f = FileAccess.open("user://corrupt_test.json", FileAccess.WRITE)
	f.store_string("this is not valid json {{{")
	f.close()
	var loaded = SaveManager.load_save("user://corrupt_test.json")
	DirAccess.remove_absolute("user://corrupt_test.json")
	expect("corrupt JSON returns empty", loaded.is_empty())

func test_load_wrong_version_returns_empty() -> void:
	var f = FileAccess.open("user://wrong_version_test.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"save_version": 999, "state": {"foo": "bar"}}))
	f.close()
	var loaded = SaveManager.load_save("user://wrong_version_test.json")
	DirAccess.remove_absolute("user://wrong_version_test.json")
	expect("wrong version returns empty", loaded.is_empty())

func test_save_exists() -> void:
	SaveManager.save(_make_test_state(), TEST_SAVE_PATH)
	expect("save_exists returns true", SaveManager.save_exists(TEST_SAVE_PATH))

func test_delete_save() -> void:
	SaveManager.save(_make_test_state(), TEST_SAVE_PATH)
	SaveManager.delete_save(TEST_SAVE_PATH)
	expect("save_exists returns false after delete", not SaveManager.save_exists(TEST_SAVE_PATH))

func test_get_metadata_valid() -> void:
	SaveManager.save(_make_test_state(), TEST_SAVE_PATH)
	var meta = SaveManager.get_save_metadata(TEST_SAVE_PATH)
	expect("metadata has save_version", meta.has("save_version"))
	expect("metadata valid=true", meta.get("valid", false) == true)

func test_get_metadata_invalid() -> void:
	var meta = SaveManager.get_save_metadata("user://does_not_exist_abc.json")
	expect("metadata empty for missing file", meta.is_empty())

# ============ TechTree ============

func _make_tech_player(prestige: float = 500.0) -> Dictionary:
	return {
		"id": 0, "prestige": prestige,
		"tech_unlocks": [],
		"buildings": [],
		"food": {"apples": 50, "cheese": 0, "meat": 0, "bread": 0, "ale": 0},
	}

func test_tech_lookup_valid() -> void:
	var defn = TechTree.lookup("crop_tiers")
	expect("crop_tiers has name", defn.has("name"))
	expect("crop_tiers has cost_prestige", defn.get("cost_prestige", 0) > 0)

func test_tech_lookup_invalid() -> void:
	var defn = TechTree.lookup("nonexistent_tech")
	expect("unknown tech returns empty", defn.is_empty())

func test_tech_is_unlocked_false() -> void:
	var p = _make_tech_player()
	expect("not unlocked by default", TechTree.is_unlocked(p, "crop_tiers") == false)

func test_tech_is_unlocked_true() -> void:
	var p = _make_tech_player()
	p["tech_unlocks"] = ["crop_tiers"]
	expect("is unlocked after adding to list", TechTree.is_unlocked(p, "crop_tiers") == true)

func test_tech_can_research_missing_prereq() -> void:
	var p = _make_tech_player(1000.0)
	# animal_husbandry requires crop_tiers
	var result = TechTree.can_research(p, "animal_husbandry")
	expect("animal_husbandry fails without crop_tiers", result["ok"] == false)

func test_tech_can_research_insufficient_prestige() -> void:
	var p = _make_tech_player(50.0)  # crop_tiers costs 100
	var result = TechTree.can_research(p, "crop_tiers")
	expect("can_research fails with insufficient prestige", result["ok"] == false)

func test_tech_can_research_already_unlocked() -> void:
	var p = _make_tech_player(1000.0)
	p["tech_unlocks"] = ["crop_tiers"]
	var result = TechTree.can_research(p, "crop_tiers")
	expect("can_research fails if already unlocked", result["ok"] == false)

func test_tech_can_research_ok() -> void:
	var p = _make_tech_player(500.0)
	var result = TechTree.can_research(p, "crop_tiers")
	expect("can_research succeeds with prereqs+prestige", result["ok"] == true)

func test_tech_research_deducts_prestige() -> void:
	var p = _make_tech_player(500.0)
	var cost = TechTree.lookup("crop_tiers").get("cost_prestige", 0)
	TechTree.research(p, "crop_tiers")
	expect("prestige deducted after research", absf(p["prestige"] - (500.0 - cost)) < 0.01)

func test_tech_research_adds_to_unlocks() -> void:
	var p = _make_tech_player(500.0)
	TechTree.research(p, "crop_tiers")
	expect("tech_unlocks contains crop_tiers", "crop_tiers" in p["tech_unlocks"])

func test_tech_research_returns_buildings() -> void:
	var p = _make_tech_player(500.0)
	var result = TechTree.research(p, "crop_tiers")
	expect("result ok", result["ok"] == true)
	expect("unlocked_buildings non-empty", result["unlocked_buildings"].size() > 0)

func test_tech_research_fails_prereq() -> void:
	var p = _make_tech_player(1000.0)
	var result = TechTree.research(p, "animal_husbandry")
	expect("research fails without prereq", result["ok"] == false)
	expect("prestige not deducted on failure", p["prestige"] == 1000.0)

func test_tech_get_researchable_empty() -> void:
	var p = _make_tech_player(0.0)  # No prestige
	var researchable = TechTree.get_researchable(p)
	expect("no researchable tech with 0 prestige", researchable.is_empty())

func test_tech_get_researchable_after_unlock() -> void:
	var p = _make_tech_player(1000.0)
	TechTree.research(p, "crop_tiers")
	var researchable = TechTree.get_researchable(p)
	# Should include farming_speed and storage_capacity (both require crop_tiers)
	expect("farming_speed now researchable", "farming_speed" in researchable)

func test_tech_get_branch_returns_subset() -> void:
	var branch = TechTree.get_branch(TechTree.Branch.AGRICULTURE)
	expect("agriculture branch has 5 techs", branch.size() == 5)
	expect("crop_tiers in agriculture branch", "crop_tiers" in branch)

func test_tech_get_all_modifiers_empty() -> void:
	var p = _make_tech_player()
	var mods = TechTree.get_all_modifiers(p)
	expect("no modifiers with no unlocks", mods.is_empty())

func test_tech_get_all_modifiers_stacks() -> void:
	var p = _make_tech_player(1000.0)
	TechTree.research(p, "crop_tiers")
	TechTree.research(p, "farming_speed")
	var mods = TechTree.get_all_modifiers(p)
	expect("farming_speed modifier present", mods.has("harvest_rate_bonus"))
	expect("harvest_rate_bonus = 0.2", absf(mods["harvest_rate_bonus"] - 0.2) < 0.01)

# ============ PrestigeSystem ============

func _make_prestige_player(popularity: float = 60.0, food_variety: int = 1, is_starving: bool = false) -> Dictionary:
	var food: Dictionary = {"apples": 0, "cheese": 0, "meat": 0, "bread": 0, "ale": 0}
	var food_types = ["apples", "cheese", "meat", "bread"]
	for i in range(food_variety):
		food[food_types[i]] = 10
	return {
		"id": 0, "is_alive": true, "is_starving": is_starving,
		"popularity": popularity, "prestige": 0.0,
		"shire_id": -1, "buildings": [], "food": food,
	}

func test_prestige_tick_no_day_boundary() -> void:
	var p = _make_prestige_player()
	var result = PrestigeSystem.tick(p, {}, 100)
	expect("prestige tick empty at non-day-boundary", result.is_empty())

func test_prestige_tick_generates_at_day_boundary() -> void:
	var p = _make_prestige_player()
	var result = PrestigeSystem.tick(p, {}, 240)
	expect("prestige tick non-empty at day boundary", not result.is_empty())
	expect("delta > 0", result.get("delta", 0.0) > 0.0)
	expect("prestige increased", p["prestige"] > 0.0)

func test_prestige_starvation_halts_generation() -> void:
	var p = _make_prestige_player(60.0, 1, true)  # is_starving=true
	var result = PrestigeSystem.tick(p, {}, 240)
	# Should return empty (no generation when starving)
	expect("starvation halts prestige generation", result.is_empty() or result.get("delta", 0.0) == 0.0)

func test_prestige_food_variety_increases_gain() -> void:
	var p_low = _make_prestige_player(60.0, 1)   # 1 food type
	var p_high = _make_prestige_player(60.0, 4)  # 4 food types
	var r_low = PrestigeSystem.tick(p_low, {}, 240)
	var r_high = PrestigeSystem.tick(p_high, {}, 480)
	expect("more food variety = more prestige", r_high.get("delta", 0.0) > r_low.get("delta", 0.0))

func test_prestige_popularity_multiplier_low() -> void:
	var p = _make_prestige_player(15.0)  # Very low popularity
	var result = PrestigeSystem.tick(p, {}, 240)
	var low_delta = result.get("delta", 0.0)
	var p2 = _make_prestige_player(80.0)  # High popularity
	var r2 = PrestigeSystem.tick(p2, {}, 480)
	expect("low popularity yields less prestige than high", r2.get("delta", 0.0) > low_delta)

func test_prestige_popularity_multiplier_high() -> void:
	var p = _make_prestige_player(85.0)  # Above 80 → 1.5× multiplier
	var result = PrestigeSystem.tick(p, {}, 240)
	expect("high popularity generates prestige", result.get("delta", 0.0) > 0.0)

func test_prestige_capital_multiplier() -> void:
	var p = _make_prestige_player(60.0)
	p["shire_id"] = 0
	var world = {"shires": [{"id": 0, "capital_level": 3}]}
	var result = PrestigeSystem.tick(p, world, 240)
	expect("capital level adds prestige multiplier", result.get("delta", 0.0) > 0.0)

func test_prestige_spend_succeeds() -> void:
	var p = _make_prestige_player()
	p["prestige"] = 200.0
	var ok = PrestigeSystem.spend(p, 100.0)
	expect("spend returns true with sufficient prestige", ok == true)
	expect("prestige reduced to 100", absf(p["prestige"] - 100.0) < 0.01)

func test_prestige_spend_fails_insufficient() -> void:
	var p = _make_prestige_player()
	p["prestige"] = 50.0
	var ok = PrestigeSystem.spend(p, 100.0)
	expect("spend returns false with insufficient prestige", ok == false)
	expect("prestige unchanged on failure", absf(p["prestige"] - 50.0) < 0.01)

func test_prestige_can_afford() -> void:
	var p = _make_prestige_player()
	p["prestige"] = 100.0
	expect("can_afford true when sufficient", PrestigeSystem.can_afford(p, 100.0) == true)
	expect("can_afford false when insufficient", PrestigeSystem.can_afford(p, 101.0) == false)

func test_prestige_defeat_loss() -> void:
	var p = _make_prestige_player()
	p["prestige"] = 200.0
	var loss = PrestigeSystem.apply_defeat_loss(p)
	expect("defeat_loss positive", loss > 0.0)
	expect("prestige reduced by loss", absf(p["prestige"] - (200.0 - loss)) < 0.01)

# ============ CapitalSystem ============

func _make_shire(level: int = 0) -> Dictionary:
	var shire: Dictionary = {"id": 0, "capital_level": level}
	CapitalSystem.ensure_capital_fields(shire)
	return shire

func _make_cap_player() -> Dictionary:
	return {
		"id": 0,
		"resources": {"wood": 1000, "stone": 5000, "iron": 500},
	}

func test_capital_ensure_fields() -> void:
	var shire: Dictionary = {"id": 0}
	CapitalSystem.ensure_capital_fields(shire)
	expect("capital_level field added", shire.has("capital_level"))
	expect("capital_donations field added", shire.has("capital_donations"))

func test_capital_record_donation() -> void:
	var shire = _make_shire()
	var p = _make_cap_player()
	CapitalSystem.record_donation(p, shire, "wood", 100)
	expect("donation recorded", CapitalSystem.get_total_donated(shire, "wood") == 100)

func test_capital_total_donated() -> void:
	var shire = _make_shire()
	var p0 = _make_cap_player()
	var p1 = {"id": 1, "resources": {"wood": 1000}}
	CapitalSystem.record_donation(p0, shire, "wood", 100)
	CapitalSystem.record_donation(p1, shire, "wood", 50)
	expect("total donated sums both players", CapitalSystem.get_total_donated(shire, "wood") == 150)

func test_capital_player_donations() -> void:
	var shire = _make_shire()
	var p = _make_cap_player()
	CapitalSystem.record_donation(p, shire, "stone", 200)
	var pd = CapitalSystem.get_player_donations(shire, 0)
	expect("player donations returns stone", pd.get("stone", 0) == 200)

func test_capital_can_upgrade_no_donations() -> void:
	var shire = _make_shire(0)
	var result = CapitalSystem.can_upgrade(shire, {})
	# Level 0→1 requires some resources (cost dict is empty for first level)
	expect("level 0 can upgrade without cost", result["ok"] == true)

func test_capital_can_upgrade_sufficient_donations() -> void:
	var shire = _make_shire(1)
	# Level 1→2 requires wood:200, stone:100
	CapitalSystem.record_donation({"id": 0}, shire, "stone", 200)
	CapitalSystem.record_donation({"id": 0}, shire, "wood", 100)
	var result = CapitalSystem.can_upgrade(shire, {})
	expect("can upgrade with sufficient donations", result["ok"] == true)

func test_capital_upgrade_increases_level() -> void:
	var shire = _make_shire(0)
	var new_level = CapitalSystem.upgrade(shire, {})
	expect("upgrade increases capital_level", new_level == 1)
	expect("capital_level field updated", shire["capital_level"] == 1)

func test_capital_upgrade_resets_donations() -> void:
	var shire = _make_shire(0)
	CapitalSystem.record_donation({"id": 0}, shire, "wood", 100)
	CapitalSystem.upgrade(shire, {})
	expect("donations reset after upgrade", shire["capital_donations"].is_empty())

func test_capital_upgrade_max_level() -> void:
	var shire = _make_shire(CapitalSystem.MAX_LEVEL)
	var result = CapitalSystem.can_upgrade(shire, {})
	expect("cannot upgrade past max level", result["ok"] == false)

func test_capital_buffs_level_0() -> void:
	var shire = _make_shire(0)
	var buffs = CapitalSystem.get_capital_buffs(shire)
	expect("level 0 has no buffs", buffs.is_empty())

func test_capital_buffs_level_3() -> void:
	var shire = _make_shire(3)
	var buffs = CapitalSystem.get_capital_buffs(shire)
	expect("level 3 has prestige_mult", buffs.has("prestige_mult"))
	expect("level 3 has edict_tier_cap", buffs.has("edict_tier_cap"))
	expect("level 3 has iron_mining_bonus", buffs.has("iron_mining_bonus"))

func test_capital_prestige_multiplier() -> void:
	var shire = _make_shire(3)
	var mult = CapitalSystem.get_prestige_multiplier(shire)
	expect("level 3 prestige multiplier = 0.3", absf(mult - 0.3) < 0.01)

func test_capital_edict_tier_cap() -> void:
	var shire0 = _make_shire(0)
	var shire3 = _make_shire(3)
	expect("level 0 tier cap = 0", CapitalSystem.get_edict_tier_cap(shire0) == 0)
	expect("level 3 tier cap = 2", CapitalSystem.get_edict_tier_cap(shire3) == 2)

# ============ EdictSystem ============

func _make_edict_player(points: int = 20) -> Dictionary:
	return {
		"id": 0,
		"edict_points": points,
		"active_edicts": [],
		"tech_unlocks": [],
		"population": 50,
		"popularity": 60.0,
		"gold": 200,
	}

func test_edict_lookup_valid() -> void:
	var defn = EdictSystem.lookup("agrarian_subsidies")
	expect("agrarian_subsidies has name", defn.has("name"))
	expect("agrarian_subsidies is passive", defn.get("type", -1) == EdictSystem.EdictType.PASSIVE)

func test_edict_lookup_invalid() -> void:
	var defn = EdictSystem.lookup("nonexistent_edict")
	expect("unknown edict returns empty", defn.is_empty())

func test_edict_is_active_false() -> void:
	var p = _make_edict_player()
	expect("edict not active by default", EdictSystem.is_active(p, "agrarian_subsidies") == false)

func test_edict_can_activate_no_tech() -> void:
	var p = _make_edict_player(20)
	# agrarian_subsidies requires "royal_edicts" tech
	var result = EdictSystem.can_activate(p, "agrarian_subsidies", 0)
	expect("can_activate fails without required tech", result["ok"] == false)

func test_edict_can_activate_no_points() -> void:
	var p = _make_edict_player(0)
	p["tech_unlocks"] = ["royal_edicts"]
	var result = EdictSystem.can_activate(p, "agrarian_subsidies", 0)
	expect("can_activate fails with 0 edict_points", result["ok"] == false)

func test_edict_can_activate_ok() -> void:
	var p = _make_edict_player(20)
	p["tech_unlocks"] = ["royal_edicts"]
	var result = EdictSystem.can_activate(p, "agrarian_subsidies", 0)
	expect("can_activate succeeds with tech+points", result["ok"] == true)

func test_edict_activate_deducts_points() -> void:
	var p = _make_edict_player(20)
	p["tech_unlocks"] = ["royal_edicts"]
	var cost = EdictSystem.lookup("agrarian_subsidies").get("cost_points", 0)
	EdictSystem.activate(p, "agrarian_subsidies", 0)
	expect("edict points deducted", p["edict_points"] == 20 - cost)

func test_edict_activate_adds_to_active() -> void:
	var p = _make_edict_player(20)
	p["tech_unlocks"] = ["royal_edicts"]
	EdictSystem.activate(p, "agrarian_subsidies", 0)
	expect("edict added to active_edicts", EdictSystem.is_active(p, "agrarian_subsidies"))

func test_edict_activate_duplicate_fails() -> void:
	var p = _make_edict_player(20)
	p["tech_unlocks"] = ["royal_edicts"]
	EdictSystem.activate(p, "agrarian_subsidies", 0)
	var result = EdictSystem.activate(p, "agrarian_subsidies", 0)
	expect("duplicate activation fails", result["ok"] == false)

func test_edict_cooldown_after_active_edict() -> void:
	var p = _make_edict_player(20)
	p["tech_unlocks"] = ["royal_edicts"]
	EdictSystem.activate(p, "taxation_bumps", 0)
	# taxation_bumps has cooldown, but is already active — deactivate manually
	EdictSystem.deactivate(p, "taxation_bumps")
	# Cooldown should prevent re-activation immediately
	var result = EdictSystem.can_activate(p, "taxation_bumps", 1)
	expect("edict on cooldown after use", result["ok"] == false)

func test_edict_tick_expires_active() -> void:
	var p = _make_edict_player(20)
	p["tech_unlocks"] = ["royal_edicts"]
	EdictSystem.activate(p, "taxation_bumps", 0)
	# taxation_bumps duration = 240 ticks. Tick to 241.
	var expired = EdictSystem.tick(p, 241)
	expect("taxation_bumps expired after duration", "taxation_bumps" in expired or not EdictSystem.is_active(p, "taxation_bumps"))

func test_edict_get_modifiers_empty() -> void:
	var p = _make_edict_player()
	var mods = EdictSystem.get_active_modifiers(p)
	expect("no modifiers with no active edicts", mods.is_empty())

func test_edict_get_modifiers_stacks() -> void:
	var p = _make_edict_player(20)
	p["tech_unlocks"] = ["royal_edicts", "transport_logistics"]
	EdictSystem.activate(p, "agrarian_subsidies", 0)
	EdictSystem.activate(p, "iron_tariffs", 0)
	var mods = EdictSystem.get_active_modifiers(p)
	expect("agrarian_subsidies modifier present", mods.has("orchard_yield_bonus"))
	expect("iron_tariffs modifier present", mods.has("cart_speed_bonus"))

func test_edict_levy_summons_instant_effects() -> void:
	var p = _make_edict_player(20)
	p["tech_unlocks"] = ["army_logistics"]
	var pop_before = p["population"]
	var pop_before_score = p["popularity"]
	EdictSystem.activate(p, "levy_summons", 0)
	# levy_summons should have instant_effect modifiers for summon_peasants and popularity_delta
	var mods = EdictSystem.lookup("levy_summons").get("modifiers", {})
	expect("levy summons has summon_peasants modifier", mods.has("summon_peasants"))
	expect("levy summons has popularity_delta", mods.has("popularity_delta"))

func test_edict_festival_triggers_event() -> void:
	var defn = EdictSystem.lookup("festival_decree")
	expect("festival_decree has instant_event modifier", defn.get("modifiers", {}).has("instant_event"))
	expect("festival_decree instant_event = festival", defn["modifiers"]["instant_event"] == "festival")

# ============ GameState Phase 5 integration ============

func _init_gs_player_p5() -> void:
	_gs.players.clear()
	_gs.initialize_player(0, "TestLord", 100, 100)
	_gs._grid = null
	_gs._next_building_id = 1
	_sc.current_tick = 0
	_cq.clear()
	if not _gs.world.has("market_prices"):
		from_preload_MarketSystem_initialize_prices()

func from_preload_MarketSystem_initialize_prices() -> void:
	# Call without preload by going through GameState.setup_world won't work (needs grid).
	# Just set a stub market_prices since Phase 5 tests don't need full market.
	_gs.world["market_prices"] = {"wood": 3, "stone": 5, "iron": 8}

func test_gs_prestige_generated_at_day_boundary() -> void:
	_init_gs_player_p5()
	_gs.players[0]["prestige"] = 0.0
	_gs.players[0]["is_starving"] = false
	_gs.players[0]["popularity"] = 60.0
	_gs.players[0]["food"]["apples"] = 50
	# Advance to day boundary
	for _i in range(240):
		_sc._advance_tick()
	expect("prestige generated after 1 game-day", _gs.players[0].get("prestige", 0.0) > 0.0)

func test_gs_tech_tree_unlocks_buildings() -> void:
	_init_gs_player_p5()
	_gs.players[0]["prestige"] = 500.0
	var result = _gs.players[0]
	TechTree.research(result, "crop_tiers")
	expect("crop_tiers in tech_unlocks", "crop_tiers" in _gs.players[0].get("tech_unlocks", []))

func test_gs_activate_edict_via_command() -> void:
	_init_gs_player_p5()
	_gs.players[0]["edict_points"] = 20
	_gs.players[0]["tech_unlocks"] = ["royal_edicts"]
	_cq.enqueue(CT_ACTIVATE_EDICT, {"edict_id": "agrarian_subsidies"}, 0)
	_sc._advance_tick()
	expect("edict active after command", EdictSystem.is_active(_gs.players[0], "agrarian_subsidies"))

func test_gs_donate_to_capital_via_command() -> void:
	_init_gs_player_p5()
	_gs.players[0]["shire_id"] = 0
	_gs.players[0]["resources"]["wood"] = 500
	if _gs.world.get("shires", []).is_empty():
		_gs.world["shires"] = [{"id": 0, "capital_level": 0, "capital_donations": {}}]
	_cq.enqueue(CT_DONATE_TO_CAPITAL, {"resource": "wood", "amount": 100}, 0)
	_sc._advance_tick()
	var shire = _gs.world["shires"][0]
	expect("wood donated to capital", CapitalSystem.get_total_donated(shire, "wood") == 100)
	expect("wood deducted from player", _gs.players[0]["resources"]["wood"] == 400)

func test_gs_save_load_roundtrip() -> void:
	_init_gs_player_p5()
	_gs.players[0]["gold"] = 999
	_gs.players[0]["prestige"] = 123.0
	var state = _gs.serialize()
	SaveManager.save(state, TEST_SAVE_PATH)
	var loaded = SaveManager.load_save(TEST_SAVE_PATH)
	expect("loaded state not empty", not loaded.is_empty())
	var loaded_players = loaded.get("players", [])
	expect("players preserved in save", loaded_players.size() == 1)
	expect("gold preserved", loaded_players[0].get("gold", -1) == 999)
	expect("prestige preserved", absf(loaded_players[0].get("prestige", 0.0) - 123.0) < 0.01)

# ============ Assertion helpers ============

func expect(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  PASS: ", label)
	else:
		_fail += 1
		_errors.append(label)
		print("  FAIL: ", label)
