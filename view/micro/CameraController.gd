extends Camera2D
# Handles panning (WASD / arrow keys / middle-mouse drag) and zoom (scroll wheel).
# Position is in isometric screen space (pixels). The IsometricGrid reads camera position
# to determine which tiles to draw.

const PAN_SPEED: float  = 400.0  # pixels per second at zoom 1.0
const ZOOM_SPEED: float = 0.12
const ZOOM_MIN: float   = 0.25
const ZOOM_MAX: float   = 3.0

const IsoGrid = preload("res://view/micro/IsometricGrid.gd")

var _drag_active: bool   = false
var _drag_origin: Vector2 = Vector2.ZERO
var _cam_origin:  Vector2 = Vector2.ZERO
var _track_id: int = -1   # wildlife id the camera is following (-1 = none)

func _ready() -> void:
	enabled = true
	# Dev hook: SR_ZOOM=<f> sets the initial zoom (for close-up visual inspection / screenshots).
	if OS.get_environment("SR_ZOOM") != "":
		var z: float = clampf(float(OS.get_environment("SR_ZOOM")), ZOOM_MIN, ZOOM_MAX)
		if z > 0.0:
			zoom = Vector2(z, z)

# Begin following a wildlife animal by id; the cursor becomes a threat to it.
func track_animal(animal_id: int) -> void:
	_track_id = animal_id

func stop_tracking() -> void:
	_track_id = -1
	GameState.wildlife_cursor_threat = Vector2.INF

func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	if _track_id >= 0:
		_follow_tracked()

func _follow_tracked() -> void:
	for a in GameState.wildlife:
		if a is Dictionary and a.get("id", -1) == _track_id and a.get("is_alive", false):
			var target := Vector2((a["x"] - a["y"]) * 32.0, (a["x"] + a["y"]) * 16.0)
			position = position.lerp(target, 0.15)   # smooth follow
			# While tracking, the cursor scares the deer (test request).
			var m: Vector2 = get_global_mouse_position()
			var g: Vector2i = IsoGrid.screen_to_grid(m.x, m.y)
			GameState.wildlife_cursor_threat = Vector2(g.x, g.y)
			return
	stop_tracking()   # the animal is gone

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _drag_active:
		_handle_drag(event)

func _handle_keyboard_pan(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if dir != Vector2.ZERO:
		if _track_id >= 0:
			stop_tracking()   # manual pan breaks animal-follow
		var speed: float = PAN_SPEED / zoom.x
		position += dir.normalized() * speed * delta

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_MIDDLE:
			_drag_active = event.pressed
			if event.pressed:
				_drag_origin = event.global_position
				_cam_origin  = position
		MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(ZOOM_SPEED)
		MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(-ZOOM_SPEED)

func _handle_drag(event: InputEventMouseMotion) -> void:
	var delta: Vector2 = (event.global_position - _drag_origin) / zoom.x
	position = _cam_origin - delta

func _zoom_by(amount: float) -> void:
	var new_z: float = clampf(zoom.x + amount, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(new_z, new_z)

func center_on(world_pos: Vector2) -> void:
	position = world_pos
