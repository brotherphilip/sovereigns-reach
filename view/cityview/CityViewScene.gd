extends Node
# City simulation scene. Reads selected_city_id from GameState.world to
# configure seed and starting position. Adds "World Map" return button.
# Replaces GameBootstrap as the runtime entry for city play.

const PLAYER_NAME:          String = "Your Lord"
const DEFAULT_SEED:         int    = 42
const DEFAULT_SHIRE_COUNT:  int    = 4
const DEFAULT_KEEP_X:       int    = 100
const DEFAULT_KEEP_Y:       int    = 100
const STARTING_AREA_RADIUS: int    = 8

const CT_RESEARCH_TECH  = 25
const CT_ACTIVATE_EDICT = 16
const CT_BUY_RESOURCE   = 5
const CT_SELL_RESOURCE  = 6

var _keep_x: int = DEFAULT_KEEP_X
var _keep_y: int = DEFAULT_KEEP_Y
var _map_seed: int = DEFAULT_SEED

var _camera:        Camera2D    = null
var _world_root:    Node2D      = null
var _iso_grid:      Node2D      = null
var _decor_layer:   Node2D      = null
var _bld_layer:     Node2D      = null
var _unit_layer:    Node2D      = null
var _animal_layer:  Node2D      = null
var _citizen_layer: Node2D      = null
var _hud:           CanvasLayer = null
var _macro_view:    CanvasLayer = null
var _input_handler: Node        = null

func _ready() -> void:
	_resolve_city()
	_init_simulation()
	_build_scene()
	_connect_signals()
	# No auto-placed buildings: the player must build a Hall (anywhere free) to begin.
	SimulationClock.set_speed(SimulationClock.SPEED_NORMAL)
	print("[CityView] Game initialized. Player: %s at (%d,%d)" % [PLAYER_NAME, _keep_x, _keep_y])

# ── City resolution ───────────────────────────────────────────────────────────

func _resolve_city() -> void:
	var city_id: int = GameState.world.get("selected_city_id", -1)
	if city_id < 0:
		return
	var city: Dictionary = GameState.get_city(city_id)
	if city.is_empty():
		return
	# Use city position (world map coords 0–1600 × 0–900) mapped to sim grid (0–200)
	# Map: world_x/MAP_WIDTH * grid_width (both default to 200)
	const WM_W: float = 1600.0; const WM_H: float = 900.0
	const SIM_W: float = 200.0; const SIM_H: float = 200.0
	_keep_x = int(clampf(city.get("pos_x", WM_W * 0.5) / WM_W * SIM_W, 10, 190))
	_keep_y = int(clampf(city.get("pos_y", WM_H * 0.5) / WM_H * SIM_H, 10, 190))
	# Each city gets a unique seed based on its id
	_map_seed = DEFAULT_SEED + city.get("id", 0) * 7

# ── Simulation init ───────────────────────────────────────────────────────────

func _init_simulation() -> void:
	GameState.setup_world(_map_seed, DEFAULT_SHIRE_COUNT)
	# No cleared "starting zone": just spawn the player on nearby buildable land so
	# their first Hall can be placed. No terrain is altered.
	_snap_keep_to_buildable()
	GameState.initialize_player(0, PLAYER_NAME, _keep_x, _keep_y)
	var p: Dictionary = GameState.players[0]
	p["gold"]                   = 500
	p["prestige"]               = 0
	p["resources"]["wood"]      = 300
	p["resources"]["stone"]     = 100
	p["resources"]["iron"]      = 50
	p["food"]["apples"]         = 100
	p["population"]             = 50
	GameState.add_ai_faction("bandit_king",   20,  20)
	GameState.add_ai_faction("ashen_barony", 180, 180)

# Move the start position to the nearest buildable (grass/valley) tile so the
# player's first Hall can be placed there — without clearing any terrain.
func _snap_keep_to_buildable() -> void:
	const GRASS := 0
	const VALLEY := 7
	if GameState.get_terrain_at(_keep_x, _keep_y) in [GRASS, VALLEY]:
		return
	for radius in range(1, 40):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue   # ring only
				var x: int = _keep_x + dx
				var y: int = _keep_y + dy
				if GameState.grid_in_bounds(x, y) and GameState.get_terrain_at(x, y) in [GRASS, VALLEY]:
					_keep_x = x
					_keep_y = y
					return

# ── Scene tree ────────────────────────────────────────────────────────────────

func _build_scene() -> void:
	_camera = preload("res://view/micro/CameraController.gd").new()
	_camera.name     = "Camera"
	_camera.position = _iso_origin(_keep_x, _keep_y)
	add_child(_camera)

	_world_root = Node2D.new()
	_world_root.name = "WorldRoot"
	add_child(_world_root)

	_iso_grid = preload("res://view/micro/IsometricGrid.gd").new()
	_iso_grid.name = "IsometricGrid"
	_world_root.add_child(_iso_grid)
	_iso_grid.set_camera(_camera)

	# Terrain decoration layer (trees, rocks, water ripples)
	_decor_layer = preload("res://view/micro/TerrainDecorationLayer.gd").new()
	_decor_layer.name = "DecorationLayer"
	_world_root.add_child(_decor_layer)
	_decor_layer.set_camera(_camera)

	_bld_layer = preload("res://view/micro/BuildingLayer.gd").new()
	_bld_layer.name = "BuildingLayer"
	_world_root.add_child(_bld_layer)

	_unit_layer = preload("res://view/micro/UnitLayer.gd").new()
	_unit_layer.name = "UnitLayer"
	_world_root.add_child(_unit_layer)

	_animal_layer = preload("res://view/micro/AnimalLayer.gd").new()
	_animal_layer.name = "AnimalLayer"
	_world_root.add_child(_animal_layer)

	_citizen_layer = preload("res://view/micro/CitizenLayer.gd").new()
	_citizen_layer.name = "CitizenLayer"
	_world_root.add_child(_citizen_layer)

	_hud = preload("res://view/hud/HUDNode.gd").new()
	_hud.name  = "HUD"
	_hud.layer = 10
	add_child(_hud)

	_add_minimap()

	_macro_view = CanvasLayer.new()
	_macro_view.name  = "MacroView"
	_macro_view.layer = 5
	add_child(_macro_view)
	var macro_ctrl := preload("res://view/macro/MacroMapView.gd").new()
	macro_ctrl.name = "MacroMapControl"
	macro_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	macro_ctrl.visible = false
	_macro_view.add_child(macro_ctrl)

	_input_handler = preload("res://view/main/PlayerInputHandler.gd").new()
	_input_handler.name = "InputHandler"
	add_child(_input_handler)
	_input_handler.setup(_iso_grid, _camera, _unit_layer)
	_input_handler.set_building_layer(_bld_layer)
	_input_handler.set_animal_layer(_animal_layer)

	# "World Map" return button (added to a small persistent overlay)
	_add_world_map_button()

func _add_minimap() -> void:
	var overlay := CanvasLayer.new()
	overlay.name  = "MinimapLayer"
	overlay.layer = 9
	add_child(overlay)
	var minimap := preload("res://view/micro/Minimap.gd").new()
	minimap.name = "Minimap"
	minimap.position = Vector2(4, 4)
	minimap.set_camera(_camera)
	overlay.add_child(minimap)

func _add_world_map_button() -> void:
	var overlay := CanvasLayer.new()
	overlay.name  = "WorldMapOverlay"
	overlay.layer = 8
	add_child(overlay)
	var btn := Button.new()
	btn.text     = "World Map"
	btn.position = Vector2(4, 200)
	btn.size     = Vector2(90, 28)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(_on_return_to_world_map)
	overlay.add_child(btn)

func _iso_origin(gx: int, gy: int) -> Vector2:
	return Vector2((gx - gy) * 32.0, (gx + gy) * 16.0)

# ── Signal wiring ─────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	_hud.build_requested.connect(_input_handler.enter_build_mode)
	_hud.tax_changed.connect(_input_handler.set_tax_rate)
	_hud.food_ration_changed.connect(_input_handler.set_food_ration)
	_hud.ale_ration_changed.connect(_input_handler.set_ale_ration)
	_hud.speed_changed.connect(_input_handler.set_game_speed)
	_hud.save_requested.connect(_input_handler.save_game)
	_hud.recruit_requested.connect(_input_handler.recruit_unit)
	_hud.macro_view_toggled.connect(_toggle_macro_view)
	_hud.tech_research_requested.connect(_on_research_tech)
	_hud.edict_activate_requested.connect(_on_activate_edict)
	_hud.trade_buy_requested.connect(_on_trade_buy)
	_hud.trade_sell_requested.connect(_on_trade_sell)

	_input_handler.build_mode_changed.connect(_hud.set_build_mode_display)
	_input_handler.placement_failed.connect(func(r): _hud.show_notification("Cannot build: " + r))
	_input_handler.entity_selected.connect(_on_entity_selected)
	_input_handler.entity_deselected.connect(func(): _hud.clear_selection())

	EventBus.weather_changed.connect(func(name, _d): _hud.show_notification("Weather: " + name, 4.0))
	EventBus.building_placement_failed.connect(func(_p, _b, _gx, _gy, reason): _hud.show_notification(reason, 3.0))
	EventBus.ai_siege_assembling.connect(func(fid, _tpid, eta): _hud.show_notification("⚠ AI faction %d assembling siege! ETA: %d ticks" % [fid, eta], 6.0))
	EventBus.unit_killed.connect(_on_unit_killed)
	EventBus.building_destroyed.connect(_on_building_destroyed)
	EventBus.ai_faction_defeated.connect(_on_ai_faction_defeated)
	EventBus.popularity_changed.connect(_on_popularity_changed)
	EventBus.edict_activated.connect(func(_pid, eid, _d): _hud.show_notification("Edict in effect: " + eid, 3.0))
	EventBus.edict_expired.connect(func(_pid, eid): _hud.show_notification("Edict expired: " + eid, 3.0))
	EventBus.save_requested.connect(_do_save)
	EventBus.load_requested.connect(_do_load)

	set_process_input(true)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_toggle_macro_view()
		get_viewport().set_input_as_handled()

func _toggle_macro_view() -> void:
	var ctrl := _macro_view.get_node_or_null("MacroMapControl")
	if ctrl: ctrl.visible = not ctrl.visible

func _on_entity_selected(entity_type: String, entity_data: Dictionary) -> void:
	match entity_type:
		"building": _hud.show_selected_building(entity_data)
		"unit":     _hud.show_selected_unit(entity_data)

func _on_research_tech(tech_id: String) -> void:
	CommandQueue.enqueue(CT_RESEARCH_TECH, {"tech_id": tech_id}, 0)
	_hud.show_notification("Researching: " + tech_id, 3.0)

func _on_activate_edict(edict_id: String) -> void:
	CommandQueue.enqueue(CT_ACTIVATE_EDICT, {"edict_id": edict_id}, 0)
	_hud.show_notification("Edict activated: " + edict_id, 3.0)

func _on_trade_buy(resource: String, amount: int) -> void:
	CommandQueue.enqueue(CT_BUY_RESOURCE, {"resource": resource, "amount": amount}, 0)
	_hud.show_notification("Bought %d %s" % [amount, resource], 2.0)

func _on_trade_sell(resource: String, amount: int) -> void:
	CommandQueue.enqueue(CT_SELL_RESOURCE, {"resource": resource, "amount": amount}, 0)
	_hud.show_notification("Sold %d %s" % [amount, resource], 2.0)

# ── Navigation ────────────────────────────────────────────────────────────────

func _on_return_to_world_map() -> void:
	SimulationClock.set_speed(SimulationClock.SPEED_PAUSED)
	get_tree().change_scene_to_file("res://view/worldmap/WorldMapScene.tscn")

# ── Combat / win-loss handlers ────────────────────────────────────────────────

func _on_unit_killed(unit_id: int, _killer_id: int, cause: String) -> void:
	if GameState.players.size() == 0: return
	for unit in GameState.players[0].get("units", []):
		if unit is Dictionary and unit.get("id", -1) == unit_id:
			_hud.show_notification("Unit lost: %s (%s)" % [unit.get("type", "?"), cause], 3.0)
			return

func _on_building_destroyed(player_id: int, building_id: int, _cause: String) -> void:
	if player_id != 0 or GameState.players.size() == 0: return
	for bld in GameState.players[0].get("buildings", []):
		if bld is Dictionary and bld.get("id", -1) == building_id:
			var btype: String = bld.get("type", "")
			_hud.show_notification("Building destroyed: %s!" % btype, 4.0)
			if btype == "village_hall" or btype == "keep":
				_show_game_over(false, "Your keep has fallen! The realm is lost.")
			return

func _on_ai_faction_defeated(faction_id: int) -> void:
	_hud.show_notification("Enemy faction %d has been defeated!" % faction_id, 5.0)
	var all_dead: bool = true
	for fac in GameState.ai_factions:
		if fac is Dictionary and fac.get("is_alive", true):
			all_dead = false; break
	if all_dead and GameState.ai_factions.size() > 0:
		_show_game_over(true, "All enemies vanquished! Sovereign's Reach is yours!")

func _on_popularity_changed(_pid: int, _old: float, new_val: float) -> void:
	if new_val < 10.0:
		_show_game_over(false, "The people have revolted! Your reign is over.")

var _game_over_shown: bool = false

func _show_game_over(victory: bool, message: String) -> void:
	if _game_over_shown: return
	_game_over_shown = true
	SimulationClock.set_speed(0)

	var overlay := CanvasLayer.new()
	overlay.name  = "GameOverOverlay"
	overlay.layer = 20
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2(340, 220)
	panel.size     = Vector2(600, 260)
	var style := StyleBoxFlat.new()
	style.bg_color         = Color(0.10, 0.12, 0.16, 0.98)
	style.set_border_width_all(2)
	style.border_color     = Color.GOLD if victory else Color.DARK_RED
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)

	var title := Label.new()
	title.text = "VICTORY!" if victory else "DEFEAT"
	title.position = Vector2(20, 20); title.size = Vector2(560, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color.GOLD if victory else Color.ORANGE_RED)
	panel.add_child(title)

	var msg := Label.new()
	msg.text = message; msg.position = Vector2(20, 80); msg.size = Vector2(560, 80)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 16)
	msg.add_theme_color_override("font_color", Color.WHITE_SMOKE)
	panel.add_child(msg)

	var day_lbl := Label.new()
	day_lbl.text = "Day %d reached." % SimulationClock.game_day()
	day_lbl.position = Vector2(20, 160); day_lbl.size = Vector2(560, 24)
	day_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_lbl.add_theme_font_size_override("font_size", 13)
	day_lbl.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	panel.add_child(day_lbl)

	var restart_btn := Button.new()
	restart_btn.text = "Play Again"; restart_btn.position = Vector2(80, 200)
	restart_btn.size = Vector2(140, 40)
	restart_btn.add_theme_font_size_override("font_size", 14)
	restart_btn.pressed.connect(func(): get_tree().reload_current_scene())
	panel.add_child(restart_btn)

	var map_btn := Button.new()
	map_btn.text = "World Map"; map_btn.position = Vector2(240, 200)
	map_btn.size = Vector2(140, 40)
	map_btn.add_theme_font_size_override("font_size", 14)
	map_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://view/worldmap/WorldMapScene.tscn"))
	panel.add_child(map_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Main Menu"; quit_btn.position = Vector2(400, 200)
	quit_btn.size = Vector2(120, 40)
	quit_btn.add_theme_font_size_override("font_size", 14)
	quit_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://view/menu/MainMenuScene.tscn"))
	panel.add_child(quit_btn)

# ── Starting buildings ────────────────────────────────────────────────────────

func _place_starting_buildings() -> void:
	var kx: int = _keep_x; var ky: int = _keep_y
	_force_place("village_hall", kx - 1, ky - 1)
	_force_place("hovel", kx + 2, ky - 1)
	_force_place("hovel", kx + 2, ky)
	_force_place("hovel", kx + 2, ky + 1)
	_force_place("hovel", kx - 2, ky - 1)
	_force_place("hovel", kx - 2, ky)
	_force_place("apple_orchard", kx + 4, ky)
	_auto_assign_workers()

func _force_place(btype: String, gx: int, gy: int) -> void:
	if not GameState.grid_in_bounds(gx, gy): return
	GameState.prepare_starting_area(gx, gy, 2)
	var player: Dictionary = GameState.players[0]
	var sw: int = player["resources"].get("wood", 0)
	var ss: int = player["resources"].get("stone", 0)
	var sg: int = player.get("gold", 0)
	player["resources"]["wood"]  = 9999
	player["resources"]["stone"] = 9999
	player["gold"]               = 9999
	CommandQueue.enqueue(7, {"building_type": btype, "grid_x": gx, "grid_y": gy}, 0)
	SimulationClock._advance_tick()
	player["resources"]["wood"]  = sw
	player["resources"]["stone"] = ss
	player["gold"]               = sg

func _auto_assign_workers() -> void:
	if GameState.players.size() == 0: return
	const WorkerSystem = preload("res://simulation/player/WorkerSystem.gd")
	WorkerSystem.auto_assign(GameState.players[0])

# ── Persistence ────────────────────────────────────────────────────────────────

func _do_save() -> void:
	const SM = preload("res://simulation/persistence/SaveManager.gd")
	const DiffSystem = preload("res://simulation/core/DifficultySystem.gd")
	var state: Dictionary = GameState.serialize()
	var p: Dictionary = GameState.players[0] if GameState.players.size() > 0 else {}
	var meta: Dictionary = {
		"game_day": SimulationClock.game_day(),
		"shire_count": p.get("shire_ids", []).size(),
		"difficulty": DiffSystem.level_name(DiffSystem.current),
	}
	var ok: bool = SM.save(state, SM.DEFAULT_SAVE_PATH, meta)
	if ok:
		_hud.show_notification("Game saved!", 2.0)
		EventBus.save_completed.emit(SM.DEFAULT_SAVE_PATH)
	else:
		_hud.show_notification("Save failed!", 2.0)

func _do_load(path: String) -> void:
	const SM = preload("res://simulation/persistence/SaveManager.gd")
	var data: Dictionary = SM.load_save(path)
	if data.is_empty():
		EventBus.load_completed.emit(false)
		return
	GameState.deserialize(data)
	EventBus.load_completed.emit(true)
	_hud.show_notification("Game loaded!", 2.0)
