extends Node
# Processes mouse/keyboard input for the micro view.
# Translates screen clicks to grid coordinates and enqueues Commands.
# Maintains build-mode and selection state.

# CommandType integer constants (avoid compile-time autoload resolution)
const CT_PLACE_BUILDING    = 7
const CT_DEMOLISH_BUILDING = 8
const CT_SET_WORKERS       = 9
const CT_RECRUIT_UNIT      = 11
const CT_ISSUE_MOVE_ORDER  = 12
const CT_ISSUE_ATTACK_ORDER = 13
const CT_DISBAND_UNIT      = 15
const CT_SET_TAX_RATE      = 0
const CT_SET_FOOD_RATION   = 1
const CT_SET_ALE_RATION    = 2
const CT_SET_GAME_SPEED    = 20
const CT_SAVE_GAME         = 23

signal build_mode_changed(building_type: String)
signal entity_selected(entity_type: String, entity_data: Dictionary)
signal entity_deselected()
signal placement_failed(reason: String)

var _build_mode_type: String = ""   # empty = not in build mode
var _selected_building_id: int = -1
var _selected_unit_id: int = -1

var _iso_grid:    Node2D   = null
var _camera:      Camera2D = null
var _unit_layer:  Node2D   = null
var _bld_layer:   Node2D   = null

func setup(iso_grid: Node2D, camera: Camera2D, unit_layer: Node2D) -> void:
	_iso_grid     = iso_grid
	_camera       = camera
	_unit_layer   = unit_layer

var _animal_layer: Node2D = null

func set_animal_layer(layer: Node2D) -> void:
	_animal_layer = layer

func set_building_layer(layer: Node2D) -> void:
	_bld_layer = layer

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(event.global_position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_on_right_click(event.global_position)
	elif event is InputEventMouseMotion and _build_mode_type != "":
		_update_ghost(event.global_position)
	elif event is InputEventKey and event.pressed:
		_on_key(event)

func _on_left_click(screen_pos: Vector2) -> void:
	# Click-through guard: ignore world clicks that land on a HUD control.
	# (Godot 4 has no Viewport.gui_is_hovered(); use gui_get_hovered_control().)
	if get_viewport().gui_get_hovered_control() != null:
		return
	if _iso_grid == null or _camera == null:
		return
	# Convert screen position to world (iso) coordinates, accounting for camera
	var canvas_transform := _iso_grid.get_canvas_transform()
	var world_pos: Vector2 = canvas_transform.affine_inverse() * screen_pos
	var grid_pos: Vector2i = _iso_grid.screen_to_grid(world_pos.x, world_pos.y)

	if _build_mode_type != "":
		_try_place_building(grid_pos)
	else:
		_try_select(grid_pos, world_pos)

func _try_place_building(grid_pos: Vector2i) -> void:
	if GameState.players.size() == 0:
		return
	# Validate first (view-side check for UI feedback)
	var player: Dictionary = GameState.players[0]
	var preview: Dictionary = _get_build_preview(grid_pos.x, grid_pos.y, player)
	if not preview.get("valid", false):
		placement_failed.emit(preview.get("reason", "Cannot place here"))
		return

	CommandQueue.enqueue(CT_PLACE_BUILDING, {
		"building_type": _build_mode_type,
		"grid_x": grid_pos.x,
		"grid_y": grid_pos.y,
	}, 0)
	# Stay in build mode for rapid placement (right-click or Escape to exit)

func _get_build_preview(gx: int, gy: int, player: Dictionary) -> Dictionary:
	const MVC = preload("res://view/micro/MicroViewController.gd")
	# Pass the live grid so the preview doesn't re-deserialise the whole map each frame.
	return MVC.get_build_preview(_build_mode_type, gx, gy, player, GameState.world, GameState._grid)

func _try_select(grid_pos: Vector2i, world_pos: Vector2) -> void:
	if GameState.players.size() == 0:
		return
	var player: Dictionary = GameState.players[0]

	# Check wildlife first — clicking a deer starts camera tracking (test feature).
	for a in GameState.wildlife:
		if not (a is Dictionary and a.get("is_alive", false)):
			continue
		var asx: float = (a["x"] - a["y"]) * 32.0
		var asy: float = (a["x"] + a["y"]) * 16.0
		if world_pos.distance_to(Vector2(asx, asy)) < 18.0:
			_select_animal(a)
			return

	# Check units first (closer to click center)
	for unit in player.get("units", []):
		if not unit is Dictionary or not unit.get("is_alive", false):
			continue
		var ux: int = unit.get("pos_x", 0)
		var uy: int = unit.get("pos_y", 0)
		var unit_screen := Vector2((ux - uy) * 32.0, (ux + uy) * 16.0)
		if world_pos.distance_to(unit_screen) < 16.0:
			_select_unit(unit)
			return

	# Check buildings
	for building in player.get("buildings", []):
		if not building is Dictionary:
			continue
		var bx: int = building.get("grid_x", 0)
		var by: int = building.get("grid_y", 0)
		if bx == grid_pos.x and by == grid_pos.y:
			_select_building(building)
			return

	# Nothing selected — deselect
	_deselect()

# Clicking a deer: follow it with the camera (and the cursor scares it).
func _select_animal(a: Dictionary) -> void:
	_selected_building_id = -1
	_selected_unit_id = -1
	if _unit_layer != null:
		_unit_layer.set_selected(-1)
	if _animal_layer != null:
		_animal_layer.set_selected(a.get("id", -1))
	if _camera != null and _camera.has_method("track_animal"):
		_camera.track_animal(a.get("id", -1))
	entity_selected.emit("animal", a)

func _stop_tracking() -> void:
	if _animal_layer != null:
		_animal_layer.set_selected(-1)
	if _camera != null and _camera.has_method("stop_tracking"):
		_camera.stop_tracking()

func _select_building(building: Dictionary) -> void:
	_stop_tracking()
	_selected_building_id = building.get("id", -1)
	_selected_unit_id = -1
	entity_selected.emit("building", building)
	_update_cursor()

func _select_unit(unit: Dictionary) -> void:
	_stop_tracking()
	_selected_unit_id = unit.get("id", -1)
	_selected_building_id = -1
	if _unit_layer != null:
		_unit_layer.set_selected(_selected_unit_id)
	entity_selected.emit("unit", unit)
	_update_cursor()

func _deselect() -> void:
	_stop_tracking()
	_selected_building_id = -1
	_selected_unit_id = -1
	if _unit_layer != null:
		_unit_layer.set_selected(-1)
	entity_deselected.emit()
	_update_cursor()

func _update_cursor() -> void:
	if _build_mode_type != "":
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	elif _selected_unit_id >= 0:
		Input.set_default_cursor_shape(Input.CURSOR_MOVE)
	elif _selected_building_id >= 0:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _on_right_click(screen_pos: Vector2) -> void:
	if _build_mode_type != "":
		_cancel_build()
		return
	# Right-click with unit selected → issue move order
	if _selected_unit_id >= 0 and _iso_grid != null and _camera != null:
		var canvas_transform := _iso_grid.get_canvas_transform()
		var world_pos: Vector2 = canvas_transform.affine_inverse() * screen_pos
		var grid_pos: Vector2i = _iso_grid.screen_to_grid(world_pos.x, world_pos.y)
		issue_move_to_selected(grid_pos.x, grid_pos.y)

func _update_ghost(screen_pos: Vector2) -> void:
	if _iso_grid == null or _camera == null or _bld_layer == null:
		return
	var canvas_transform := _iso_grid.get_canvas_transform()
	var world_pos: Vector2 = canvas_transform.affine_inverse() * screen_pos
	var grid_pos: Vector2i = _iso_grid.screen_to_grid(world_pos.x, world_pos.y)
	if GameState.players.size() == 0:
		return
	var player: Dictionary = GameState.players[0]
	var preview: Dictionary = _get_build_preview(grid_pos.x, grid_pos.y, player)
	var valid: bool = preview.get("valid", false)
	_bld_layer.set_ghost(_build_mode_type, grid_pos.x, grid_pos.y, valid)
	_iso_grid.set_hover_tile(grid_pos.x, grid_pos.y, valid)

func _cancel_build() -> void:
	_build_mode_type = ""
	build_mode_changed.emit("")
	if _bld_layer != null:
		_bld_layer.clear_ghost()
	if _iso_grid != null:
		_iso_grid.clear_hover_tile()
	_update_cursor()

func _on_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			if _build_mode_type != "":
				_cancel_build()
			else:
				_deselect()
		KEY_DELETE:
			_try_demolish_selected()
		# Quick game-speed toggles: 1 = Normal, 2 = Fast (2×), 3 = Fastest (5×).
		KEY_1:
			set_game_speed(SimulationClock.SPEED_NORMAL)
		KEY_2:
			set_game_speed(SimulationClock.SPEED_FAST)
		KEY_3:
			set_game_speed(SimulationClock.SPEED_FASTEST)

func _try_demolish_selected() -> void:
	if _selected_building_id < 0:
		return
	CommandQueue.enqueue(CT_DEMOLISH_BUILDING, {"building_id": _selected_building_id}, 0)
	_deselect()

# ── Public API called by HUD buttons ─────────────────────────────────────────

func enter_build_mode(building_type: String) -> void:
	_build_mode_type = building_type
	_deselect()
	build_mode_changed.emit(building_type)
	_update_cursor()

func set_workers_on_selected(count: int) -> void:
	if _selected_building_id < 0:
		return
	CommandQueue.enqueue(CT_SET_WORKERS, {
		"building_id": _selected_building_id,
		"workers": count,
	}, 0)

func recruit_unit(unit_type: String) -> void:
	CommandQueue.enqueue(CT_RECRUIT_UNIT, {"unit_type": unit_type}, 0)

func set_tax_rate(rate: int) -> void:
	CommandQueue.enqueue(CT_SET_TAX_RATE, {"rate": rate}, 0)

func set_food_ration(level: int) -> void:
	CommandQueue.enqueue(CT_SET_FOOD_RATION, {"level": level}, 0)

func set_ale_ration(level: int) -> void:
	CommandQueue.enqueue(CT_SET_ALE_RATION, {"level": level}, 0)

func set_game_speed(speed: int) -> void:
	# Apply directly, NOT via the CommandQueue. The queue is only drained inside
	# SimulationClock._advance_tick, which doesn't run while paused — so a queued
	# "resume" command could never process and pausing would softlock the game.
	# Speed is a local presentation concern (real-time→tick mapping), not part of
	# the deterministic sim command stream, so setting the clock directly is correct.
	SimulationClock.set_speed(speed)

func save_game() -> void:
	CommandQueue.enqueue(CT_SAVE_GAME, {}, 0)

func issue_move_to_selected(tx: int, ty: int) -> void:
	if _selected_unit_id < 0:
		return
	CommandQueue.enqueue(CT_ISSUE_MOVE_ORDER, {
		"unit_id": _selected_unit_id,
		"target_x": tx, "target_y": ty,
	}, 0)
