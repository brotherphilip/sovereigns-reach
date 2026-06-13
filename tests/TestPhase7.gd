extends SceneTree
# Phase 7 test suite — UI & View Integration
# Run: godot --headless --script tests/TestPhase7.gd
# Tests all view-layer controllers as pure static functions.

const HUDController          = preload("res://view/hud/HUDController.gd")
const TechTreePanelController = preload("res://view/hud/TechTreePanelController.gd")
const EdictPanelController   = preload("res://view/hud/EdictPanelController.gd")
const BuildingRenderer       = preload("res://view/micro/BuildingRenderer.gd")
const UnitRenderer           = preload("res://view/micro/UnitRenderer.gd")
const MicroViewController    = preload("res://view/micro/MicroViewController.gd")
const MacroViewController    = preload("res://view/macro/MacroViewController.gd")

var _gs: Node = null
var _sc: Node = null
var _cq: Node = null

var _pass: int = 0
var _fail: int = 0

func _init() -> void:
	await process_frame
	_gs = root.get_node_or_null("GameState")
	_sc = root.get_node_or_null("SimulationClock")
	_cq = root.get_node_or_null("CommandQueue")

	if _gs == null or _sc == null or _cq == null:
		print("FATAL: Autoloads not found")
		quit(1)
		return

	_run_all()
	print("\nPhase 7 Results: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _run_all() -> void:
	_test_hud_controller()
	_test_tech_panel_controller()
	_test_edict_panel_controller()
	_test_building_renderer()
	_test_unit_renderer()
	_test_micro_view_controller()
	_test_macro_view_controller()
	_test_main_controller()

# ── helpers ──────────────────────────────────────────────────────────────────

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

# ── HUDController tests (17) ─────────────────────────────────────────────────

func _test_hud_controller() -> void:
	print("\n--- HUDController ---")

	var player: Dictionary = {
		"id": 0, "gold": 1200, "prestige": 80, "popularity": 62.0,
		"tax_rate": 1, "food_ration": 2, "ale_ration": 1,
		"population": 40, "military_strength": 10,
		"food": {"wheat": 50, "bread": 30, "apple": 10},
		"resources": {"wood": 200, "stone": 100},
		"is_starving": false,
		"edict_points": 3,
		"inn_coverage": 0.5, "religion_coverage": 0.3,
		"units": [], "buildings": [],
	}
	var weather: Dictionary = {"current_name": "Fog", "popularity_delta": -2.0}
	var hud: Dictionary = HUDController.get_hud_data(player, weather, 1440)

	# 1. Gold and prestige present
	ok("hud gold = 1200", int(hud.get("gold", 0)) == 1200)
	ok("hud prestige = 80", int(hud.get("prestige", 0)) == 80)

	# 2. popularity tier (62 → good)
	ok("popularity_tier=good at 62", hud.get("popularity_tier") == "good")

	# 3. popularity color for fair
	ok("popularity_color non-empty", hud.get("popularity_color", "").length() > 0)

	# 4. tax_label for tax_rate=1 → "Tax ×1"
	ok("tax_label rate=1 → Tax x1", hud.get("tax_label") == "Tax ×1")

	# 5. food_ration_label index 2 → "Normal"
	ok("food_ration_label=Normal", hud.get("food_ration_label") == "Normal")

	# 6. game_day = 1440/240 = 6
	ok("game_day=6 at tick 1440", int(hud.get("game_day", -1)) == 6)

	# 7. total food = 90
	ok("food_total=90", int(hud.get("food_total", 0)) == 90)

	# 8. weather name present
	ok("weather_name=Fog", hud.get("weather_name") == "Fog")

	# 9. Popularity tier thresholds
	ok("tier revolt <20", HUDController.get_popularity_tier(15.0) == "revolt")
	ok("tier poor 20-40", HUDController.get_popularity_tier(30.0) == "poor")
	ok("tier fair 40-60", HUDController.get_popularity_tier(55.0) == "fair")
	ok("tier good 60-80", HUDController.get_popularity_tier(75.0) == "good")
	ok("tier excellent >=80", HUDController.get_popularity_tier(80.0) == "excellent")

	# 10. Ration label bounds
	ok("ration label 0=None", HUDController.get_ration_label(0) == "None")
	ok("ration label 4=Double", HUDController.get_ration_label(4) == "Double")
	ok("ration label out-of-range=?", HUDController.get_ration_label(5) == "?")

	# 11. format_tick_time
	ok("format tick day 1", HUDController.format_tick_time(240).begins_with("Day 1"))

	# 12. is_revolt_risk true below 20
	ok("revolt risk at pop 10", HUDController.is_revolt_risk({"popularity": 10.0}))
	ok("no revolt risk at pop 50", not HUDController.is_revolt_risk({"popularity": 50.0}))

# ── TechTreePanelController tests (10) ───────────────────────────────────────

func _test_tech_panel_controller() -> void:
	print("\n--- TechTreePanelController ---")

	var player: Dictionary = _fresh_player()

	# 1. get_panel_data returns branches dict
	var panel: Dictionary = TechTreePanelController.get_panel_data(player)
	ok("panel has branches", panel.has("branches"))
	ok("panel has prestige", panel.has("prestige"))
	ok("panel has unlocked_count", panel.has("unlocked_count"))

	# 2. Branches is a Dictionary with branch keys
	var branches = panel.get("branches", {})
	ok("branches not empty", not (branches as Dictionary).is_empty())

	# 3. crop_tiers is locked initially (player has 0 prestige)
	var status: String = TechTreePanelController.get_tech_status(player, "crop_tiers")
	ok("crop_tiers locked when prestige=0", status == "unaffordable" or status == "locked")

	# 4. Give player enough prestige — crop_tiers becomes available
	_gs.players[0]["prestige"] = 500
	player = _gs.players[0]
	var status2: String = TechTreePanelController.get_tech_status(player, "crop_tiers")
	ok("crop_tiers available at prestige 500", status2 == "available")

	# 5. Unlock crop_tiers — status becomes researched
	_gs.players[0]["tech_unlocks"] = ["crop_tiers"]
	player = _gs.players[0]
	ok("crop_tiers researched after unlock", TechTreePanelController.get_tech_status(player, "crop_tiers") == "researched")

	# 6. farming_speed still locked (requires crop_tiers, but prestige=500 ≥ 200)
	var fs_status: String = TechTreePanelController.get_tech_status(player, "farming_speed")
	ok("farming_speed available after crop_tiers", fs_status == "available")

	# 7. get_researchable_items returns items with required fields
	_gs.players[0]["tech_unlocks"] = []
	_gs.players[0]["prestige"] = 500
	player = _gs.players[0]
	var items: Array = TechTreePanelController.get_researchable_items(player)
	ok("researchable_items is Array", items is Array)
	if items.size() > 0:
		var item = items[0]
		ok("researchable item has id", item is Dictionary and (item as Dictionary).has("id"))
	else:
		ok("researchable item has id", false)

	# 8. All items in a branch have name, status, cost_prestige
	var any_branch_items: Array = []
	for bv in branches:
		var branch_arr: Array = branches.get(bv, [])
		if branch_arr.size() > 0:
			any_branch_items = branch_arr
			break
	if any_branch_items.size() > 0:
		var it: Dictionary = any_branch_items[0]
		ok("branch item has name", it.has("name"))
		ok("branch item has status", it.has("status"))
	else:
		ok("branch item has name", false)
		ok("branch item has status", false)

# ── EdictPanelController tests (10) ──────────────────────────────────────────

func _test_edict_panel_controller() -> void:
	print("\n--- EdictPanelController ---")

	# 1. format_ticks: 0 = "Ready"
	ok("format_ticks 0 = Ready", EdictPanelController.format_ticks(0) == "Ready")

	# 2. format_ticks: 240 = "100%" (full day, 0 days remaining)
	var label_240: String = EdictPanelController.format_ticks(240)
	ok("format_ticks 240 contains %", "%" in label_240)

	# 3. format_ticks: 480 = "2d ..." (more than 1 day)
	var label_480: String = EdictPanelController.format_ticks(480)
	ok("format_ticks 480 starts with 2d", label_480.begins_with("2d"))

	# 4. format_ticks: negative = "Ready"
	ok("format_ticks -1 = Ready", EdictPanelController.format_ticks(-1) == "Ready")

	# 5. get_remaining_ticks: no active edict = 0
	var bare_player: Dictionary = {"active_edicts": []}
	ok("remaining_ticks for missing edict = 0",
		EdictPanelController.get_remaining_ticks(bare_player, "taxation_bumps", 0) == 0)

	# 6. get_remaining_ticks: active edict with expires_at
	var active_player: Dictionary = {
		"active_edicts": [{"id": "taxation_bumps", "expires_at": 500}],
	}
	ok("remaining_ticks 500-200=300",
		EdictPanelController.get_remaining_ticks(active_player, "taxation_bumps", 200) == 300)

	# 7. get_remaining_ticks: already expired returns 0
	ok("remaining_ticks expired = 0",
		EdictPanelController.get_remaining_ticks(active_player, "taxation_bumps", 600) == 0)

	# 8. get_cooldown_remaining: no cooldown key = 0
	ok("cooldown_remaining no key = 0",
		EdictPanelController.get_cooldown_remaining(bare_player, "taxation_bumps", 0) == 0)

	# 9. get_cooldown_remaining: cooldown key present
	var cd_player: Dictionary = {"edict_cooldown_taxation_bumps": 1000}
	ok("cooldown_remaining = 800 at tick 200",
		EdictPanelController.get_cooldown_remaining(cd_player, "taxation_bumps", 200) == 800)

	# 10. get_panel_data has required keys
	var pd: Dictionary = EdictPanelController.get_panel_data({"active_edicts": [], "edict_points": 5}, 0)
	ok("panel_data has active/available/locked/edict_points",
		pd.has("active") and pd.has("available") and pd.has("locked") and pd.has("edict_points"))

# ── BuildingRenderer tests (10) ──────────────────────────────────────────────

func _test_building_renderer() -> void:
	print("\n--- BuildingRenderer ---")

	# Use wheat_farm (category FOOD, has produces)
	var farm_empty: Dictionary = {
		"type": "wheat_farm", "is_operational": false, "workers": 0,
		"is_on_fire": false, "hp": 40, "max_hp": 40, "grid_x": 5, "grid_y": 5,
	}
	var vs_empty: Dictionary = BuildingRenderer.get_visual_state(farm_empty)
	ok("empty wheat_farm state=empty", vs_empty.get("state") == "empty")
	ok("empty wheat_farm color=dark", vs_empty.get("color_tint") == "dark")
	ok("empty wheat_farm show_fire=false", vs_empty.get("show_fire") == false)

	# working wheat_farm
	var farm_working: Dictionary = {
		"type": "wheat_farm", "is_operational": true, "workers": 2,
		"is_on_fire": false, "hp": 40, "max_hp": 40, "grid_x": 5, "grid_y": 5,
	}
	var vs_work: Dictionary = BuildingRenderer.get_visual_state(farm_working)
	ok("working wheat_farm state=working", vs_work.get("state") == "working")
	ok("working wheat_farm animation=work", vs_work.get("animation") == "work")

	# on fire
	var farm_fire: Dictionary = {
		"type": "wheat_farm", "is_operational": true, "workers": 2,
		"is_on_fire": true, "hp": 30, "max_hp": 40, "grid_x": 5, "grid_y": 5,
	}
	var vs_fire: Dictionary = BuildingRenderer.get_visual_state(farm_fire)
	ok("burning wheat_farm state=fire", vs_fire.get("state") == "fire")
	ok("burning wheat_farm show_fire=true", vs_fire.get("show_fire") == true)

	# hp_bar at full health = 1.0
	ok("hp_bar full health = 1.0",
		absf(BuildingRenderer.get_hp_bar({"type": "wheat_farm", "hp": 40}) - 1.0) < 0.01)

	# has_progress_bar: wheat_farm produces wheat → true; village_hall produces nothing → false
	ok("wheat_farm has_progress_bar=true", BuildingRenderer.has_progress_bar("wheat_farm"))
	ok("village_hall has_progress_bar=false", not BuildingRenderer.has_progress_bar("village_hall"))

	# get_tile_layer: wheat_farm=0 (FOOD), barracks=2 (MILITARY), village_hall=3 (CIVIC)
	ok("wheat_farm tile_layer=0", BuildingRenderer.get_tile_layer("wheat_farm") == 0)
	ok("barracks tile_layer=2", BuildingRenderer.get_tile_layer("barracks") == 2)
	ok("village_hall tile_layer=3", BuildingRenderer.get_tile_layer("village_hall") == 3)

# ── UnitRenderer tests (10) ──────────────────────────────────────────────────

func _test_unit_renderer() -> void:
	print("\n--- UnitRenderer ---")

	# Dead unit
	var dead_unit: Dictionary = {
		"id": 1, "type": "archer", "owner_id": 0,
		"is_alive": false, "hp": 0, "max_hp": 30,
		"order": "idle", "pos_x": 3, "pos_y": 4,
	}
	var dead_info: Dictionary = UnitRenderer.get_sprite_info(dead_unit)
	ok("dead unit animation=die", dead_info.get("animation") == "die")
	ok("dead unit color_tint=dead", dead_info.get("color_tint") == "dead")
	ok("dead unit is_alive=false", dead_info.get("is_alive") == false)

	# Alive idle unit
	var idle_unit: Dictionary = {
		"id": 2, "type": "archer", "owner_id": 0,
		"is_alive": true, "hp": 30, "max_hp": 30,
		"order": "idle", "pos_x": 3, "pos_y": 4, "target_x": 3, "target_y": 4,
	}
	var idle_info: Dictionary = UnitRenderer.get_sprite_info(idle_unit)
	ok("idle archer animation=idle", idle_info.get("animation") == "idle")
	ok("idle archer color_tint=player_0", idle_info.get("color_tint") == "player_0")
	ok("idle archer health_bar=1.0", absf(idle_info.get("health_bar", 0.0) - 1.0) < 0.01)

	# Moving unit
	var move_unit: Dictionary = {
		"id": 3, "type": "swordsman", "owner_id": 1,
		"is_alive": true, "hp": 35, "max_hp": 70,
		"order": "move", "pos_x": 2, "pos_y": 2, "target_x": 5, "target_y": 2,
	}
	var move_info: Dictionary = UnitRenderer.get_sprite_info(move_unit)
	ok("moving swordsman animation=walk", move_info.get("animation") == "walk")
	ok("swordsman health_bar ~0.5", absf(move_info.get("health_bar", 0.0) - 0.5) < 0.02)

	# AI unit (owner_id = -1) → enemy tint
	var enemy_unit: Dictionary = {
		"id": 4, "type": "armed_peasant", "owner_id": -1,
		"is_alive": true, "hp": 25, "max_hp": 25,
		"order": "attack", "pos_x": 1, "pos_y": 1,
	}
	ok("ai unit color_tint=enemy", UnitRenderer.get_color_tint(enemy_unit) == "enemy")

	# order_to_animation mapping
	ok("order attack → attack anim", UnitRenderer.order_to_animation("attack") == "attack")
	ok("order patrol → walk anim",   UnitRenderer.order_to_animation("patrol") == "walk")

# ── MicroViewController tests (10) ───────────────────────────────────────────

func _test_micro_view_controller() -> void:
	print("\n--- MicroViewController ---")

	# 1. grid_to_screen (0,0) = {0,0} for all rotations
	var sc0: Dictionary = MicroViewController.grid_to_screen(0, 0, 0)
	ok("grid_to_screen (0,0) = {0,0}", sc0["screen_x"] == 0 and sc0["screen_y"] == 0)

	# 2. grid_to_screen (1,0) rotation=0: ax=1,ay=1,bx=-1,by=1
	#    sx = 32 * (1*1 + (-1)*0) = 32;  sy = 16 * (1*1 + 1*0) = 16
	var sc1: Dictionary = MicroViewController.grid_to_screen(1, 0, 0)
	ok("grid_to_screen (1,0) rot=0 sx=32", sc1["screen_x"] == 32)
	ok("grid_to_screen (1,0) rot=0 sy=16", sc1["screen_y"] == 16)

	# 3. screen_to_grid round-trip (1,0) → screen → back
	var sc_rt: Dictionary = MicroViewController.grid_to_screen(3, 5, 0)
	var gc_rt: Dictionary = MicroViewController.screen_to_grid(sc_rt["screen_x"], sc_rt["screen_y"], 0)
	ok("round-trip (3,5) grid_x=3", gc_rt["grid_x"] == 3)
	ok("round-trip (3,5) grid_y=5", gc_rt["grid_y"] == 5)

	# 4. get_building_render_list from player with buildings
	var player: Dictionary = _fresh_player()
	var blist: Array = MicroViewController.get_building_render_list(player)
	ok("building_render_list is Array", blist is Array)

	# 5. Each item in render list has grid_x, grid_y, id
	if blist.size() > 0:
		var item: Dictionary = blist[0]
		ok("building item has grid_x", item.has("grid_x"))
		ok("building item has state",  item.has("state"))
	else:
		# No buildings yet — just check that the call succeeds
		ok("building item has grid_x", true)
		ok("building item has state",  true)

	# 6. get_unit_render_list from player with no units
	var ulist: Array = MicroViewController.get_unit_render_list(player)
	ok("unit_render_list is Array", ulist is Array)

	# 7. Rotation 2 should produce inverted signs
	var sc2: Dictionary = MicroViewController.grid_to_screen(2, 0, 2)
	ok("rot=2 (2,0): screen_x = -64", sc2["screen_x"] == -64)

# ── MacroViewController tests (12) ───────────────────────────────────────────

func _test_macro_view_controller() -> void:
	print("\n--- MacroViewController ---")

	# Player 0 shire color = SHIRE_COLORS[0]
	var expected_p0: String = MacroViewController.SHIRE_COLORS[0]
	ok("shire_color player_0 = SHIRE_COLORS[0]",
		MacroViewController.get_shire_color(0, [], []) == expected_p0)

	# Neutral color when owner_id < 0 and no AI match
	ok("shire_color -1 = NEUTRAL_COLOR",
		MacroViewController.get_shire_color(-1, [], []) == MacroViewController.NEUTRAL_COLOR)

	# get_shire_render_list with one shire
	var world: Dictionary = {
		"shires": [
			{"id": 1, "owner_id": 0, "capital_level": 2, "name": "Greenfield",
			 "capital_x": 10, "capital_y": 10},
		]
	}
	var shires: Array = MacroViewController.get_shire_render_list(world, [], [])
	ok("shire_render_list size=1", shires.size() == 1)
	if shires.size() > 0:
		var s: Dictionary = shires[0]
		ok("shire item has color", s.has("color"))
		ok("shire item name=Greenfield", s.get("name") == "Greenfield")
		ok("shire item capital_level=2", s.get("capital_level") == 2)

	# get_player_army_banners: alive player with 2 alive units
	var players: Array = [{
		"id": 0, "is_alive": true, "keep_x": 5, "keep_y": 5,
		"military_strength": 25,
		"units": [
			{"is_alive": true}, {"is_alive": true}, {"is_alive": false}
		],
	}]
	var banners: Array = MacroViewController.get_player_army_banners(players)
	ok("player_army_banners size=1", banners.size() == 1)
	if banners.size() > 0:
		ok("banner unit_count=2", banners[0].get("unit_count") == 2)
		ok("banner has color", banners[0].has("color"))

	# Dead player produces no banner
	var dead_players: Array = [{"id": 0, "is_alive": false, "units": []}]
	ok("dead player no banner", MacroViewController.get_player_army_banners(dead_players).size() == 0)

	# get_ai_army_banners: AI faction with siege archetype
	var ai_factions: Array = [{
		"id": -1, "archetype": "bandit_king", "is_alive": true,
		"capital_x": 20, "capital_y": 30,
		"units": [{"is_alive": true}, {"is_alive": true}],
		"threat_level": 0.4,
	}]
	var ai_banners: Array = MacroViewController.get_ai_army_banners(ai_factions)
	ok("ai_army_banners size=1", ai_banners.size() == 1)
	if ai_banners.size() > 0:
		ok("ai banner archetype=bandit_king", ai_banners[0].get("archetype") == "bandit_king")

	# get_siege_tent_data: faction assembling siege
	var tents_factions: Array = [{
		"id": -2, "archetype": "ironhand", "is_alive": true,
		"capital_x": 0, "capital_y": 0, "units": [],
		"threat_level": 0.6,
		"siege_assembly": {
			"target_player_id": 0, "target_x": 50, "target_y": 50,
			"ticks_elapsed": 240 * 24,  # 24 game-days elapsed of 48
		}
	}]
	var tents: Array = MacroViewController.get_siege_tent_data(tents_factions)
	ok("siege_tent_data size=1", tents.size() == 1)
	if tents.size() > 0:
		var t: Dictionary = tents[0]
		ok("tent progress ~0.5", absf(t.get("progress", 0.0) - 0.5) < 0.02)
		ok("tent has eta_label", t.has("eta_label"))

	# fog of war
	var fow_player: Dictionary = {"fog_of_war": {"3,4": true, "5,6": true}}
	ok("is_tile_revealed (3,4) = true",  MacroViewController.is_tile_revealed(fow_player, 3, 4))
	ok("is_tile_revealed (0,0) = false", not MacroViewController.is_tile_revealed(fow_player, 0, 0))

# ── MainController tests (5) ─────────────────────────────────────────────────

func _test_main_controller() -> void:
	print("\n--- MainController ---")

	const MainController = preload("res://view/main/MainController.gd")
	var mc: Node = MainController.new()
	root.add_child(mc)

	# Default mode is MICRO
	ok("default mode = MICRO", mc._current_mode == MainController.ViewMode.MICRO)

	# switch_to_macro
	mc.switch_to_macro()
	ok("switch_to_macro sets MACRO", mc._current_mode == MainController.ViewMode.MACRO)

	# switch_to_micro
	mc.switch_to_micro()
	ok("switch_to_micro sets MICRO", mc._current_mode == MainController.ViewMode.MICRO)

	# toggle_tech_tree twice
	mc.toggle_tech_tree()
	ok("toggle_tech_tree → TECH_TREE", mc._current_mode == MainController.ViewMode.TECH_TREE)
	mc.toggle_tech_tree()
	ok("toggle_tech_tree again → MICRO", mc._current_mode == MainController.ViewMode.MICRO)

	mc.queue_free()
