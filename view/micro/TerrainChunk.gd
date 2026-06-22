extends Node2D
# One CHUNK×CHUNK block of terrain tiles, painted once. Splitting the map into
# many small canvas items lets Godot's 2D renderer cull the off-screen chunks —
# so zoomed in, only the handful of visible chunks are drawn each frame instead
# of the whole 200×200 map. Terrain is static, so each chunk paints once.

const HALF_W: float = 32.0
const HALF_H: float = 16.0

const SeasonSystem = preload("res://simulation/world/SeasonSystem.gd")

# Vegetation terrains that recolour with the season (grass/forest/marsh/valley).
const VEG_TERRAIN: Array = [0, 1, 4, 7]

const TERRAIN_COLORS: Array = [
	Color(0.45, 0.62, 0.32),  # 0 GRASS — warmed/muted toward the painterly building-plot grass so the sprite plots blend into the ground instead of reading as brighter squares
	Color(0.12, 0.40, 0.17),  # 1 FOREST
	Color(0.26, 0.25, 0.26),  # 2 MOUNTAIN — dark rock base; the DecorChunk draws the raised cliff/plateau on top, so this only shows as shadow at the foot of the rim
	Color(0.12, 0.30, 0.44),  # 3 RIVER — muted deep base; the organic water layer floats on top, so this only shows as the deeper water hugging the rounded banks (was a bright cobalt that rimmed every tile)
	Color(0.44, 0.52, 0.24),  # 4 MARSH
	Color(0.43, 0.43, 0.48),  # 5 ROCK
	Color(0.66, 0.43, 0.26),  # 6 ORE_VEIN
	Color(0.50, 0.67, 0.35),  # 7 VALLEY — muted toward GRASS (was a bright 0.58,0.82,0.40 that popped as light squares against the warmed grass); kept a touch lighter/lusher so the biome still reads
	Color(0.20, 0.44, 0.56),  # 8 COASTAL — muted deep base under the organic water layer (matches the shader's deep tone so the rounded banks read as deeper water, not a bright rim)
	Color(0.62, 0.47, 0.30),  # 9 ROAD — worn earthen path; darker/browner than the old pale tan so trodden roads read clearly against the green fields
	Color(0.41, 0.33, 0.28),  # 10 RUIN
	Color(0.12, 0.30, 0.44),  # 11 BRIDGE — dark water under the plank deck (deck drawn on top by BuildingLayer)
]

var _x0: int = 0
var _y0: int = 0
var _x1: int = 0
var _y1: int = 0

func _ready() -> void:
	# Terrain is otherwise static, but the season repaints the land and the player can
	# lay paths at runtime — so listen and repaint when our cells change.
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
	# Build the whole chunk as ONE triangle soup and submit it in a single draw call. The old
	# path issued a draw_colored_polygon PER TILE — with the whole map visible (zoomed out) that
	# was ~40k draw calls/frame and pinned the framerate to single digits. Batching a 16×16 chunk
	# into one canvas_item_add_triangle_array makes it one draw call: ~156 for the entire map.
	var season: int = int(GameState.world.get("season", SeasonSystem.Season.SUMMER))
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var base: int = 0
	var crop_tiles: Array = []   # field tiles → a per-tile crop-detail pass after the base batch
	for gy in range(_y0, _y1):
		for gx in range(_x0, _x1):
			var t: int = GameState.get_terrain_at(gx, gy)
			# Water, mountain AND forest cells are painted as plain GRASS ground. Water floats
			# an organic body on top (banks meet grass directly); the mountain is a raised grassy
			# MESA whose rocky cliff is drawn by the DecorChunk; and the forest's trees are drawn
			# by the TreeLayer — so the ground UNDER the trees is the same grass texture as the
			# open fields, not a darker forest-green patch.
			var ft: int = 0 if (t == 3 or t == 8 or t == 2 or t == 1) else t
			var fill: Color = _season_fill(ft, TERRAIN_COLORS[mini(ft, TERRAIN_COLORS.size() - 1)], season)
			fill = _vary(fill, ft, gx, gy)
			# A field building stamps a CROP onto the real terrain, so this very tile renders as
			# farmland (wheat/tilled/mud) instead of grass — no separate building "floor". The base
			# colour goes in the batch; the texture (strands/clods) is the per-tile pass below.
			var crop: int = GameState.get_field_crop_at(gx, gy)
			if crop != 0:
				fill = _vary(_crop_base(crop, season), 0, gx, gy)
				crop_tiles.append([gx, gy, crop])
			var cx: float = (gx - gy) * HALF_W
			var cy: float = (gx + gy) * HALF_H
			points.append(Vector2(cx, cy - HALF_H))
			points.append(Vector2(cx + HALF_W, cy))
			points.append(Vector2(cx, cy + HALF_H))
			points.append(Vector2(cx - HALF_W, cy))
			colors.append(fill); colors.append(fill); colors.append(fill); colors.append(fill)
			indices.append(base); indices.append(base + 1); indices.append(base + 2)
			indices.append(base); indices.append(base + 2); indices.append(base + 3)
			base += 4
	if not points.is_empty():
		RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(), indices, points, colors)
	# Per-tile crop texture (drawn on top of the base diamonds, still at TERRAIN level → below the
	# pawns, so workers toil ON the crop). Cheap: only the handful of field tiles, deterministic.
	for ct in crop_tiles:
		_draw_crop_detail(ct[0], ct[1], int(ct[2]), season)

# Base ground colour for a crop tile (seasonal for wheat). 1 wheat, 2 orchard, 3 pasture, 4 mud, 5 hops.
func _crop_base(crop: int, season: int) -> Color:
	match crop:
		1:   return Color(0.40, 0.29, 0.19)   # wheat — TILLED BROWN SOIL at every stage; the crop
											  # (green→gold) GROWS on top (see _draw_crop_detail)
		2:   return Color(0.40, 0.55, 0.29)   # orchard — kept grass
		3:   return Color(0.44, 0.58, 0.32)   # pasture
		4:   return Color(0.45, 0.35, 0.23)   # mud (pig pen)
		5:   return Color(0.44, 0.56, 0.30)   # hops yard
	return Color(0.45, 0.62, 0.32)

func _ch(gx: int, gy: int, salt: int) -> float:
	var h: int = ((gx * 73856093) ^ (gy * 19349663) ^ (salt * 83492791)) & 0xffff
	return float(h) / 65535.0

# One tile's worth of crop texture. Wheat grows literal strands out of the ground; mud gets clods;
# the grassy crops get a few tufts. Deterministic from the tile coords (stable across repaints).
func _draw_crop_detail(gx: int, gy: int, crop: int, season: int) -> void:
	var cx: float = (gx - gy) * HALF_W
	var cy: float = (gx + gy) * HALF_H
	if crop == 1:
		# FURROW ROWS in the tilled soil — parallel lines that connect across tiles along the iso
		# row, so the bare field reads as ploughed earth (the reference's brown plot).
		var top := Vector2(cx, cy - HALF_H)
		var rgt := Vector2(cx + HALF_W, cy)
		var bot := Vector2(cx, cy + HALF_H)
		var lft := Vector2(cx - HALF_W, cy)
		var furrow := Color(0.31, 0.22, 0.14, 0.8)
		var ridge := Color(0.47, 0.35, 0.23, 0.55)
		for f in [0.18, 0.40, 0.62, 0.84]:
			draw_line(top.lerp(lft, f), rgt.lerp(bot, f), furrow, 1.2)
			draw_line(top.lerp(lft, f + 0.06), rgt.lerp(bot, f + 0.06), ridge, 0.8)
		var stage: int = SeasonSystem.growth_stage(season)
		if stage == 0:
			return   # winter/just-tilled — bare furrowed soil, no standing grain yet
		# The crop GROWS on the soil: sparse short green sprouts (brown soil shows) → a DENSE near-
		# solid stand of ripe gold. From stage 2 a translucent crop "canopy" fills between the
		# strands so the maturing field reads as a full crop, not dirt with a few blades.
		var ripe: bool = stage == 3
		var lo: Color; var hi: Color
		match stage:
			1: lo = Color(0.40, 0.56, 0.22); hi = Color(0.54, 0.68, 0.30)
			2: lo = Color(0.34, 0.52, 0.16); hi = Color(0.48, 0.62, 0.22)
			_: lo = Color(0.78, 0.60, 0.16); hi = Color(0.96, 0.82, 0.34)
		if stage >= 2:
			var canopy: Color = (Color(0.40, 0.56, 0.20, 0.55) if stage == 2
				else Color(0.88, 0.72, 0.24, 0.78))   # gold canopy nearly covers the soil when ripe
			draw_colored_polygon(PackedVector2Array([top, rgt, bot, lft]), canopy)
		var n: int = 22 if stage == 1 else (46 if stage == 2 else 64)
		for i in range(n):
			var ox: float = (_ch(gx, gy, i) - 0.5) * 1.25 * HALF_W
			var oy: float = (_ch(gx, gy, i + 40) - 0.5) * 1.25 * HALF_H
			var bp := Vector2(cx + ox, cy + oy)
			var hgt: float = (4.0 + _ch(gx, gy, i + 80) * 4.0) * (0.5 if stage == 1 else (0.8 if stage == 2 else 1.0))
			var lean: float = (_ch(gx, gy, i + 120) - 0.5) * 1.6
			var tp := bp + Vector2(lean, -hgt)
			var col: Color = lo.lerp(hi, _ch(gx, gy, i + 160))
			draw_line(bp, tp, col.darkened(0.16), 0.9)                 # stalk
			# A fuller ear: a short thick spike that nods over, with side awns when ripe.
			var ear_tip := tp + Vector2(signf(lean) * 0.5, -1.0).normalized() * (hgt * 0.5 + 2.2)
			draw_line(tp, ear_tip, col.lightened(0.12) if ripe else col, 2.0)
			if ripe:
				var mid := tp.lerp(ear_tip, 0.55)
				draw_line(mid + Vector2(1.0, 0), ear_tip + Vector2(0.7, 0.3), hi, 0.7)
				draw_line(mid + Vector2(-1.0, 0), ear_tip + Vector2(-0.7, 0.3), hi, 0.7)
				draw_circle(ear_tip, 0.9, hi.lightened(0.1))
	elif crop == 4:
		for i in range(4):   # mud clods + a glint of damp
			var p := Vector2(cx + (_ch(gx, gy, i) - 0.5) * 1.6 * HALF_W, cy + (_ch(gx, gy, i + 20) - 0.5) * 1.6 * HALF_H)
			draw_circle(p, 1.2 + _ch(gx, gy, i + 60) * 1.0, Color(0.34, 0.26, 0.18) if i % 2 == 0 else Color(0.52, 0.42, 0.28))
	else:
		var tuft := _crop_base(crop, season).darkened(0.16)   # grassy crops: a couple of blades
		for i in range(3):
			var p := Vector2(cx + (_ch(gx, gy, i) - 0.5) * 1.5 * HALF_W, cy + (_ch(gx, gy, i + 10) - 0.5) * 1.5 * HALF_H)
			draw_line(p, p + Vector2((_ch(gx, gy, i + 30) - 0.5) * 1.6, -2.2), tuft, 0.8)

# Subtle, deterministic per-tile variation so open ground reads as living grass instead of a
# flat colour void: soft large-scale meadow mottling + a fine per-tile grain + a gentle warm/cool
# hue drift. Deterministic from coords (stable across repaints — no shimmer). Water/road stay clean.
func _vary(base: Color, t: int, gx: int, gy: int) -> Color:
	if t == 3 or t == 8 or t == 9 or t == 11:   # RIVER / COASTAL / ROAD / BRIDGE — keep crisp
		return base
	# Soft patches (meadow clumps) — two low-freq waves blended.
	var patch: float = 0.5 * sin(gx * 0.37 + gy * 0.21) + 0.5 * sin((gx + gy) * 0.17 + 1.3)
	# A slower, larger color ZONE wave — broad warmer/cooler stretches of meadow so the
	# field reads as textured ground with character, not one flat carpet (still calm).
	var zone: float = sin(gx * 0.09 - gy * 0.07 + 2.1) * 0.6 + sin((gx - gy) * 0.05) * 0.4
	# Fine per-tile grain — deterministic hash in [-0.5, 0.5].
	var h: int = ((gx * 73856093) ^ (gy * 19349663)) & 0xffff
	var grain: float = float(h) / 65535.0 - 0.5
	var amt: float = patch * 0.050 + grain * 0.028 + zone * 0.022   # patches + soft zones + fine grain
	var c: Color = base.lightened(amt) if amt >= 0.0 else base.darkened(-amt)
	# Gentle hue drift: brighter patches lean warm/yellow-green, darker lean cool/blue-green.
	c = c.lerp(Color(c.r * 1.06, c.g * 1.02, c.b * 0.90, c.a), clampf(patch, 0.0, 1.0) * 0.18)
	c = c.lerp(Color(c.r * 0.92, c.g * 0.99, c.b * 1.08, c.a), clampf(-patch, 0.0, 1.0) * 0.18)
	# Broad warm/cool color zones layered on top (low amplitude → reads as terrain, not noise).
	c = c.lerp(Color(c.r * 1.05, c.g * 1.01, c.b * 0.92, c.a), clampf(zone, 0.0, 1.0) * 0.14)
	c = c.lerp(Color(c.r * 0.94, c.g * 1.00, c.b * 1.06, c.a), clampf(-zone, 0.0, 1.0) * 0.14)
	return Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0), base.a)

# Recolour a tile for the season: vegetation greens up in spring, deepens in summer,
# turns gold in autumn and is blanketed pale in winter; rock/water barely shift.
func _season_fill(t: int, base: Color, season: int) -> Color:
	if t not in VEG_TERRAIN:
		if season == SeasonSystem.Season.WINTER:
			return base.lerp(Color(0.80, 0.85, 0.92), 0.12)
		return base
	match season:
		SeasonSystem.Season.SPRING: return base.lerp(Color(0.55, 0.82, 0.42), 0.30)
		SeasonSystem.Season.SUMMER: return base
		SeasonSystem.Season.AUTUMN: return base.lerp(Color(0.74, 0.56, 0.24), 0.40)
		SeasonSystem.Season.WINTER: return base.lerp(Color(0.85, 0.88, 0.94), 0.58)
	return base
