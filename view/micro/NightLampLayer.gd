extends Node2D
# Warm night lighting for the city view. Drawn ABOVE the darkening wash (NightLayer)
# with an ADD blend mode, so light genuinely brightens the ground, the building it sits
# on, and any pawn standing in it — instead of just tinting the scene.
#
# REDESIGN (iter321): a lamp is no longer a big floating radial circle per torch (dozens
# of those stacked into a shapeless orange smear that read as "Photoshop glow brushes").
# Instead each LIT building casts ONE warm, iso-elliptical POOL of light hugging its
# footprint — so the structure and the lane in front of it read as a cosy lamplit home —
# plus two small, defined flames at the door corners and a couple of windows aglow. The
# pool peaks are kept modest so a dense town stays a constellation of warm hearths with
# pockets of moonlit dark between them, never a single blown-out mass.
# Self-driven from the simulation clock.

const SeasonSystem     = preload("res://simulation/world/SeasonSystem.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

const HALF_W: float = 32.0          # must match BuildingLayer's iso half-tile
const HALF_H: float = 16.0

# Ground light-pool (the main illumination — one per building, sized to its footprint).
# Per-source alphas are kept LOW on purpose: a dense town overlaps many pools, and additive
# light sums — so modest peaks keep an overlapped centre warm amber instead of blowing to
# white glitter, while a lone outlying hovel still reads as clearly lit.
const POOL_ALPHA: float      = 0.26   # additive warmth of the outer pool
const POOL_CORE_ALPHA: float = 0.11   # tighter, hotter heart that defines the hearth
const POOL_MARGIN: float     = 26.0   # how far the pool spills past the footprint (x), px
const POOL_RISE: float       = 12.0   # lift the pool centre toward the building body, px

# Small flame halo right at each door torch (NOT a town-wide glow).
const FLAME_GLOW_R: float     = 24.0
const FLAME_GLOW_ALPHA: float = 0.17
const TORCH_RISE: float       = 14.0  # torches sit up the wall a bit, not on the ground

const WARM: Color     = Color(1.0, 0.64, 0.32)   # ground-pool amber (a touch desaturated)
const CORE_COL: Color = Color(1.0, 0.80, 0.48)   # hotter heart of the pool
const WINDOW_COL: Color = Color(1.0, 0.80, 0.46) # lit-window warm yellow

# Structures that carry NO hearth/torch (a fenced perimeter must not glow like a bonfire).
const NO_LIGHT := ["wooden_palisade", "stone_wall", "stockpile"]

var _night: float = 0.0
var _buildings: Array = []
var _refresh_accum: float = 1.0
var _grad: GradientTexture2D = null
var _t: float = 0.0   # wall-clock seconds, for flame flicker

func _ready() -> void:
	# Additive blend so the light ADDS to the darkened scene below.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	# A soft radial gradient with a fairly FLAT bright centre and a long gentle tail — this
	# reads as light spilling across flat ground, not as a hot point/orb. Stretched into a
	# wide rect it becomes the iso ground ellipse.
	var g := Gradient.new()
	g.set_offset(0, 0.0); g.set_color(0, Color(1, 1, 1, 0.95))
	g.add_point(0.55, Color(1, 1, 1, 0.42))
	g.set_offset(g.get_point_count() - 1, 1.0); g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	_grad = GradientTexture2D.new()
	_grad.gradient = g
	_grad.fill = GradientTexture2D.FILL_RADIAL
	_grad.fill_from = Vector2(0.5, 0.5)
	_grad.fill_to = Vector2(1.0, 0.5)
	_grad.width = 128
	_grad.height = 128

func _process(delta: float) -> void:
	_t += delta
	var n: float = SeasonSystem.night_factor(SimulationClock.current_tick)
	_refresh_accum += delta
	if _refresh_accum >= 1.0:
		_refresh_accum = 0.0
		_refresh_buildings()
	if n > 0.02 or _night > 0.02:
		_night = n
		queue_redraw()
	else:
		_night = n

func _refresh_buildings() -> void:
	var arr: Array = []
	if GameState.players.size() > 0:
		arr = GameState.players[0].get("buildings", []).duplicate()
	for fac in GameState.ai_factions:
		if fac is Dictionary:
			for b in fac.get("buildings", []):
				if b is Dictionary:
					arr.append(b)
	_buildings = arr

func _draw() -> void:
	if _night < 0.03 or _grad == null:
		return
	# Lights ramp in over dusk and reach full at deep night.
	var lit: float = smoothstep(0.1, 0.7, _night)
	if lit <= 0.0:
		return
	for b in _buildings:
		if not (b is Dictionary) or not b.get("built", true):
			continue
		var bt: String = String(b.get("type", ""))
		if BuildingRegistry.is_path(bt) or bt in NO_LIGHT:
			continue
		var gx: int = int(b.get("grid_x", 0))
		var gy: int = int(b.get("grid_y", 0))
		var defn: Dictionary = BuildingRegistry.lookup(bt)
		var w: int = maxi(1, int(defn.get("width", 1)))
		var h: int = maxi(1, int(defn.get("height", 1)))
		var cx: float = (gx - gy) * HALF_W
		var cy: float = (gx + gy) * HALF_H
		var phase: float = float((gx * 7 + gy * 13) % 628) * 0.01
		var flick: float = _flicker(phase)
		# ── Ground light-pool hugging the footprint (the main illumination). ──
		# Footprint ground-centroid, then nudge UP so the pool also catches the building body.
		var fcx: float = cx + (w - h) * 0.5 * HALF_W
		var fcy: float = cy + (w + h - 2) * 0.5 * HALF_H - POOL_RISE
		var rx: float = (w + h) * 0.5 * HALF_W + POOL_MARGIN
		var ry: float = (w + h) * 0.5 * HALF_H + POOL_MARGIN * 0.62
		_blit_ellipse(Vector2(fcx, fcy), rx, ry,
			Color(WARM.r, WARM.g, WARM.b, POOL_ALPHA * lit * flick))
		_blit_ellipse(Vector2(fcx, fcy), rx * 0.56, ry * 0.56,
			Color(CORE_COL.r, CORE_COL.g, CORE_COL.b, POOL_CORE_ALPHA * lit * flick))
		# ── The two door-corner flames (the actual fire sources) + a tight halo each. ──
		var left_corner: Vector2 = Vector2(cx - h * HALF_W, cy + (h - 1) * HALF_H)
		var bot_corner:  Vector2 = Vector2(cx + (w - h) * HALF_W, cy + (w + h - 1) * HALF_H)
		_draw_torch_point(left_corner + Vector2(0, -TORCH_RISE), lit, phase)
		_draw_torch_point(bot_corner + Vector2(0, -TORCH_RISE), lit, phase + 1.7)
		# ── Windows aglow on the front face — the touch of life that says "home". ──
		_draw_windows(left_corner, bot_corner, w, h, lit, phase)

func _flicker(phase: float) -> float:
	# Believable flicker: three sine waves at different sub-20Hz rates (slow breath + mid
	# waver + fast jitter) so the light pulses organically without ever strobing. Kept >= 0.6
	# so a pool never gutters fully out.
	var f: float = 1.0 \
		+ 0.05 * sin(_t * 1.7 + phase) \
		+ 0.07 * sin(_t * 6.3 + phase * 1.9) \
		+ 0.05 * sin(_t * 11.0 + phase * 0.7)
	return maxf(f, 0.6)

func _draw_torch_point(p: Vector2, lit: float, phase: float) -> void:
	var flick: float = _flicker(phase)
	var rw: float = 1.0 + 0.04 * sin(_t * 5.1 + phase * 1.3)
	# A small, contained warm halo at the flame — no town-wide reach.
	_blit_ellipse(p, FLAME_GLOW_R * rw, FLAME_GLOW_R * rw * 0.82,
		Color(CORE_COL.r, CORE_COL.g, CORE_COL.b, FLAME_GLOW_ALPHA * lit * flick))
	_draw_flame(p, lit, phase)

func _draw_windows(c1: Vector2, c2: Vector2, w: int, h: int, lit: float, phase: float) -> void:
	# 1–2 small warm windows spaced along the front (door) wall, raised to wall height. Each
	# breathes at its own slow rate (different hearths, different fires). Kept dim — these are
	# accents on an already-lit home, not lanterns; too bright and a town reads as glitter.
	var n: int = clampi(maxi(w, h), 1, 2)
	for i in range(n):
		var t: float = (i + 1.0) / (n + 1.0)
		var wp: Vector2 = c1.lerp(c2, t) + Vector2(0, -12.0)
		var breathe: float = 0.62 + 0.20 * sin(_t * (2.3 + 0.6 * i) + phase + i * 1.3)
		var a: float = clampf(breathe, 0.0, 1.0) * lit
		_blit_ellipse(wp, 6.0, 5.0, Color(WINDOW_COL.r, WINDOW_COL.g, WINDOW_COL.b, 0.12 * a))
		draw_rect(Rect2(wp - Vector2(1.5, 2.0), Vector2(3.0, 4.0)),
			Color(WINDOW_COL.r, WINDOW_COL.g, WINDOW_COL.b, 0.5 * a))

func _draw_flame(c: Vector2, lit: float, phase: float) -> void:
	# Irregular fire flicker (fast + a faster harmonic) and a lateral lick/sway.
	var fl: float = 0.72 + 0.22 * sin(_t * 13.0 + phase) + 0.12 * sin(_t * 23.0 + phase * 2.1)
	var h: float = 7.0 * maxf(fl, 0.4)
	var sway: float = 1.2 * sin(_t * 9.0 + phase * 1.7) + 0.6 * sin(_t * 17.0 + phase)
	var bw: float = 2.2
	var tip: Vector2 = c + Vector2(sway, -h)
	# Outer flame (orange).
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-bw, 0.5), c + Vector2(-bw * 0.7, -h * 0.45), tip,
		c + Vector2(bw * 0.7, -h * 0.45), c + Vector2(bw, 0.5)]),
		Color(1.0, 0.45, 0.12, 0.85 * lit))
	# Inner flame (bright yellow), smaller and swaying a touch less.
	var ih: float = h * 0.58
	var itip: Vector2 = c + Vector2(sway * 0.6, -ih)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-bw * 0.5, 0.3), c + Vector2(-bw * 0.32, -ih * 0.5), itip,
		c + Vector2(bw * 0.32, -ih * 0.5), c + Vector2(bw * 0.5, 0.3)]),
		Color(1.0, 0.85, 0.45, 0.9 * lit))
	# Tiny hot core at the wick.
	draw_circle(c + Vector2(0, -1.0), 1.0, Color(1.0, 0.95, 0.72, 0.7 * lit))

func _blit_ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	draw_texture_rect(_grad, Rect2(c - Vector2(rx, ry), Vector2(rx * 2.0, ry * 2.0)), false, col)
