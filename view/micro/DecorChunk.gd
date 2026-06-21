extends Node2D
# One CHUNK×CHUNK block of static terrain decorations (trees/mountains/rocks/
# water), painted once. Chunking lets the renderer cull off-screen decoration
# blocks so only visible ones are drawn each frame.

const HALF_W: float = 32.0
const HALF_H: float = 16.0
const T_GRASS: int = 0
const T_FOREST: int = 1
const T_MOUNTAIN: int = 2
const T_RIVER: int = 3
const T_ROCK: int = 5
const T_ORE: int = 6
const T_VALLEY: int = 7
const T_COASTAL: int = 8

const MountainHeight = preload("res://view/micro/MountainHeight.gd")

const SeasonSystem = preload("res://simulation/world/SeasonSystem.gd")

var _x0: int = 0
var _y0: int = 0
var _x1: int = 0
var _y1: int = 0
var _season: int = SeasonSystem.Season.SUMMER

func _ready() -> void:
	if EventBus.has_signal("season_changed"):
		EventBus.season_changed.connect(func(_s, _n): queue_redraw())
	if EventBus.has_signal("terrain_painted"):
		EventBus.terrain_painted.connect(func(x, y):
			if x >= _x0 and x < _x1 and y >= _y0 and y < _y1:
				queue_redraw())

func setup(x0: int, y0: int, x1: int, y1: int) -> void:
	_x0 = x0; _y0 = y0; _x1 = x1; _y1 = y1
	queue_redraw()

func _draw() -> void:
	_season = int(GameState.world.get("season", SeasonSystem.Season.SUMMER))
	for gy in range(_y0, _y1):
		for gx in range(_x0, _x1):
			_draw_decor(gx, gy)

func _h(gx: int, gy: int, salt: int) -> float:
	var n: float = sin(float(gx) * 127.1 + float(gy) * 311.7 + float(salt) * 74.7) * 43758.5453
	return n - floor(n)

func _draw_decor(gx: int, gy: int) -> void:
	var terrain: int = GameState.get_terrain_at(gx, gy)
	var cx: float = (gx - gy) * HALF_W
	var cy: float = (gx + gy) * HALF_H
	match terrain:
		T_FOREST:   pass  # trees are drawn by the animated TreeLayer (living forest), not here
		T_MOUNTAIN: _draw_mountain(cx, cy, gx, gy)
		T_ROCK:     _draw_rock(cx, cy, gx, gy)
		T_ORE:      _draw_ore(cx, cy, gx, gy)
		T_RIVER:    _draw_river(cx, cy)
		T_COASTAL:  _draw_coastal(cx, cy)
		T_GRASS:    _draw_ground_decor(cx, cy, gx, gy)
		T_VALLEY:   _draw_ground_decor(cx, cy, gx, gy)

# Sparse, subtle ground cover on open grass/valley tiles so the world doesn't read as
# a bare green sheet (Content-Density). Deterministic per-tile: only ~1 in 5 tiles bears
# anything, and each piece is tiny + low-contrast so it's texture, not clutter. Seasonal:
# flowers in spring/summer, dry tufts in autumn, snow specks in winter.
func _draw_ground_decor(cx: float, cy: float, gx: int, gy: int) -> void:
	if _h(gx, gy, 60) < 0.80:
		return   # ~80% of tiles stay clear
	var ox: float = (_h(gx, gy, 61) - 0.5) * 30.0
	var oy: float = (_h(gx, gy, 62) - 0.5) * 14.0
	var p := Vector2(cx + ox, cy + oy)
	var kind: float = _h(gx, gy, 63)
	if _season == SeasonSystem.Season.WINTER:
		# A small snow clump — everything else sleeps under the frost.
		draw_circle(p, 1.8, Color(0.92, 0.95, 1.0, 0.7))
		return
	if kind < 0.18:
		_draw_pebble(p, _h(gx, gy, 64))
	elif kind < 0.55 and _season != SeasonSystem.Season.AUTUMN:
		_draw_flower(p, gx, gy)
	else:
		_draw_tuft(p, gx, gy)

func _draw_tuft(p: Vector2, gx: int, gy: int) -> void:
	# A few short blades fanning up — colour shifts with the season's grass.
	var base: Color
	match _season:
		SeasonSystem.Season.SPRING: base = Color(0.30, 0.58, 0.24)
		SeasonSystem.Season.AUTUMN: base = Color(0.55, 0.50, 0.22)
		_:                          base = Color(0.27, 0.50, 0.22)
	var blades: int = 2 + int(_h(gx, gy, 65) * 2.0)
	for i in range(blades):
		var dx: float = (_h(gx, gy, 70 + i) - 0.5) * 4.0
		var hgt: float = 3.0 + _h(gx, gy, 80 + i) * 2.5
		draw_line(p + Vector2(dx, 0), p + Vector2(dx * 1.6, -hgt), base, 1.0)

func _draw_flower(p: Vector2, gx: int, gy: int) -> void:
	# A thin stem topped by a small petal dot — white/yellow/violet, picked by hash.
	draw_line(p, p + Vector2(0, -3.0), Color(0.30, 0.52, 0.22), 1.0)
	var pick: float = _h(gx, gy, 66)
	var petal: Color
	if pick < 0.4:    petal = Color(0.95, 0.92, 0.55)   # buttercup
	elif pick < 0.75: petal = Color(0.96, 0.96, 0.98)   # daisy
	else:             petal = Color(0.72, 0.55, 0.86)   # clover/violet
	draw_circle(p + Vector2(0, -3.6), 1.4, petal)
	draw_circle(p + Vector2(0, -3.6), 0.6, Color(0.95, 0.80, 0.30))  # tiny centre

func _draw_pebble(p: Vector2, s: float) -> void:
	var r: float = 1.6 + s * 1.2
	draw_circle(p + Vector2(0, 0.6), r, Color(0, 0, 0, 0.12))         # faint shadow
	draw_circle(p, r, Color(0.55, 0.54, 0.52))
	draw_circle(p + Vector2(-0.4, -0.4), r * 0.5, Color(0.66, 0.65, 0.62))

func _draw_forest(cx: float, cy: float, gx: int, gy: int) -> void:
	var count: int = 1 + int(_h(gx, gy, 1) * 3.0)
	for i in range(count):
		var ox: float = (_h(gx, gy, 10 + i) - 0.5) * 24.0
		var oy: float = (_h(gx, gy, 20 + i) - 0.5) * 12.0
		var s: float  = 0.7 + _h(gx, gy, 30 + i) * 0.7
		var hue: float = _h(gx, gy, 40 + i)
		_draw_one_tree(cx + ox, cy + oy, s, hue)

func _draw_one_tree(cx: float, cy: float, s: float, hue: float) -> void:
	draw_rect(Rect2(cx - 1.6 * s, cy - 4.0 * s, 3.2 * s, 9.0 * s), Color(0.40, 0.26, 0.14))
	if _season == SeasonSystem.Season.WINTER:
		# Bare, snow-dusted crown.
		draw_line(Vector2(cx, cy - 4.0 * s), Vector2(cx - 4.0 * s, cy - 12.0 * s), Color(0.36, 0.24, 0.14), 1.4 * s)
		draw_line(Vector2(cx, cy - 6.0 * s), Vector2(cx + 4.0 * s, cy - 13.0 * s), Color(0.36, 0.24, 0.14), 1.4 * s)
		draw_circle(Vector2(cx, cy - 14.0 * s), 2.4 * s, Color(0.90, 0.93, 0.98, 0.85))
		return
	var dark: Color
	match _season:
		SeasonSystem.Season.SPRING: dark = Color(0.28, 0.56, 0.22).lerp(Color(0.40, 0.64, 0.22), hue)
		SeasonSystem.Season.AUTUMN: dark = Color(0.55, 0.38, 0.14).lerp(Color(0.68, 0.50, 0.16), hue)
		_:                          dark = Color(0.10, 0.34, 0.14).lerp(Color(0.17, 0.43, 0.13), hue)
	var lite: Color = dark.lightened(0.16)
	draw_circle(Vector2(cx, cy - 9.0 * s), 8.0 * s, dark)
	draw_circle(Vector2(cx - 3.0 * s, cy - 13.0 * s), 6.0 * s, dark)
	draw_circle(Vector2(cx + 3.0 * s, cy - 13.0 * s), 6.0 * s, lite)
	draw_circle(Vector2(cx, cy - 18.0 * s), 5.0 * s, lite)

func _is_mountain(gx: int, gy: int) -> bool:
	return GameState.get_terrain_at(gx, gy) == T_MOUNTAIN

# A grassy mountain rendered as STACKED TERRACES: each tile is raised by its terrace level,
# so short rock steps near the rim climb in layers to a tall peak — a natural slope that
# blends into the fields, not one uniform wall. The top is grass; only the drop to a LOWER
# neighbour terrace shows as a columnar rock face. Still a full blocker. (Terrace heights
# come from MountainHeight so the grass-blade overlay lands on the same tops.)
func _draw_mountain(cx: float, cy: float, gx: int, gy: int) -> void:
	var level: int = MountainHeight.level(gx, gy)
	var e: float = MountainHeight.elevation_for_level(level)
	var l_se: int = MountainHeight.level_or0(gx + 1, gy)
	var l_sw: int = MountainHeight.level_or0(gx, gy + 1)
	# Cast a soft shadow onto the grass at the foot of an OUTER cliff (where the massif meets
	# open ground) — the single strongest cue that this is a raised landmass, not flat rock.
	var be := Vector2(cx + HALF_W, cy)
	var bs := Vector2(cx, cy + HALF_H)
	var bw := Vector2(cx - HALF_W, cy)
	if l_se == 0:
		var o := Vector2(HALF_W * 0.26, HALF_H * 0.26)
		draw_colored_polygon(PackedVector2Array([be, bs, bs + o, be + o]), Color(0, 0, 0, 0.17))
	if l_sw == 0:
		var o2 := Vector2(-HALF_W * 0.26, HALF_H * 0.26)
		draw_colored_polygon(PackedVector2Array([bs, bw, bw + o2, bs + o2]), Color(0, 0, 0, 0.17))
	var tn := Vector2(cx, cy - HALF_H - e)
	var te := Vector2(cx + HALF_W, cy - e)
	var ts := Vector2(cx, cy + HALF_H - e)
	var tw := Vector2(cx - HALF_W, cy - e)
	# Faces drop only to the lower FRONT neighbour terrace (south-east & south-west edges),
	# so the massif reads as layers stacking up to the peak rather than a single cliff.
	var e_se: float = MountainHeight.elevation_for_level(l_se)
	var e_sw: float = MountainHeight.elevation_for_level(l_sw)
	if e - e_se > 0.5:
		var d := Vector2(0.0, e - e_se)
		_cliff_column_face(te, ts, te + d, ts + d, gx, gy, 1)
	if e - e_sw > 0.5:
		var d2 := Vector2(0.0, e - e_sw)
		_cliff_column_face(ts, tw, ts + d2, tw + d2, gx, gy, 2)
	# Grassy terrace top — each higher terrace a touch lighter than the ground proper, so the
	# layers read as rising elevation (the grass-blade overlay then textures it to match).
	var top := _mtn_top_grass(level)
	draw_colored_polygon(PackedVector2Array([tn, te, ts, tw]), top)
	var ctr := Vector2(cx, cy - e)
	if _h(gx, gy, 2) > 0.5:
		draw_circle(ctr + Vector2((_h(gx, gy, 3) - 0.5) * 28.0, (_h(gx, gy, 4) - 0.5) * 12.0),
			2.4, top.darkened(0.10))
	if _h(gx, gy, 7) > 0.80:
		var rp := ctr + Vector2((_h(gx, gy, 8) - 0.5) * 22.0, (_h(gx, gy, 9) - 0.5) * 9.0)
		draw_circle(rp + Vector2(0, 1.0), 2.6, Color(0, 0, 0, 0.12))
		draw_circle(rp, 2.6, Color(0.50, 0.48, 0.44))
		draw_circle(rp + Vector2(-0.6, -0.6), 1.3, Color(0.60, 0.57, 0.52))
	if _season == SeasonSystem.Season.WINTER:
		draw_colored_polygon(PackedVector2Array([tn, te, ts, tw]), Color(0.95, 0.96, 1.0, 0.40))
	# Mossy lip + the odd perched boulder along edges that actually drop a terrace.
	if e - e_se > 0.5:
		draw_line(te, ts, Color(0.29, 0.41, 0.19, 0.65), 2.0)
		if _h(gx * 3, gy, 50) > 0.55:
			_rim_boulder(te.lerp(ts, 0.5), gx, gy, 1)
	if e - e_sw > 0.5:
		draw_line(ts, tw, Color(0.29, 0.41, 0.19, 0.65), 2.0)
		if _h(gx, gy * 3, 51) > 0.55:
			_rim_boulder(ts.lerp(tw, 0.5), gx, gy, 2)

# Grass colour for a terrace top: the seasonal ground grass, lightened a touch per terrace
# level so each higher layer is a slightly lighter green than the ground proper (a sense of
# rising elevation). The blade-texture overlay (MountainGrassLayer) then matches the fields.
func _mtn_top_grass(level: int = 1) -> Color:
	var g := Color(0.45, 0.62, 0.32)
	match _season:
		SeasonSystem.Season.SPRING: g = g.lerp(Color(0.55, 0.82, 0.42), 0.30)
		SeasonSystem.Season.AUTUMN: g = g.lerp(Color(0.74, 0.56, 0.24), 0.40)
		SeasonSystem.Season.WINTER: g = g.lerp(Color(0.85, 0.88, 0.94), 0.58)
	return g.lightened(0.05 * float(level))

# A rocky cliff face built from rounded vertical stone columns of varied width — the
# Stardew-style basalt look. t0→t1 is the (grassy) top edge; b0→b1 the ground contact.
func _cliff_column_face(t0: Vector2, t1: Vector2, b0: Vector2, b1: Vector2, gx: int, gy: int, salt: int) -> void:
	var base := Color(0.42, 0.40, 0.36)
	# Dark backing so the grooves between columns read as shadow.
	draw_colored_polygon(PackedVector2Array([t0, t1, b1, b0]), Color(0.23, 0.21, 0.20))
	var u: float = 0.0
	var k: int = 0
	while u < 0.999:
		var wf: float = 0.16 + _h(gx * 7 + k, gy * 3 + salt, 12 + k) * 0.18   # column width 0.16–0.34
		var u1: float = minf(1.0, u + wf)
		var ct0 := t0.lerp(t1, u)
		var ct1 := t0.lerp(t1, u1)
		var cb0 := b0.lerp(b1, u)
		var cb1 := b0.lerp(b1, u1)
		# Each column dips a little differently → an uneven, varied top edge. Scaled to the
		# face height so short terrace steps don't dip past their own base.
		var fh: float = (t0.distance_to(b0) + t1.distance_to(b1)) * 0.5
		var dip: float = (0.12 + _h(gx + k, gy * 2 + salt, 30 + k) * 0.34) * fh
		ct0 += Vector2(0, dip)
		ct1 += Vector2(0, dip)
		var shade := base.lerp(Color(0.53, 0.50, 0.45), _h(gx * 5 + k, gy + salt, 20 + k))
		var hw: float = ct0.distance_to(ct1) * 0.55
		# Column body + rounded boulder head + rounded foot.
		draw_colored_polygon(PackedVector2Array([ct0, ct1, cb1, cb0]), shade)
		var head := (ct0 + ct1) * 0.5
		draw_circle(head, hw, shade.lightened(0.10))                 # rounded top
		draw_circle((cb0 + cb1) * 0.5, hw * 0.85, shade.darkened(0.10))   # rounded foot
		# Lit left flank, shadowed groove on the right.
		draw_line(ct0, cb0, shade.lightened(0.22), 1.2)
		draw_line(ct1, cb1, Color(0.16, 0.14, 0.13, 0.85), 1.6)
		draw_circle((cb0 + cb1) * 0.5, hw * 0.7, Color(0.14, 0.13, 0.12, 0.45))   # contact shadow
		# A little moss clinging where the rock meets the grassy lip.
		if _h(gx + k, gy + salt, 40 + k) > 0.5:
			draw_circle(head + Vector2(0, -hw * 0.3), hw * 0.62, Color(0.32, 0.44, 0.20, 0.45))
		u = u1
		k += 1

# A boulder perched on the cliff lip, rising into the grass so the top edge reads uneven.
func _rim_boulder(p: Vector2, gx: int, gy: int, salt: int) -> void:
	var r: float = 3.4 + _h(gx, gy, 60 + salt) * 2.6
	var base := Color(0.45, 0.43, 0.39)
	draw_circle(p + Vector2(0, 1.0), r, Color(0, 0, 0, 0.12))               # ground shadow
	draw_circle(p + Vector2(0, -r * 0.35), r, base)                        # body rising above lip
	draw_circle(p + Vector2(-r * 0.3, -r * 0.6), r * 0.5, base.lightened(0.15))   # highlight
	draw_arc(p + Vector2(0, -r * 0.95), r * 0.7, PI, TAU, 9, Color(0.31, 0.43, 0.20, 0.55), 1.6)  # moss cap

# A low iron outcrop for the foothills — a rocky lump flecked with ore, sits minable on
# grass at the foot of the massif (ore is no longer carved into the cliff itself).
func _draw_ore(cx: float, cy: float, gx: int, gy: int) -> void:
	var s: float = 0.8 + _h(gx, gy, 5) * 0.5
	draw_circle(Vector2(cx, cy + 4.0), 7.0 * s, Color(0, 0, 0, 0.15))
	var rock := Color(0.42, 0.40, 0.40)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 8.0 * s, cy + 2.0), Vector2(cx - 4.0 * s, cy - 6.0 * s),
		Vector2(cx + 3.0 * s, cy - 7.0 * s), Vector2(cx + 8.0 * s, cy - 1.0),
		Vector2(cx + 4.0 * s, cy + 4.0), Vector2(cx - 4.0 * s, cy + 4.0),
	]), rock)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 3.0 * s, cy - 3.0 * s), Vector2(cx + 2.0 * s, cy - 5.0 * s), Vector2(cx + 1.0 * s, cy),
	]), rock.lightened(0.18))
	draw_circle(Vector2(cx - 2.0 * s, cy - 1.0), 1.3, Color(0.62, 0.45, 0.30))   # iron flecks
	draw_circle(Vector2(cx + 3.0 * s, cy - 2.0 * s), 1.1, Color(0.70, 0.52, 0.34))

func _draw_rock(cx: float, cy: float, gx: int, gy: int) -> void:
	var s: float = 0.8 + _h(gx, gy, 5) * 0.6
	var col := Color(0.46, 0.45, 0.49)
	draw_circle(Vector2(cx, cy + 4.0), 7.0 * s, Color(0, 0, 0, 0.15))
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 9.0 * s, cy + 2.0), Vector2(cx - 5.0 * s, cy - 7.0 * s),
		Vector2(cx + 3.0 * s, cy - 8.0 * s), Vector2(cx + 9.0 * s, cy - 1.0),
		Vector2(cx + 5.0 * s, cy + 5.0), Vector2(cx - 4.0 * s, cy + 5.0),
	]), col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 3.0 * s, cy - 4.0 * s), Vector2(cx + 2.0 * s, cy - 6.0 * s),
		Vector2(cx + 1.0 * s, cy - 1.0),
	]), col.lightened(0.20))
	draw_polyline(PackedVector2Array([
		Vector2(cx - 9.0 * s, cy + 2.0), Vector2(cx - 5.0 * s, cy - 7.0 * s),
		Vector2(cx + 3.0 * s, cy - 8.0 * s), Vector2(cx + 9.0 * s, cy - 1.0),
	]), Color(0.25, 0.25, 0.29, 0.6), 0.8)

func _draw_river(cx: float, cy: float) -> void:
	# Faint sub-surface streaks. The water_flow shader now carries the ripples/foam, so
	# these stay barely-there instead of stamping a bright arc onto every tile.
	var col: Color = Color(0.62, 0.78, 0.92, 0.18)
	draw_arc(Vector2(cx - 4.0, cy + 2.0), 7.0,  0.1 * PI, 0.9 * PI, 12, col, 1.4)
	draw_arc(Vector2(cx + 4.0, cy - 2.0), 7.0,  1.1 * PI, 1.9 * PI, 12, col, 1.4)

func _draw_coastal(cx: float, cy: float) -> void:
	draw_arc(Vector2(cx, cy + 4.0), 12.0, 0.15 * PI, 0.85 * PI, 14,
		Color(0.80, 0.88, 1.0, 0.16), 2.0)
