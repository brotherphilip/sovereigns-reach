extends Node2D
# Drifting cloud shadows over the whole settlement (daytime only). One big world-space quad
# with the cloud_shadow shader (multiply blend) covers the iso map; the GPU scrolls fbm noise
# across it so soft shadows glide over ground, buildings and people. `coverage` (set by the
# weather system) scales from sparse patches on a fine day up to heavy overcast; `daylight`
# fades it out at night. Sits above the world content, below the night wash + HUD.

const HALF_W: float = 32.0
const HALF_H: float = 16.0

const SeasonSystem = preload("res://simulation/world/SeasonSystem.gd")

var _mat: ShaderMaterial

func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://view/micro/cloud_shadow.gdshader")
	material = _mat

# Cloud coverage 0..1 — the weather system drives this (sparse fine-day → overcast pre-rain).
func set_coverage(c: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("coverage", clampf(c, 0.0, 1.0))

func _process(_delta: float) -> void:
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
