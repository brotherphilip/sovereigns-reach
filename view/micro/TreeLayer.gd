extends Node2D
# The LIVING FOREST, drawn from GameState.world["trees"]. Every wooded tile is a tree in one of
# three growth phases that morph as it matures — sapling → young → adult — plus a cut stump.
# Adults are big and layered. When a woodcutter fells one it TOPPLES (a fall animation read from
# world["tree_falls"]), and while a tree is being chopped it SHAKES. Culled to the camera view
# and hidden when zoomed far out (trees are the heaviest art and illegible when tiny).

const HALF_W: float = 32.0
const HALF_H: float = 16.0
const DECOR_MIN_ZOOM: float = 0.45
const FALL_DUR: float = 1.25          # seconds for a felled trunk to teeter + swing flat
const FALL_LINGER: float = 1.5        # then the downed log fades over this long
const DUST_DUR: float = 0.6           # ground-impact dust + leaf burst lifetime

const SeasonSystem = preload("res://simulation/world/SeasonSystem.gd")
const ForestSystem = preload("res://simulation/world/ForestSystem.gd")
const SfxGen = preload("res://simulation/audio/SfxGen.gd")
const FALL_SFX_POOL: int = 3           # a tree crash is infrequent — a tiny pool suffices

var _camera: Camera2D = null
var _season: int = SeasonSystem.Season.SUMMER
var _t: float = 0.0
var _view: Rect2 = Rect2()
var _falls: Array = []                 # active topple animations: {x,y,dir,age}
var _chop: Dictionary = {}             # tile_key -> true while a worker chops it (this frame)
var _sfx_pool: Array = []              # positional players for the impact crash
var _fall_stream: AudioStream = null

func set_camera(cam: Camera2D) -> void:
	_camera = cam

func _ready() -> void:
	# Positional crash players: a felled tree booms from its world spot, panning + fading
	# with distance off the camera (same soundscape model as the workers' chop SFX).
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	for i in range(FALL_SFX_POOL):
		var pl := AudioStreamPlayer2D.new()
		pl.bus = bus
		pl.max_distance = 1100.0       # a crash carries further than a single axe chop
		pl.attenuation = 1.5
		pl.panning_strength = 1.4
		add_child(pl)
		_sfx_pool.append(pl)

# Play the "timber" crash at a felled tile's world position through a free pooled player.
func _play_crash(gx: int, gy: int) -> void:
	if _sfx_pool.is_empty():
		return
	if _fall_stream == null:
		_fall_stream = SfxGen.for_event("TREE_FALL")
	var pick: AudioStreamPlayer2D = _sfx_pool[0]
	for pl in _sfx_pool:
		if not pl.playing:
			pick = pl
			break
	pick.stream = _fall_stream
	pick.global_position = Vector2((gx - gy) * HALF_W, (gx + gy) * HALF_H)
	pick.volume_db = -6.0
	pick.pitch_scale = randf_range(0.92, 1.06)   # variance so repeats don't sound canned
	pick.play()

func _process(delta: float) -> void:
	_t += delta
	if _camera != null:
		visible = _camera.zoom.x >= DECOR_MIN_ZOOM
		if not visible:
			return
	# Pull freshly-felled trees into our own animation list, then clear the sim queue.
	var queued: Array = GameState.world.get("tree_falls", [])
	if not queued.is_empty():
		for f in queued:
			_falls.append({"x": int(f.get("x", 0)), "y": int(f.get("y", 0)),
				"dir": float(f.get("dir", 1.0)), "age": 0.0})
		GameState.world["tree_falls"] = []
	# Age the topples; play the crash as each crosses impact; drop finished ones.
	var keep: Array = []
	for f in _falls:
		var prev: float = float(f["age"])
		var now: float = prev + delta
		f["age"] = now
		if prev < FALL_DUR and now >= FALL_DUR:
			_play_crash(int(f["x"]), int(f["y"]))   # trunk hits the ground → timber!
		if now < FALL_DUR + FALL_LINGER:
			keep.append(f)
	_falls = keep
	# Note which tiles are being chopped right now (continuous shake while felling).
	_chop.clear()
	for c in GameState.citizens:
		if not (c is Dictionary):
			continue
		var ph := String(c.get("work_phase", ""))
		if (ph == "gather" or ph == "prep") and int(c.get("node_x", -1)) >= 0:
			_chop[int(c["node_y"]) * 100000 + int(c["node_x"])] = true
	queue_redraw()

func _compute_view() -> void:
	if _camera == null:
		_view = Rect2(-1e9, -1e9, 2e9, 2e9)
		return
	var vp := get_viewport()
	var half: Vector2 = (vp.get_visible_rect().size * 0.5) / _camera.zoom
	var ctr: Vector2 = _camera.get_screen_center_position()
	_view = Rect2(ctr - half, half * 2.0).grow(80.0)

func _draw() -> void:
	_season = int(GameState.world.get("season", SeasonSystem.Season.SUMMER))
	_compute_view()
	var size: Vector2i = GameState.get_grid_size()
	var w: int = size.x if size.x > 0 else 200
	var h: int = size.y if size.y > 0 else 200
	var trees: Dictionary = GameState.world.get("trees", {})
	# Only the tiles under the camera (iso screen-rect → tile bbox), so the per-frame cost
	# scales with what's on screen, not the whole map.
	var b: Rect2i = _visible_tile_bounds(w, h)
	for gy in range(b.position.y, b.end.y):
		for gx in range(b.position.x, b.end.x):
			if GameState.get_terrain_at(gx, gy) != 1:   # 1 == FOREST
				continue
			var sx: float = (gx - gy) * HALF_W
			var sy: float = (gx + gy) * HALF_H
			if not _view.has_point(Vector2(sx, sy)):
				continue
			# Tree state if the living-forest model registered this tile; else a default adult
			# (spectated / legacy maps with raw FOREST terrain still show full trees).
			var stage: int = ForestSystem.ADULT
			var g: float = 1.0
			var t = trees.get(str(gy * w + gx))
			if t != null:
				stage = int(t[0]); g = clampf(float(t[1]), 0.0, 1.0)
			var shake: float = 0.0
			if _chop.has(gy * 100000 + gx):
				shake = sin(_t * 34.0) * 1.6
			_draw_tree(sx, sy, gx, gy, stage, g, shake)
	# Toppling trees on top (they were just removed from the standing set).
	for f in _falls:
		_draw_falling(f)

# Tile-space bounding box that covers the (grown) camera view rect. Inverts the iso projection
# at the four screen corners and pads by one tile.
func _visible_tile_bounds(w: int, h: int) -> Rect2i:
	var corners := [_view.position, Vector2(_view.end.x, _view.position.y),
		Vector2(_view.position.x, _view.end.y), _view.end]
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for p in corners:
		var gx: int = int(floor(p.x / (2.0 * HALF_W) + p.y / (2.0 * HALF_H)))
		var gy: int = int(floor(p.y / (2.0 * HALF_H) - p.x / (2.0 * HALF_W)))
		lo.x = mini(lo.x, gx); lo.y = mini(lo.y, gy)
		hi.x = maxi(hi.x, gx); hi.y = maxi(hi.y, gy)
	lo.x = clampi(lo.x - 1, 0, w); lo.y = clampi(lo.y - 1, 0, h)
	hi.x = clampi(hi.x + 2, 0, w); hi.y = clampi(hi.y + 2, 0, h)
	return Rect2i(lo, hi - lo)

func _h(gx: int, gy: int, salt: int) -> float:
	var n: float = sin(float(gx) * 127.1 + float(gy) * 311.7 + float(salt) * 74.7) * 43758.5453
	return n - floor(n)

# Foliage palette for the season (adult/young crowns). hue 0..1 varies within a stand.
func _crown(hue: float) -> Array:
	var dark: Color
	match _season:
		SeasonSystem.Season.SPRING: dark = Color(0.26, 0.55, 0.21).lerp(Color(0.40, 0.66, 0.22), hue)
		SeasonSystem.Season.AUTUMN: dark = Color(0.58, 0.36, 0.12).lerp(Color(0.72, 0.52, 0.16), hue)
		SeasonSystem.Season.WINTER: dark = Color(0.20, 0.34, 0.22).lerp(Color(0.26, 0.40, 0.24), hue)
		_:                          dark = Color(0.10, 0.34, 0.14).lerp(Color(0.18, 0.45, 0.14), hue)
	return [dark, dark.lightened(0.18), dark.darkened(0.22)]

const TRUNK := Color(0.40, 0.27, 0.15)
const TRUNK_D := Color(0.30, 0.20, 0.11)

func _draw_tree(sx: float, sy: float, gx: int, gy: int, stage: int, g: float, shake: float) -> void:
	match stage:
		ForestSystem.STUMP:
			_draw_stump(sx, sy)
		ForestSystem.SAPLING:
			_draw_sapling(sx, sy, gx, gy, 0.55 + 0.45 * g)
		ForestSystem.YOUNG:
			_draw_young(sx, sy, gx, gy, 0.7 + 0.3 * g, shake)
		_:
			_draw_adult(sx, sy, gx, gy, 1.0, shake)

func _draw_stump(sx: float, sy: float) -> void:
	draw_circle(Vector2(sx, sy + 2.0), 5.0, Color(0, 0, 0, 0.14))
	draw_rect(Rect2(sx - 3.0, sy - 4.0, 6.0, 6.0), TRUNK)
	draw_circle(Vector2(sx, sy - 4.0), 3.2, Color(0.62, 0.46, 0.28))   # pale cut top
	draw_circle(Vector2(sx, sy - 4.0), 1.4, Color(0.50, 0.36, 0.20))

func _draw_sapling(sx: float, sy: float, gx: int, gy: int, s: float) -> void:
	draw_circle(Vector2(sx, sy + 2.0), 3.0 * s, Color(0, 0, 0, 0.10))
	draw_line(Vector2(sx, sy + 1.0), Vector2(sx, sy - 8.0 * s), Color(0.34, 0.46, 0.20), 1.6)
	var c: Array = _crown(_h(gx, gy, 40))
	if _season == SeasonSystem.Season.WINTER:
		return
	draw_circle(Vector2(sx, sy - 9.0 * s), 4.0 * s, c[0])
	draw_circle(Vector2(sx - 1.2 * s, sy - 11.0 * s), 2.6 * s, c[1])

func _draw_young(sx: float, sy: float, gx: int, gy: int, s: float, shake: float) -> void:
	draw_circle(Vector2(sx, sy + 3.0), 6.0 * s, Color(0, 0, 0, 0.14))
	draw_rect(Rect2(sx - 1.8 * s, sy - 6.0 * s, 3.6 * s, 9.0 * s), TRUNK)
	var top := Vector2(sx + shake, sy)
	if _season == SeasonSystem.Season.WINTER:
		_draw_bare(sx, sy, s, shake)
		return
	var c: Array = _crown(_h(gx, gy, 41))
	draw_circle(top + Vector2(0, -10.0 * s), 7.0 * s, c[2])
	draw_circle(top + Vector2(-2.5 * s, -13.0 * s), 5.0 * s, c[0])
	draw_circle(top + Vector2(2.5 * s, -14.0 * s), 4.5 * s, c[1])
	draw_circle(top + Vector2(0, -17.0 * s), 4.0 * s, c[1])

func _draw_adult(sx: float, sy: float, gx: int, gy: int, s: float, shake: float) -> void:
	var hue: float = _h(gx, gy, 42)
	var sway: float = sin(_t * 1.1 + float(gx) * 0.6 + float(gy) * 0.4) * 0.8   # gentle idle breeze
	var lean: float = shake + sway
	# Long ground shadow + thick buttressed trunk.
	draw_circle(Vector2(sx, sy + 4.0), 11.0 * s, Color(0, 0, 0, 0.16))
	var tw: float = 3.0 * s
	draw_colored_polygon(PackedVector2Array([
		Vector2(sx - tw, sy + 3.0), Vector2(sx + tw, sy + 3.0),
		Vector2(sx + tw * 0.6 + lean, sy - 16.0 * s), Vector2(sx - tw * 0.6 + lean, sy - 16.0 * s),
	]), TRUNK)
	draw_line(Vector2(sx - tw * 0.2, sy + 2.0), Vector2(sx - tw * 0.2 + lean, sy - 15.0 * s), TRUNK_D, 1.0)
	var top := Vector2(sx + lean, sy)
	if _season == SeasonSystem.Season.WINTER:
		_draw_bare(sx, sy, 1.3 * s, lean)
		return
	# Layered, billowing canopy — several overlapping clumps with light from upper-right.
	var c: Array = _crown(hue)
	var clumps := [
		[Vector2(0, -18.0), 10.0, c[2]],
		[Vector2(-7.0, -22.0), 8.0, c[0]],
		[Vector2(7.0, -23.0), 8.0, c[0]],
		[Vector2(0, -27.0), 8.5, c[0]],
		[Vector2(-3.0, -31.0), 6.5, c[1]],
		[Vector2(5.0, -30.0), 6.0, c[1]],
		[Vector2(1.0, -35.0), 5.0, c[1]],
	]
	for cl in clumps:
		draw_circle(top + (cl[0] as Vector2) * s, (cl[1] as float) * s, cl[2])
	# A couple of bright dabs for sun glint.
	draw_circle(top + Vector2(6.0, -33.0) * s, 2.6 * s, c[1].lightened(0.18))
	draw_circle(top + Vector2(-5.0, -25.0) * s, 2.0 * s, c[1].lightened(0.12))

func _draw_bare(sx: float, sy: float, s: float, lean: float) -> void:
	var base := Vector2(sx, sy - 4.0 * s)
	var crown := Vector2(sx + lean, sy - 20.0 * s)
	draw_line(base, crown, TRUNK_D, 1.6 * s)
	draw_line(crown, crown + Vector2(-6.0 * s, -5.0 * s), TRUNK_D, 1.2 * s)
	draw_line(crown + Vector2(0, 2.0 * s), crown + Vector2(6.0 * s, -4.0 * s), TRUNK_D, 1.2 * s)
	draw_circle(crown + Vector2(0, -2.0 * s), 3.0 * s, Color(0.90, 0.93, 0.98, 0.8))  # snow cap

func _draw_falling(f: Dictionary) -> void:
	var gx: int = int(f["x"]); var gy: int = int(f["y"])
	var sx: float = (gx - gy) * HALF_W
	var sy: float = (gx + gy) * HALF_H
	if not _view.has_point(Vector2(sx, sy)):
		return
	_paint_fall(Vector2(sx, sy), gx, gy, float(f["dir"]), float(f["age"]))

# Paint one toppling tree at an explicit pivot — the felling "theatre". A brief teeter (the
# cut tree leans back, gathering) then an accelerating swing flat, and at impact a dust puff
# kicks up where the crown slams down with a few leaves knocked loose. Split out from
# _draw_falling so the dev preview (_FellShowcase) can drive it at fixed ages.
func _paint_fall(pivot: Vector2, gx: int, gy: int, dir: float, age: float) -> void:
	var p: float = clampf(age / FALL_DUR, 0.0, 1.0)
	var go: float = clampf((p - 0.2) / 0.8, 0.0, 1.0)
	var fall: float = 1.0 - pow(1.0 - go, 2.4)                       # accelerating swing to flat
	var back: float = 0.09 * sin(clampf(p / 0.2, 0.0, 1.0) * PI) * (1.0 - go)   # teeter, gone by impact
	var angle: float = dir * (fall * (PI * 0.5) - back)
	var alpha: float = 1.0
	if age > FALL_DUR:
		alpha = clampf(1.0 - (age - FALL_DUR) / FALL_LINGER, 0.0, 1.0)
	# Trunk + a simple adult crown, drawn in local space (pivoting about the base).
	draw_set_transform(pivot, angle, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3.0, 3.0), Vector2(3.0, 3.0), Vector2(2.0, -16.0), Vector2(-2.0, -16.0),
	]), Color(TRUNK.r, TRUNK.g, TRUNK.b, alpha))
	var c: Array = _crown(_h(gx, gy, 42))
	var cc := Color(c[0].r, c[0].g, c[0].b, alpha)
	var cl := Color(c[1].r, c[1].g, c[1].b, alpha)
	draw_circle(Vector2(0, -22.0), 10.0, cc)
	draw_circle(Vector2(-6.0, -27.0), 7.0, cc)
	draw_circle(Vector2(6.0, -27.0), 7.0, cl)
	draw_circle(Vector2(0, -32.0), 6.0, cl)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# ── Ground-impact theatre: dust kicks up + leaves scatter where the crown hits ──
	if age >= FALL_DUR:
		var dp: float = clampf((age - FALL_DUR) / DUST_DUR, 0.0, 1.0)
		var land := pivot + Vector2(dir * 26.0, 2.0)
		var da: float = (1.0 - dp) * 0.5
		var rad: float = 5.0 + dp * 17.0
		draw_circle(land, rad, Color(0.82, 0.79, 0.70, da))
		draw_circle(land + Vector2(-rad * 0.45, -2.0), rad * 0.70, Color(0.86, 0.83, 0.74, da * 0.8))
		draw_circle(land + Vector2(rad * 0.50, -1.0), rad * 0.60, Color(0.78, 0.75, 0.66, da * 0.7))
		# A few leaves knocked loose — pop up and out, then settle as the dust clears.
		for i in range(5):
			var ia: float = _h(gx * 5 + i, gy * 3, i) * TAU
			var spread: float = (9.0 + _h(gx, gy * 7 + i, i + 11) * 13.0) * dp
			var arc: float = -16.0 * dp + 26.0 * dp * dp        # rise then fall
			var lp := land + Vector2(cos(ia) * spread, arc - absf(sin(ia)) * 3.0)
			draw_circle(lp, 1.3, Color(cl.r, cl.g, cl.b, (1.0 - dp) * 0.9))
