extends Node
# Autoload singleton. Registers all input actions programmatically.
# This keeps project.godot clean and avoids Godot's verbose serialized
# input event format. Called once at startup before any scene loads.

func _ready() -> void:
	_register_all_actions()

func _register_all_actions() -> void:
	# Simulation control
	_key("cmd_pause", KEY_SPACE)
	_key("cmd_cancel", KEY_ESCAPE)

	# View control
	_key("cmd_toggle_map_view", KEY_M)
	_key("cmd_rotate_view", KEY_R)

	# Game speed (GDD §1.5 — real-time progression)
	_key("ui_speed_1", KEY_1)   # Normal
	_key("ui_speed_2", KEY_2)   # Fast (2×)
	_key("ui_speed_3", KEY_3)   # Fastest (5×)

	# Camera pan (view-layer only, no simulation effect)
	_key("cam_pan_up", KEY_UP)
	_key("cam_pan_down", KEY_DOWN)
	_key("cam_pan_left", KEY_LEFT)
	_key("cam_pan_right", KEY_RIGHT)
	_key("cam_pan_up_alt", KEY_W)
	_key("cam_pan_down_alt", KEY_S)
	_key("cam_pan_left_alt", KEY_A)
	_key("cam_pan_right_alt", KEY_D)

	# Building placement shortcuts (view layer reads these)
	_key("ui_demolish", KEY_DELETE)
	_key("ui_save", KEY_F5)
	_key("ui_load", KEY_F9)

func _key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)
