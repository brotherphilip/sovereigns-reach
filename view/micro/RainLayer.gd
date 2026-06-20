extends CanvasLayer
# Screen-space rain. A full-viewport rect with the rain_overlay shader draws falling streaks
# + a cool wet wash whenever the weather is RAIN/STORM. Intensity ramps smoothly so showers
# fade in/out rather than snap. Sits below the HUD (layer 10) so the UI stays clear.

const WeatherSystem = preload("res://simulation/world/WeatherSystem.gd")

var _mat: ShaderMaterial
var _rect: ColorRect
var _intensity: float = 0.0

func _ready() -> void:
	layer = 9
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://view/micro/rain_overlay.gdshader")
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(1, 1, 1, 1)
	add_child(_rect)

# Target rain strength for the current weather (snow/fog/clear are dry here).
func _target() -> float:
	match int(GameState.weather.get("current", 0)):
		WeatherSystem.WeatherType.RAIN:  return 0.62
		WeatherSystem.WeatherType.STORM: return 1.0
		_:                                return 0.0

func _process(delta: float) -> void:
	# Ramp ~2s so a shower rolls in/out smoothly.
	_intensity = move_toward(_intensity, _target(), delta * 0.5)
	_mat.set_shader_parameter("intensity", _intensity)
