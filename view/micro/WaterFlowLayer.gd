extends Node2D
# Animated river/sea surface. Every water tile (RIVER / COASTAL) is drawn once as an
# ORGANIC rounded shape (not a hard iso diamond) with the water_flow shader. Corners
# that face land are rounded off while corners that continue into water stay full, so a
# connected channel or lake reads as one smooth body with natural banks instead of a
# grid of boxes — and the bends feel like flowing water, not stacked cubes. Tiles are
# inflated a touch so neighbouring water overlaps (no seams). The mesh is static (built
# once); the GPU animates it via TIME, so it costs ~nothing per frame.
#
# Each vertex colour bakes: rg = the channel's downstream flow direction (so the current
# follows the bends), b = water type (0 river / 1 coastal), a = depth/interior amount
# (1 = deep centre, 0 = bank) which the shader uses to deepen the water and lace foam
# along the shoreline.

const HALF_W: float = 32.0
const HALF_H: float = 16.0
const MARGIN: float = 0.10   # inflate each tile so neighbouring water overlaps (kills seams, merges the body)

const T_GRASS := 0
const T_RIVER := 3
const T_COASTAL := 8

# Per-corner neighbour lookup: [cardinal A, cardinal B, diagonal] for top/right/bottom/left.
# A corner is rounded when its two cardinal neighbours are land (it sticks out), kept full
# when they are water (the body continues); the diagonal feeds the depth/shore gradient.
const _CORNER_DATA := [
	[Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)],  # top
	[Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, -1)],    # right
	[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],      # bottom
	[Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, 1)],    # left
]

var _built: bool = false

func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://view/micro/water_flow.gdshader")
	# Child order (added after terrain, before decor) keeps it above the flat water
	# base and below trees/buildings — no z_index override needed.

func _is_water(gx: int, gy: int) -> bool:
	var t: int = GameState.get_terrain_at(gx, gy)
	return t == T_RIVER or t == T_COASTAL

# Downstream tangent of the channel, in screen space. Rivers run generally north→south
# (+gy); we take the vector from the upstream (north) water centroid to the downstream
# (south) one, so the current follows the channel axis smoothly through every bend
# instead of snapping per tile. Falls back gracefully at sources/mouths and lakes.
func _flow_dir(gx: int, gy: int) -> Vector2:
	var north := Vector2.ZERO
	var south := Vector2.ZERO
	var nn: int = 0
	var ns: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if _is_water(gx + dx, gy + dy):
				if dy > 0:
					south += Vector2(dx, dy); ns += 1
				elif dy < 0:
					north += Vector2(dx, dy); nn += 1
	var grid_dir: Vector2
	if ns > 0 and nn > 0:
		grid_dir = south / float(ns) - north / float(nn)
	elif ns > 0:
		grid_dir = south / float(ns)
	elif nn > 0:
		grid_dir = -north / float(nn)
	else:
		grid_dir = Vector2(0, 1)
	# Grid → iso screen direction (HALF_H/HALF_W = 0.5).
	var scr := Vector2(grid_dir.x - grid_dir.y, (grid_dir.x + grid_dir.y) * 0.5)
	if scr.length() < 0.001:
		scr = Vector2(-0.894, 0.447)  # default iso-south
	return scr.normalized()

func _draw() -> void:
	var gs: Vector2i = GameState.get_grid_size()
	for gy in range(gs.y):
		for gx in range(gs.x):
			if _is_water(gx, gy):
				_draw_tile(gx, gy)
	_built = true

func _draw_tile(gx: int, gy: int) -> void:
	var center := Vector2((gx - gy) * HALF_W, (gx + gy) * HALF_H)
	var k: float = 1.0 + MARGIN
	# top, right, bottom, left — inflated so adjacent water tiles overlap.
	var corners := [
		center + Vector2(0.0, -HALF_H) * k,
		center + Vector2(HALF_W, 0.0) * k,
		center + Vector2(0.0, HALF_H) * k,
		center + Vector2(-HALF_W, 0.0) * k,
	]
	var bevel := [0.0, 0.0, 0.0, 0.0]
	var interior := [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		var d: Array = _CORNER_DATA[i]
		var ca: bool = _is_water(gx + d[0].x, gy + d[0].y)
		var cb: bool = _is_water(gx + d[1].x, gy + d[1].y)
		var diag: bool = _is_water(gx + d[2].x, gy + d[2].y)
		var wc: int = (1 if ca else 0) + (1 if cb else 0)
		# Both cardinals water → interior corner, keep sharp (seamless). One → gentle
		# round (straight bank). Neither → convex tip jutting into land, round it hard.
		# Kept < 0.5 so adjacent rounded corners never overlap (self-intersecting outline).
		bevel[i] = 0.0 if wc == 2 else (0.32 if wc == 1 else 0.46)
		interior[i] = (wc + (1 if diag else 0)) / 3.0

	var fdir := _flow_dir(gx, gy)
	var type_flag: float = 1.0 if GameState.get_terrain_at(gx, gy) == T_COASTAL else 0.0
	var rx: float = fdir.x * 0.5 + 0.5
	var ry: float = fdir.y * 0.5 + 0.5

	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in 4:
		var c: Vector2 = corners[i]
		var col := Color(rx, ry, type_flag, interior[i])
		var t: float = bevel[i]
		if t <= 0.0:
			pts.append(c)
			cols.append(col)
		else:
			# Round the corner: a small convex arc (quadratic Bézier through the tip)
			# joining the two adjacent edges, so the outline curves like a bank.
			var p_in: Vector2 = c.lerp(corners[(i + 3) % 4], t)
			var p_out: Vector2 = c.lerp(corners[(i + 1) % 4], t)
			var seg: int = 4
			for s in range(seg + 1):
				var u: float = float(s) / float(seg)
				var iu: float = 1.0 - u
				pts.append(iu * iu * p_in + 2.0 * iu * u * c + u * u * p_out)
				cols.append(col)
	draw_polygon(pts, cols)
