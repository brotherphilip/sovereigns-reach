extends Node2D
# Ambient drifting motes that make the open world feel ALIVE and a little magical.
#   • Dusk & night → FIREFLIES: warm yellow-green sparks that drift low over the land and blink
#     on and off (sharp flash, long dark), thinning out in winter.
#   • Day → faint pollen/dust motes catching the light (very subtle).
# Additive blend, view-culled, ~no sim cost — the motes recycle into the camera rect as it pans,
# so density follows the view instead of populating the whole 200×200 map. Self-driven from the
# simulation clock. Hidden when zoomed far out (sub-pixel sparkle = noise).

const SeasonSystem = preload("res://simulation/world/SeasonSystem.gd")

const COUNT: int = 90
const MIN_ZOOM: float = 0.55          # below this the motes are sub-pixel — hide the whole layer

var _camera: Camera2D = null
var _t: float = 0.0
var _motes: Array = []                # {pos, vel, phase, rate, size, hue}
var _seeded: bool = false
var _view: Rect2 = Rect2()
var _glow: GradientTexture2D = null

func set_camera(cam: Camera2D) -> void:
	_camera = cam

func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	# Soft radial glow sprite (bright centre → transparent) for the firefly halo.
	var g := Gradient.new()
	g.set_offset(0, 0.0); g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.45, Color(1, 1, 1, 0.40))
	g.set_offset(g.get_point_count() - 1, 1.0); g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 64
	_glow.height = 64
	set_process(true)

func _compute_view() -> void:
	if _camera == null:
		_view = Rect2(-1e6, -1e6, 2e6, 2e6)
		return
	var vp := get_viewport()
	var half: Vector2 = (vp.get_visible_rect().size * 0.5) / _camera.zoom
	var ctr: Vector2 = _camera.get_screen_center_position()
	_view = Rect2(ctr - half, half * 2.0).grow(50.0)

func _new_mote() -> Dictionary:
	return {
		"pos": Vector2(randf_range(_view.position.x, _view.end.x), randf_range(_view.position.y, _view.end.y)),
		"vel": Vector2(randf_range(-7.0, 7.0), randf_range(-6.0, 2.0)),   # slow drift, faint upward bias
		"phase": randf() * TAU,
		"rate": randf_range(0.55, 1.5),     # blink speed
		"size": randf_range(0.8, 1.7),
		"hue": randf(),                     # green↔amber firefly tint
	}

func _process(delta: float) -> void:
	_t += delta
	if _camera != null:
		var want: bool = _camera.zoom.x >= MIN_ZOOM
		if want != visible:
			visible = want
		if not want:
			return
	_compute_view()
	if not _seeded:
		_motes.clear()
		for i in range(COUNT):
			_motes.append(_new_mote())
		_seeded = true
	for m in _motes:
		# Gentle wander: linear drift + a slow sine sway, so motes meander rather than fly straight.
		var v: Vector2 = m["vel"]
		m["pos"] += v * delta
		m["pos"] += Vector2(sin(_t * 0.8 + m["phase"]) * 5.0, cos(_t * 0.6 + m["phase"]) * 3.5) * delta
		# Recycle motes that drift out of view back into it (density follows the camera).
		if not _view.has_point(m["pos"]):
			var nm := _new_mote()
			m["pos"] = nm["pos"]; m["vel"] = nm["vel"]
	queue_redraw()

func _draw() -> void:
	if not _seeded:
		return
	var n: float = SeasonSystem.night_factor(SimulationClock.current_tick)
	var night: float = smoothstep(0.22, 0.62, n)        # fireflies emerge at dusk
	var day: float = 1.0 - smoothstep(0.04, 0.28, n)
	var season: int = int(GameState.world.get("season", SeasonSystem.Season.SUMMER))
	var ff_season: float = 0.18 if season == SeasonSystem.Season.WINTER else 1.0
	for m in _motes:
		var p: Vector2 = m["pos"]
		var s: float = m["size"]
		if night > 0.01 and ff_season > 0.0:
			# Firefly: a sharp flash with a long dark gap (pow steepens the off-time).
			var b: float = 0.5 + 0.5 * sin(_t * (1.7 * float(m["rate"])) + float(m["phase"]) * 3.0)
			var a: float = pow(b, 2.6) * night * ff_season
			if a > 0.02:
				var col: Color = Color(0.72, 1.0, 0.42).lerp(Color(1.0, 0.86, 0.40), float(m["hue"]))
				_blit(p, 5.2 * s, Color(col.r, col.g, col.b, a * 0.55))
				draw_circle(p, 1.05 * s, Color(col.r, col.g, col.b, a))
		if day > 0.01:
			# Faint pollen/dust mote catching the daylight (kept very subtle under the bright scene).
			draw_circle(p, 0.9 * s, Color(1.0, 0.97, 0.82, day * 0.10))

func _blit(c: Vector2, r: float, col: Color) -> void:
	draw_texture_rect(_glow, Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, col)
