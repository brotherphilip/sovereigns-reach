extends Node2D
# Drifting cloud shadows over the whole settlement (daytime only). One big world-space quad
# with the cloud_shadow shader (multiply blend) covers the iso map; the GPU scrolls fbm noise
# across it so soft shadows glide over ground, buildings and people. `coverage` (set by the
# weather system) scales from sparse patches on a fine day up to heavy overcast; `daylight`
# fades it out at night. Sits above the world content, below the night wash + HUD.

const HALF_W: float = 32.0
const HALF_H: float = 16.0

const SeasonSystem  = preload("res://simulation/world/SeasonSystem.gd")
const WeatherSystem = preload("res://simulation/world/WeatherSystem.gd")

var _mat: ShaderMaterial
var _coverage: float = 0.28
var _override: float = -1.0   # set ≥0 to force coverage (weather build-up); -1 = derive from weather

func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://view/micro/cloud_shadow.gdshader")
	material = _mat

# The weather build-up (sun-cycle) can force a coverage; -1 hands control back to the weather type.
func set_coverage_override(c: float) -> void:
	_override = c

# Cloud coverage for the current weather: fine days a few patches, overcast before/under rain.
func _weather_coverage() -> float:
	match int(GameState.weather.get("current", 0)):
		WeatherSystem.WeatherType.CLEAR:   return 0.26
		WeatherSystem.WeatherType.DROUGHT: return 0.12
		WeatherSystem.WeatherType.FOG:     return 0.62
		WeatherSystem.WeatherType.SNOW:    return 0.70
		WeatherSystem.WeatherType.RAIN:    return 0.85
		WeatherSystem.WeatherType.STORM:   return 1.0
	return 0.30

func _process(delta: float) -> void:
	# Ease coverage toward its target (weather override, else weather type) so skies shift gently.
	var target: float = _override if _override >= 0.0 else _weather_coverage()
	_coverage = move_toward(_coverage, target, delta * 0.15)
	_mat.set_shader_parameter("coverage", _coverage)
	# Fade the shadows out at night (the night wash takes over then).
	var day: float = 1.0 - SeasonSystem.night_factor(SimulationClock.current_tick)
	_mat.set_shader_parameter("daylight", day)

func _draw() -> void:
	var gs: Vector2i = GameState.get_grid_size()
	var m: float = 256.0
	var x_min: float = -float(gs.y) * HALF_W - m
	var x_max: float =  float(gs.x) * HALF_W + m
	var y_min: float = -HALF_H - m
	var y_max: float =  float(gs.x + gs.y) * HALF_H + m
	draw_colored_polygon(PackedVector2Array([
		Vector2(x_min, y_min), Vector2(x_max, y_min),
		Vector2(x_max, y_max), Vector2(x_min, y_max),
	]), Color(1, 1, 1, 1))
