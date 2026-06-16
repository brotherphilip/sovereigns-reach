extends RefCounted
# Bespoke low-poly iso models for every FINISHED building type — each composed from
# shaded primitives so it actually looks like the thing it is (a windmill has turning
# sails, a church has a steeple + cross, a quarry is an open pit, a barracks is a
# fortified longhouse, etc.). Drawn by BuildingLayer._draw_building when built==true.
#
# All draw_* calls go through the passed CanvasItem `ci` (BuildingLayer), so these are
# stateless static helpers. Footprint is given by the iso corners top/right/bot/left
# (screen space); +Y is down, "up" is Vector2(0,-h). Front faces meet at `bot`.

const SeasonSystem = preload("res://simulation/world/SeasonSystem.gd")

# ── Shared palette ──────────────────────────────────────────────────────────────
const WOOD    := Color(0.55, 0.40, 0.25)
const WOOD_D  := Color(0.40, 0.28, 0.16)
const WOOD_L  := Color(0.68, 0.52, 0.33)
const STONE   := Color(0.74, 0.72, 0.66)
const STONE_D := Color(0.55, 0.53, 0.49)
const STONE_L := Color(0.84, 0.82, 0.76)
const THATCH  := Color(0.80, 0.66, 0.34)
const THATCH_D:= Color(0.60, 0.47, 0.22)
const SLATE   := Color(0.42, 0.45, 0.52)
const TILE    := Color(0.74, 0.34, 0.24)
const TILE_D  := Color(0.58, 0.25, 0.18)
const IRON    := Color(0.45, 0.47, 0.52)
const IRON_D  := Color(0.30, 0.31, 0.35)
const GOLD    := Color(0.92, 0.78, 0.30)
const GLASS   := Color(0.98, 0.86, 0.48)
const LEAF    := Color(0.22, 0.50, 0.22)
const LEAF_D  := Color(0.15, 0.38, 0.16)
const DIRT    := Color(0.46, 0.36, 0.24)
const WATER   := Color(0.18, 0.42, 0.66)
const RED     := Color(0.74, 0.20, 0.18)
const EDGE    := Color(0.0, 0.0, 0.0, 0.28)

# Wall surface textures (passed to _box so masonry/timber/plank lift every box-building).
const TEX_NONE   := 0
const TEX_STONE  := 1   # ashlar courses + staggered joints
const TEX_TIMBER := 2   # half-timber framing (studs + mid-rail) over a daub infill
const TEX_PLANK  := 3   # vertical board cladding (barns/sheds)

# ── Primitives ──────────────────────────────────────────────────────────────────

static func _box(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ht: float, wall: Color, tex: int = TEX_NONE) -> PackedVector2Array:
	var u := Vector2(0, -ht)
	var tu := t + u; var ru := r + u; var bu := b + u; var lu := l + u
	# Faces, with a touch more contrast between the shaded and lit sides than before.
	ci.draw_colored_polygon(PackedVector2Array([l, b, bu, lu]), wall.darkened(0.34))   # front-left (shaded)
	ci.draw_colored_polygon(PackedVector2Array([b, r, ru, bu]), wall.darkened(0.10))   # front-right (lit)
	ci.draw_colored_polygon(PackedVector2Array([tu, ru, bu, lu]), wall.lightened(0.08))# top
	# Surface texture on the two visible front faces (masonry/timber/plank) so the
	# walls read as built material instead of a flat colour fill.
	if tex != TEX_NONE:
		_wall_tex(ci, l, b, r, ht, wall, tex)
	# Ambient occlusion: the wall grounds darker where it meets the earth, so the
	# building sits in the world instead of floating as a flat slab.
	var aoh: float = minf(ht * 0.24, 7.0)
	var ao := Color(0, 0, 0, 0.16)
	ci.draw_colored_polygon(PackedVector2Array([l, b, b + Vector2(0, -aoh), l + Vector2(0, -aoh)]), ao)
	ci.draw_colored_polygon(PackedVector2Array([b, r, r + Vector2(0, -aoh), b + Vector2(0, -aoh)]), ao)
	# Vertical corner posts catch the light — a subtle highlight that reads as edges.
	ci.draw_line(b, bu, wall.lightened(0.14), 0.8)
	# Eave rim along the wall-top so the silhouette pops against the roof above.
	ci.draw_polyline(PackedVector2Array([lu, bu, ru]), wall.lightened(0.22), 0.8)
	ci.draw_polyline(PackedVector2Array([l, b, r]), EDGE, 0.6)
	ci.draw_polyline(PackedVector2Array([l, lu, bu, ru, r]), EDGE, 0.5)
	return PackedVector2Array([tu, ru, bu, lu])

# Wall surface texture on the two front faces of a _box. The left face spans l→b
# (ground) up by ht; the right face spans b→r. Drawn after the face fills so the
# joints/beams sit on top, before the base ambient-occlusion grounds them.
static func _wall_tex(ci: CanvasItem, l: Vector2, b: Vector2, r: Vector2, ht: float, wall: Color, kind: int) -> void:
	match kind:
		TEX_STONE:  _stone_tex(ci, l, b, r, ht, wall)
		TEX_TIMBER: _timber_tex(ci, l, b, r, ht, wall)
		TEX_PLANK:  _plank_tex(ci, l, b, r, ht, wall)

# Ashlar masonry: horizontal courses + staggered vertical joints, brick-bonded so
# each row offsets the one below. Joint colour is a recessed (darker) mortar line.
static func _stone_tex(ci: CanvasItem, l: Vector2, b: Vector2, r: Vector2, ht: float, wall: Color) -> void:
	var joint := wall.darkened(0.26)
	var n: int = int(clampf(ht / 7.0, 3.0, 7.0))
	for k in range(1, n):
		var lo := Vector2(0, -ht * float(k) / float(n))
		ci.draw_line(l + lo, b + lo, joint, 0.6)
		ci.draw_line(b + lo, r + lo, joint, 0.6)
	var per := 3
	for k in range(n):
		var y0 := Vector2(0, -ht * float(k) / float(n))
		var y1 := Vector2(0, -ht * float(k + 1) / float(n))
		var stag: float = 0.0 if k % 2 == 0 else 0.5
		for s in range(per + 1):
			var f := (float(s) + stag) / float(per)
			if f <= 0.02 or f >= 0.98:
				continue
			ci.draw_line(l.lerp(b, f) + y0, l.lerp(b, f) + y1, joint, 0.5)
			ci.draw_line(b.lerp(r, f) + y0, b.lerp(r, f) + y1, joint, 0.5)

# Half-timber framing: vertical studs at intervals + a horizontal mid-rail, in dark
# beams over the (lighter daub) wall fill — the classic medieval timber-frame look.
static func _timber_tex(ci: CanvasItem, l: Vector2, b: Vector2, r: Vector2, ht: float, wall: Color) -> void:
	var beam := WOOD_D
	var u := Vector2(0, -ht)
	var studs := 4
	for s in range(1, studs):
		var f := float(s) / float(studs)
		ci.draw_line(l.lerp(b, f), l.lerp(b, f) + u, beam, 1.0)
		ci.draw_line(b.lerp(r, f), b.lerp(r, f) + u, beam, 1.0)
	var rail := Vector2(0, -ht * 0.5)
	ci.draw_line(l + rail, b + rail, beam, 1.0)
	ci.draw_line(b + rail, r + rail, beam, 1.0)

# Vertical board cladding for barns/sheds: thin vertical lines + a couple of cross
# battens, in a darker tone of the wall.
static func _plank_tex(ci: CanvasItem, l: Vector2, b: Vector2, r: Vector2, ht: float, wall: Color) -> void:
	var line := wall.darkened(0.20)
	var u := Vector2(0, -ht)
	var n := 6
	for s in range(1, n):
		var f := float(s) / float(n)
		ci.draw_line(l.lerp(b, f), l.lerp(b, f) + u, line, 0.5)
		ci.draw_line(b.lerp(r, f), b.lerp(r, f) + u, line, 0.5)
	for yf in [0.32, 0.72]:
		var lo := Vector2(0, -ht * yf)
		ci.draw_line(l + lo, b + lo, line.darkened(0.10), 0.4)
		ci.draw_line(b + lo, r + lo, line.darkened(0.10), 0.4)

# Shingle/tile courses across a roof slope. `eave` = the down-slope edge vertices
# (left→right); r0/r1 = the ridge ends matching eave's first/last vertex. Lines run
# parallel to the ridge, stepping down to the eave — reads as rows of tiles/thatch.
static func _courses(ci: CanvasItem, eave: Array, r0: Vector2, r1: Vector2, col: Color, n: int = 3) -> void:
	var m: int = eave.size()
	if m < 2:
		return
	var targets: Array = []
	for i in range(m):
		targets.append(r0.lerp(r1, float(i) / float(m - 1)))
	for k in range(1, n + 1):
		var f: float = float(k) / float(n + 1)
		var pts := PackedVector2Array()
		for i in range(m):
			pts.append((eave[i] as Vector2).lerp(targets[i], f))
		ci.draw_polyline(pts, col, 0.6)

# Courses on a triangular (hip) roof face — lines parallel to the base, toward apex.
static func _tri_courses(ci: CanvasItem, a: Vector2, bb: Vector2, apex: Vector2, col: Color, n: int = 3) -> void:
	for k in range(1, n + 1):
		var f: float = float(k) / float(n + 1)
		ci.draw_line(a.lerp(apex, f), bb.lerp(apex, f), col, 0.6)

# A thin closed elliptical ring (banding for cones/silos).
static func _ring(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, wd: float = 0.7) -> void:
	var pts := PackedVector2Array()
	for i in range(19):
		var a := TAU * float(i) / 18.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_polyline(pts, col, wd)

# Hip roof over the box's top diamond. Returns the apex.
static func _hip(ci: CanvasItem, c: PackedVector2Array, rh: float, roof: Color) -> Vector2:
	var tu: Vector2 = c[0]; var ru: Vector2 = c[1]; var bu: Vector2 = c[2]; var lu: Vector2 = c[3]
	var apex := (tu + bu) * 0.5 + Vector2(0, -rh)
	var c_back := roof.darkened(0.06)
	var c_left := roof.darkened(0.16)
	var c_litR := roof.lightened(0.10)
	var c_lit  := roof.lightened(0.02)
	ci.draw_colored_polygon(PackedVector2Array([lu, tu, apex]), c_back)
	ci.draw_colored_polygon(PackedVector2Array([tu, ru, apex]), c_litR)
	ci.draw_colored_polygon(PackedVector2Array([lu, bu, apex]), c_left)
	ci.draw_colored_polygon(PackedVector2Array([ru, bu, apex]), c_lit)
	# Tile courses on the two front (most-visible) faces.
	_tri_courses(ci, lu, bu, apex, c_left.darkened(0.16))
	_tri_courses(ci, ru, bu, apex, c_lit.darkened(0.16))
	# Hip ridges catch a highlight from apex down each corner.
	for corner in [lu, ru, bu]:
		ci.draw_line(apex, corner, roof.lightened(0.20), 0.8)
	ci.draw_polyline(PackedVector2Array([lu, apex, ru]), EDGE, 0.5)
	ci.draw_polyline(PackedVector2Array([bu, apex]), EDGE, 0.5)
	return apex

# Gabled roof with a horizontal ridge running along the tu→bu (depth) axis.
static func _gable(ci: CanvasItem, c: PackedVector2Array, rh: float, roof: Color) -> void:
	var tu: Vector2 = c[0]; var ru: Vector2 = c[1]; var bu: Vector2 = c[2]; var lu: Vector2 = c[3]
	var rback := tu + Vector2(0, -rh)
	var rfront := bu + Vector2(0, -rh)
	var c_left := roof.darkened(0.18)
	var c_right := roof.lightened(0.08)
	ci.draw_colored_polygon(PackedVector2Array([lu, tu, rback, rfront, bu]), c_left)   # left slope
	ci.draw_colored_polygon(PackedVector2Array([tu, ru, bu, rfront, rback]), c_right)  # right slope
	# Tile courses running parallel to the ridge down each slope.
	_courses(ci, [tu, lu, bu], rback, rfront, c_left.darkened(0.16))
	_courses(ci, [tu, ru, bu], rback, rfront, c_right.darkened(0.16))
	# Bright ridge cap + darker eave overhang give the roof real thickness.
	ci.draw_line(rback, rfront, roof.lightened(0.26), 1.4)
	ci.draw_polyline(PackedVector2Array([lu, bu, ru]), roof.darkened(0.30), 0.9)
	ci.draw_polyline(PackedVector2Array([rback, rfront]), EDGE, 0.6)
	ci.draw_polyline(PackedVector2Array([lu, rback]), EDGE, 0.4)

static func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(18):
		var a := TAU * float(i) / 18.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)

# Upright cylinder (tower/silo body) centred on ground point g.
static func _cyl(ci: CanvasItem, g: Vector2, rx: float, ry: float, ht: float, body: Color) -> Vector2:
	var topc := g + Vector2(0, -ht)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(g.x - rx, g.y), Vector2(g.x + rx, g.y),
		Vector2(g.x + rx, g.y - ht), Vector2(g.x - rx, g.y - ht)]), body.darkened(0.10))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(g.x - rx, g.y), Vector2(g.x, g.y),
		Vector2(g.x, g.y - ht), Vector2(g.x - rx, g.y - ht)]), body.darkened(0.24))  # shaded half
	_ellipse(ci, topc, rx, ry, body.lightened(0.10))
	return topc

# Cone roof on ground-projected centre c with base radius rx/ry and height ht.
static func _cone(ci: CanvasItem, c: Vector2, rx: float, ry: float, ht: float, col: Color) -> void:
	var apex := c + Vector2(0, -ht)
	var pts := PackedVector2Array()
	for i in range(18):
		var a := TAU * float(i) / 18.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	for i in range(18):
		var p0: Vector2 = pts[i]; var p1: Vector2 = pts[(i + 1) % 18]
		if (p0 + p1).y * 0.5 < c.y - ry * 0.4:   # back faces first (mostly hidden)
			ci.draw_colored_polygon(PackedVector2Array([p0, p1, apex]), col.darkened(0.18))
	for i in range(18):
		var p0: Vector2 = pts[i]; var p1: Vector2 = pts[(i + 1) % 18]
		if (p0 + p1).y * 0.5 >= c.y - ry * 0.4:   # front faces
			var sh := col.darkened(0.12) if p0.x < c.x else col
			ci.draw_colored_polygon(PackedVector2Array([p0, p1, apex]), sh)
	# Banding rings up the cone (thatch/tile courses) for surface texture.
	for fr in [0.30, 0.58, 0.82]:
		var ringc := c + Vector2(0, -ht * fr)
		_ring(ci, ringc, rx * (1.0 - fr), ry * (1.0 - fr), col.darkened(0.22), 0.6)

static func _post(ci: CanvasItem, base: Vector2, ht: float, col: Color, wd: float = 1.6) -> Vector2:
	var top := base + Vector2(0, -ht)
	ci.draw_line(base, top, col, wd)
	return top

static func _shadow(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2) -> void:
	# Soft grounding shadow: a broad faint pool with a denser core, cast down-right.
	# Reads as a real cast shadow rather than a hard duplicate of the footprint.
	var ctr := (t + b) * 0.5 + Vector2(3, 5)
	var rx: float = absf(r.x - l.x) * 0.5
	var ry: float = absf(b.y - t.y) * 0.5
	_ellipse(ci, ctr, rx * 0.98, ry * 0.98, Color(0, 0, 0, 0.10))
	_ellipse(ci, ctr, rx * 0.68, ry * 0.68, Color(0, 0, 0, 0.13))

# A door centred on the front-left face (l→b edge).
static func _door(ci: CanvasItem, l: Vector2, b: Vector2, ht: float, col: Color = Color(0.16, 0.10, 0.06)) -> void:
	var base := l.lerp(b, 0.5)
	var e := (b - l).normalized() * 2.8
	var dh := minf(ht * 0.7, 12.0)
	ci.draw_colored_polygon(PackedVector2Array([base - e, base + e, base + e + Vector2(0, -dh), base - e + Vector2(0, -dh)]), col)
	ci.draw_circle(base + Vector2(0, -dh), 2.8, col)

static func _win(ci: CanvasItem, p: Vector2, col: Color = GLASS) -> void:
	ci.draw_rect(Rect2(p.x - 1.8, p.y - 2.0, 3.6, 4.0), col)

# ── Dispatcher ──────────────────────────────────────────────────────────────────

static func draw_finished(ci: CanvasItem, btype: String, cat: int, w: int, h: int,
		t: Vector2, r: Vector2, b: Vector2, l: Vector2,
		wall: Color, roof: Color, trim: Color, time: float, season: int = SeasonSystem.Season.SUMMER) -> void:
	var ctr := (t + b) * 0.5
	_shadow(ci, t, r, b, l)
	match btype:
		"village_hall":      _village_hall(ci, t, r, b, l, ctr)
		"keep":              _keep(ci, t, r, b, l, ctr, time)
		"hovel":             _hovel(ci, t, r, b, l)
		"market":            _market(ci, t, r, b, l, ctr)
		"trading_post":      _trading_post(ci, t, r, b, l, ctr)
		"well":              _well(ci, t, r, b, l, ctr)
		"apothecary":        _shop(ci, t, r, b, l, ctr, Color(0.42, 0.62, 0.40), "+")
		"guildhall":         _guildhall(ci, t, r, b, l, ctr)
		"woodcutter_camp":   _woodcutter(ci, t, r, b, l, ctr)
		"stone_quarry":      _quarry(ci, t, r, b, l, ctr)
		"iron_mine":         _mine(ci, t, r, b, l, ctr)
		"pitch_rig":         _pitch_rig(ci, t, r, b, l, ctr, time)
		"stockpile":         _stockpile(ci, t, r, b, l, ctr)
		"apple_orchard":     _orchard(ci, t, r, b, l, season)
		"pig_farm":          _pen(ci, t, r, b, l, ctr, Color(0.86, 0.62, 0.62))
		"dairy_farm":        _dairy(ci, t, r, b, l, ctr)
		"wheat_farm":        _wheat(ci, t, r, b, l, ctr, season)
		"hops_farm":         _hops(ci, t, r, b, l, season)
		"mill":              _windmill(ci, t, r, b, l, ctr, time)
		"bakery":            _bakery(ci, t, r, b, l, ctr, time)
		"brewery":           _brewery(ci, t, r, b, l, ctr)
		"inn":               _inn(ci, t, r, b, l, ctr)
		"granary":           _granary(ci, t, r, b, l, ctr)
		"church":            _church(ci, t, r, b, l, ctr, false)
		"cathedral":         _church(ci, t, r, b, l, ctr, true)
		"barracks":          _barracks(ci, t, r, b, l, ctr)
		"siege_workshop":    _siege(ci, t, r, b, l, ctr)
		"blacksmith", "armorer": _forge(ci, t, r, b, l, ctr, time)
		"armory":            _armory(ci, t, r, b, l, ctr)
		"fletcher":          _shop(ci, t, r, b, l, ctr, WOOD, "arrow")
		"crossbow_workshop": _shop(ci, t, r, b, l, ctr, WOOD, "bow")
		"poleturner":        _poleturner(ci, t, r, b, l, ctr)
		"tannery":           _tannery(ci, t, r, b, l, ctr)
		"wooden_palisade":   _palisade(ci, t, r, b, l)
		"stone_wall":        _stone_wall(ci, t, r, b, l)
		"gatehouse":         _gatehouse(ci, t, r, b, l, ctr)
		"watchtower", "lookout_tower": _watchtower(ci, t, r, b, l, ctr)
		"great_tower":       _great_tower(ci, t, r, b, l, ctr)
		_:                   _generic(ci, t, r, b, l, wall, roof)

# ── CIVIC ────────────────────────────────────────────────────────────────────────

static func _village_hall(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	var c := _box(ci, t, r, b, l, 26.0, WOOD_L, TEX_TIMBER)
	_door(ci, l, b, 26.0)
	_win(ci, l.lerp(b, 0.25) + Vector2(0, -16))
	_win(ci, b.lerp(r, 0.75) + Vector2(0, -16))
	_gable(ci, c, 16.0, TILE)
	# banner pole on the ridge
	var apex := (c[0] + c[2]) * 0.5 + Vector2(0, -16.0)
	var tp := _post(ci, apex, 12.0, WOOD_D, 1.5)
	ci.draw_colored_polygon(PackedVector2Array([tp, tp + Vector2(11, 3), tp + Vector2(0, 8)]), RED)

static func _keep(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, time: float) -> void:
	var c := _box(ci, t, r, b, l, 40.0, STONE, TEX_STONE)
	_door(ci, l, b, 40.0, Color(0.20, 0.14, 0.10))
	# crenellated parapet around the top diamond
	_merlons(ci, c[3], c[2], STONE_L, 4)
	_merlons(ci, c[2], c[1], STONE_L, 4)
	# corner turret with conical roof + flag
	var tcap := _cyl(ci, c[0].lerp(c[1], 0.5) + Vector2(0, -2), 5.0, 2.4, 12.0, STONE_L)
	_cone(ci, tcap, 6.0, 3.0, 10.0, SLATE)
	var fp := tcap + Vector2(0, -10)
	var ftp := _post(ci, fp, 9.0, WOOD_D, 1.2)
	var wav := sin(time * 3.0) * 2.0
	ci.draw_colored_polygon(PackedVector2Array([ftp, ftp + Vector2(9 + wav, 3), ftp + Vector2(0, 7)]), RED)

static func _merlons(ci: CanvasItem, a: Vector2, bb: Vector2, col: Color, n: int) -> void:
	for i in range(n):
		var p: Vector2 = a.lerp(bb, (float(i) + 0.5) / float(n))
		ci.draw_rect(Rect2(p.x - 2.4, p.y - 4.5, 4.8, 4.5), col)

static func _hovel(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2) -> void:
	var c := _box(ci, t, r, b, l, 11.0, Color(0.72, 0.62, 0.45))
	_door(ci, l, b, 11.0)
	_gable(ci, c, 8.0, THATCH)

static func _market(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# open-air stalls: striped awnings on posts + crates
	var stalls := [[l.lerp(ctr, 0.55), Color(0.82, 0.30, 0.24)], [r.lerp(ctr, 0.55), Color(0.86, 0.82, 0.74)],
		[b.lerp(ctr, 0.45), Color(0.30, 0.46, 0.72)]]
	for s in stalls:
		var g: Vector2 = s[0]
		var p1 := _post(ci, g + Vector2(-7, 0), 12.0, WOOD_D)
		var p2 := _post(ci, g + Vector2(7, 0), 12.0, WOOD_D)
		ci.draw_colored_polygon(PackedVector2Array([p1, p2, p2 + Vector2(0, 4), p1 + Vector2(0, 4)]), s[1])
		ci.draw_colored_polygon(PackedVector2Array([p1, p2, (p1 + p2) * 0.5 + Vector2(0, 5)]), (s[1] as Color).darkened(0.15))
		ci.draw_rect(Rect2(g.x - 5, g.y - 4, 10, 4), WOOD)  # crate counter
	_crate(ci, ctr + Vector2(0, 6), 4.0)

static func _trading_post(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	var c := _box(ci, t, r, b, l, 18.0, WOOD, TEX_PLANK)
	_door(ci, l, b, 18.0)
	_gable(ci, c, 11.0, WOOD_D)
	# hanging coin sign
	var sp := b.lerp(r, 0.5) + Vector2(0, -16)
	ci.draw_line(sp, sp + Vector2(6, 0), WOOD_D, 1.2)
	ci.draw_circle(sp + Vector2(6, 5), 3.0, GOLD)
	_crate(ci, l.lerp(ctr, 0.4) + Vector2(0, 6), 3.5)
	_barrel(ci, r.lerp(ctr, 0.4) + Vector2(0, 4), 3.0)

static func _well(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	_cyl(ci, ctr + Vector2(0, 4), 7.0, 3.4, 7.0, STONE)
	_ellipse(ci, ctr + Vector2(0, -3), 6.0, 2.8, Color(0.10, 0.20, 0.34))  # water
	var p1 := _post(ci, ctr + Vector2(-7, 4), 16.0, WOOD_D)
	var p2 := _post(ci, ctr + Vector2(7, 4), 16.0, WOOD_D)
	ci.draw_line(p1, p1 + Vector2(7, -3), THATCH_D, 1.4)   # little roof
	ci.draw_line(p2, p2 + Vector2(-7, -3), THATCH_D, 1.4)
	ci.draw_colored_polygon(PackedVector2Array([p1, p2, (p1 + p2) * 0.5 + Vector2(0, -5)]), THATCH)
	ci.draw_rect(Rect2(ctr.x - 2, ctr.y - 8, 4, 4), WOOD)  # bucket

static func _guildhall(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	var c := _box(ci, t, r, b, l, 24.0, STONE_L, TEX_STONE)
	# columns on the front-left face
	for f in [0.25, 0.5, 0.75]:
		var bp: Vector2 = l.lerp(b, f)
		_post(ci, bp, 24.0, STONE_D, 2.2)
	_door(ci, l, b, 24.0)
	_gable(ci, c, 10.0, TILE)
	# pediment sign
	ci.draw_circle((c[0] + c[2]) * 0.5 + Vector2(0, -6), 3.0, GOLD)

# ── HARVESTING ───────────────────────────────────────────────────────────────────

static func _woodcutter(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# lean-to + log pile + chopping block with axe
	var c := _box(ci, t.lerp(ctr, 0.3), r.lerp(ctr, 0.3), b.lerp(ctr, 0.3), l.lerp(ctr, 0.3), 9.0, WOOD)
	_gable(ci, c, 5.0, THATCH_D)
	# log stack
	for i in range(3):
		_log(ci, b.lerp(l, 0.5) + Vector2(-2 + i * 5, 2 - i * 3), 5.0)
	# chopping block + axe
	var blk := r.lerp(ctr, 0.5) + Vector2(0, 2)
	ci.draw_rect(Rect2(blk.x - 3, blk.y - 5, 6, 5), WOOD_D)
	ci.draw_line(blk + Vector2(0, -5), blk + Vector2(5, -11), WOOD_D, 1.4)
	ci.draw_colored_polygon(PackedVector2Array([blk + Vector2(5, -11), blk + Vector2(9, -10), blk + Vector2(6, -13)]), IRON)

static func _quarry(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# open pit: terraced grey, with cut blocks + a crane
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), STONE_D.darkened(0.2))
	ci.draw_colored_polygon(PackedVector2Array([t.lerp(ctr, 0.35), r.lerp(ctr, 0.35), b.lerp(ctr, 0.35), l.lerp(ctr, 0.35)]), Color(0.34, 0.33, 0.31))
	for i in range(3):
		ci.draw_rect(Rect2(ctr.x - 10 + i * 8, ctr.y - 2 + (i % 2) * 4, 6, 5), STONE_L)  # cut blocks
	# timber crane
	var cb := r.lerp(ctr, 0.5)
	var ctop := _post(ci, cb, 20.0, WOOD_D, 2.0)
	ci.draw_line(ctop, ctop + Vector2(-12, 4), WOOD_D, 1.6)
	ci.draw_line(ctop + Vector2(-12, 4), ctop + Vector2(-12, 12), IRON_D, 1.0)

static func _mine(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# mound with a timber-framed adit + minecart + ore
	ci.draw_colored_polygon(PackedVector2Array([l, t, (t + ctr) * 0.5 + Vector2(0, -22), (l + ctr) * 0.5 + Vector2(0, -18)]), Color(0.40, 0.34, 0.28))
	ci.draw_colored_polygon(PackedVector2Array([t, r, (r + ctr) * 0.5 + Vector2(0, -18), (t + ctr) * 0.5 + Vector2(0, -22)]), Color(0.32, 0.27, 0.22))
	# adit entrance facing front
	var e := b.lerp(ctr, 0.35)
	ci.draw_line(e + Vector2(-6, 0), e + Vector2(-6, -10), WOOD_D, 2.0)
	ci.draw_line(e + Vector2(6, 0), e + Vector2(6, -10), WOOD_D, 2.0)
	ci.draw_line(e + Vector2(-6, -10), e + Vector2(6, -10), WOOD_D, 2.0)
	ci.draw_colored_polygon(PackedVector2Array([e + Vector2(-5, 0), e + Vector2(5, 0), e + Vector2(5, -9), e + Vector2(-5, -9)]), Color(0.05, 0.05, 0.07))
	# minecart with ore
	var mc := b.lerp(l, 0.4) + Vector2(0, 3)
	ci.draw_rect(Rect2(mc.x - 4, mc.y - 4, 8, 4), IRON_D)
	ci.draw_circle(mc + Vector2(-2, 1), 1.4, Color(0.1, 0.1, 0.1))
	ci.draw_circle(mc + Vector2(2, 1), 1.4, Color(0.1, 0.1, 0.1))
	ci.draw_circle(mc + Vector2(0, -5), 1.6, Color(0.62, 0.43, 0.30))

static func _pitch_rig(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, time: float) -> void:
	_ellipse(ci, ctr + Vector2(0, 4), 9.0, 4.0, Color(0.10, 0.09, 0.10))  # tar pool
	# derrick (4 legs to an apex)
	var apex := ctr + Vector2(0, -26)
	for corner in [l, t, r, b]:
		ci.draw_line(corner.lerp(ctr, 0.45), apex, WOOD_D, 1.4)
	ci.draw_line(apex, apex + Vector2(0, 4), IRON_D, 1.2)
	# bobbing pump
	var by := sin(time * 2.0) * 2.0
	ci.draw_line(apex, ctr + Vector2(0, -4 + by), IRON, 1.6)

static func _stockpile(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	_crate(ci, ctr + Vector2(-5, 2), 4.0)
	_crate(ci, ctr + Vector2(5, 0), 4.0)
	_crate(ci, ctr + Vector2(0, -4), 4.0)
	_barrel(ci, ctr + Vector2(8, 5), 3.0)
	_sack(ci, ctr + Vector2(-9, 6))

# ── FOOD ─────────────────────────────────────────────────────────────────────────

# A real grove: trees laid out in rows across the whole footprint, each rendered in
# its seasonal stage (bare winter → budding spring → leafy summer → fruiting autumn).
static func _orchard(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, season: int) -> void:
	# Ground tinted for the season (lush in spring/summer, golden autumn, pale winter).
	var ground := Color(0.40, 0.56, 0.30) * SeasonSystem.ground_tint(season)
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), ground)
	var stage: int = SeasonSystem.growth_stage(season)
	# Lay a grid of trees across the parallelogram l→t (one axis) and l→b (the other),
	# painter-ordered back-to-front so nearer trees overlap farther ones correctly.
	var ex := t - l
	var ey := b - l
	var rows: Array[float] = [0.18, 0.40, 0.62, 0.84]
	for v in rows:
		for u in rows:
			var base: Vector2 = l + ex * u + ey * v
			_tree(ci, base, stage, season)

# One tree at its seasonal growth stage. 0 bare, 1 budding, 2 leafy, 3 fruiting.
static func _tree(ci: CanvasItem, base: Vector2, stage: int, season: int) -> void:
	ci.draw_line(base, base + Vector2(0, -7), WOOD_D, 1.8)
	if stage == 0:
		# Winter — bare branches, a touch of frost.
		ci.draw_line(base + Vector2(0, -6), base + Vector2(-3, -11), WOOD_D, 1.0)
		ci.draw_line(base + Vector2(0, -6), base + Vector2(3, -10), WOOD_D, 1.0)
		ci.draw_line(base + Vector2(0, -4), base + Vector2(-2, -8), WOOD_D, 0.8)
		ci.draw_circle(base + Vector2(0, -11), 1.4, Color(0.86, 0.90, 0.95, 0.8))
		return
	var canopy := SeasonSystem.foliage_tint(season)
	var rad: float = 3.4 if stage == 1 else 5.0   # budding crowns are smaller
	ci.draw_circle(base + Vector2(0, -11), rad, canopy.darkened(0.25))
	ci.draw_circle(base + Vector2(-2, -13), rad * 0.7, canopy)
	ci.draw_circle(base + Vector2(2.5, -12), rad * 0.64, canopy.lightened(0.08))
	if stage == 1:
		# Spring blossom.
		ci.draw_circle(base + Vector2(-1, -12), 0.9, Color(0.98, 0.92, 0.95))
		ci.draw_circle(base + Vector2(2, -13), 0.8, Color(0.98, 0.88, 0.92))
	elif stage == 3:
		# Autumn fruit.
		ci.draw_circle(base + Vector2(-2, -10), 1.1, RED)
		ci.draw_circle(base + Vector2(3, -13), 1.0, RED)
		ci.draw_circle(base + Vector2(1, -14), 1.0, RED.lightened(0.1))

static func _pen(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, animal: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), DIRT)
	# fence around
	_fence(ci, l, b); _fence(ci, b, r)
	# small sty
	var c := _box(ci, t.lerp(ctr, 0.4), t.lerp(r, 0.5).lerp(ctr, 0.2), ctr, l.lerp(t, 0.5).lerp(ctr, 0.2), 7.0, WOOD)
	_gable(ci, c, 4.0, THATCH_D)
	# two pigs
	_critter(ci, ctr + Vector2(-3, 6), animal)
	_critter(ci, ctr + Vector2(7, 9), animal)

static func _dairy(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), Color(0.42, 0.58, 0.30))
	# red barn
	var c := _box(ci, t.lerp(ctr, 0.2), r.lerp(ctr, 0.3), ctr.lerp(b, 0.3), l.lerp(ctr, 0.3), 16.0, RED.lightened(0.05), TEX_PLANK)
	_gable(ci, c, 9.0, Color(0.85, 0.82, 0.78))
	_door(ci, l.lerp(ctr, 0.2), ctr.lerp(b, 0.3), 16.0, Color(0.5, 0.12, 0.10))
	_fence(ci, b.lerp(l, 0.0), r)
	_critter(ci, b.lerp(r, 0.55) + Vector2(0, 4), Color(0.90, 0.88, 0.84))  # cow

static func _wheat(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, season: int) -> void:
	var stage: int = SeasonSystem.growth_stage(season)
	# Field colour tracks the crop: winter stubble, spring sprouts, summer green, gold autumn.
	var field := Color(0.83, 0.69, 0.30)
	match stage:
		0: field = Color(0.62, 0.56, 0.40)   # ploughed / stubble
		1: field = Color(0.55, 0.70, 0.34)   # green sprouts
		2: field = Color(0.50, 0.66, 0.28)   # tall green
		3: field = Color(0.86, 0.70, 0.26)   # ripe gold
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), field)
	var row_col := field.darkened(0.22)
	for i in range(1, 6):
		var f := float(i) / 6.0
		ci.draw_line(l.lerp(t, f), b.lerp(r, f), row_col, 0.8)
	# scarecrow
	var sc := ctr + Vector2(0, -2)
	_post(ci, sc, 12.0, WOOD_D, 1.4)
	ci.draw_line(sc + Vector2(-6, -8), sc + Vector2(6, -8), WOOD_D, 1.2)
	ci.draw_circle(sc + Vector2(0, -13), 2.4, Color(0.78, 0.66, 0.40))

static func _hops(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, season: int) -> void:
	var stage: int = SeasonSystem.growth_stage(season)
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]),
		Color(0.44, 0.56, 0.30) * SeasonSystem.ground_tint(season))
	var bine := SeasonSystem.foliage_tint(season)
	for f in [0.25, 0.5, 0.75]:
		var a := l.lerp(t, f); var bb := b.lerp(r, f)
		ci.draw_line(a, bb, WOOD_D, 0.8)  # trellis row
		for g in [0.2, 0.5, 0.8]:
			var p: Vector2 = a.lerp(bb, g)
			var tp := _post(ci, p, 13.0, Color(0.30, 0.46, 0.20), 1.0)
			if stage == 0:
				continue                                   # winter: bare poles
			var climb: float = 0.5 if stage == 1 else 1.0  # spring bines half-grown
			ci.draw_circle(tp + Vector2(0, 2), 2.4 * climb + 1.2, bine)
			if stage == 3:
				ci.draw_circle(tp + Vector2(0, 4), 1.0, bine.lightened(0.2))  # ripe cones

static func _windmill(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, time: float) -> void:
	# tapered round stone tower
	var g := ctr + Vector2(0, 4)
	_cyl(ci, g, 9.0, 4.0, 26.0, Color(0.80, 0.76, 0.66))
	var cap := g + Vector2(0, -26)
	_cone(ci, cap, 8.0, 3.6, 9.0, WOOD_D)
	_door(ci, l.lerp(ctr, 0.55), b.lerp(ctr, 0.55), 12.0)
	# four turning sails on the cap front
	var hub := cap + Vector2(0, -2)
	var spin := time * 1.4
	for k in range(4):
		var a := spin + k * PI * 0.5
		var dir := Vector2(cos(a), sin(a) * 0.5)
		var tip := hub + dir * 16.0
		ci.draw_line(hub, tip, WOOD_D, 1.6)
		var perp := Vector2(-dir.y, dir.x) * 3.0
		ci.draw_colored_polygon(PackedVector2Array([hub.lerp(tip, 0.2) + perp, tip + perp, tip - perp, hub.lerp(tip, 0.2) - perp]), Color(0.90, 0.88, 0.82, 0.92))
	ci.draw_circle(hub, 2.0, IRON_D)

static func _bakery(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, time: float) -> void:
	var c := _box(ci, t, r, b, l, 13.0, Color(0.78, 0.70, 0.55))
	_door(ci, l, b, 13.0)
	_gable(ci, c, 7.0, TILE)
	# big chimney with smoke + oven glow at door
	var ch := c[1].lerp(c[2], 0.5) + Vector2(0, -2)
	ci.draw_rect(Rect2(ch.x - 2.5, ch.y - 12, 5, 12), STONE_D)
	var s := 0.5 + 0.5 * sin(time * 2.0)
	ci.draw_circle(ch + Vector2(sin(time * 3.0) * 2, -14 - s * 3), 2.5 + s, Color(0.8, 0.8, 0.8, 0.4))
	ci.draw_circle(l.lerp(b, 0.5) + Vector2(0, -5), 2.0, Color(1.0, 0.6, 0.2, 0.6))

static func _brewery(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	var c := _box(ci, t.lerp(ctr, 0.2), r.lerp(ctr, 0.2), b.lerp(ctr, 0.2), l.lerp(ctr, 0.2), 16.0, WOOD, TEX_PLANK)
	_gable(ci, c, 8.0, THATCH_D)
	# big barrels out front
	_barrel(ci, b.lerp(l, 0.5) + Vector2(0, 3), 5.0)
	_barrel(ci, b.lerp(r, 0.5) + Vector2(0, 5), 5.0)
	_barrel(ci, b + Vector2(0, 8), 5.0)

static func _inn(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	var c := _box(ci, t, r, b, l, 24.0, WOOD_L, TEX_TIMBER)   # two storeys
	_door(ci, l, b, 24.0)
	for p in [l.lerp(b, 0.3), b.lerp(r, 0.7)]:
		_win(ci, (p as Vector2) + Vector2(0, -7)); _win(ci, (p as Vector2) + Vector2(0, -18))
	_gable(ci, c, 12.0, THATCH)
	# hanging mug sign
	var sp := b.lerp(r, 0.5) + Vector2(0, -20)
	ci.draw_line(sp, sp + Vector2(7, 0), WOOD_D, 1.2)
	ci.draw_rect(Rect2(sp.x + 5, sp.y + 2, 5, 6), THATCH)

static func _granary(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# raised round storehouse with domed thatch
	_cyl(ci, ctr + Vector2(0, 3), 11.0, 5.0, 18.0, Color(0.80, 0.70, 0.50))
	var cap := ctr + Vector2(0, -15)
	_cone(ci, cap, 12.0, 5.5, 10.0, THATCH)
	_door(ci, l.lerp(ctr, 0.5), b.lerp(ctr, 0.5), 13.0)
	_sack(ci, b.lerp(l, 0.5) + Vector2(-2, 6)); _sack(ci, b.lerp(r, 0.5) + Vector2(2, 7))

# ── RELIGIOUS ──────────────────────────────────────────────────────────────────

static func _church(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, grand: bool) -> void:
	var wallc := STONE_L if grand else STONE
	var nave_h := 26.0 if grand else 18.0
	var c := _box(ci, t, r, b, l, nave_h, wallc, TEX_STONE)
	# tall steep roof
	_gable(ci, c, 18.0 if grand else 13.0, SLATE)
	# arched windows on front-left
	for f in [0.3, 0.6]:
		var p: Vector2 = l.lerp(b, f) + Vector2(0, -nave_h * 0.55)
		ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-1.6, 2), p + Vector2(1.6, 2), p + Vector2(1.6, -2), p + Vector2(0, -4), p + Vector2(-1.6, -2)]), Color(0.45, 0.62, 0.86))
	# bell tower at the back with spire + cross
	var tg := t.lerp(ctr, 0.35)
	var tc := _box(ci, tg + Vector2(0, -6), tg + Vector2(6, -3), tg + Vector2(0, 0), tg + Vector2(-6, -3), nave_h + 14.0, wallc, TEX_STONE)
	var apx := _hip(ci, tc, 12.0 if grand else 8.0, SLATE)
	var cr := apx + Vector2(0, -2)
	ci.draw_line(cr, cr + Vector2(0, -12), GOLD, 2.0)
	ci.draw_line(cr + Vector2(-4, -8), cr + Vector2(4, -8), GOLD, 2.0)
	if grand:
		ci.draw_circle((c[0] + c[2]) * 0.5 + Vector2(0, -nave_h * 0.0 - 4), 4.0, Color(0.50, 0.66, 0.90))  # rose window

# ── MILITARY ───────────────────────────────────────────────────────────────────

static func _barracks(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	var c := _box(ci, t, r, b, l, 18.0, WOOD_D.lightened(0.05), TEX_PLANK)
	_gable(ci, c, 9.0, SLATE)
	_door(ci, l, b, 18.0, Color(0.18, 0.12, 0.08))
	# war banners
	for f in [0.3, 0.7]:
		var p := (c[0] as Vector2).lerp(c[1], f) + Vector2(0, 0)
		var tp := _post(ci, p, 10.0, WOOD_D, 1.2)
		ci.draw_colored_polygon(PackedVector2Array([tp, tp + Vector2(0, 9), tp + Vector2(5, 4)]), RED)
	# weapon rack out front
	var rk := b.lerp(r, 0.6) + Vector2(0, 4)
	ci.draw_line(rk + Vector2(-5, 0), rk + Vector2(5, 0), WOOD, 1.4)
	for i in range(3):
		ci.draw_line(rk + Vector2(-4 + i * 4, 0), rk + Vector2(-4 + i * 4, -9), IRON, 1.0)

static func _siege(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), DIRT)
	# catapult: frame + throwing arm + counterweight + wheels
	var base := ctr + Vector2(0, 3)
	ci.draw_rect(Rect2(base.x - 9, base.y - 3, 18, 3), WOOD_D)
	ci.draw_circle(base + Vector2(-7, 1), 2.6, WOOD_D)
	ci.draw_circle(base + Vector2(7, 1), 2.6, WOOD_D)
	var piv := base + Vector2(2, -8)
	ci.draw_line(base + Vector2(-6, 0), piv, WOOD, 1.6)
	ci.draw_line(base + Vector2(8, 0), piv, WOOD, 1.6)
	ci.draw_line(piv, piv + Vector2(-12, -6), WOOD_L, 2.0)   # arm
	ci.draw_circle(piv + Vector2(-12, -6), 2.4, STONE_D)     # projectile
	ci.draw_rect(Rect2(piv.x + 4, piv.y - 2, 5, 6), IRON_D)  # counterweight

static func _forge(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, time: float) -> void:
	var c := _box(ci, t, r, b, l, 14.0, STONE_D, TEX_STONE)
	_gable(ci, c, 7.0, SLATE)
	# stone chimney with glowing forge
	var ch := c[1].lerp(c[2], 0.5)
	ci.draw_rect(Rect2(ch.x - 3, ch.y - 14, 6, 14), STONE)
	var fl := 0.6 + 0.4 * sin(time * 6.0)
	ci.draw_circle(ch + Vector2(0, -15), 2.0 + fl, Color(0.5, 0.5, 0.5, 0.4))
	# anvil + glow out front
	var an := b.lerp(l, 0.5) + Vector2(0, 4)
	ci.draw_circle(an + Vector2(0, 1), 4.0 * fl, Color(1.0, 0.5, 0.1, 0.5))
	ci.draw_rect(Rect2(an.x - 3, an.y - 3, 6, 2), IRON_D)
	ci.draw_rect(Rect2(an.x - 1, an.y - 1, 2, 3), IRON_D)

static func _armory(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	var c := _box(ci, t, r, b, l, 15.0, STONE, TEX_STONE)
	_gable(ci, c, 8.0, SLATE)
	_door(ci, l, b, 15.0)
	# shield + crossed swords on the front-right face
	var fc := b.lerp(r, 0.5) + Vector2(0, -9)
	ci.draw_colored_polygon(PackedVector2Array([fc + Vector2(-3, -3), fc + Vector2(3, -3), fc + Vector2(3, 1), fc + Vector2(0, 4), fc + Vector2(-3, 1)]), RED)
	ci.draw_line(fc + Vector2(-5, 4), fc + Vector2(5, -6), IRON, 1.0)
	ci.draw_line(fc + Vector2(5, 4), fc + Vector2(-5, -6), IRON, 1.0)

static func _poleturner(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	var c := _box(ci, t.lerp(ctr, 0.25), r.lerp(ctr, 0.25), b.lerp(ctr, 0.25), l.lerp(ctr, 0.25), 11.0, WOOD)
	_gable(ci, c, 6.0, THATCH_D)
	# stacked pikes leaning
	for i in range(4):
		ci.draw_line(b.lerp(l, 0.5) + Vector2(-4 + i * 3, 4), b.lerp(l, 0.5) + Vector2(2 + i * 3, -14), WOOD_L, 1.0)

static func _tannery(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	var c := _box(ci, t.lerp(ctr, 0.25), r.lerp(ctr, 0.25), b.lerp(ctr, 0.25), l.lerp(ctr, 0.25), 10.0, WOOD)
	_gable(ci, c, 5.0, THATCH_D)
	# stretched hides on frames
	for i in range(2):
		var fr := b.lerp(r, 0.4) + Vector2(i * 9 - 4, 3)
		var tp1 := _post(ci, fr + Vector2(-4, 0), 11.0, WOOD_D)
		var tp2 := _post(ci, fr + Vector2(4, 0), 11.0, WOOD_D)
		ci.draw_colored_polygon(PackedVector2Array([tp1, tp2, tp2 + Vector2(0, 7), tp1 + Vector2(0, 7)]), Color(0.74, 0.58, 0.40))

# ── DEFENSE ──────────────────────────────────────────────────────────────────────

static func _palisade(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2) -> void:
	# row of sharpened stakes along the tile
	var a := l.lerp(b, 0.0); var bb := r
	for f in range(7):
		var p: Vector2 = l.lerp(r, float(f) / 6.0)
		var tp := _post(ci, p + Vector2(0, 2), 14.0, WOOD, 2.2)
		ci.draw_colored_polygon(PackedVector2Array([tp + Vector2(-1.6, 0), tp + Vector2(1.6, 0), tp + Vector2(0, -3)]), WOOD_L)

static func _stone_wall(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2) -> void:
	var c := _box(ci, t, r, b, l, 13.0, STONE, TEX_STONE)
	_merlons(ci, c[3], c[2], STONE_L, 3)
	_merlons(ci, c[2], c[1], STONE_L, 3)

static func _gatehouse(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	var c := _box(ci, t, r, b, l, 20.0, STONE, TEX_STONE)
	# archway through the front
	var ar := l.lerp(b, 0.5)
	ci.draw_colored_polygon(PackedVector2Array([ar + Vector2(-4, 0), ar + Vector2(4, 0), ar + Vector2(4, -10), ar + Vector2(0, -14), ar + Vector2(-4, -10)]), Color(0.06, 0.06, 0.08))
	# portcullis bars
	for i in range(3):
		ci.draw_line(ar + Vector2(-3 + i * 3, 0), ar + Vector2(-3 + i * 3, -10), IRON, 0.8)
	_merlons(ci, c[3], c[2], STONE_L, 3)
	_merlons(ci, c[2], c[1], STONE_L, 3)
	# two flanking turret caps
	ci.draw_rect(Rect2((c[3] as Vector2).x - 2, (c[3] as Vector2).y - 6, 4, 6), STONE_L)
	ci.draw_rect(Rect2((c[1] as Vector2).x - 2, (c[1] as Vector2).y - 6, 4, 6), STONE_L)

static func _watchtower(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# timber tower on legs with a roofed platform
	var g := ctr + Vector2(0, 3)
	for off in [Vector2(-6, 2), Vector2(6, 2), Vector2(0, 5)]:
		_post(ci, g + off, 22.0, WOOD_D, 1.8)
	var plat := g + Vector2(0, -20)
	ci.draw_colored_polygon(PackedVector2Array([plat + Vector2(0, -3), plat + Vector2(9, 1), plat + Vector2(0, 5), plat + Vector2(-9, 1)]), WOOD_L)
	var rc := [plat + Vector2(0, -3), plat + Vector2(9, 1), plat + Vector2(0, 5), plat + Vector2(-9, 1)]
	var apex := plat + Vector2(0, -11)
	ci.draw_colored_polygon(PackedVector2Array([rc[3], rc[0], apex]), THATCH_D)
	ci.draw_colored_polygon(PackedVector2Array([rc[0], rc[1], apex]), THATCH)

static func _great_tower(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	var c := _box(ci, t, r, b, l, 38.0, STONE, TEX_STONE)
	_door(ci, l, b, 38.0, Color(0.18, 0.12, 0.10))
	_merlons(ci, c[3], c[2], STONE_L, 4)
	_merlons(ci, c[2], c[1], STONE_L, 4)
	# small corner turret
	var tg := c[0].lerp(c[1], 0.5)
	var tc := _cyl(ci, tg + Vector2(0, 2), 4.0, 2.0, 10.0, STONE_L)
	_cone(ci, tc, 5.0, 2.5, 8.0, SLATE)

# ── Generic fallback ──────────────────────────────────────────────────────────────

static func _generic(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, wall: Color, roof: Color) -> void:
	var c := _box(ci, t, r, b, l, 16.0, wall)
	_door(ci, l, b, 16.0)
	_gable(ci, c, 9.0, roof)

static func _shop(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, accent: Color, sign: String) -> void:
	var c := _box(ci, t, r, b, l, 12.0, WOOD)
	_door(ci, l, b, 12.0)
	_gable(ci, c, 7.0, THATCH_D)
	# hanging sign with an icon
	var sp := b.lerp(r, 0.5) + Vector2(0, -11)
	ci.draw_line(sp, sp + Vector2(6, 0), WOOD_D, 1.0)
	var ic := sp + Vector2(6, 5)
	ci.draw_rect(Rect2(ic.x - 3, ic.y - 3, 6, 6), accent.darkened(0.1))
	match sign:
		"+":
			ci.draw_line(ic + Vector2(0, -2), ic + Vector2(0, 2), Color.WHITE, 1.2)
			ci.draw_line(ic + Vector2(-2, 0), ic + Vector2(2, 0), Color.WHITE, 1.2)
		"arrow":
			ci.draw_line(ic + Vector2(-2, 2), ic + Vector2(2, -2), Color.WHITE, 1.0)
			ci.draw_colored_polygon(PackedVector2Array([ic + Vector2(2, -2), ic + Vector2(0, -2), ic + Vector2(2, 0)]), Color.WHITE)
		"bow":
			ci.draw_arc(ic, 3.0, -PI * 0.5, PI * 0.5, 6, Color.WHITE, 1.0)
			ci.draw_line(ic + Vector2(0, -3), ic + Vector2(0, 3), Color.WHITE, 0.8)

# ── Small props ───────────────────────────────────────────────────────────────────

static func _crate(ci, p: Vector2, s: float) -> void:
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-s, 0), p + Vector2(0, s * 0.5), p + Vector2(s, 0), p + Vector2(0, -s * 0.5)]), WOOD_L)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-s, 0), p + Vector2(0, s * 0.5), p + Vector2(0, s * 0.5 + s), p + Vector2(-s, s)]), WOOD_D)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, s * 0.5), p + Vector2(s, 0), p + Vector2(s, s), p + Vector2(0, s * 0.5 + s)]), WOOD)

static func _barrel(ci, p: Vector2, s: float) -> void:
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-s * 0.7, -s), p + Vector2(s * 0.7, -s), p + Vector2(s * 0.8, 0), p + Vector2(s * 0.7, s), p + Vector2(-s * 0.7, s), p + Vector2(-s * 0.8, 0)]), WOOD)
	ci.draw_line(p + Vector2(-s * 0.8, -s * 0.3), p + Vector2(s * 0.8, -s * 0.3), WOOD_D, 0.8)
	ci.draw_line(p + Vector2(-s * 0.8, s * 0.3), p + Vector2(s * 0.8, s * 0.3), WOOD_D, 0.8)
	_ellipse(ci, p + Vector2(0, -s), s * 0.7, s * 0.3, WOOD_L)

static func _sack(ci, p: Vector2) -> void:
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-3, 4), p + Vector2(3, 4), p + Vector2(2, -3), p + Vector2(-2, -3)]), Color(0.78, 0.70, 0.52))
	ci.draw_circle(p + Vector2(0, -3), 1.4, Color(0.70, 0.62, 0.45))

static func _log(ci, p: Vector2, s: float) -> void:
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-s, 0), p + Vector2(s, 0), p + Vector2(s, 2.4), p + Vector2(-s, 2.4)]), WOOD)
	ci.draw_circle(p + Vector2(-s, 1.2), 1.3, WOOD_L)
	ci.draw_circle(p + Vector2(s, 1.2), 1.3, WOOD_L)

static func _fence(ci, a: Vector2, bb: Vector2) -> void:
	for i in range(5):
		var p: Vector2 = a.lerp(bb, float(i) / 4.0)
		ci.draw_line(p, p + Vector2(0, -5), WOOD_D, 1.2)
	ci.draw_line(a + Vector2(0, -3.5), bb + Vector2(0, -3.5), WOOD_D, 1.0)

static func _critter(ci, p: Vector2, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-3, 0), p + Vector2(3, 0), p + Vector2(3, -2.4), p + Vector2(-3, -2.4)]), col)
	ci.draw_circle(p + Vector2(3.4, -2), 1.4, col)
	ci.draw_line(p + Vector2(-2, 0), p + Vector2(-2, 1.6), col.darkened(0.3), 1.0)
	ci.draw_line(p + Vector2(2, 0), p + Vector2(2, 1.6), col.darkened(0.3), 1.0)
