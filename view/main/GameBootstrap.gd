extends Node
# Scene assembler and game initializer.
# Builds the entire scene tree in code, initializes simulation, connects all signals.
# Runs on Main.tscn node ready.

const PLAYER_NAME:   String = "Your Lord"
const MAP_SEED:      int    = 42
const SHIRE_COUNT:   int    = 4
const KEEP_X:        int    = 100
const KEEP_Y:        int    = 100
const STARTING_AREA_RADIUS: int = 8

# Command type constants
const CT_RESEARCH_TECH   = 25
const CT_ACTIVATE_EDICT  = 16
const CT_BUY_RESOURCE    = 5
const CT_SELL_RESOURCE   = 6

# Child node references
var _camera:      Camera2D      = null
var _world_root:  Node2D        = null
var _iso_grid:    Node2D        = null
var _bld_layer:   Node2D        = null
var _unit_layer:  Node2D        = null
var _hud:         CanvasLayer   = null
var _macro_view:  CanvasLayer   = null
var _input_handler: Node        = null

func _ready() -> void:
	_init_simulation()
	_build_scene()
	_connect_signals()
	_place_starting_buildings()
	SimulationClock.set_speed(SimulationClock.SPEED_NORMAL)
	print("[Bootstrap] Game initialized. Player: %s at (%d,%d)" % [PLAYER_NAME, KEEP_X, KEEP_Y])

# ── Simulation initialization ─────────────────────────────────────────────────

func _init_simulation() -> void:
	# Set up world
	GameState.setup_world(MAP_SEED, SHIRE_COUNT)
	# Clear impassable terrain around starting position
	GameState.prepare_starting_area(KEEP_X, KEEP_Y, STARTING_AREA_RADIUS)
	# Give player generous starting resources
	GameState.initialize_player(0, PLAYER_NAME, KEEP_X, KEEP_Y)
	var p: Dictionary = GameState.players[0]
	p["gold"]   = 500
	p["prestige"] = 0
	p["resources"]["wood"]  = 300
	p["resources"]["stone"] = 100
	p["resources"]["iron"]  = 50
	p["food"]["apples"] = 100
	# Add starting population
	p["population"] = 50
	# Add AI factions
	GameState.add_ai_faction("bandit_king",     20,  20)
	GameState.add_ai_faction("ashen_barony",   180, 180)

# ── Scene tree construction ───────────────────────────────────────────────────

func _build_scene() -> void:
	# Camera (must be first to set up viewport transform)
	_camera = preload("res://view/micro/CameraController.gd").new()
	_camera.name = "Camera"
	_camera.position = _iso_origin(KEEP_X, KEEP_Y)
	add_child(_camera)

	# World rendering root
	_world_root = Node2D.new()
	_world_root.name = "WorldRoot"
	add_child(_world_root)

	_iso_grid = preload("res://view/micro/IsometricGrid.gd").new()
	_iso_grid.name = "IsometricGrid"
	_world_root.add_child(_iso_grid)
	_iso_grid.set_camera(_camera)

	_bld_layer = preload("res://view/micro/BuildingLayer.gd").new()
	_bld_layer.name = "BuildingLayer"
	_world_root.add_child(_bld_layer)

	_unit_layer = preload("res://view/micro/UnitLayer.gd").new()
	_unit_layer.name = "UnitLayer"
	_world_root.add_child(_unit_layer)

	# HUD (high layer)
	_hud = preload("res://view/hud/HUDNode.gd").new()
	_hud.name = "HUD"
	_hud.layer = 10
	add_child(_hud)

	# Macro view overlay
	_macro_view = CanvasLayer.new()
	_macro_view.name = "MacroView"
	_macro_view.layer = 5
	add_child(_macro_view)
	var macro_ctrl := preload("res://view/macro/MacroMapView.gd").new()
	macro_ctrl.name = "MacroMapControl"
	macro_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	macro_ctrl.visible = false
	_macro_view.add_child(macro_ctrl)

	# Input handler
	_input_handler = preload("res://view/main/PlayerInputHandler.gd").new()
	_input_handler.name = "InputHandler"
	add_child(_input_handler)
	_input_handler.setup(_iso_grid, _camera, _unit_layer)

func _iso_origin(gx: int, gy: int) -> Vector2:
	return Vector2((gx - gy) * 32.0, (gx + gy) * 16.0)

# ── Signal wiring ─────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	# HUD → simulation
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

	# Input handler → HUD feedback
	_input_handler.build_mode_changed.connect(_hud.set_build_mode_display)
	_input_handler.placement_failed.connect(func(r): _hud.show_notification("Cannot build: " + r))
	_input_handler.entity_selected.connect(_on_entity_selected)
	_input_handler.entity_deselected.connect(func(): _hud.clear_selection())

	# EventBus → HUD notifications
	EventBus.weather_changed.connect(func(name, _d): _hud.show_notification("Weather: " + name, 4.0))
	EventBus.building_placement_failed.connect(func(_p, _b, _gx, _gy, reason): _hud.show_notification(reason, 3.0))
	EventBus.ai_siege_assembling.connect(func(fid, _tpid, eta): _hud.show_notification("⚠ AI faction %d assembling siege! ETA: %d ticks" % [fid, eta], 6.0))
	EventBus.unit_killed.connect(_on_unit_killed)
	EventBus.building_destroyed.connect(_on_building_destroyed)
	EventBus.ai_faction_defeated.connect(_on_ai_faction_defeated)
	EventBus.popularity_changed.connect(_on_popularity_changed)
	EventBus.edict_activated.connect(func(_pid, eid, _d): _hud.show_notification("Edict in effect: " + eid, 3.0))
	EventBus.edict_expired.connect(func(_pid, eid): _hud.show_notification("Edict expired: " + eid, 3.0))

	# Persistence
	EventBus.save_requested.connect(_do_save)
	EventBus.load_requested.connect(_do_load)

	# Tab key for macro view
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_toggle_macro_view()
		get_viewport().set_input_as_handled()

func _toggle_macro_view() -> void:
	var ctrl := _macro_view.get_node_or_null("MacroMapControl")
	if ctrl == null: return
	ctrl.visible = not ctrl.visible

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

# ── Combat and win/loss event handlers ───────────────────────────────────────

func _on_unit_killed(unit_id: int, _killer_id: int, cause: String) -> void:
	# Find out if it's a player unit for notification
	if GameState.players.size() == 0: return
	var player: Dictionary = GameState.players[0]
	for unit in player.get("units", []):
		if unit is Dictionary and unit.get("id", -1) == unit_id:
			_hud.show_notification("Unit lost: %s (%s)" % [unit.get("type", "?"), cause], 3.0)
			return

func _on_building_destroyed(player_id: int, building_id: int, cause: String) -> void:
	if player_id != 0 or GameState.players.size() == 0: return
	var player: Dictionary = GameState.players[0]
	for bld in player.get("buildings", []):
		if bld is Dictionary and bld.get("id", -1) == building_id:
			var btype: String = bld.get("type", "")
			_hud.show_notification("Building destroyed: %s!" % btype, 4.0)
			if btype == "village_hall" or btype == "keep":
				_show_game_over(false, "Your keep has fallen! The realm is lost.")
			return

func _on_ai_faction_defeated(faction_id: int) -> void:
	_hud.show_notification("Enemy faction %d has been defeated!" % faction_id, 5.0)
	# Check if all AI factions are defeated
	var all_dead: bool = true
	for fac in GameState.ai_factions:
		if fac is Dictionary and fac.get("is_alive", true):
			all_dead = false
			break
	if all_dead and GameState.ai_factions.size() > 0:
		_show_game_over(true, "All enemies vanquished! Sovereign's Reach is yours!")

func _on_popularity_changed(_pid: int, _old: float, new_val: float) -> void:
	if new_val < 10.0:
		_show_game_over(false, "The people have revolted! Your reign is over.")

# ── Game over overlay ─────────────────────────────────────────────────────────

var _game_over_shown: bool = false

func _show_game_over(victory: bool, message: String) -> void:
	if _game_over_shown: return
	_game_over_shown = true
	SimulationClock.set_speed(0)

	var overlay := CanvasLayer.new()
	overlay.name = "GameOverOverlay"
	overlay.layer = 20
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel := Panel.new()
	panel.position = Vector2(340, 220)
	panel.size = Vector2(600, 260)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.16, 0.98)
	style.border_width_all = 2
	style.border_color = Color.GOLD if victory else Color.DARK_RED
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)

	var title := Label.new()
	title.text = "VICTORY!" if victory else "DEFEAT"
	title.position = Vector2(20, 20)
	title.size = Vector2(560, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color.GOLD if victory else Color.ORANGE_RED)
	panel.add_child(title)

	var msg := Label.new()
	msg.text = message
	msg.position = Vector2(20, 80)
	msg.size = Vector2(560, 80)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 16)
	msg.add_theme_color_override("font_color", Color.WHITE_SMOKE)
	panel.add_child(msg)

	var day_lbl := Label.new()
	day_lbl.text = "Day %d reached." % SimulationClock.game_day()
	day_lbl.position = Vector2(20, 160)
	day_lbl.size = Vector2(560, 24)
	day_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_lbl.add_theme_font_size_override("font_size", 13)
	day_lbl.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	panel.add_child(day_lbl)

	# Restart button
	var restart_btn := Button.new()
	restart_btn.text = "Restart"
	restart_btn.position = Vector2(140, 200)
	restart_btn.size = Vector2(140, 40)
	restart_btn.add_theme_font_size_override("font_size", 14)
	restart_btn.pressed.connect(func(): get_tree().reload_current_scene())
	panel.add_child(restart_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit to Desktop"
	quit_btn.position = Vector2(320, 200)
	quit_btn.size = Vector2(140, 40)
	quit_btn.add_theme_font_size_override("font_size", 14)
	quit_btn.pressed.connect(func(): get_tree().quit())
	panel.add_child(quit_btn)

# ── Starting buildings ────────────────────────────────────────────────────────

func _place_starting_buildings() -> void:
	var kx: int = KEEP_X
	var ky: int = KEEP_Y
	# Village Hall (3×3 footprint, centered)
	_force_place("village_hall", kx - 1, ky - 1)
	# Hovels around the hall
	_force_place("hovel", kx + 2, ky - 1)
	_force_place("hovel", kx + 2, ky)
	_force_place("hovel", kx + 2, ky + 1)
	_force_place("hovel", kx - 2, ky - 1)
	_force_place("hovel", kx - 2, ky)
	# Apple orchard nearby
	_force_place("apple_orchard", kx + 4, ky)
	# Auto-assign workers
	_auto_assign_workers()

func _force_place(btype: String, gx: int, gy: int) -> void:
	if not GameState.grid_in_bounds(gx, gy):
		return
	# Clear terrain if needed
	GameState.prepare_starting_area(gx, gy, 2)
	# Use command queue but give player infinite resources temporarily
	var player: Dictionary = GameState.players[0]
	var saved_wood: int  = player["resources"].get("wood", 0)
	var saved_stone: int = player["resources"].get("stone", 0)
	var saved_gold: int  = player.get("gold", 0)
	player["resources"]["wood"]  = 9999
	player["resources"]["stone"] = 9999
	player["gold"]               = 9999
	CommandQueue.enqueue(7, {"building_type": btype, "grid_x": gx, "grid_y": gy}, 0)
	# Process immediately
	SimulationClock._advance_tick()
	# Restore resources
	player["resources"]["wood"]  = saved_wood
	player["resources"]["stone"] = saved_stone
	player["gold"]               = saved_gold

func _auto_assign_workers() -> void:
	if GameState.players.size() == 0: return
	var player: Dictionary = GameState.players[0]
	const WorkerSystem = preload("res://simulation/player/WorkerSystem.gd")
	WorkerSystem.auto_assign(player)

# ── Persistence handlers ──────────────────────────────────────────────────────

func _do_save() -> void:
	const SaveManager = preload("res://simulation/persistence/SaveManager.gd")
	var state: Dictionary = GameState.serialize()
	var ok: bool = SaveManager.save(state, "save_slot_1")
	if ok:
		_hud.show_notification("Game saved!", 2.0)
		EventBus.save_completed.emit("save_slot_1")
	else:
		_hud.show_notification("Save failed!", 2.0)

func _do_load(path: String) -> void:
	const SaveManager = preload("res://simulation/persistence/SaveManager.gd")
	var data: Dictionary = SaveManager.load_save(path)
	if data.is_empty():
		EventBus.load_completed.emit(false)
		return
	GameState.deserialize(data)
	EventBus.load_completed.emit(true)
	_hud.show_notification("Game loaded!", 2.0)
