extends Node
# NOT an autoload — attach to a Node in the View layer's scene tree.
# This is the single boundary between Godot's Input system and the simulation.
# It translates raw InputEvents into Command dictionaries pushed to CommandQueue.
# No game logic lives here. No state is read from GameState directly.

var player_id: int = 0
var _view_mode: String = "micro"
var _view_rotation: int = 0     # 0–3 (increments by 1 per R press, wraps at 4)
var _active_build_type: String = ""

func _ready() -> void:
	EventBus.view_mode_changed.connect(_on_view_mode_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cmd_pause"):
		_toggle_pause()
	elif event.is_action_pressed("ui_speed_1"):
		_enqueue_speed(SimulationClock.SPEED_NORMAL)
	elif event.is_action_pressed("ui_speed_2"):
		_enqueue_speed(SimulationClock.SPEED_FAST)
	elif event.is_action_pressed("ui_speed_3"):
		_enqueue_speed(SimulationClock.SPEED_FASTEST)
	elif event.is_action_pressed("cmd_toggle_map_view"):
		_toggle_view()
	elif event.is_action_pressed("cmd_rotate_view"):
		_rotate_view()
	elif event.is_action_pressed("cmd_cancel"):
		_cancel()
	elif event.is_action_pressed("ui_save"):
		CommandQueue.enqueue(CommandQueue.CommandType.SAVE_GAME, {}, player_id)

# Called by the View layer when the player clicks a grid cell to place a building.
func issue_place_building(build_type: String, grid_x: int, grid_y: int) -> void:
	CommandQueue.enqueue(
		CommandQueue.CommandType.PLACE_BUILDING,
		{"building_type": build_type, "grid_x": grid_x, "grid_y": grid_y},
		player_id
	)

# Called by the View layer when the player clicks an entity to select it.
func issue_select(entity_id: int, entity_type: String) -> void:
	CommandQueue.enqueue(
		CommandQueue.CommandType.SELECT_ENTITY,
		{"entity_id": entity_id, "entity_type": entity_type},
		player_id
	)

# Called by the View layer for tax slider changes.
func issue_set_tax_rate(rate: int) -> void:
	CommandQueue.enqueue(
		CommandQueue.CommandType.SET_TAX_RATE,
		{"rate": rate},
		player_id
	)

# Called by the View layer for ration slider changes.
func issue_set_food_ration(level: int) -> void:
	CommandQueue.enqueue(
		CommandQueue.CommandType.SET_RATION_FOOD,
		{"level": level},
		player_id
	)

func issue_set_ale_ration(level: int) -> void:
	CommandQueue.enqueue(
		CommandQueue.CommandType.SET_RATION_ALE,
		{"level": level},
		player_id
	)

# --- Private helpers ---

func _toggle_pause() -> void:
	if SimulationClock.is_paused():
		_enqueue_speed(SimulationClock.SPEED_NORMAL)
	else:
		_enqueue_speed(SimulationClock.SPEED_PAUSED)

func _enqueue_speed(speed: int) -> void:
	CommandQueue.enqueue(
		CommandQueue.CommandType.SET_GAME_SPEED,
		{"speed": speed},
		player_id
	)

func _toggle_view() -> void:
	var new_mode: String = "macro" if _view_mode == "micro" else "micro"
	CommandQueue.enqueue(
		CommandQueue.CommandType.TOGGLE_VIEW_MODE,
		{"mode": new_mode},
		player_id
	)

func _rotate_view() -> void:
	_view_rotation = (_view_rotation + 1) % 4
	CommandQueue.enqueue(
		CommandQueue.CommandType.ROTATE_VIEW,
		{"rotation_index": _view_rotation},
		player_id
	)

func _cancel() -> void:
	_active_build_type = ""
	CommandQueue.enqueue(
		CommandQueue.CommandType.DESELECT,
		{},
		player_id
	)

func set_active_build_type(build_type: String) -> void:
	_active_build_type = build_type

func _on_view_mode_changed(mode: String) -> void:
	_view_mode = mode
