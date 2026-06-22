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
const SNOW    := Color(0.92, 0.94, 0.98)        # settled snow — roof dusting in winter

# Set once per building in draw_finished(): when true, the shared roof primitives
# (_gable/_hip/_cone) lay a pale snow dusting on their upper faces so the town reads
# as wintry alongside the already-snowy terrain and trees — without erasing the
# type-distinguishing roof colours (the dusting hugs the ridge/apex, eaves stay clear).
static var _winter := false

# Set once per building in draw_finished(): true when the building is staffed/active (or a
# dwelling). Chimney smoke only rises when active — so a cold, idle workshop reads as quiet
# and a busy one as alive. Set just before the per-type model is drawn.
static var _active := true

# Distinct roof hues so building TYPES read apart at a glance from the top-down iso view
# (the roof is the dominant surface). Previously ~everything was TILE/THATCH/SLATE, so the
# town clustered into a few look-alike groups (iter175).
const ROOF_COPPER := Color(0.34, 0.56, 0.50)   # weathered copper-green — civic landmarks (guildhall)
const ROOF_RUST   := Color(0.52, 0.23, 0.15)   # dark iron-red — smith/forge
const ROOF_MOSS   := Color(0.36, 0.48, 0.28)   # painted/mossy green — inn/brewery
const ROOF_BLUE   := Color(0.28, 0.40, 0.62)   # painted blue — trade/market
const ROOF_PALE   := Color(0.82, 0.82, 0.76)   # whitewashed — apothecary/healing
const ROOF_RUSSET := Color(0.78, 0.46, 0.20)   # warm clay — bakery/oven
const ROOF_LEATHER:= Color(0.46, 0.32, 0.20)   # tan leather-brown — tannery

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
	# Winter: snow settles on the upper third of each face, fanning down from the apex.
	if _winter:
		var g := 0.6   # snow reaches 40% down from the apex toward each eave corner
		for face in [[lu, tu, 0.74], [tu, ru, 0.90], [lu, bu, 0.74], [ru, bu, 0.88]]:
			ci.draw_colored_polygon(PackedVector2Array([apex,
				(face[0] as Vector2).lerp(apex, g), (face[1] as Vector2).lerp(apex, g)]),
				Color(SNOW, face[2]))
	ci.draw_polyline(PackedVector2Array([lu, apex, ru]), EDGE, 0.5)
	ci.draw_polyline(PackedVector2Array([bu, apex]), EDGE, 0.5)
	return apex

# Fill a roof slope as a triangle fan from an off-axis apex over a chain of (possibly
# collinear) edge points — robust where a single concave polygon's triangulation fails.
static func _slope_fan(ci: CanvasItem, apex: Vector2, pts: PackedVector2Array, col: Color) -> void:
	for i in range(pts.size() - 1):
		ci.draw_colored_polygon(PackedVector2Array([apex, pts[i], pts[i + 1]]), col)

# Gabled roof with a horizontal ridge running along the tu→bu (depth) axis.
static func _gable(ci: CanvasItem, c: PackedVector2Array, rh: float, roof: Color) -> void:
	var tu: Vector2 = c[0]; var ru: Vector2 = c[1]; var bu: Vector2 = c[2]; var lu: Vector2 = c[3]
	var rback := tu + Vector2(0, -rh)
	var rfront := bu + Vector2(0, -rh)
	var c_left := roof.darkened(0.18)
	var c_right := roof.lightened(0.08)
	# Each slope runs from a side eave (lu / ru) up to the raised ridge (rback→rfront).
	# tu, rback, rfront, bu are vertically COLLINEAR (the ridge sits on the depth axis), so
	# filling the slope as one concave pentagon makes draw_colored_polygon's triangulation
	# fail (a self-overlapping sliver). Fanning triangles from the OFF-AXIS eave corner is
	# always a valid decomposition — same fill, no per-frame "triangulation failed" spam.
	_slope_fan(ci, lu, PackedVector2Array([tu, rback, rfront, bu]), c_left)    # left slope
	_slope_fan(ci, ru, PackedVector2Array([tu, rback, rfront, bu]), c_right)   # right slope
	# Tile courses running parallel to the ridge down each slope.
	_courses(ci, [tu, lu, bu], rback, rfront, c_left.darkened(0.16))
	_courses(ci, [tu, ru, bu], rback, rfront, c_right.darkened(0.16))
	# Bright ridge cap + darker eave overhang give the roof real thickness.
	ci.draw_line(rback, rfront, roof.lightened(0.26), 1.4)
	ci.draw_polyline(PackedVector2Array([lu, bu, ru]), roof.darkened(0.30), 0.9)
	# Winter: a snow dusting hugging the ridge on each slope (eaves stay clear, so the
	# roof's type colour still reads). Right (lit) slope brighter than the shaded left.
	if _winter:
		var f := 0.5
		ci.draw_colored_polygon(PackedVector2Array(
			[rback, rfront, rfront.lerp(lu, f), rback.lerp(lu, f)]), Color(SNOW, 0.70))
		ci.draw_colored_polygon(PackedVector2Array(
			[rback, rfront, rfront.lerp(ru, f), rback.lerp(ru, f)]), Color(SNOW, 0.84))
		ci.draw_line(rback, rfront, Color(SNOW, 0.95), 1.6)
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
	# Winter: a snowcap over the top of the cone, fanning from the apex to an upper ring
	# (top ~37%, so the cone's type colour still reads on the body below).
	if _winter:
		var capfr := 0.63
		var rc := c + Vector2(0, -ht * capfr)
		var crx := rx * (1.0 - capfr)
		var cry := ry * (1.0 - capfr)
		for i in range(18):
			var a0 := TAU * float(i) / 18.0
			var a1 := TAU * float(i + 1) / 18.0
			var p0 := rc + Vector2(cos(a0) * crx, sin(a0) * cry)
			var p1 := rc + Vector2(cos(a1) * crx, sin(a1) * cry)
			var lit := 0.90 if (p0 + p1).y * 0.5 >= rc.y else 0.72   # front faces brighter
			ci.draw_colored_polygon(PackedVector2Array([p0, p1, apex]), Color(SNOW, lit))

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
	_ellipse(ci, ctr, rx * 0.98, ry * 0.98, Color(0, 0, 0, 0.12))
	_ellipse(ci, ctr, rx * 0.66, ry * 0.66, Color(0, 0, 0, 0.16))
	# Tight contact shadow hugging the front footprint edges (l→b→r) so the building reads as
	# planted ON the ground at its base — kills the "decal floating over grass" seam. A slim band
	# just below the front sill, fading outward.
	var drop := Vector2(0, 3.2)
	ci.draw_colored_polygon(PackedVector2Array([l, b, b + drop, l + drop]), Color(0, 0, 0, 0.26))
	ci.draw_colored_polygon(PackedVector2Array([b, r, r + drop, b + drop]), Color(0, 0, 0, 0.22))
	ci.draw_polyline(PackedVector2Array([l, b, r]), Color(0, 0, 0, 0.30), 1.0)

# Building btypes that ARE fields — they paint their own farmland ground, so they get NO earth pad.
const _FIELD_BTYPES := {
	"apple_orchard": true, "wheat_farm": true, "pig_farm": true, "dairy_farm": true, "hops_farm": true,
}

# Trodden-earth foundation pad: the grass underfoot is worn to packed, bare dirt where a building stands
# and folk come and go all day. Plants the structure in the world instead of leaving it floating on a
# manicured lawn — and scatters a few embedded stones/scuffs so the ground reads as lived-in. iter310.
static func _foundation(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2) -> void:
	var c := (t + b) * 0.5
	# A faint worn margin slightly beyond the footprint (grass → dirt), then the packed-earth core.
	var ex := 1.10
	var T := c + (t - c) * ex
	var R := c + (r - c) * ex
	var B := c + (b - c) * ex
	var L := c + (l - c) * ex
	var margin := Color(0.34, 0.28, 0.19, 0.30)
	var core   := Color(0.40, 0.33, 0.23, 0.62)
	var scuff  := Color(0.25, 0.20, 0.14, 0.55)
	if _winter:
		margin = Color(0.66, 0.68, 0.72, 0.28); core = Color(0.78, 0.80, 0.84, 0.5); scuff = Color(0.55, 0.58, 0.64, 0.45)
	ci.draw_colored_polygon(PackedVector2Array([T, R, B, L]), margin)
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), core)
	# Deterministic embedded stones/scuffs (seeded by tile position so they don't shimmer).
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(t.x) * 73856093) ^ (int(t.y) * 19349663)
	for _i in range(5):
		var u := rng.randf()
		var v := rng.randf()
		var p := l.lerp(t, u).lerp(b.lerp(r, u), v)   # a point inside the iso diamond
		ci.draw_circle(p, rng.randf_range(0.7, 1.5), scuff)

# ── Ambient yard props ───────────────────────────────────────────────────────────
# Barrels / crates / log piles / sacks scattered at a building's front so the settlement reads as a
# working, lived-in place rather than tidy empty boxes. Deterministic per tile (no shimmer),
# btype-flavoured, drawn AFTER the building model so they sit in front of it. iter311.
const _NO_PROP_BTYPES := {
	"wooden_palisade": true, "stone_wall": true, "gatehouse": true, "watchtower": true,
	"lookout_tower": true, "great_tower": true, "well": true, "stockpile": true, "pitch_rig": true,
	"apple_orchard": true, "wheat_farm": true, "pig_farm": true, "dairy_farm": true, "hops_farm": true,
}

static func _prop(ci: CanvasItem, base: Vector2, kind: String, rng: RandomNumberGenerator) -> void:
	# Reuses the file's existing prop primitives (_crate/_barrel/_sack/_log). A soft contact shadow
	# first so each prop sits on the earth rather than floating.
	_ellipse(ci, base + Vector2(0.8, 1.2), 3.6, 1.5, Color(0, 0, 0, 0.15))
	match kind:
		"crate":   _crate(ci, base + Vector2(0, -3.6), rng.randf_range(2.6, 3.3))
		"sacks":   _sack(ci, base + Vector2(-1.4, -1.0)); _sack(ci, base + Vector2(1.8, 0.6))
		"logpile":
			_log(ci, base + Vector2(0, -3.0), 1.8)
			_log(ci, base + Vector2(0.4, -0.6), 1.8)
		_:         _barrel(ci, base + Vector2(0, -2.6), rng.randf_range(2.3, 2.9))

static func _props(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, btype: String, seed: int) -> void:
	if _NO_PROP_BTYPES.has(btype):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(b.x) * 2654435761) ^ (int(b.y) * 40503) ^ (seed * 2246822519 + 7)
	var kinds := ["barrel", "crate", "sacks"]
	if btype in ["woodcutter_camp", "poleturner", "fletcher", "crossbow_workshop", "siege_workshop"]:
		kinds = ["logpile", "logpile", "crate"]
	elif btype in ["granary", "bakery", "mill"]:
		kinds = ["sacks", "sacks", "barrel"]
	elif btype in ["brewery", "inn", "tannery"]:
		kinds = ["barrel", "barrel", "crate"]
	if rng.randf() < 0.78:   # front-left, just outside the wall, on the earth pad
		_prop(ci, l.lerp(b, 0.62) + Vector2(-3.0, 2.0), kinds[rng.randi() % kinds.size()], rng)
	if rng.randf() < 0.5:    # sometimes a second on the front-right
		_prop(ci, b.lerp(r, 0.4) + Vector2(3.0, 2.0), kinds[rng.randi() % kinds.size()], rng)

# A clearly-readable entrance centred on the front-left face (l→b edge): a stone
# surround, an arched dark opening with a warm-lit interior, and a threshold step —
# so the player (and pawns) can plainly see where folk go in.
static func _door(ci: CanvasItem, l: Vector2, b: Vector2, ht: float, col: Color = Color(0.16, 0.10, 0.06)) -> void:
	var base := l.lerp(b, 0.5)
	var dir := (b - l).normalized()
	var e := dir * 3.4
	var fe := dir * 4.9
	var dh := minf(ht * 0.72, 14.0)
	# Threshold stone step at the foot (drawn first, under the opening).
	ci.draw_colored_polygon(PackedVector2Array([base - fe + Vector2(0, 0.5), base + fe + Vector2(0, 0.5),
		base + fe * 1.06 + Vector2(0, 3.4), base - fe * 1.06 + Vector2(0, 3.4)]), STONE_L.darkened(0.06))
	# Stone/timber frame surround (lighter), arched at the top.
	ci.draw_colored_polygon(PackedVector2Array([base - fe, base + fe, base + fe + Vector2(0, -dh - 2),
		base + Vector2(0, -dh - 6), base - fe + Vector2(0, -dh - 2)]), col.lightened(0.55))
	# Dark doorway opening (arched).
	ci.draw_colored_polygon(PackedVector2Array([base - e, base + e, base + e + Vector2(0, -dh),
		base + Vector2(0, -dh - 3.5), base - e + Vector2(0, -dh)]), col)
	# Warm interior — the way in glows softly so the entrance is unmistakable.
	var ie := dir * 2.3
	ci.draw_colored_polygon(PackedVector2Array([base - ie, base + ie, base + ie + Vector2(0, -dh * 0.72),
		base - ie + Vector2(0, -dh * 0.72)]), Color(0.95, 0.62, 0.28, 0.38))

static func _win(ci: CanvasItem, p: Vector2, col: Color = GLASS) -> void:
	ci.draw_rect(Rect2(p.x - 1.8, p.y - 2.0, 3.6, 4.0), col)

# A heater shield (heraldic) centred on c, half-width hw, in field colour with a charge dot.
static func _shield(ci: CanvasItem, c: Vector2, hw: float, field: Color, charge: Color) -> void:
	var h := hw * 1.3
	var pts := PackedVector2Array([
		c + Vector2(-hw, -h), c + Vector2(hw, -h), c + Vector2(hw, h * 0.2),
		c + Vector2(0, h), c + Vector2(-hw, h * 0.2)])
	ci.draw_colored_polygon(pts, field)
	ci.draw_polyline(pts, field.darkened(0.4), 0.7)
	ci.draw_line(c + Vector2(0, -h), c + Vector2(0, h * 0.6), field.lightened(0.25), 0.7)  # pale
	ci.draw_circle(c + Vector2(0, -h * 0.25), hw * 0.42, charge)

# A rose window: stone ring, blue glass, radial tracery spokes.
static func _rose(ci: CanvasItem, c: Vector2, rad: float) -> void:
	ci.draw_circle(c, rad + 1.2, STONE_L)
	ci.draw_circle(c, rad, Color(0.34, 0.46, 0.74))
	for k in range(6):
		var a := TAU * float(k) / 6.0
		ci.draw_line(c, c + Vector2(cos(a), sin(a)) * rad, Color(0.78, 0.82, 0.92), 0.6)
	ci.draw_circle(c, rad * 0.3, Color(0.62, 0.72, 0.90))

# ── Massing & detail vocabulary (iter321) ────────────────────────────────────────
# These let a building be COMPOSED from several masses + rich detail so it reads as a real
# structure with a characterful silhouette, not a single box wearing one giant roof. The
# footprint is param-mapped: _pt(u,v) with l=(0,0) t=(1,0) r=(1,1) b=(0,1) — so a wing can be
# placed over any sub-rectangle of the plot.

static func _pt(t: Vector2, r: Vector2, b: Vector2, l: Vector2, u: float, v: float) -> Vector2:
	return l + (t - l) * u + (b - l) * v

# A box occupying the sub-rect [u0,u1]×[v0,v1] of the footprint. Returns the box's top diamond
# corners [tu,ru,bu,lu] so a roof (_gable/_hip) can be laid on it. Draw back masses (small v/u)
# before front masses (large v) for correct overlap.
static func _subbox(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2,
		u0: float, v0: float, u1: float, v1: float, ht: float, wall: Color, tex: int = TEX_NONE) -> PackedVector2Array:
	var st := _pt(t, r, b, l, u1, v0)
	var sr := _pt(t, r, b, l, u1, v1)
	var sb := _pt(t, r, b, l, u0, v1)
	var sl := _pt(t, r, b, l, u0, v0)
	return _box(ci, st, sr, sb, sl, ht, wall, tex)

# A small finial — ball + spike — to cap a ridge/spire/post.
static func _finial(ci: CanvasItem, top: Vector2, col: Color = GOLD, s: float = 1.0) -> void:
	ci.draw_line(top, top + Vector2(0, -5.0 * s), col.darkened(0.2), 1.3 * s)
	ci.draw_circle(top + Vector2(0, -5.0 * s), 1.7 * s, col)
	ci.draw_circle(top + Vector2(-0.5, -5.5 * s), 0.7 * s, col.lightened(0.3))

# A proper brick/stone chimney stack rising `ht` from `base`, with a corbelled cap and (when the
# building is _active) a drifting hearth-smoke plume. The signature roof detail that says "hearth".
static func _chimney(ci: CanvasItem, base: Vector2, ht: float, time: float,
		brick: Color = Color(0.47, 0.35, 0.27), smoke: bool = true) -> void:
	var w := 2.4
	var top := base + Vector2(0, -ht)
	ci.draw_colored_polygon(PackedVector2Array([base + Vector2(-w, 0), base + Vector2(w, 0),
		top + Vector2(w, 0), top + Vector2(-w, 0)]), brick)
	ci.draw_colored_polygon(PackedVector2Array([base + Vector2(0, 0), base + Vector2(w, 0),
		top + Vector2(w, 0), top + Vector2(0, 0)]), brick.darkened(0.16))   # shaded half
	for k in range(1, int(ht / 4.0)):                                       # brick courses
		var y := top.y + float(k) * 4.0
		ci.draw_line(Vector2(base.x - w, y), Vector2(base.x + w, y), brick.darkened(0.22), 0.4)
	ci.draw_rect(Rect2(top.x - w - 0.9, top.y - 2.2, (w + 0.9) * 2.0, 2.6), brick.lightened(0.16))  # corbel cap
	if smoke and _active:
		for k in range(3):
			var sy: float = fmod(time * 6.0 + float(k) * 5.0, 16.0)
			ci.draw_circle(top + Vector2(sin(time * 1.7 + float(k)) * 2.0, -3.0 - sy),
				1.3 + sy * 0.11, Color(0.84, 0.84, 0.84, 0.26 * (1.0 - sy / 16.0)))

# A gabled dormer poking out of a roof slope at p (its eave point), facing front: a little wall
# face, a gable, and a lit window. Breaks up a big roof plane so it reads as inhabited.
static func _dormer(ci: CanvasItem, p: Vector2, wd: float, ht: float, roof: Color) -> void:
	var hw := wd * 0.5
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-hw, 0), p + Vector2(hw, 0),
		p + Vector2(hw, -ht), p + Vector2(-hw, -ht)]), Color(0.74, 0.68, 0.54))      # dormer wall
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-hw - 1.0, -ht), p + Vector2(hw + 1.0, -ht),
		p + Vector2(0, -ht - hw * 1.1)]), roof.lightened(0.05))                      # dormer gable roof
	ci.draw_rect(Rect2(p.x - hw * 0.5, p.y - ht + 1.0, hw, ht - 2.0), GLASS)         # window
	ci.draw_line(p + Vector2(0, -ht + 1.0), p + Vector2(0, -1.0), WOOD_D, 0.5)

# A tall slender spire (octagonal-read cone) on ground-projected centre c, capped with a finial.
static func _spire(ci: CanvasItem, c: Vector2, rx: float, ht: float, col: Color) -> void:
	_cone(ci, c, rx, rx * 0.5, ht, col)
	_finial(ci, c + Vector2(0, -ht), GOLD, 1.1)

# A tall pointed (lancet/gothic) window centred at p, height h.
static func _lancet(ci: CanvasItem, p: Vector2, h: float, glass: Color = Color(0.40, 0.55, 0.82)) -> void:
	var w := h * 0.20
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-w, 0), p + Vector2(w, 0),
		p + Vector2(w, -h * 0.66), p + Vector2(0, -h), p + Vector2(-w, -h * 0.66)]), STONE_L)  # surround
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-w * 0.66, -1.2), p + Vector2(w * 0.66, -1.2),
		p + Vector2(w * 0.66, -h * 0.64), p + Vector2(0, -h * 0.9), p + Vector2(-w * 0.66, -h * 0.64)]), glass)
	ci.draw_line(p + Vector2(0, -1.2), p + Vector2(0, -h * 0.86), glass.darkened(0.3), 0.5)

# A round-headed (arched) window/opening centred at p.
static func _arched_win(ci: CanvasItem, p: Vector2, w: float, h: float, glass: Color = GLASS) -> void:
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-w, 0), p + Vector2(w, 0),
		p + Vector2(w, -h * 0.7), p + Vector2(w * 0.6, -h), p + Vector2(-w * 0.6, -h), p + Vector2(-w, -h * 0.7)]), glass)
	ci.draw_polyline(PackedVector2Array([p + Vector2(-w, 0), p + Vector2(-w, -h * 0.7),
		p + Vector2(-w * 0.6, -h), p + Vector2(w * 0.6, -h), p + Vector2(w, -h * 0.7), p + Vector2(w, 0)]), STONE_D, 0.6)

# A hanging shop sign on a bracket arm off a wall point `p`, with a small painted board.
static func _hanging_sign(ci: CanvasItem, p: Vector2, board: Color, icon: Callable = Callable()) -> void:
	ci.draw_line(p, p + Vector2(7, -1), WOOD_D, 1.2)                       # bracket arm
	ci.draw_line(p + Vector2(2, -1), p + Vector2(6, -4), WOOD_D, 0.8)      # diagonal stay
	var bc := p + Vector2(7, 5)
	ci.draw_line(p + Vector2(7, -1), bc + Vector2(-2, -4), WOOD_D, 0.5)    # hang chains
	ci.draw_line(p + Vector2(7, -1), bc + Vector2(2, -4), WOOD_D, 0.5)
	ci.draw_rect(Rect2(bc.x - 3.4, bc.y - 4.0, 6.8, 7.0), board)
	ci.draw_rect(Rect2(bc.x - 3.4, bc.y - 4.0, 6.8, 7.0), WOOD_D, false, 0.7)
	if icon.is_valid():
		icon.call(ci, bc + Vector2(0, -0.5))

# A covered entrance porch: two posts carrying a little lean-to/awning roof over the front door,
# centred on the l→b face. `dir` is the front-face direction (b-l normalised).
static func _porch(ci: CanvasItem, l: Vector2, b: Vector2, ht: float, roof: Color, depth: float = 5.0) -> void:
	var base := l.lerp(b, 0.5)
	var e := (b - l).normalized()
	var fwd := Vector2(-depth * 0.4, depth)
	var pL := base - e * 4.0 + fwd
	var pR := base + e * 4.0 + fwd
	var pLt := _post(ci, pL, ht * 0.55, WOOD_D, 1.6)
	var pRt := _post(ci, pR, ht * 0.55, WOOD_D, 1.6)
	var wL := base - e * 4.2 + Vector2(0, -ht * 0.62)
	var wR := base + e * 4.2 + Vector2(0, -ht * 0.62)
	ci.draw_colored_polygon(PackedVector2Array([wL, wR, pRt, pLt]), roof.darkened(0.06))
	ci.draw_polyline(PackedVector2Array([wL, pLt]), roof.darkened(0.28), 0.6)
	ci.draw_polyline(PackedVector2Array([pLt, pRt]), roof.lightened(0.2), 0.8)

# A square battlemented stone tower over a sub-rect of the footprint, capped EITHER with
# crenellations ("battle") or a conical roof ("cone"). Returns the top diamond corners.
static func _stone_tower(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2,
		u0: float, v0: float, u1: float, v1: float, ht: float, cap: String = "battle",
		wall: Color = STONE) -> PackedVector2Array:
	var c := _subbox(ci, t, r, b, l, u0, v0, u1, v1, ht, wall, TEX_STONE)
	if cap == "cone":
		var cc := (c[0] + c[2]) * 0.5
		var rx: float = absf((c[1].x - c[3].x)) * 0.5 + 1.5
		_cone(ci, cc, rx, rx * 0.5, rx * 1.4, SLATE)
		_finial(ci, cc + Vector2(0, -rx * 1.4), GOLD, 0.9)
	else:
		_snow_top(ci, c, 0.4)
		_merlons(ci, c[3], c[2], wall.lightened(0.12), 3)
		_merlons(ci, c[2], c[1], wall.lightened(0.12), 3)
	return c

# A buttress leaning against the l→b wall at fraction f, rising to bh — stepped stone with a
# weathered set-off. Extracted from the church so any masonry building can use it.
static func _buttress(ci: CanvasItem, l: Vector2, b: Vector2, f: float, bh: float, wall: Color) -> void:
	var bs := l.lerp(b, f)
	var fo := bs + Vector2(-3, 3)
	ci.draw_colored_polygon(PackedVector2Array([bs, fo, fo + Vector2(0, -bh * 0.82), bs + Vector2(0, -bh)]), wall.darkened(0.06))
	ci.draw_colored_polygon(PackedVector2Array([bs + Vector2(0, -bh), fo + Vector2(0, -bh * 0.82), bs + Vector2(0, -bh - 4)]), STONE_L)
	ci.draw_polyline(PackedVector2Array([fo, fo + Vector2(0, -bh * 0.82)]), EDGE, 0.5)

# ── Dispatcher ──────────────────────────────────────────────────────────────────

static func draw_finished(ci: CanvasItem, btype: String, cat: int, w: int, h: int,
		t: Vector2, r: Vector2, b: Vector2, l: Vector2,
		wall: Color, roof: Color, trim: Color, time: float, season: int = SeasonSystem.Season.SUMMER,
		seed: int = 0, active: bool = true) -> void:
	var ctr := (t + b) * 0.5
	_winter = (season == SeasonSystem.Season.WINTER)
	_active = active
	# Worn-earth pad under structures (fields paint their own ground), then the cast shadow on top.
	if not _FIELD_BTYPES.has(btype):
		_foundation(ci, t, r, b, l)
	_shadow(ci, t, r, b, l)
	match btype:
		"village_hall":      _village_hall(ci, t, r, b, l, ctr)
		"keep":              _keep(ci, t, r, b, l, ctr, time)
		"hovel":             _hovel(ci, t, r, b, l, time)
		"market":            _market(ci, t, r, b, l, ctr, seed)
		"trading_post":      _trading_post(ci, t, r, b, l, ctr)
		"well":              _well(ci, t, r, b, l, ctr)
		"apothecary":        _apothecary(ci, t, r, b, l, ctr)
		"guildhall":         _guildhall(ci, t, r, b, l, ctr)
		"woodcutter_camp":   _woodcutter(ci, t, r, b, l, ctr, seed)
		"stone_quarry":      _quarry(ci, t, r, b, l, ctr)
		"iron_mine":         _mine(ci, t, r, b, l, ctr)
		"pitch_rig":         _pitch_rig(ci, t, r, b, l, ctr, time)
		"stockpile":         _stockpile(ci, t, r, b, l, ctr)
		"apple_orchard":     _orchard(ci, t, r, b, l, season, seed)
		"pig_farm":          _pen(ci, t, r, b, l, ctr, Color(0.86, 0.62, 0.62))
		"dairy_farm":        _dairy(ci, t, r, b, l, ctr)
		"wheat_farm":        _wheat(ci, t, r, b, l, ctr, season, seed)
		"hops_farm":         _hops(ci, t, r, b, l, season)
		"mill":              _windmill(ci, t, r, b, l, ctr, time)
		"bakery":            _bakery(ci, t, r, b, l, ctr, time)
		"brewery":           _brewery(ci, t, r, b, l, ctr, time)
		"inn":               _inn(ci, t, r, b, l, ctr, time)
		"granary":           _granary(ci, t, r, b, l, ctr)
		"church":            _church(ci, t, r, b, l, ctr, false)
		"cathedral":         _church(ci, t, r, b, l, ctr, true)
		"barracks":          _barracks(ci, t, r, b, l, ctr, seed)
		"siege_workshop":    _siege(ci, t, r, b, l, ctr)
		"blacksmith", "armorer": _forge(ci, t, r, b, l, ctr, time, seed)
		"armory":            _armory(ci, t, r, b, l, ctr)
		"fletcher":          _fletcher(ci, t, r, b, l, ctr, time)
		"crossbow_workshop": _crossbow(ci, t, r, b, l, ctr, time)
		"poleturner":        _poleturner(ci, t, r, b, l, ctr)
		"tannery":           _tannery(ci, t, r, b, l, ctr)
		"wooden_palisade":   _palisade(ci, t, r, b, l)
		"stone_wall":        _stone_wall(ci, t, r, b, l)
		"gatehouse":         _gatehouse(ci, t, r, b, l, ctr)
		"watchtower", "lookout_tower": _watchtower(ci, t, r, b, l, ctr)
		"great_tower":       _great_tower(ci, t, r, b, l, ctr)
		_:                   _generic(ci, t, r, b, l, wall, roof)
	# Ambient yard props at the front (barrels/crates/logs/sacks) — drawn last so they sit in front.
	_props(ci, t, r, b, l, btype, seed)

# ── CIVIC ────────────────────────────────────────────────────────────────────────

static func _village_hall(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# A timber-framed MANOR HALL: a back service wing, a broad main hall, and a projecting cross-
	# gabled entrance porch bay — an L/T plan with a broken roofline, chimneys, dormers and heraldry,
	# rather than one box under a single tile pyramid.
	# Back service wing (drawn first).
	var wing := _subbox(ci, t, r, b, l, 0.55, 0.10, 0.92, 0.52, 24.0, WOOD, TEX_TIMBER)
	_gable(ci, wing, 12.0, TILE.darkened(0.04))
	_chimney(ci, _pt(t, r, b, l, 0.88, 0.30) + Vector2(0, -24), 16.0, 0.0, Color(0.5, 0.36, 0.28), false)
	# Main hall (broad, front).
	var hall := _subbox(ci, t, r, b, l, 0.10, 0.40, 0.92, 0.94, 28.0, WOOD_L, TEX_TIMBER)
	var hl: Vector2 = hall[3] + Vector2(0, 28.0); var hb: Vector2 = hall[2] + Vector2(0, 28.0); var hr: Vector2 = hall[1] + Vector2(0, 28.0)
	_win(ci, hl.lerp(hb, 0.30) + Vector2(0, -17)); _win(ci, hl.lerp(hb, 0.30) + Vector2(0, -8))
	_win(ci, hb.lerp(hr, 0.70) + Vector2(0, -17)); _win(ci, hb.lerp(hr, 0.70) + Vector2(0, -8))
	_gable(ci, hall, 16.0, TILE)
	# Dormers breaking the main roof slope (front-right face).
	_dormer(ci, hb.lerp(hr, 0.36) + Vector2(0, -30), 6.0, 5.0, TILE)
	_dormer(ci, hb.lerp(hr, 0.64) + Vector2(0, -30), 6.0, 5.0, TILE)
	# Hall chimney + ridge banner.
	_chimney(ci, _pt(t, r, b, l, 0.20, 0.6) + Vector2(0, -28), 18.0, 0.0, Color(0.5, 0.36, 0.28), false)
	var ridge := (hall[0] + hall[2]) * 0.5 + Vector2(0, -16.0)
	var tp := _post(ci, ridge, 11.0, WOOD_D, 1.5)
	ci.draw_colored_polygon(PackedVector2Array([tp, tp + Vector2(11, 3), tp + Vector2(0, 8)]), RED)
	ci.draw_circle(tp + Vector2(3, 3), 1.1, GOLD)
	# Projecting cross-gabled entrance porch bay (drawn last, frontmost).
	var porch := _subbox(ci, t, r, b, l, 0.32, 0.66, 0.64, 1.02, 22.0, WOOD_L, TEX_TIMBER)
	_gable(ci, porch, 13.0, TILE)
	_door(ci, _pt(t, r, b, l, 0.34, 0.98), _pt(t, r, b, l, 0.62, 0.98), 22.0)
	_shield(ci, porch[2] + Vector2(0, -7), 3.6, Color(0.22, 0.34, 0.6), GOLD)

# A round corner drum-tower for the keep: tapered stone drum, a corbelled machicolation ring, a
# steep conical roof + finial, and (optionally) a flying banner.
static func _keep_tower(ci: CanvasItem, g: Vector2, rx: float, ht: float, time: float, banner: bool) -> void:
	var top := _cyl(ci, g, rx, rx * 0.5, ht, STONE)
	_ring(ci, top + Vector2(0, 1.5), rx + 1.4, (rx + 1.4) * 0.5, STONE_D, 1.4)   # corbel/machicolation ring
	_ring(ci, top + Vector2(0, 0.0), rx + 0.6, (rx + 0.6) * 0.5, STONE_L, 0.8)
	for hy in [ht * 0.40, ht * 0.66]:                                            # arrow-slits
		ci.draw_rect(Rect2(g.x - 0.7, g.y - hy - 3.0, 1.4, 6.0), Color(0.06, 0.06, 0.08))
	_cone(ci, top + Vector2(0, -1.0), rx + 1.0, (rx + 1.0) * 0.5, rx * 2.2, SLATE)
	_finial(ci, top + Vector2(0, -1.0 - rx * 2.2), GOLD, 1.0)
	if banner:
		var fp: Vector2 = top + Vector2(0, -1.0 - rx * 2.2 - 5.0)
		var ftp := _post(ci, fp, 10.0, WOOD_D, 1.2)
		var wav := sin(time * 3.0) * 2.0
		ci.draw_colored_polygon(PackedVector2Array([ftp, ftp + Vector2(10 + wav, 3), ftp + Vector2(0, 8)]), RED)
		ci.draw_circle(ftp + Vector2(3, 3), 1.2, GOLD)

static func _keep(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, time: float) -> void:
	# A great rectangular DONJON with four round corner drum-towers rising above the battlements, a
	# projecting gatehouse forebuilding, arrow-slits and a realm banner — an imposing castle keep,
	# not a flat grey slab.
	var Hmain := 46.0
	var trx: float = clampf(l.distance_to(r) * 0.065, 5.5, 9.0)
	var Htwr := Hmain + 14.0
	var gL := _pt(t, r, b, l, 0.11, 0.11)
	var gT := _pt(t, r, b, l, 0.89, 0.11)
	var gR := _pt(t, r, b, l, 0.89, 0.89)
	var gB := _pt(t, r, b, l, 0.11, 0.89)
	# Back drum-towers first (painter's order).
	_keep_tower(ci, gL, trx, Htwr, time, false)
	_keep_tower(ci, gT, trx, Htwr, time, false)
	# Main keep block.
	var c := _subbox(ci, t, r, b, l, 0.13, 0.13, 0.87, 0.87, Hmain, STONE, TEX_STONE)
	# Arrow-slit windows in two registers on both front faces.
	var ml: Vector2 = c[3] + Vector2(0, Hmain); var mb: Vector2 = c[2] + Vector2(0, Hmain); var mr: Vector2 = c[1] + Vector2(0, Hmain)
	for f in [0.30, 0.70]:
		for hy in [Hmain * 0.42, Hmain * 0.68]:
			var sl := ml.lerp(mb, f) + Vector2(0, -hy)
			ci.draw_rect(Rect2(sl.x - 0.8, sl.y - 3.5, 1.6, 7.0), Color(0.05, 0.05, 0.07))
			ci.draw_line(sl + Vector2(-1.8, -3.7), sl + Vector2(1.8, -3.7), STONE_L, 0.6)
			var sr := mb.lerp(mr, f) + Vector2(0, -hy)
			ci.draw_rect(Rect2(sr.x - 0.8, sr.y - 3.5, 1.6, 7.0), Color(0.05, 0.05, 0.07))
			ci.draw_line(sr + Vector2(-1.8, -3.7), sr + Vector2(1.8, -3.7), STONE_L, 0.6)
	_snow_top(ci, c, 0.4)
	_merlons(ci, c[3], c[2], STONE_L, 4)
	_merlons(ci, c[2], c[1], STONE_L, 4)
	# Projecting gatehouse forebuilding at the front, with an arched gate + portcullis.
	var fb := _subbox(ci, t, r, b, l, 0.30, 0.74, 0.70, 1.0, 26.0, STONE, TEX_STONE)
	var ar := _pt(t, r, b, l, 0.5, 1.0)
	ci.draw_colored_polygon(PackedVector2Array([ar + Vector2(-5, -1), ar + Vector2(5, -1),
		ar + Vector2(5, -13), ar + Vector2(0, -18), ar + Vector2(-5, -13)]), Color(0.05, 0.05, 0.07))
	for i in range(4):
		ci.draw_line(ar + Vector2(-3.6 + i * 2.4, -1), ar + Vector2(-3.6 + i * 2.4, -12), IRON, 0.7)
	for i in range(2):
		ci.draw_line(ar + Vector2(-5, -3 - i * 4), ar + Vector2(5, -3 - i * 4), IRON_D, 0.6)
	_merlons(ci, fb[3], fb[2], STONE_L, 2)
	_merlons(ci, fb[2], fb[1], STONE_L, 2)
	# Front drum-towers last (banner on the front-right).
	_keep_tower(ci, gB, trx, Htwr, time, false)
	_keep_tower(ci, gR, trx, Htwr, time, true)

static func _merlons(ci: CanvasItem, a: Vector2, bb: Vector2, col: Color, n: int) -> void:
	for i in range(n):
		var p: Vector2 = a.lerp(bb, (float(i) + 0.5) / float(n))
		ci.draw_rect(Rect2(p.x - 2.4, p.y - 4.5, 4.8, 4.5), col)
		if _winter:   # snow piled on each crenellation
			ci.draw_rect(Rect2(p.x - 2.7, p.y - 5.7, 5.4, 1.7), SNOW)

# Translucent snow dusting over a box's top diamond (an exposed wall-walk / parapet).
static func _snow_top(ci: CanvasItem, c: PackedVector2Array, alpha: float = 0.5) -> void:
	if not _winter:
		return
	ci.draw_colored_polygon(PackedVector2Array([c[0], c[1], c[2], c[3]]), Color(SNOW, alpha))

static func _hovel(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, time: float = 0.0) -> void:
	# A humble cob-and-timber COTTAGE: a thatched main block with a lower lean-to wing, a stout
	# smoking hearth chimney and a roof dormer — reads as a lived-in home, not a plain box.
	var daub := Color(0.74, 0.64, 0.47)
	# Lean-to wing at the back-right (drawn first so the main block overlaps it).
	var wing := _subbox(ci, t, r, b, l, 0.60, 0.12, 0.98, 0.60, 10.5, daub.darkened(0.05), TEX_TIMBER)
	_gable(ci, wing, 6.0, THATCH_D)
	# Main block.
	var c := _subbox(ci, t, r, b, l, 0.05, 0.10, 0.74, 0.95, 16.0, daub, TEX_TIMBER)
	var mb: Vector2 = c[2] + Vector2(0, 16.0); var mr: Vector2 = c[1] + Vector2(0, 16.0)
	_win(ci, mb.lerp(mr, 0.6) + Vector2(0, -9))
	_door(ci, _pt(t, r, b, l, 0.05, 0.18), _pt(t, r, b, l, 0.05, 0.95), 16.0)
	_gable(ci, c, 12.0, THATCH)
	_dormer(ci, mb.lerp(mr, 0.3) + Vector2(0, -16), 5.0, 4.0, THATCH)
	# Stout hearth chimney at the gable end, with a hearth-smoke wisp when the home is occupied.
	_chimney(ci, _pt(t, r, b, l, 0.16, 0.5) + Vector2(0, -16), 13.0, time, Color(0.46, 0.34, 0.22))

static func _market(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, seed: int = 0) -> void:
	# Open-air stalls around a stone market cross — stall count, awning colours and goods
	# vary per market so a row of them reads as distinct squares, not clones.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 2654435761 + 91
	var awnings := [Color(0.82, 0.30, 0.24), Color(0.86, 0.82, 0.74), Color(0.30, 0.46, 0.72), Color(0.40, 0.62, 0.34), Color(0.74, 0.58, 0.24)]
	awnings.shuffle()
	# Trodden market ground.
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), Color(0.52, 0.47, 0.34))
	# Packed-earth / cobbled square — speckled tones so the trodden market ground reads as worked
	# stone-and-dirt, not a flat slab. Count scales with the plot area so a big square stays covered.
	_speckle_ground(ci, l, t - l, b - l,
		[Color(0.60, 0.55, 0.42), Color(0.46, 0.41, 0.30), Color(0.50, 0.47, 0.40), Color(0.40, 0.36, 0.28)],
		clampi(int(90.0 * absf((t - l).cross(b - l)) / 900.0), 90, 900), 0.7, 1.5, rng)
	var anchors := [l.lerp(ctr, 0.55), r.lerp(ctr, 0.55), b.lerp(ctr, 0.45), t.lerp(ctr, 0.5)]
	var stalls := []
	var n_stalls: int = rng.randi_range(3, 4)
	for i in range(n_stalls):
		stalls.append([anchors[i] + Vector2(rng.randf_range(-3, 3), rng.randf_range(-2, 2)), awnings[i % awnings.size()]])
	for s in stalls:
		var g: Vector2 = s[0]
		var p1 := _post(ci, g + Vector2(-7, 0), 12.0, WOOD_D)
		var p2 := _post(ci, g + Vector2(7, 0), 12.0, WOOD_D)
		ci.draw_colored_polygon(PackedVector2Array([p1, p2, p2 + Vector2(0, 4), p1 + Vector2(0, 4)]), s[1])
		ci.draw_colored_polygon(PackedVector2Array([p1, p2, (p1 + p2) * 0.5 + Vector2(0, 5)]), (s[1] as Color).darkened(0.15))
		ci.draw_rect(Rect2(g.x - 5, g.y - 4, 10, 4), WOOD)  # crate counter
	# Hero detail: a stone market cross — the heart of the marketplace.
	var mc := ctr + Vector2(0, -1)
	for i in range(3):                                  # stepped plinth
		var sw := 8.0 - float(i) * 2.2
		_ellipse(ci, mc + Vector2(0, 2 - float(i) * 2.0), sw, sw * 0.42, STONE_L.darkened(0.05 * float(i)))
	var shaft := _post(ci, mc + Vector2(0, -2), 19.0, STONE, 2.4)
	ci.draw_circle(shaft + Vector2(0, 1), 1.6, STONE_D)
	ci.draw_circle(shaft + Vector2(0, -3), 3.0, STONE_L)   # ball finial
	# produce on display + a sack of grain
	var disp := r.lerp(ctr, 0.55) + Vector2(0, 6)
	for fp in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2)]:
		ci.draw_circle(disp + fp, 1.3, Color(0.82, 0.30, 0.22))
	_sack(ci, l.lerp(ctr, 0.55) + Vector2(2, 7))
	_crate(ci, b.lerp(ctr, 0.45) + Vector2(6, 6), 3.5)

static func _trading_post(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# A merchant's house with an open-fronted market LOGGIA: a planked main block with a goods loft
	# dormer + blue roof, an awninged stall along the front piled with wares, and a gilt coin sign.
	# Main block (back).
	var c := _subbox(ci, t, r, b, l, 0.34, 0.10, 0.92, 0.88, 19.0, WOOD, TEX_PLANK)
	var ml: Vector2 = c[3] + Vector2(0, 19.0); var mb: Vector2 = c[2] + Vector2(0, 19.0); var mr: Vector2 = c[1] + Vector2(0, 19.0)
	_win(ci, mb.lerp(mr, 0.6) + Vector2(0, -11))
	_door(ci, _pt(t, r, b, l, 0.34, 0.20), _pt(t, r, b, l, 0.34, 0.88), 19.0)
	_gable(ci, c, 12.0, ROOF_BLUE)
	_dormer(ci, mb.lerp(mr, 0.35) + Vector2(0, -21), 6.0, 5.0, ROOF_BLUE)
	# Open market loggia along the front-left (a striped awning on posts over a goods counter).
	var aL := _pt(t, r, b, l, 0.06, 0.30); var aR := _pt(t, r, b, l, 0.06, 0.92)
	var pL := _post(ci, aL + Vector2(0, 2), 14.0, WOOD_D, 1.8)
	var pR := _post(ci, aR + Vector2(0, 2), 14.0, WOOD_D, 1.8)
	var aLt := aL + Vector2(0, -17); var aRt := aR + Vector2(0, -17)
	ci.draw_colored_polygon(PackedVector2Array([aLt, aRt, pR, pL]), Color(0.82, 0.36, 0.28))   # awning
	for f in [0.2, 0.5, 0.8]:
		ci.draw_line(aLt.lerp(aRt, f), pL.lerp(pR, f), Color(0.92, 0.86, 0.78), 1.2)            # stripes
	ci.draw_colored_polygon(PackedVector2Array([pL + Vector2(0, -1), pR + Vector2(0, -1), pR + Vector2(0, 3), pL + Vector2(0, 3)]), WOOD)  # counter
	_crate(ci, aL.lerp(aR, 0.3) + Vector2(2, 4), 3.0)
	_barrel(ci, aL.lerp(aR, 0.7) + Vector2(2, 4), 3.0)
	for fp in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2)]:
		ci.draw_circle(aL.lerp(aR, 0.5) + Vector2(0, 1) + fp, 1.2, Color(0.84, 0.34, 0.24))
	# Gilt coin sign over the door.
	_hanging_sign(ci, mb.lerp(mr, 0.45) + Vector2(0, -16), Color(0.30, 0.34, 0.5),
		func(c2, p): c2.draw_circle(p, 2.4, GOLD); c2.draw_circle(p, 1.1, GOLD.darkened(0.2)))

static func _well(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# A proper stone wellhead — enlarged + detailed so it reads at play-zoom (the old version was
	# a tiny puck that vanished among the bigger buildings). A wider/taller stone rim with a dark
	# water disc, two stout posts carrying a little gabled roof, a windlass crossbar, rope + bucket.
	var topc := _cyl(ci, ctr + Vector2(0, 5), 9.0, 4.2, 9.0, STONE)              # stone wellhead
	_ellipse(ci, topc, 7.6, 3.4, STONE.lightened(0.12))                          # rim lip
	_ellipse(ci, topc + Vector2(0, 0.6), 6.0, 2.6, Color(0.08, 0.17, 0.30))      # dark water
	var p1 := _post(ci, ctr + Vector2(-9, 5), 22.0, WOOD_D, 2.4)
	var p2 := _post(ci, ctr + Vector2(9, 5), 22.0, WOOD_D, 2.4)
	var apex := (p1 + p2) * 0.5 + Vector2(0, -8)                                 # gabled roof
	ci.draw_colored_polygon(PackedVector2Array([p1, p2, apex]), THATCH)
	ci.draw_line(p1, apex, THATCH_D, 1.6)
	ci.draw_line(p2, apex, THATCH_D, 1.6)
	var bar_y: float = (p1.y + p2.y) * 0.5 + 3.0
	ci.draw_line(Vector2(p1.x, bar_y), Vector2(p2.x, bar_y), WOOD, 2.2)          # windlass crossbar
	ci.draw_line(Vector2(ctr.x, bar_y), ctr + Vector2(0, -3), Color(0.45, 0.38, 0.26), 1.2)  # rope
	ci.draw_rect(Rect2(ctr.x - 3, ctr.y - 5, 6, 6), WOOD)                        # bucket
	ci.draw_rect(Rect2(ctr.x - 3, ctr.y - 5, 6, 1.6), WOOD_D)                    # bucket rim

static func _guildhall(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# A dignified civic hall: an ashlar main block with a hipped copper roof, a colonnaded entrance
	# portico under a pediment, arched windows, and a central copper-domed cupola lantern with a
	# clock and a gilt finial — the town's landmark, not a plain box.
	var c := _subbox(ci, t, r, b, l, 0.08, 0.16, 0.92, 0.88, 30.0, STONE_L, TEX_STONE)
	var gl: Vector2 = c[3] + Vector2(0, 30.0); var gb: Vector2 = c[2] + Vector2(0, 30.0); var gr: Vector2 = c[1] + Vector2(0, 30.0)
	# Arched windows along the upper walls.
	for f in [0.28, 0.72]:
		_arched_win(ci, gl.lerp(gb, f) + Vector2(0, -16), 2.2, 8.0)
		_arched_win(ci, gb.lerp(gr, f) + Vector2(0, -16), 2.2, 8.0)
	_hip(ci, c, 12.0, ROOF_COPPER)
	# Colonnaded portico across the front (entrance) face with an entablature + pediment.
	var cols := []
	for f in [0.20, 0.40, 0.60, 0.80]:
		var bp: Vector2 = gl.lerp(gb, f) + Vector2(-1.5, 3.0)
		cols.append(_post(ci, bp, 22.0, STONE_L, 2.4))
		ci.draw_line(bp, bp + Vector2(0, -22.0), STONE_D, 0.6)   # flute shadow
	ci.draw_colored_polygon(PackedVector2Array([cols[0] + Vector2(0, -1), cols[3] + Vector2(0, -1),
		cols[3] + Vector2(0, -5), cols[0] + Vector2(0, -5)]), STONE_L)   # entablature
	ci.draw_colored_polygon(PackedVector2Array([cols[0] + Vector2(-1, -5), cols[3] + Vector2(1, -5),
		(cols[0] + cols[3]) * 0.5 + Vector2(0, -12)]), ROOF_COPPER)      # pediment
	ci.draw_circle((cols[0] + cols[3]) * 0.5 + Vector2(0, -6), 1.8, GOLD)
	_door(ci, gl.lerp(gb, 0.34), gl.lerp(gb, 0.66), 22.0)
	# Central cupola lantern: a small octagon-read drum + copper dome + clock + finial.
	var cu := (c[0] + c[2]) * 0.5 + Vector2(0, -10)
	_cyl(ci, cu, 5.0, 2.4, 9.0, STONE_L)
	ci.draw_circle(cu + Vector2(0, -5), 2.6, Color(0.92, 0.90, 0.82))    # clock face
	ci.draw_line(cu + Vector2(0, -5), cu + Vector2(0, -7), IRON_D, 0.7)
	ci.draw_line(cu + Vector2(0, -5), cu + Vector2(1.4, -5), IRON_D, 0.7)
	var dome := cu + Vector2(0, -9)
	_cone(ci, dome, 6.0, 3.0, 8.0, ROOF_COPPER.lightened(0.05))
	_finial(ci, dome + Vector2(0, -8), GOLD, 1.0)

# ── HARVESTING ───────────────────────────────────────────────────────────────────

static func _woodcutter(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, seed: int = 0) -> void:
	# A LOGGING YARD that fills the plot (no two alike): trodden ground, a corner lean-to,
	# scattered log stacks, fresh-cut stumps, and a chopping block with an axe.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 40503 + 7
	var ex := t - l
	var ey := b - l
	# Cleared, trodden earth across the plot.
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), Color(0.46, 0.40, 0.27).lerp(DIRT, 0.5))
	# Corner lean-to hut (the cutters' shelter), set toward the back.
	var hc: Vector2 = l.lerp(ctr, 0.55) + ex * 0.10
	var hut := _box(ci, hc.lerp(t, 0.26), hc.lerp(r, 0.26), hc.lerp(b, 0.26), hc.lerp(l, 0.26), rng.randf_range(10.5, 12.5), WOOD)
	_gable(ci, hut, rng.randf_range(5.5, 6.8), THATCH_D)
	# Fresh-cut stumps dotted about.
	for i in range(rng.randi_range(2, 4)):
		var sp: Vector2 = l + ex * rng.randf_range(0.2, 0.9) + ey * rng.randf_range(0.2, 0.9)
		ci.draw_circle(sp, 2.0, WOOD_D)
		ci.draw_circle(sp, 1.1, Color(0.70, 0.54, 0.34))
	# Stacks of cut logs across the yard.
	for i in range(rng.randi_range(3, 5)):
		var u: float = rng.randf_range(0.42, 0.92)
		var v: float = rng.randf_range(0.30, 0.88)
		var pos: Vector2 = l + ex * u + ey * v
		for k in range(rng.randi_range(2, 3)):
			_log(ci, pos + Vector2(-2.0 + float(k) * 4.5, 1.0 - float(k) * 3.0), 5.0)
	# Chopping block + buried axe.
	var blk: Vector2 = ctr + Vector2(rng.randf_range(-5.0, 6.0), 3.0)
	ci.draw_rect(Rect2(blk.x - 3.0, blk.y - 5.0, 6.0, 5.0), WOOD_D)
	ci.draw_line(blk + Vector2(0, -5.0), blk + Vector2(5.0, -11.0), WOOD_D, 1.4)
	ci.draw_colored_polygon(PackedVector2Array([blk + Vector2(5.0, -11.0), blk + Vector2(9.0, -10.0), blk + Vector2(6.0, -13.0)]), IRON)

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
	# A working storage YARD: an open lean-to store-shelter over stacked crates, plus barrels, sacks
	# and a tarp-covered pile — reads as a depot, not three loose boxes on the grass.
	var pBL := _pt(t, r, b, l, 0.24, 0.28); var pBR := _pt(t, r, b, l, 0.74, 0.28)
	var pFL := _pt(t, r, b, l, 0.24, 0.60); var pFR := _pt(t, r, b, l, 0.74, 0.60)
	var tBL := _post(ci, pBL, 16.0, WOOD_D, 1.6); var tBR := _post(ci, pBR, 16.0, WOOD_D, 1.6)
	var tFL := _post(ci, pFL, 12.0, WOOD_D, 1.6); var tFR := _post(ci, pFR, 12.0, WOOD_D, 1.6)
	ci.draw_colored_polygon(PackedVector2Array([tBL, tBR, tFR, tFL]), WOOD.darkened(0.04))   # lean-to roof
	ci.draw_polyline(PackedVector2Array([tBL, tBR]), WOOD_L, 0.8)
	for f in [0.25, 0.5, 0.75]:
		ci.draw_line(tBL.lerp(tBR, f), tFL.lerp(tFR, f), WOOD_D, 0.4)
	# Stacked crates under the shelter.
	_crate(ci, pBL.lerp(pBR, 0.4) + Vector2(0, -2), 4.0)
	_crate(ci, pBL.lerp(pBR, 0.4) + Vector2(0, -9), 3.4)
	_crate(ci, pBL.lerp(pBR, 0.64) + Vector2(2, -1), 4.0)
	# Goods scattered in front.
	_barrel(ci, _pt(t, r, b, l, 0.30, 0.86) + Vector2(0, 2), 3.4)
	_barrel(ci, _pt(t, r, b, l, 0.46, 0.92) + Vector2(0, 3), 3.0)
	_sack(ci, _pt(t, r, b, l, 0.66, 0.86) + Vector2(0, 3)); _sack(ci, _pt(t, r, b, l, 0.74, 0.90) + Vector2(2, 4))
	# Tarp-covered pile, front-right.
	var tp := _pt(t, r, b, l, 0.82, 0.80)
	ci.draw_colored_polygon(PackedVector2Array([tp + Vector2(-7, 2), tp + Vector2(7, 2), tp + Vector2(5, -5), tp + Vector2(-5, -5)]), Color(0.40, 0.36, 0.28))
	ci.draw_polyline(PackedVector2Array([tp + Vector2(-7, 2), tp + Vector2(-5, -5), tp + Vector2(5, -5), tp + Vector2(7, 2)]), Color(0.30, 0.27, 0.20), 0.6)

# ── FOOD ─────────────────────────────────────────────────────────────────────────

# A real grove: trees laid out in rows across the whole footprint, each rendered in
# its seasonal stage (bare winter → budding spring → leafy summer → fruiting autumn).
# Painterly GRASS-FLOOR texture for a grassy farm plot (orchard / hops yard): faint mown
# bands + a scatter of darker grass tufts break up the flat fill so the ground reads as a
# tended sward, matching the wheat field's ridge-and-furrow and the painted buildings.
# Deterministic from the plot's screen position (stable, no shimmer). Call right after the
# base ground fill, before trees/posts are drawn on top.
static func _grass_floor_texture(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, base: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(t.x * 131.0 + b.y * 977.0 + l.x * 17.0)) + 7
	var ex := t - l
	var ey := b - l
	# Mown bands — every other strip a touch lighter (sun-caught grass).
	var nb: int = 8
	for i in range(nb):
		if i % 2 == 1:
			continue
		var f0: float = float(i) / float(nb); var f1: float = float(i + 1) / float(nb)
		var a0: Vector2 = l.lerp(t, f0); var a1: Vector2 = l.lerp(t, f1)
		var c0: Vector2 = b.lerp(r, f0); var c1: Vector2 = b.lerp(r, f1)
		ci.draw_colored_polygon(PackedVector2Array([a0, a1, c1, c0]), base.lightened(0.05))
	# Grass tufts — small dark blades scattered over the sward.
	var tuft := base.darkened(0.14)
	for i in range(12):
		var p: Vector2 = l + ex * rng.randf_range(0.08, 0.92) + ey * rng.randf_range(0.08, 0.92)
		ci.draw_line(p, p + Vector2(rng.randf_range(-0.8, 0.8), -2.0), tuft, 0.8)

# Scatter small colour flecks across the plot (anchored at l, spanning ex=t-l and ey=b-l) so a
# farm/market floor reads as WORKED, textured ground — a speckled mix of tones — instead of a flat
# slab. Cheap (drawn once when the building paints). Pass a palette to vary the grain/soil/cobble.
static func _speckle_ground(ci: CanvasItem, l: Vector2, ex: Vector2, ey: Vector2,
		cols: Array, n: int, smin: float, smax: float, rng: RandomNumberGenerator) -> void:
	for _i in range(n):
		var p: Vector2 = l + ex * rng.randf_range(0.02, 0.98) + ey * rng.randf_range(0.02, 0.98)
		ci.draw_circle(p, rng.randf_range(smin, smax), cols[rng.randi_range(0, cols.size() - 1)])

# One wheat strand growing UP out of the ground at `base`: a leaning stalk topped by a nodding
# grain ear (with a few awns when ripe). Many of these dotted across a field = standing grain.
static func _wheat_strand(ci: CanvasItem, base: Vector2, h: float, col: Color, ripe: bool, rng: RandomNumberGenerator) -> void:
	var lean: float = rng.randf_range(-1.0, 1.0)
	var top: Vector2 = base + Vector2(lean, -h)
	ci.draw_line(base, top, col.darkened(0.12), 0.8)               # stalk
	var head: Color = col.lightened(0.12) if ripe else col
	var ear_dir: Vector2 = Vector2(signf(lean) * 0.6, -1.0).normalized()
	var ear_tip: Vector2 = top + ear_dir * (h * 0.42 + 1.6)
	ci.draw_line(top, ear_tip, head, 1.3)                          # the nodding ear
	if ripe:
		for k in range(3):
			var gp: Vector2 = top.lerp(ear_tip, 0.3 + float(k) / 3.0 * 0.6)
			ci.draw_line(gp, gp + Vector2(0.8, -0.4), head, 0.5)  # awns fanning off the ear
			ci.draw_line(gp, gp + Vector2(-0.8, -0.4), head, 0.5)

static func _orchard_ground(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, season: int, seed: int = 0) -> void:
	# Seasonal grassy orchard floor with a small per-plot hue/brightness wobble + mown bands/tufts.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 2654435761 + 12345
	var gt: float = rng.randf_range(0.93, 1.08)
	var ground := Color(0.40, 0.56, 0.30).lerp(Color(0.36, 0.52, 0.26), rng.randf()) * SeasonSystem.ground_tint(season) * gt
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), ground)
	_grass_floor_texture(ci, t, r, b, l, ground)

static func _orchard(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, season: int, seed: int = 0) -> void:
	# Trees, fences, shed, crates — the props ABOVE the pawns. The grassy floor is _orchard_ground.
	# NO two orchards look alike: a per-plot RNG jitters every tree, varies planting density, nudges
	# the shed and crates, so each instance reads distinct.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 2654435761 + 67890   # structure RNG (ground uses its own seed below)
	var ctr: Vector2 = (t + r + b + l) * 0.25
	var stage: int = SeasonSystem.growth_stage(season)
	var ex := t - l
	var ey := b - l
	# FULL-SIZE apple trees now (matched to the level's forest trees), so the orchard is planted in
	# a wider, sparser grid — real spaced trees, not a hedge.
	var slots: Array[float] = [0.18, 0.50, 0.82]
	var density: float = rng.randf_range(0.80, 1.0)        # some plots are sparser
	# True for the central clearing kept open for the shed + yard.
	var _clear := func(u: float, v: float) -> bool:
		return u > 0.30 and u < 0.74 and v > 0.34 and v < 0.82
	# Each tree: jittered position + a per-tree size/growth wobble, so ranks aren't a rigid grid.
	var _plant := func(u: float, v: float) -> void:
		if _clear.call(u, v) or rng.randf() > density:
			return
		var ju: float = u + rng.randf_range(-0.06, 0.06)
		var jv: float = v + rng.randf_range(-0.06, 0.06)
		var st2: int = stage
		if stage >= 2 and rng.randf() < 0.18:
			st2 = stage - 1                                # a few younger/older trees
		_tree(ci, l + ex * ju + ey * jv + Vector2(0, rng.randf_range(-1.0, 1.0)), st2, season, rng.randf_range(0.85, 1.1))
	# Back rows (everything but the frontmost rank) — drawn before the shed.
	for vi in range(slots.size() - 1):
		for u in slots:
			_plant.call(u, slots[vi])
	# Rail fence along the two front edges (the enclosure reads as a kept plot).
	_fence(ci, l, b)
	_fence(ci, b, r)
	# Central timber shed (store/press), nudged a little within the yard per plot.
	var sc: Vector2 = ctr + ex * rng.randf_range(-0.06, 0.06) + ey * rng.randf_range(-0.06, 0.06)
	var shed := _box(ci, sc.lerp(t, 0.30), sc.lerp(r, 0.30), sc.lerp(b, 0.30), sc.lerp(l, 0.30), rng.randf_range(8.0, 10.5), WOOD, TEX_PLANK)
	_gable(ci, shed, rng.randf_range(4.5, 5.8), THATCH_D)
	_door(ci, sc.lerp(l, 0.30), sc.lerp(b, 0.30), 9.0, Color(0.30, 0.20, 0.12))
	# Stacked apple crates by the shed door (count varies).
	var crate: Vector2 = sc.lerp(b, 0.52)
	ci.draw_rect(Rect2(crate.x - 4.0, crate.y - 3.0, 8.0, 5.0), WOOD_D)
	if rng.randf() < 0.7:
		ci.draw_rect(Rect2(crate.x - 3.0, crate.y - 7.0, 6.0, 4.0), WOOD)
		for k in range(rng.randi_range(2, 4)):
			ci.draw_circle(crate + Vector2(-2.0 + float(k) * 2.0, -7.0), 1.0, RED)
	# Orchard EQUIPMENT: a picking ladder leant in the yard + a couple of apple baskets.
	var lad: Vector2 = sc.lerp(r, 0.42) + ey * 0.06
	ci.draw_line(lad, lad + Vector2(5, -16), WOOD_D, 1.4)             # ladder rails
	ci.draw_line(lad + Vector2(3, 0), lad + Vector2(8, -16), WOOD_D, 1.4)
	for rr in range(1, 5):
		ci.draw_line(lad + Vector2(float(rr) * 0.6, -float(rr) * 3.2), lad + Vector2(3 + float(rr) * 0.6, -float(rr) * 3.2), WOOD, 0.8)
	for bi in range(2):
		var bk: Vector2 = sc.lerp(l, 0.5) + ex * (0.04 + 0.10 * float(bi)) + ey * 0.10
		ci.draw_colored_polygon(PackedVector2Array([bk + Vector2(-3, 0), bk + Vector2(3, 0), bk + Vector2(2, 4), bk + Vector2(-2, 4)]), Color(0.52, 0.38, 0.22))
		for ai in range(3):
			ci.draw_circle(bk + Vector2(-1.6 + float(ai) * 1.6, -0.5), 1.0, RED if stage == 3 else Color(0.6, 0.75, 0.3))
	# Frontmost rank, drawn last so it correctly overlaps the shed/yard.
	for u in slots:
		_plant.call(u, slots[slots.size() - 1])

# One tree at its seasonal growth stage. 0 bare, 1 budding, 2 leafy, 3 fruiting.
# A FULL-SIZE apple tree, matched to the level's forest trees (TreeLayer) so an orchard reads as
# real trees, not bushes. ~34px tall: buttressed trunk + a billowing layered crown, with seasonal
# blossom/fruit. `s` scales it (per-tree variation).
static func _tree(ci: CanvasItem, base: Vector2, stage: int, season: int, s: float = 1.0) -> void:
	ci.draw_circle(base + Vector2(0, 4.0), 10.0 * s, Color(0, 0, 0, 0.15))   # ground shadow
	var tw: float = 3.0 * s
	ci.draw_colored_polygon(PackedVector2Array([
		base + Vector2(-tw, 3.0), base + Vector2(tw, 3.0),
		base + Vector2(tw * 0.6, -15.0 * s), base + Vector2(-tw * 0.6, -15.0 * s)]), WOOD_D)
	ci.draw_line(base + Vector2(-tw * 0.2, 2.0), base + Vector2(-tw * 0.2, -14.0 * s), WOOD_D.darkened(0.2), 1.0)
	if stage == 0:
		# Winter — bare, snow-dusted branches.
		ci.draw_line(base + Vector2(0, -13 * s), base + Vector2(-6 * s, -23 * s), WOOD_D, 1.6)
		ci.draw_line(base + Vector2(0, -13 * s), base + Vector2(6 * s, -22 * s), WOOD_D, 1.6)
		ci.draw_line(base + Vector2(0, -10 * s), base + Vector2(-4 * s, -17 * s), WOOD_D, 1.2)
		ci.draw_circle(base + Vector2(0, -22 * s), 3.0 * s, Color(0.88, 0.92, 0.98, 0.85))
		return
	var canopy := SeasonSystem.foliage_tint(season)
	var dark := canopy.darkened(0.22)
	var lite := canopy.lightened(0.10)
	var grow: float = 0.72 if stage == 1 else 1.0   # budding crowns a touch smaller
	var clumps := [
		[Vector2(0, -17), 9.0, dark], [Vector2(-6, -21), 7.0, dark], [Vector2(6, -22), 7.0, dark],
		[Vector2(0, -26), 7.5, canopy], [Vector2(-3, -30), 5.5, lite], [Vector2(4, -29), 5.0, lite], [Vector2(1, -33), 4.5, lite],
	]
	for cl in clumps:
		ci.draw_circle(base + (cl[0] as Vector2) * s * grow, (cl[1] as float) * s * grow, cl[2])
	if stage == 1:
		for bp in [Vector2(-4, -23), Vector2(5, -25), Vector2(0, -29), Vector2(-2, -19)]:
			ci.draw_circle(base + bp * s * grow, 1.4 * s, Color(0.98, 0.92, 0.95))   # blossom
	elif stage == 3:
		for ap in [Vector2(-5, -20), Vector2(6, -24), Vector2(-2, -28), Vector2(3, -31), Vector2(0, -22), Vector2(-6, -26)]:
			ci.draw_circle(base + ap * s, 1.7 * s, RED)                              # apples
			ci.draw_circle(base + ap * s + Vector2(-0.5, -0.5), 0.7 * s, RED.lightened(0.2))

# Pig-pen GROUND: churned, muddy earth — speckled clods + a couple of puddles (terrain level).
static func _pen_ground(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, seed: int = 0) -> void:
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), DIRT)
	var prng := RandomNumberGenerator.new()
	prng.seed = int(seed) * 9176 + 3
	_speckle_ground(ci, l, t - l, b - l,
		[DIRT.lightened(0.10), DIRT.darkened(0.12), Color(0.34, 0.26, 0.18)],
		clampi(int(80.0 * absf((t - l).cross(b - l)) / 900.0), 80, 800), 0.6, 1.5, prng)
	for _i in range(2):
		var pud: Vector2 = l + (t - l) * prng.randf_range(0.2, 0.8) + (b - l) * prng.randf_range(0.2, 0.8)
		ci.draw_circle(pud, prng.randf_range(1.8, 3.0), Color(0.30, 0.28, 0.26, 0.55))

# Pig-pen STRUCTURE (above pawns): fence, sty, pigs. Ground is _pen_ground.
static func _pen(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, animal: Color) -> void:
	# fence around
	_fence(ci, l, b); _fence(ci, b, r)
	# small sty
	var c := _box(ci, t.lerp(ctr, 0.4), t.lerp(r, 0.5).lerp(ctr, 0.2), ctr, l.lerp(t, 0.5).lerp(ctr, 0.2), 7.0, WOOD)
	_gable(ci, c, 4.0, THATCH_D)
	# two pigs
	_critter(ci, ctr + Vector2(-3, 6), animal)
	_critter(ci, ctr + Vector2(7, 9), animal)

static func _dairy(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# Barn + fence + cow only; the grassy paddock floor is drawn by _plain_ground (terrain level).
	# red barn
	var c := _box(ci, t.lerp(ctr, 0.2), r.lerp(ctr, 0.3), ctr.lerp(b, 0.3), l.lerp(ctr, 0.3), 16.0, RED.lightened(0.05), TEX_PLANK)
	_gable(ci, c, 9.0, Color(0.85, 0.82, 0.78))
	_door(ci, l.lerp(ctr, 0.2), ctr.lerp(b, 0.3), 16.0, Color(0.5, 0.12, 0.10))
	_fence(ci, b.lerp(l, 0.0), r)
	_critter(ci, b.lerp(r, 0.55) + Vector2(0, 4), Color(0.90, 0.88, 0.84))  # cow

# ── FIELD GROUND ───────────────────────────────────────────────────────────────────
# Farms/orchards are WALKABLE — workers toil INSIDE the footprint — so their GROUND (tilled soil,
# the crop, mud, grass) is the ACTUAL terrain, painted BELOW the pawns by FieldGroundLayer; the
# building model draws only the STRUCTURE + props (barn, trees, fences) ABOVE the pawns. So a
# worker standing in the field shows on top of the crop, never buried under a fake building floor.
static func draw_field_ground(ci: CanvasItem, btype: String, t: Vector2, r: Vector2, b: Vector2, l: Vector2, season: int, seed: int = 0) -> void:
	match btype:
		"wheat_farm":    _wheat_ground(ci, t, r, b, l, season, seed)
		"apple_orchard": _orchard_ground(ci, t, r, b, l, season, seed)
		"hops_farm":     _hops_ground(ci, t, r, b, l, season)
		"pig_farm":      _pen_ground(ci, t, r, b, l, seed)
		"dairy_farm":    _plain_ground(ci, t, r, b, l, Color(0.42, 0.58, 0.30) * SeasonSystem.ground_tint(season))

static func _plain_ground(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), col)
	_grass_floor_texture(ci, t, r, b, l, col)

static func _wheat_ground(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, season: int, seed: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 2246822519 + 5
	var stage: int = SeasonSystem.growth_stage(season)
	var field := Color(0.83, 0.69, 0.30)
	match stage:
		0: field = Color(0.62, 0.56, 0.40)   # ploughed / stubble
		1: field = Color(0.55, 0.70, 0.34)   # green sprouts
		2: field = Color(0.50, 0.66, 0.28)   # tall green
		3: field = Color(0.86, 0.70, 0.26)   # ripe gold
	field = field * rng.randf_range(0.94, 1.07)
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), field)
	var ex := t - l
	var ey := b - l
	# RIDGE-AND-FURROW: fill alternating bands across the plot (a lit ridge crest + a shaded
	# furrow trough) so the field reads as ploughed, textured earth instead of a flat colour —
	# matches the painterly buildings. Bands run l→b across to t→r; per-plot row count wobbles.
	var nrows: int = rng.randi_range(11, 15)
	var ridge_lit := field.lightened(0.06)
	var furrow_dk := field.darkened(0.10)
	var furrow_line := field.darkened(0.26)
	for i in range(nrows):
		var f0: float = float(i) / float(nrows)
		var f1: float = float(i + 1) / float(nrows)
		var a0: Vector2 = l.lerp(t, f0); var a1: Vector2 = l.lerp(t, f1)
		var c0: Vector2 = b.lerp(r, f0); var c1: Vector2 = b.lerp(r, f1)
		ci.draw_colored_polygon(PackedVector2Array([a0, a1, c1, c0]),
			ridge_lit if (i % 2 == 0) else furrow_dk)
		ci.draw_line(a0, c0, furrow_line, 0.7)            # furrow shadow seam
	# Density scales with the plot's actual screen AREA (a wheat_farm is 5×4 = 20 tiles, ~20× the
	# 1×1 reference), so a big field is FULLY covered with grain rather than a few sparse strands.
	var dens: float = absf(ex.cross(ey)) / 900.0   # 1.0 at one tile
	# Speckled "wheat mix" ground — flecks of varied grain/soil tones scattered over the ridges,
	# so the field is a living, mottled crop colour rather than one flat fill.
	var speck: Array = []
	match stage:
		0: speck = [field.darkened(0.08), field.lightened(0.06), DIRT.lightened(0.10)]
		1: speck = [Color(0.50, 0.66, 0.30), Color(0.62, 0.72, 0.34), field.lightened(0.05)]
		2: speck = [Color(0.46, 0.62, 0.24), Color(0.58, 0.68, 0.28), field.lightened(0.06)]
		_: speck = [Color(0.90, 0.76, 0.32), Color(0.82, 0.64, 0.22), Color(0.74, 0.58, 0.20), Color(0.96, 0.85, 0.44)]
	_speckle_ground(ci, l, ex, ey, speck, clampi(int(150.0 * dens), 140, 1400), 0.5, 1.1, rng)
	# Literal wheat strands growing OUT of the ground — densely enough to carpet the whole field:
	# sparse green sprouts in spring → a thick ripe-gold stand in autumn.
	if stage >= 1:
		var s_lo: Color; var s_hi: Color
		match stage:
			1: s_lo = Color(0.42, 0.60, 0.24); s_hi = Color(0.56, 0.70, 0.30)
			2: s_lo = Color(0.36, 0.54, 0.18); s_hi = Color(0.50, 0.64, 0.24)
			_: s_lo = Color(0.74, 0.58, 0.18); s_hi = Color(0.94, 0.80, 0.36)
		var ripe: bool = stage == 3
		var per_tile: int = 40 if stage == 1 else (70 if stage == 2 else 80)
		var n_strands: int = clampi(int(float(per_tile) * dens), 30, 1200)
		for i in range(n_strands):
			var sp: Vector2 = l + ex * rng.randf_range(0.03, 0.97) + ey * rng.randf_range(0.03, 0.97)
			var hh: float = rng.randf_range(3.0, 6.0) * (0.7 if stage == 1 else 1.0)
			_wheat_strand(ci, sp, hh, s_lo.lerp(s_hi, rng.randf()), ripe, rng)
	# Autumn: stacked sheaves dotted across the stubble (harvest piles — part of the ground).
	if stage == 3:
		for i in range(rng.randi_range(3, 6)):
			var sp: Vector2 = l + ex * rng.randf_range(0.35, 0.92) + ey * rng.randf_range(0.35, 0.92)
			ci.draw_colored_polygon(PackedVector2Array([sp + Vector2(-2.5, 1), sp + Vector2(2.5, 1), sp + Vector2(0, -5)]), Color(0.84, 0.70, 0.32))
			ci.draw_line(sp + Vector2(-1.5, 0), sp + Vector2(1.5, 0), Color(0.66, 0.52, 0.22), 0.8)

# Wheat STRUCTURE (above pawns): threshing barn + scarecrows. The field itself is _wheat_ground.
static func _wheat(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, season: int, seed: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 2246822519 + 17
	var ex := t - l
	var ey := b - l
	# A rail fence bounds the field on its two front edges (the enclosure reads as a kept plot).
	_fence(ci, l, b)
	_fence(ci, b, r)
	# Corner threshing barn (box + gable + door), tucked toward the back.
	var bc: Vector2 = l + ex * rng.randf_range(0.18, 0.26) + ey * rng.randf_range(0.18, 0.26)
	var barn := _box(ci, bc.lerp(t, 0.18), bc.lerp(r, 0.18), bc.lerp(b, 0.18), bc.lerp(l, 0.18), rng.randf_range(11.0, 13.0), WOOD_D.lightened(0.06), TEX_PLANK)
	_gable(ci, barn, rng.randf_range(6.0, 7.5), ROOF_LEATHER if rng.randf() < 0.5 else THATCH_D)
	# Work equipment: a HAY CART parked by the barn (bed + two wheels + a shaft) and a leaning scythe.
	var cart: Vector2 = bc.lerp(b, 0.42) + ex * 0.04
	ci.draw_colored_polygon(PackedVector2Array([cart + Vector2(-7, -2), cart + Vector2(7, -2), cart + Vector2(6, 2), cart + Vector2(-6, 2)]), WOOD)
	ci.draw_colored_polygon(PackedVector2Array([cart + Vector2(-6, -2), cart + Vector2(6, -2), cart + Vector2(5, -6), cart + Vector2(-5, -6)]), Color(0.86, 0.72, 0.34))   # hay load
	ci.draw_circle(cart + Vector2(-4, 3), 2.4, WOOD_D); ci.draw_circle(cart + Vector2(4, 3), 2.4, WOOD_D)
	ci.draw_line(cart + Vector2(7, 0), cart + Vector2(12, 2), WOOD_D, 1.2)   # shaft
	var scy: Vector2 = bc.lerp(l, 0.5) + ey * 0.08
	ci.draw_line(scy, scy + Vector2(2, -13), WOOD_D, 1.4)                    # snath
	ci.draw_arc(scy + Vector2(2, -13), 5.0, -0.2 * PI, 0.5 * PI, 8, Color(0.78, 0.80, 0.84), 1.2)   # blade
	# One or two scarecrows at varied spots.
	for i in range(rng.randi_range(1, 2)):
		var sc: Vector2 = l + ex * rng.randf_range(0.4, 0.85) + ey * rng.randf_range(0.35, 0.8)
		_post(ci, sc, 12.0, WOOD_D, 1.4)
		ci.draw_line(sc + Vector2(-6, -8), sc + Vector2(6, -8), WOOD_D, 1.2)
		ci.draw_circle(sc + Vector2(0, -13), 2.4, Color(0.78, 0.66, 0.40))

static func _hops(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, season: int) -> void:
	var stage: int = SeasonSystem.growth_stage(season)
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

static func _hops_ground(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, season: int) -> void:
	var hops_ground: Color = Color(0.44, 0.56, 0.30) * SeasonSystem.ground_tint(season)
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), hops_ground)
	_grass_floor_texture(ci, t, r, b, l, hops_ground)   # tended yard under the trellises

static func _windmill(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, time: float) -> void:
	# tapered round stone tower
	var g := ctr + Vector2(0, 4)
	_cyl(ci, g, 9.0, 4.0, 26.0, Color(0.80, 0.76, 0.66))
	var cap := g + Vector2(0, -26)
	_cone(ci, cap, 8.0, 3.6, 9.0, WOOD_D)
	_door(ci, l.lerp(ctr, 0.55), b.lerp(ctr, 0.55), 12.0)
	# Hero detail: a timber gallery (reefing stage) wrapping the tower + railing.
	var gy := g + Vector2(0, -14)
	_ellipse(ci, gy, 11.0, 4.6, WOOD_D)
	_ellipse(ci, gy, 9.2, 3.8, Color(0.80, 0.76, 0.66))
	for k in range(7):
		var ra := TAU * float(k) / 7.0
		if sin(ra) < -0.1:
			continue   # skip railing posts on the hidden back arc
		var rp := gy + Vector2(cos(ra) * 10.0, sin(ra) * 4.2)
		ci.draw_line(rp, rp + Vector2(0, -4), WOOD_D, 1.0)
	# sacks of flour stacked at the base
	_sack(ci, b.lerp(ctr, 0.5) + Vector2(-4, 4))
	_sack(ci, b.lerp(ctr, 0.5) + Vector2(3, 6))
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
	# A BAKEHOUSE: a plastered timber main block with a great stone domed-oven stack on one flank
	# (its tall chimney always at work), an arched oven-mouth glowing with fire, and fresh loaves on
	# a display board out front.
	var plaster := Color(0.82, 0.74, 0.58)
	# Oven house (stone, back-right) drawn first.
	var oven := _subbox(ci, t, r, b, l, 0.66, 0.16, 1.0, 0.80, 15.0, STONE_D.lightened(0.06), TEX_STONE)
	var og := _pt(t, r, b, l, 0.83, 0.48)
	var odome := _cyl(ci, og + Vector2(0, -15), 6.0, 3.0, 4.0, STONE.lightened(0.05))   # the oven dome
	_ellipse(ci, odome, 6.0, 3.0, STONE.lightened(0.1))
	_chimney(ci, og + Vector2(0, -19), 16.0, time, Color(0.42, 0.32, 0.27))
	# Main block.
	var c := _subbox(ci, t, r, b, l, 0.06, 0.10, 0.70, 0.92, 17.0, plaster, TEX_TIMBER)
	var ml: Vector2 = c[3] + Vector2(0, 17.0); var mb: Vector2 = c[2] + Vector2(0, 17.0)
	_gable(ci, c, 11.0, ROOF_RUSSET)
	# Arched oven-mouth with a hot glow on the front-left face.
	var om := ml.lerp(mb, 0.5)
	_arched_win(ci, om + Vector2(0, -1), 3.0, 7.0, Color(0.20, 0.10, 0.06))
	if _active:
		var s := 0.5 + 0.5 * sin(time * 3.0)
		ci.draw_circle(om + Vector2(0, -4), 2.6 + s, Color(1.0, 0.58, 0.18, 0.55))
	# Loaves cooling on a board out front.
	var brd := mb + Vector2(0, 6)
	ci.draw_colored_polygon(PackedVector2Array([brd + Vector2(-6, -1), brd + Vector2(6, -1), brd + Vector2(7, 2), brd + Vector2(-7, 2)]), WOOD)
	for k in range(3):
		ci.draw_circle(brd + Vector2(-4.0 + float(k) * 4.0, -1.5), 1.6, Color(0.80, 0.58, 0.30))

static func _brewery(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, time: float = 0.0) -> void:
	# A BREWHOUSE in the oast-house manner: a planked main block with a tall round kiln (set at the
	# visible front-right) topped by a white tilting cowl venting steam — plus the rank of fat ale
	# barrels out front.
	# Main block (back-left).
	var c := _subbox(ci, t, r, b, l, 0.06, 0.10, 0.66, 0.92, 16.0, WOOD, TEX_PLANK)
	_door(ci, _pt(t, r, b, l, 0.06, 0.20), _pt(t, r, b, l, 0.06, 0.92), 16.0)
	_gable(ci, c, 9.0, ROOF_MOSS)
	# Tall oast kiln at the front-right, rising clear of the main roof (drawn after it).
	var kg := _pt(t, r, b, l, 0.84, 0.66)
	var kt := _cyl(ci, kg, 7.5, 3.7, 25.0, Color(0.74, 0.57, 0.41))
	_ring(ci, kt + Vector2(0, 1), 8.1, 4.0, WOOD_D, 1.0)
	_cone(ci, kt, 8.0, 3.9, 9.0, Color(0.60, 0.45, 0.31))
	# White tilting cowl + venting steam.
	var cw := kt + Vector2(0, -9)
	ci.draw_colored_polygon(PackedVector2Array([cw + Vector2(-2.6, 0), cw + Vector2(2.6, 0), cw + Vector2(4.4, -4.4), cw + Vector2(-1.0, -4.4)]), Color(0.92, 0.90, 0.84))
	if _active:
		for k in range(3):
			var sy: float = fmod(time * 6.0 + float(k) * 5.0, 14.0)
			ci.draw_circle(cw + Vector2(3.4 + sin(time * 2.0 + k) * 1.5, -5.0 - sy), 1.3 + sy * 0.12, Color(0.92, 0.92, 0.92, 0.26 * (1.0 - sy / 14.0)))
	# Rank of ale barrels out front.
	_barrel(ci, _pt(t, r, b, l, 0.26, 1.0) + Vector2(0, 3), 5.0)
	_barrel(ci, _pt(t, r, b, l, 0.48, 1.04) + Vector2(0, 6), 5.5)

static func _inn(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, time: float) -> void:
	# A welcoming two-storey JETTIED timber inn: an L of a tall main block + a back cross-wing, a
	# jutting upper floor on brackets, a big smoking stone chimney, warm-lit windows, a hanging mug
	# sign and a lantern by the door.
	# Back cross-wing first.
	var wing := _subbox(ci, t, r, b, l, 0.10, 0.06, 0.52, 0.52, 24.0, WOOD, TEX_TIMBER)
	_gable(ci, wing, 11.0, ROOF_MOSS.darkened(0.05))
	# Tall main block (two storeys).
	var c := _subbox(ci, t, r, b, l, 0.08, 0.34, 0.92, 0.95, 26.0, WOOD_L, TEX_TIMBER)
	var ml: Vector2 = c[3] + Vector2(0, 26.0); var mb: Vector2 = c[2] + Vector2(0, 26.0); var mr: Vector2 = c[1] + Vector2(0, 26.0)
	# Jetty: a timber sill band where the upper storey oversails, with little brackets.
	ci.draw_line(ml + Vector2(0, -13), mb + Vector2(0, -13), WOOD_D, 1.6)
	ci.draw_line(mb + Vector2(0, -13), mr + Vector2(0, -13), WOOD_D, 1.6)
	for f in [0.3, 0.7]:
		var bp: Vector2 = mb.lerp(mr, f)
		ci.draw_line(bp + Vector2(0, -10), bp + Vector2(0, -13), WOOD_D, 1.0)
	# Two registers of warm-lit windows.
	for f in [0.32, 0.68]:
		_win(ci, ml.lerp(mb, f) + Vector2(0, -6), Color(1.0, 0.82, 0.46)); _win(ci, ml.lerp(mb, f) + Vector2(0, -18), Color(1.0, 0.82, 0.46))
		_win(ci, mb.lerp(mr, f) + Vector2(0, -6), Color(1.0, 0.82, 0.46)); _win(ci, mb.lerp(mr, f) + Vector2(0, -18), Color(1.0, 0.82, 0.46))
	_door(ci, _pt(t, r, b, l, 0.08, 0.42), _pt(t, r, b, l, 0.08, 0.95), 26.0)
	_gable(ci, c, 13.0, ROOF_MOSS)
	_chimney(ci, _pt(t, r, b, l, 0.5, 0.55) + Vector2(0, -26), 16.0, time, STONE_D)
	# Warm flickering lantern by the door + a hanging mug sign.
	var lp := mb.lerp(mr, 0.18) + Vector2(0, -16)
	ci.draw_line(lp, lp + Vector2(0, 3), WOOD_D, 1.0)
	var fl := 0.8 + 0.2 * sin(time * 7.0)
	ci.draw_circle(lp + Vector2(0, 5), 3.4 * fl, Color(1.0, 0.7, 0.3, 0.32))
	ci.draw_circle(lp + Vector2(0, 5), 1.5, Color(1.0, 0.86, 0.52))
	_hanging_sign(ci, mb.lerp(mr, 0.5) + Vector2(0, -19), Color(0.40, 0.28, 0.16),
		func(c2, p): c2.draw_rect(Rect2(p.x - 1.8, p.y - 2.2, 3.6, 4.4), THATCH); c2.draw_line(p + Vector2(1.8, -1.4), p + Vector2(3.0, -0.6), THATCH, 1.0))

static func _granary(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# A big timber GRANARY raised on mushroom staddle-stones (keeping grain off the damp and the
	# rats), with a domed thatch cap, a loading ladder and sacks of grain at its foot.
	var g := ctr + Vector2(0, 5)
	for off in [Vector2(-9, 3), Vector2(9, 3), Vector2(0, 7), Vector2(0, -1)]:   # staddle stones
		var sp: Vector2 = g + off
		ci.draw_rect(Rect2(sp.x - 1.4, sp.y - 4.0, 2.8, 4.0), STONE_D)
		_ellipse(ci, sp + Vector2(0, -4.0), 3.4, 1.6, STONE_L)
	var bodyG := g + Vector2(0, -5)
	_cyl(ci, bodyG, 13.0, 6.0, 20.0, Color(0.80, 0.70, 0.50))
	_ring(ci, bodyG + Vector2(0, -7.0), 13.0, 6.0, WOOD_D, 0.8)
	_cone(ci, bodyG + Vector2(0, -20.0), 14.0, 6.5, 11.0, THATCH)
	_door(ci, l.lerp(ctr, 0.55), b.lerp(ctr, 0.55), 14.0)
	# Loading ladder.
	var lad := b.lerp(ctr, 0.42) + Vector2(0, 4)
	ci.draw_line(lad, lad + Vector2(2, -16), WOOD_D, 1.2)
	ci.draw_line(lad + Vector2(3, 0), lad + Vector2(5, -16), WOOD_D, 1.2)
	for rr in range(1, 5):
		ci.draw_line(lad + Vector2(float(rr) * 0.5, -float(rr) * 3.4), lad + Vector2(3.0 + float(rr) * 0.5, -float(rr) * 3.4), WOOD, 0.7)
	_sack(ci, b.lerp(l, 0.5) + Vector2(-2, 8)); _sack(ci, b.lerp(r, 0.5) + Vector2(2, 9)); _sack(ci, b + Vector2(0, 11))

# ── RELIGIOUS ──────────────────────────────────────────────────────────────────

static func _church(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, grand: bool) -> void:
	# A CRUCIFORM stone church: a long gabled nave, a rounded apse at the liturgical (back) end, a
	# crossing transept (grand only), and tall west tower(s) with spires at the entrance front —
	# drawn FRONT-MOST so the towers cleanly overlap the nave. No longer one giant pyramid box.
	var wallc := STONE_L if grand else STONE
	var nave_h := 34.0 if grand else 24.0
	var rh := 22.0 if grand else 15.0
	# Apse: a rounded chapel projecting from the back (low-v) end of the nave.
	var apse_g := _pt(t, r, b, l, 0.5, 0.04)
	var apse_rx := _pt(t, r, b, l, 0.74, 0.10).distance_to(_pt(t, r, b, l, 0.26, 0.10)) * 0.5
	var apse_top := _cyl(ci, apse_g, apse_rx, apse_rx * 0.5, nave_h * 0.82, wallc)
	_cone(ci, apse_top, apse_rx + 1.0, apse_rx * 0.5, rh * 0.8, SLATE)
	# Nave — the long main body, slightly inset so the apse/transept read as projections.
	var nave := _subbox(ci, t, r, b, l, 0.22, 0.06, 0.78, 0.94, nave_h, wallc, TEX_STONE)
	# Buttresses along the nave's two front faces.
	var nl: Vector2 = nave[3] + Vector2(0, nave_h)   # ground-level left/bot corners
	var nb: Vector2 = nave[2] + Vector2(0, nave_h)
	var nr: Vector2 = nave[1] + Vector2(0, nave_h)
	for f in [0.22, 0.5, 0.78]:
		_buttress(ci, nl, nb, f, nave_h * 0.6, wallc)
		_buttress(ci, nb, nr, f, nave_h * 0.6, wallc)
	# Lancet windows down the nave sides.
	for f in [0.30, 0.5, 0.70]:
		_lancet(ci, nl.lerp(nb, f) + Vector2(0, -nave_h * 0.5), nave_h * 0.5)
		_lancet(ci, nb.lerp(nr, f) + Vector2(0, -nave_h * 0.5), nave_h * 0.5)
	_gable(ci, nave, rh, SLATE)
	# Transept (grand): a perpendicular cross-arm through the crossing, with its own gable.
	if grand:
		var trans := _subbox(ci, t, r, b, l, 0.02, 0.40, 0.98, 0.66, nave_h * 0.92, wallc, TEX_STONE)
		_gable(ci, trans, rh * 0.82, SLATE)
		# Rose window on the front face of the transept.
		_rose(ci, _pt(t, r, b, l, 0.5, 0.66) + Vector2(0, -nave_h * 0.6), 5.0)
		# A slender crossing fleche (small spire) where nave + transept meet.
		_spire(ci, _pt(t, r, b, l, 0.5, 0.5) + Vector2(0, -nave_h - rh), 3.0, 16.0, SLATE.lightened(0.05))
	# Arched west door at the entrance front.
	_door(ci, _pt(t, r, b, l, 0.30, 0.96), _pt(t, r, b, l, 0.70, 0.96), nave_h * 0.7, Color(0.16, 0.10, 0.06))
	if not grand:
		_rose(ci, _pt(t, r, b, l, 0.5, 0.92) + Vector2(0, -nave_h * 0.62), 3.4)
	# West tower(s) at the front — the dominant vertical. Grand: twin flanking towers. Else: one.
	var twr_h := nave_h + (34.0 if grand else 20.0)
	var twr_spire := 30.0 if grand else 22.0
	var tower_spans := [[0.06, 0.34]] if not grand else [[0.02, 0.26], [0.74, 0.98]]
	for span in tower_spans:
		var u0: float = span[0]; var u1: float = span[1]
		var tw := _subbox(ci, t, r, b, l, u0, 0.78, u1, 1.0, twr_h, wallc, TEX_STONE)
		# Belfry louvres on the two visible faces.
		var tlb: Vector2 = tw[2] + Vector2(0, twr_h * 0.30)
		_arched_win(ci, tw[3].lerp(tw[2], 0.5) + Vector2(0, twr_h * 0.28), 2.0, 6.0, Color(0.12, 0.10, 0.10))
		_arched_win(ci, tw[2].lerp(tw[1], 0.5) + Vector2(0, twr_h * 0.28), 2.0, 6.0, Color(0.12, 0.10, 0.10))
		_merlons(ci, tw[3], tw[2], STONE_L, 2)
		_merlons(ci, tw[2], tw[1], STONE_L, 2)
		var sc := (tw[0] + tw[2]) * 0.5
		var srx: float = absf(tw[1].x - tw[3].x) * 0.5
		_spire(ci, sc + Vector2(0, -2), srx, twr_spire, SLATE.darkened(0.04))
		# Gilt cross atop the spire.
		var cr := sc + Vector2(0, -2 - twr_spire - 5.0)
		ci.draw_line(cr, cr + Vector2(0, -9), GOLD, 1.8)
		ci.draw_line(cr + Vector2(-3, -6), cr + Vector2(3, -6), GOLD, 1.8)

# ── MILITARY ───────────────────────────────────────────────────────────────────

static func _barracks(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, seed: int = 0) -> void:
	# A timber longhouse set on the BACK of the plot, with an open training YARD in front —
	# a pell (practice post), a weapon rack and war banners, varied per instance.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 374761393 + 17
	var ex := t - l
	var ey := b - l
	# Packed-earth muster yard across the whole plot.
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), Color(0.50, 0.45, 0.33))
	# Longhouse occupies the back ~62% of the footprint (toward t), leaving a front yard.
	var c := _box(ci, t, t + ey * 0.62, l + ey * 0.62, l, 18.0, WOOD_D.lightened(0.05), TEX_PLANK)
	_gable(ci, c, 9.0, ROOF_LEATHER)
	# War banners along the eaves.
	for f in [0.3, 0.7]:
		var p := (c[0] as Vector2).lerp(c[1], f)
		var tp := _post(ci, p, 10.0, WOOD_D, 1.2)
		ci.draw_colored_polygon(PackedVector2Array([tp, tp + Vector2(0, 9), tp + Vector2(5, 4)]), RED)
	# Front-yard training props (positions/counts vary).
	var yard: Vector2 = ctr.lerp(b, 0.45)
	# Pell — a practice post wrapped with a straw man.
	var pell: Vector2 = yard + ex * rng.randf_range(-0.12, 0.04) + ey * rng.randf_range(-0.02, 0.10)
	_post(ci, pell, 11.0, WOOD_D, 2.0)
	ci.draw_circle(pell + Vector2(0, -11), 2.2, Color(0.78, 0.66, 0.40))
	ci.draw_line(pell + Vector2(-4, -8), pell + Vector2(4, -8), WOOD_D, 1.4)
	# Weapon rack with a varied number of spears.
	var rk: Vector2 = yard + ex * rng.randf_range(0.10, 0.22) + ey * rng.randf_range(0.05, 0.18)
	ci.draw_line(rk + Vector2(-5, 0), rk + Vector2(5, 0), WOOD, 1.4)
	for i in range(rng.randi_range(2, 4)):
		ci.draw_line(rk + Vector2(-4 + i * 3, 0), rk + Vector2(-4 + i * 3, -9), IRON, 1.0)

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

# Shared craft-workshop shell: a work-house over the back ~56% of the plot (door + window + gabled
# roof + optional roof louvre), leaving an OPEN WORK-YARD across the front for trade props. Each
# trade then dresses that yard distinctly so the row of workshops never reads as cloned boxes.
static func _workshop_shell(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2,
		wall: Color, roof: Color, tex: int, vent: bool = false) -> void:
	var ey := b - l
	var hR := t + ey * 0.56
	var hB := l + ey * 0.56
	var c := _box(ci, t, hR, hB, l, 15.0, wall, tex)
	_door(ci, l, hB, 15.0)
	_win(ci, l.lerp(hB, 0.32) + Vector2(0, -8))
	_gable(ci, c, 8.5, roof)
	if vent:
		var vc := (c[0] + c[2]) * 0.5 + Vector2(0, -8.5)
		ci.draw_rect(Rect2(vc.x - 2.6, vc.y - 5.0, 5.2, 5.0), wall.darkened(0.12))
		ci.draw_colored_polygon(PackedVector2Array([vc + Vector2(-3.4, -5.0), vc + Vector2(3.4, -5.0), vc + Vector2(0, -9.0)]), roof.darkened(0.06))

static func _fletcher(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, time: float = 0.0) -> void:
	# Bowyer/fletcher: a timber work-house with a yard of drying bow-staves, an arrow bundle and a bow sign.
	_workshop_shell(ci, t, r, b, l, WOOD_L, THATCH_D, TEX_TIMBER)
	var rk := _pt(t, r, b, l, 0.62, 0.80)
	ci.draw_line(rk + Vector2(-8, 0), rk + Vector2(8, 0), WOOD_D, 1.6)            # rack rail
	for i in range(6):
		ci.draw_line(rk + Vector2(-7.0 + i * 2.6, 1.5), rk + Vector2(-5.0 + i * 2.6, -13), WOOD_L, 1.0)
	var ab := _pt(t, r, b, l, 0.28, 0.84)
	for i in range(5):
		ci.draw_line(ab + Vector2(i * 1.3 - 3.0, 2.0), ab + Vector2(i * 1.3 - 2.4, -9.0), WOOD, 0.8)
	ci.draw_line(ab + Vector2(-3, -9), ab + Vector2(3.5, -9), IRON, 0.6)
	_hanging_sign(ci, _pt(t, r, b, l, 0.5, 1.0) + Vector2(0, -12), Color(0.42, 0.30, 0.18),
		func(c2, p): c2.draw_arc(p + Vector2(-1, 0), 3.4, -PI * 0.5, PI * 0.5, 6, Color(0.86, 0.80, 0.70), 1.1); c2.draw_line(p + Vector2(-1, -3.2), p + Vector2(-1, 3.2), Color(0.86, 0.80, 0.70), 0.7))

static func _crossbow(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, time: float = 0.0) -> void:
	# Crossbow workshop: a planked, slate-roofed shop (with a vent) and a test-frame holding a mounted
	# crossbow plus a grindstone in the yard — distinct from the fletcher's bow-staves.
	_workshop_shell(ci, t, r, b, l, WOOD, SLATE, TEX_PLANK, true)
	var tf := _pt(t, r, b, l, 0.62, 0.80)
	_post(ci, tf + Vector2(-5, 0), 12.0, WOOD_D, 1.6)
	_post(ci, tf + Vector2(5, 0), 12.0, WOOD_D, 1.6)
	ci.draw_line(tf + Vector2(-5, -11), tf + Vector2(5, -11), WOOD_D, 1.4)
	ci.draw_line(tf + Vector2(-4.5, -7), tf + Vector2(4.5, -7), IRON_D, 1.3)      # the bow
	ci.draw_line(tf + Vector2(0, -7), tf + Vector2(0, -2), WOOD, 1.2)             # stock
	var gs := _pt(t, r, b, l, 0.28, 0.86)
	ci.draw_circle(gs + Vector2(0, -3), 3.2, STONE_D)
	ci.draw_circle(gs + Vector2(0, -3), 1.0, IRON_D)
	_post(ci, gs + Vector2(-3, 0), 3.0, WOOD_D, 1.0)
	_post(ci, gs + Vector2(3, 0), 3.0, WOOD_D, 1.0)

static func _apothecary(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# Apothecary/herbalist: a snug whitewashed cottage with hanging herb bundles under the eave, a
	# green-cross sign and a small herb-garden bed out front.
	var c := _subbox(ci, t, r, b, l, 0.10, 0.12, 0.82, 0.94, 16.0, Color(0.82, 0.80, 0.72), TEX_TIMBER)
	var ml: Vector2 = c[3] + Vector2(0, 16.0); var mb: Vector2 = c[2] + Vector2(0, 16.0); var mr: Vector2 = c[1] + Vector2(0, 16.0)
	_win(ci, mb.lerp(mr, 0.62) + Vector2(0, -9))
	_door(ci, _pt(t, r, b, l, 0.10, 0.22), _pt(t, r, b, l, 0.10, 0.94), 16.0)
	_gable(ci, c, 11.0, ROOF_PALE)
	for f in [0.3, 0.55]:
		var hp := ml.lerp(mb, f) + Vector2(0, -13)
		ci.draw_line(hp, hp + Vector2(0, 4), WOOD_D, 0.6)
		ci.draw_colored_polygon(PackedVector2Array([hp + Vector2(-1.4, 4), hp + Vector2(1.4, 4), hp + Vector2(0, 8)]), LEAF)
	_hanging_sign(ci, mb.lerp(mr, 0.4) + Vector2(0, -14), Color(0.88, 0.86, 0.80),
		func(c2, p): c2.draw_line(p + Vector2(0, -2.4), p + Vector2(0, 2.4), Color(0.30, 0.60, 0.32), 1.7); c2.draw_line(p + Vector2(-2.4, 0), p + Vector2(2.4, 0), Color(0.30, 0.60, 0.32), 1.7))
	var gb := _pt(t, r, b, l, 0.58, 1.0) + Vector2(0, 2)
	ci.draw_colored_polygon(PackedVector2Array([gb + Vector2(-7, 0), gb + Vector2(7, 0), gb + Vector2(8, 3), gb + Vector2(-8, 3)]), DIRT)
	for i in range(4):
		ci.draw_circle(gb + Vector2(-6.0 + i * 4.0, 1.0), 1.5, LEAF.lightened(0.1))

static func _forge(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, time: float, seed: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 1099087573 + 23
	var ey := b - l
	# Sooty work-yard ground across the plot.
	ci.draw_colored_polygon(PackedVector2Array([t, r, b, l]), Color(0.34, 0.31, 0.29))
	# Stone forge-house on the back ~60% of the plot.
	var c := _box(ci, t, t + ey * 0.60, l + ey * 0.60, l, 14.0, STONE_D, TEX_STONE)
	_gable(ci, c, 7.0, ROOF_RUST)
	# Stone chimney with a heat shimmer.
	var ch: Vector2 = (c[1] as Vector2).lerp(c[2], 0.5)
	ci.draw_rect(Rect2(ch.x - 3, ch.y - 14, 6, 14), STONE)
	var fl := 0.6 + 0.4 * sin(time * 6.0)
	if _active:
		ci.draw_circle(ch + Vector2(0, -15), 2.0 + fl, Color(0.5, 0.5, 0.5, 0.4))
	# Front work-yard: anvil with a hot glow, a coal heap, a water trough — placed with jitter.
	var yard: Vector2 = ctr.lerp(b, 0.5)
	var an: Vector2 = yard + Vector2(rng.randf_range(-6, 0), rng.randf_range(0, 4))
	ci.draw_circle(an + Vector2(0, 1), 4.0 * fl, Color(1.0, 0.5, 0.1, 0.5))
	ci.draw_rect(Rect2(an.x - 3, an.y - 3, 6, 2), IRON_D)
	ci.draw_rect(Rect2(an.x - 1, an.y - 1, 2, 3), IRON_D)
	# Coal heap.
	var coal: Vector2 = yard + Vector2(rng.randf_range(4, 9), rng.randf_range(-1, 3))
	ci.draw_circle(coal, 3.2, Color(0.12, 0.11, 0.12))
	ci.draw_circle(coal + Vector2(-1, -1), 1.4, Color(0.22, 0.20, 0.22))
	# Water trough.
	var tr: Vector2 = yard + Vector2(rng.randf_range(-2, 4), rng.randf_range(5, 8))
	ci.draw_rect(Rect2(tr.x - 4, tr.y - 2, 8, 4), WOOD_D)
	ci.draw_rect(Rect2(tr.x - 3, tr.y - 1.5, 6, 2), Color(0.32, 0.48, 0.62))

static func _armory(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# A fortified ARSENAL: a stout ashlar block with a reinforced door, arrow-loop windows, a slate
	# roof, a shield-and-crossed-swords trophy and a stand of spears by the door.
	var c := _subbox(ci, t, r, b, l, 0.06, 0.10, 0.94, 0.90, 17.0, STONE, TEX_STONE)
	var mb: Vector2 = c[2] + Vector2(0, 17.0); var mr: Vector2 = c[1] + Vector2(0, 17.0)
	_door(ci, _pt(t, r, b, l, 0.06, 0.22), _pt(t, r, b, l, 0.06, 0.90), 17.0, Color(0.18, 0.12, 0.10))
	for f in [0.36, 0.72]:
		var s := mb.lerp(mr, f) + Vector2(0, -11)
		ci.draw_rect(Rect2(s.x - 0.8, s.y - 3.0, 1.6, 6.0), Color(0.05, 0.05, 0.07))
		ci.draw_line(s + Vector2(-1.6, -3.2), s + Vector2(1.6, -3.2), STONE_L, 0.5)
	_gable(ci, c, 8.5, SLATE)
	var fc := mb.lerp(mr, 0.5) + Vector2(0, -9)
	_shield(ci, fc, 3.0, RED, GOLD)
	ci.draw_line(fc + Vector2(-5, 4), fc + Vector2(5, -6), IRON, 1.0)
	ci.draw_line(fc + Vector2(5, 4), fc + Vector2(-5, -6), IRON, 1.0)
	var sp := _pt(t, r, b, l, 0.22, 1.0) + Vector2(0, 2)
	for i in range(4):
		ci.draw_line(sp + Vector2(-3.0 + i * 2.0, 2.0), sp + Vector2(-2.0 + i * 2.0, -12.0), IRON, 0.8)

static func _poleturner(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# Poleturner: a timber work-house with a pole-lathe in the yard (springy pole + cord + workpiece)
	# and a stack of finished pikes leaning to dry.
	_workshop_shell(ci, t, r, b, l, WOOD, THATCH_D, TEX_TIMBER)
	var lb := _pt(t, r, b, l, 0.60, 0.82)
	ci.draw_line(lb + Vector2(-8, 0), lb + Vector2(8, -1), WOOD_D, 2.0)           # lathe bed
	_post(ci, lb + Vector2(-7, 0), 14.0, WOOD_D, 1.2)
	ci.draw_line(lb + Vector2(-7, -14), lb + Vector2(7, -9), WOOD_L, 1.0)         # springy pole
	ci.draw_line(lb + Vector2(7, -9), lb + Vector2(6, -1), Color(0.5, 0.4, 0.26), 0.7)   # cord
	ci.draw_line(lb + Vector2(-6, -2.5), lb + Vector2(6, -2.5), WOOD_L, 1.2)      # workpiece
	var pk := _pt(t, r, b, l, 0.26, 0.86)
	for i in range(4):
		ci.draw_line(pk + Vector2(-3.0 + i * 2.0, 3.0), pk + Vector2(2.0 + i * 2.0, -14.0), WOOD_L, 0.9)

static func _tannery(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# Tannery: a planked work-house with stretched hides on frames and dark tan-pits in the yard.
	_workshop_shell(ci, t, r, b, l, WOOD, ROOF_LEATHER, TEX_PLANK)
	for i in range(2):
		var fr := _pt(t, r, b, l, 0.42 + float(i) * 0.26, 0.80)
		var tp1 := _post(ci, fr + Vector2(-4, 0), 12.0, WOOD_D)
		var tp2 := _post(ci, fr + Vector2(4, 0), 12.0, WOOD_D)
		ci.draw_colored_polygon(PackedVector2Array([tp1, tp2, tp2 + Vector2(0, 8), tp1 + Vector2(0, 8)]), Color(0.74, 0.58, 0.40))
		ci.draw_polyline(PackedVector2Array([tp1, tp2, tp2 + Vector2(0, 8), tp1 + Vector2(0, 8), tp1]), WOOD_D, 0.5)
	for i in range(2):
		var pit := _pt(t, r, b, l, 0.28 + float(i) * 0.12, 0.93)
		_ellipse(ci, pit, 3.4, 1.7, Color(0.30, 0.22, 0.14))
		_ellipse(ci, pit, 2.4, 1.2, Color(0.18, 0.13, 0.08))

# ── DEFENSE ──────────────────────────────────────────────────────────────────────

static func _palisade(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2) -> void:
	# row of sharpened stakes along the tile
	var a := l.lerp(b, 0.0); var bb := r
	for f in range(7):
		var p: Vector2 = l.lerp(r, float(f) / 6.0)
		var tp := _post(ci, p + Vector2(0, 2), 14.0, WOOD, 2.2)
		ci.draw_colored_polygon(PackedVector2Array([tp + Vector2(-1.6, 0), tp + Vector2(1.6, 0), tp + Vector2(0, -3)]), WOOD_L)
		if _winter:   # snow dab capping each sharpened stake
			ci.draw_colored_polygon(PackedVector2Array([tp + Vector2(-1.6, 0), tp + Vector2(1.6, 0), tp + Vector2(0, -2.4)]), SNOW)

static func _stone_wall(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2) -> void:
	var c := _box(ci, t, r, b, l, 13.0, STONE, TEX_STONE)
	_snow_top(ci, c, 0.55)   # snow on the wall-walk
	_merlons(ci, c[3], c[2], STONE_L, 3)
	_merlons(ci, c[2], c[1], STONE_L, 3)

static func _gatehouse(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# A proper fortified GATEHOUSE: a tall ashlar gate-block with a deep arched passage + portcullis,
	# a projecting machicolation box over the gate, battlements, and conical-capped corner bartizans.
	var H := 26.0
	var c := _subbox(ci, t, r, b, l, 0.04, 0.04, 0.96, 0.96, H, STONE, TEX_STONE)
	var ml: Vector2 = c[3] + Vector2(0, H); var mb: Vector2 = c[2] + Vector2(0, H); var mr: Vector2 = c[1] + Vector2(0, H)
	# Arched passage through the front-left face, with a portcullis.
	var ar := ml.lerp(mb, 0.5)
	var e := (mb - ml).normalized()
	ci.draw_colored_polygon(PackedVector2Array([ar - e * 5.0, ar + e * 5.0, ar + e * 5.0 + Vector2(0, -13),
		ar + Vector2(0, -18), ar - e * 5.0 + Vector2(0, -13)]), Color(0.05, 0.05, 0.07))
	for i in range(5):
		ci.draw_line(ar - e * 4.0 + e * (i * 2.0), ar - e * 4.0 + e * (i * 2.0) + Vector2(0, -12), IRON, 0.7)
	for i in range(2):
		ci.draw_line(ar - e * 4.5, ar + e * 4.5, IRON_D, 0.6)   # cross-bands (drawn at sill; subtle)
	# Projecting machicolation box over the gate.
	var mo := ar + Vector2(0, -H * 0.5)
	ci.draw_colored_polygon(PackedVector2Array([mo - e * 5.0, mo + e * 5.0, mo + e * 5.0 + Vector2(0, 3), mo - e * 5.0 + Vector2(0, 3)]), STONE_D)
	_snow_top(ci, c, 0.5)
	_merlons(ci, c[3], c[2], STONE_L, 3)
	_merlons(ci, c[2], c[1], STONE_L, 3)
	# Conical-capped corner bartizans at the two side corners.
	for corner in [c[3], c[1]]:
		var bt := _cyl(ci, corner + Vector2(0, 1), 3.0, 1.5, 6.0, STONE_L)
		_cone(ci, bt, 3.6, 1.8, 5.0, SLATE)

static func _watchtower(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# A substantial braced timber lookout: four splayed legs with X cross-bracing on the
	# front faces, a railed platform, a thatch cap and a pennant — reads as a real tower
	# (was a spindly 3-post stub that looked like a flagpole at play-zoom).
	var H: float = 27.0
	var platc: Vector2 = ctr + Vector2(0, 3.0 - H)
	# Leg bases pulled in from the footprint corners; platform corners are a tighter diamond.
	var bs := [l.lerp(ctr, 0.28), b.lerp(ctr, 0.28), r.lerp(ctr, 0.28), t.lerp(ctr, 0.28)]
	var pw: float = 10.0
	var ph: float = 5.5
	var plat := [platc + Vector2(0, -ph), platc + Vector2(pw, 0.5), platc + Vector2(0, ph), platc + Vector2(-pw, 0.5)]
	# Legs, back-to-front so nearer timber overlaps the far.
	for i in [3, 0, 2, 1]:
		ci.draw_line(bs[i], plat[i], WOOD_D, 2.6)
		ci.draw_line(bs[i], plat[i], WOOD_L, 1.1)
	# X cross-bracing on the two FRONT faces (left l↔b, right b↔r) — the watchtower signature.
	for pair in [[0, 1], [1, 2]]:
		ci.draw_line(bs[pair[0]], plat[pair[1]], WOOD_D, 1.2)
		ci.draw_line(bs[pair[1]], plat[pair[0]], WOOD_D, 1.2)
	# Platform deck + rim.
	ci.draw_colored_polygon(PackedVector2Array(plat), WOOD_L)
	ci.draw_polyline(PackedVector2Array([plat[0], plat[1], plat[2], plat[3], plat[0]]), WOOD_D, 1.2)
	# Railing posts + top rail.
	var rail := []
	for p in plat:
		var rp: Vector2 = p + Vector2(0, -4.5)
		ci.draw_line(p, rp, WOOD_D, 1.0)
		rail.append(rp)
	ci.draw_polyline(PackedVector2Array([rail[0], rail[1], rail[2], rail[3], rail[0]]), WOOD_D, 0.9)
	# Thatch hip cap over the platform.
	var apex: Vector2 = platc + Vector2(0, -15)
	ci.draw_colored_polygon(PackedVector2Array([rail[3], rail[0], apex]), THATCH_D)
	ci.draw_colored_polygon(PackedVector2Array([rail[0], rail[1], apex]), THATCH)
	ci.draw_colored_polygon(PackedVector2Array([rail[1], rail[2], apex]), THATCH_D.darkened(0.06))
	ci.draw_colored_polygon(PackedVector2Array([rail[2], rail[3], apex]), THATCH_D)
	if _winter:   # snowcap on the lookout's thatch hip
		var rl := [rail[3], rail[0], rail[1], rail[2]]
		for k in range(4):
			ci.draw_colored_polygon(PackedVector2Array([apex,
				rl[k].lerp(apex, 0.55), rl[(k + 1) % 4].lerp(apex, 0.55)]),
				Color(SNOW, 0.86 if k == 1 else 0.74))
	# Pennant on the apex.
	ci.draw_line(apex, apex + Vector2(0, -6), WOOD_D, 1.0)
	ci.draw_colored_polygon(PackedVector2Array([apex + Vector2(0, -6), apex + Vector2(6, -4), apex + Vector2(0, -2)]), Color(0.66, 0.22, 0.20))

static func _great_tower(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2) -> void:
	# A tall, imposing battlemented keep-tower: a stout ashlar shaft with arrow-loops, a corbelled
	# machicolation course under the crenellated parapet, a conical-roofed bartizan turret + banner.
	var H := 50.0
	var c := _subbox(ci, t, r, b, l, 0.07, 0.07, 0.93, 0.93, H, STONE, TEX_STONE)
	var ml: Vector2 = c[3] + Vector2(0, H); var mb: Vector2 = c[2] + Vector2(0, H); var mr: Vector2 = c[1] + Vector2(0, H)
	_door(ci, _pt(t, r, b, l, 0.07, 0.20), _pt(t, r, b, l, 0.07, 0.93), H, Color(0.18, 0.12, 0.10))
	for hy in [H * 0.40, H * 0.64]:
		var s1 := ml.lerp(mb, 0.5) + Vector2(0, -hy); ci.draw_rect(Rect2(s1.x - 0.8, s1.y - 3.5, 1.6, 7.0), Color(0.05, 0.05, 0.07))
		var s2 := mb.lerp(mr, 0.5) + Vector2(0, -hy); ci.draw_rect(Rect2(s2.x - 0.8, s2.y - 3.5, 1.6, 7.0), Color(0.05, 0.05, 0.07))
	# Corbelled machicolation course just under the parapet.
	for edge in [[c[3], c[2]], [c[2], c[1]]]:
		for k in range(5):
			var p: Vector2 = (edge[0] as Vector2).lerp(edge[1], (float(k) + 0.5) / 5.0)
			ci.draw_rect(Rect2(p.x - 1.5, p.y, 3.0, 2.4), STONE_D)
	_snow_top(ci, c, 0.4)
	_merlons(ci, c[3], c[2], STONE_L, 4)
	_merlons(ci, c[2], c[1], STONE_L, 4)
	# Conical-roofed bartizan turret on the back corner + a realm banner over the parapet.
	var tc := _cyl(ci, c[0] + Vector2(0, 2), 4.5, 2.2, 12.0, STONE_L)
	_cone(ci, tc, 5.5, 2.7, 9.0, SLATE)
	_finial(ci, tc + Vector2(0, -9), GOLD, 0.8)
	var bx := mb.lerp(mr, 0.5) + Vector2(0, -H - 2)
	ci.draw_colored_polygon(PackedVector2Array([bx + Vector2(-3, 0), bx + Vector2(3, 0), bx + Vector2(3, 14), bx + Vector2(0, 16), bx + Vector2(-3, 14)]), RED)
	ci.draw_circle(bx + Vector2(0, 7), 1.8, GOLD)

# ── Generic fallback ──────────────────────────────────────────────────────────────

static func _generic(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, wall: Color, roof: Color) -> void:
	# A plain-but-built fallback: textured walls (stone for pale/grey walls, half-timber otherwise),
	# a door, lit windows on both front faces, and a small ridge chimney so an unimplemented type
	# still reads as a real little building rather than a blank box.
	var tex: int = TEX_STONE if (wall.s < 0.18 and wall.v > 0.55) else TEX_TIMBER
	var c := _box(ci, t, r, b, l, 16.0, wall, tex)
	_door(ci, l, b, 16.0)
	_win(ci, l.lerp(b, 0.28) + Vector2(0, -9))
	_win(ci, b.lerp(r, 0.72) + Vector2(0, -9))
	_gable(ci, c, 9.0, roof)
	# Ridge chimney with a thin wisp so the roof has a focal detail.
	var apex := (c[0] + c[2]) * 0.5 + Vector2(0, -9.0)
	var ch := apex + Vector2(3.0, 1.0)
	ci.draw_rect(Rect2(ch.x - 1.6, ch.y - 7.0, 3.2, 8.0), WOOD_D)
	ci.draw_rect(Rect2(ch.x - 1.9, ch.y - 8.0, 3.8, 1.6), roof.darkened(0.2))

static func _shop(ci: CanvasItem, t: Vector2, r: Vector2, b: Vector2, l: Vector2, ctr: Vector2, accent: Color, sign: String) -> void:
	var c := _box(ci, t, r, b, l, 16.0, WOOD)
	_door(ci, l, b, 16.0)
	_gable(ci, c, 10.0, THATCH_D)
	# hanging sign with an icon
	var sp := b.lerp(r, 0.5) + Vector2(0, -15)
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
