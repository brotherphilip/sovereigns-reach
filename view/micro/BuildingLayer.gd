extends Node2D
# Draws all buildings as 3D-appearance multi-polygon structures (painter's
# algorithm). Depth-sorted by grid_x + grid_y ascending (back-to-front).

const HALF_W: float = 32.0
const HALF_H: float = 16.0

# Toggle for the hand-painted sprite art layered over the procedural buildings. Off for now —
# set true to bring the painted overlays back.
const DRAW_SPRITE_OVERLAY: bool = false

# Category colors (BuildingRegistry.Category enum 0–4)
const CAT_COLORS: Array = [
	Color(0.67, 0.87, 0.98),  # 0 CIVIC — light blue
	Color(0.80, 0.64, 0.36),  # 1 HARVESTING — tan
	Color(0.76, 0.96, 0.64),  # 2 FOOD — light green
	Color(0.90, 0.45, 0.40),  # 3 MILITARY — red
	Color(0.62, 0.62, 0.80),  # 4 DEFENSE — steel blue
]

const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const BuildingRenderer  = preload("res://view/micro/BuildingRenderer.gd")
const BuildingModels    = preload("res://view/micro/BuildingModels.gd")
const BuildingSpriteOverlay = preload("res://view/micro/BuildingSpriteOverlay.gd")  # painted sprite on top, where art exists
const StorageSystem     = preload("res://simulation/economy/StorageSystem.gd")

var _buildings:       Array = []
var _enemy_buildings: Array = []
var _structure_dirty: bool = true
var _has_fire:        bool = false
var _tick:            int = 0

# Ghost preview state (build-mode cursor)
var _ghost_type:  String = ""
var _ghost_gx:    int    = 0
var _ghost_gy:    int    = 0
var _ghost_valid: bool   = true

var _ghost_bridge: Array = []   # bridge deck cells (Array of [x,y]) when in bridge mode

func set_ghost(btype: String, gx: int, gy: int, valid: bool) -> void:
	_ghost_type  = btype
	_ghost_gx    = gx
	_ghost_gy    = gy
	_ghost_valid = valid
	_ghost_bridge = []
	queue_redraw()

# Bridge build mode: the whole computed span is previewed (green=valid, red=can't reach).
func set_ghost_bridge(deck: Array, valid: bool) -> void:
	_ghost_type  = "bridge"
	_ghost_bridge = deck
	_ghost_valid = valid
	queue_redraw()

func clear_ghost() -> void:
	_ghost_type = ""
	_ghost_bridge = []
	queue_redraw()

func _ready() -> void:
	EventBus.simulation_tick.connect(_on_tick)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_demolished.connect(_on_building_removed)

func _process(_delta: float) -> void:
	if _ghost_type != "" or _has_fire:
		queue_redraw()

func _on_tick(tick: int) -> void:
	_tick = tick
	# Rebuild the lists only on structure change or daily (fog refresh); the per-tick
	# queue_redraw still repaints live visual state (fire / HP / construction).
	if _structure_dirty or tick % 240 == 0:
		_rebuild()
		_structure_dirty = false
	_has_fire = false
	for b in _buildings:
		if b is Dictionary and b.get("is_on_fire", false):
			_has_fire = true
			break
	queue_redraw()

func _on_building_placed(_pid, _btype, _gx, _gy, _bid) -> void:
	_structure_dirty = true

func _on_building_removed(_pid, _bid) -> void:
	_structure_dirty = true

func _rebuild() -> void:
	_buildings = []
	_enemy_buildings = []
	if GameState.players.size() > 0:
		_buildings = GameState.players[0].get("buildings", []).duplicate()
	for fac in GameState.ai_factions:
		if fac is Dictionary:
			# Faction identity tint key: prefer a stable faction id, else fall back to colour hash.
			var fkey: int = int(fac.get("id", abs(hash(str(fac.get("name", ""))))))
			for bld in fac.get("buildings", []):
				# Fog of war disabled for now: show all enemy buildings.
				if bld is Dictionary:
					_enemy_buildings.append({"b": bld, "fac": fkey})

func _draw() -> void:
	# Combine and depth-sort by grid_x + grid_y ascending (back-to-front)
	if _ghost_type != "":
		_draw_ghost()
	var all: Array = []
	for e in _enemy_buildings:
		if e is Dictionary and e["b"] is Dictionary:
			all.append({"b": e["b"], "enemy": true, "fac": int(e.get("fac", 0))})
	for b in _buildings:
		if b is Dictionary: all.append({"b": b, "enemy": false, "fac": 0})
	all.sort_custom(func(a, e):
		var ad: int = a["b"].get("grid_x", 0) + a["b"].get("grid_y", 0)
		var ed: int = e["b"].get("grid_x", 0) + e["b"].get("grid_y", 0)
		return ad < ed)
	for entry in all:
		_draw_building(entry["b"], entry["enemy"], int(entry.get("fac", 0)))

func _draw_building(b: Dictionary, is_enemy: bool, fac_key: int = 0) -> void:
	var gx: int       = b.get("grid_x", 0)
	var gy: int       = b.get("grid_y", 0)
	var btype: String = b.get("type", "")
	# A bridge is a plank deck spanning a river — drawn from its stored span.
	if BuildingRegistry.is_bridge(btype):
		_bridge_span(b.get("bridge_deck", []),
			Color(0.50, 0.36, 0.20), Color(0.40, 0.28, 0.15), Color(0.34, 0.24, 0.13))
		return
	# A path-in-progress is just a marked tile being paved — not a structure.
	if BuildingRegistry.is_path(btype):
		var pcx: float = (gx - gy) * HALF_W
		var pcy: float = (gx + gy) * HALF_H
		var prog: float = clampf(float(b.get("build_progress", 0.0)) / maxf(1.0, float(b.get("build_required", 1.0))), 0.0, 1.0)
		var pcol := Color(0.78, 0.70, 0.48, 0.35 + 0.5 * prog)   # paving fills in as it's built
		draw_colored_polygon(PackedVector2Array([
			Vector2(pcx, pcy - HALF_H), Vector2(pcx + HALF_W, pcy),
			Vector2(pcx, pcy + HALF_H), Vector2(pcx - HALF_W, pcy)]), pcol)
		return
	var defn: Dictionary  = BuildingRegistry.lookup(btype)
	var w: int        = defn.get("width",  1)
	var h: int        = defn.get("height", 1)
	var cat: int      = defn.get("category", 0)
	var vs: Dictionary = BuildingRenderer.get_visual_state(b)

	# Material palette — natural wall/roof/trim colours per type, like the trees.
	var mat: Dictionary = _materials(cat, btype, is_enemy, fac_key)
	var wall_col: Color = mat["wall"]
	var roof_base: Color = mat["roof"]
	var trim_col: Color  = mat["trim"]
	match vs.get("state", "empty"):
		"empty":   wall_col = wall_col.darkened(0.35); roof_base = roof_base.darkened(0.3)
		"damaged": wall_col = wall_col.lerp(Color(0.55, 0.42, 0.32), 0.6)
		"fire":    wall_col = Color(0.55, 0.30, 0.18); roof_base = Color(0.45, 0.20, 0.10)
		"working": pass

	var max_w: int = defn.get("max_workers", 0)
	var built: bool = b.get("built", true)
	# Construction progress drives how high the structure has risen within the scaffold.
	var prog: float = 1.0
	if not built:
		prog = clampf(float(b.get("build_progress", 0.0)) / maxf(1.0, float(b.get("build_required", 1.0))), 0.0, 1.0)

	# Footprint corners in iso-space (painter's algorithm order)
	var cx: float    = (gx - gy) * HALF_W
	var cy: float    = (gx + gy) * HALF_H

	var top:   Vector2 = Vector2(cx,                    cy - HALF_H)
	var right: Vector2 = Vector2(cx + w * HALF_W,       cy + (w - 1) * HALF_H)
	var bot:   Vector2 = Vector2(cx + (w - h) * HALF_W, cy + (w + h - 1) * HALF_H)
	var left:  Vector2 = Vector2(cx - h * HALF_W,       cy + (h - 1) * HALF_H)

	var full_height: float = 18.0 + (w + h) * 4.0
	# Walls rise with progress; the roof goes on once mostly topped out.
	var wall_height: float = full_height * prog
	var show_roof: bool = built or prog >= 0.82

	var center: Vector2 = (top + bot) * 0.5

	var ridge_h: float = 0.0   # label/alert vertical spacing

	# Lifted wall-top corners (construction massing + the HP bar reference these).
	var top_up:   Vector2 = top   + Vector2(0, -wall_height)
	var right_up: Vector2 = right + Vector2(0, -wall_height)
	var bot_up:   Vector2 = bot   + Vector2(0, -wall_height)
	var left_up:  Vector2 = left  + Vector2(0, -wall_height)

	if built:
		# ── Finished: bespoke per-type model that looks like the thing it is ────
		if btype == "stockpile":
			# Stockpiles are a blank platform whose goods PILES grow/shrink with the realm's
			# stored stock (and vanish when empty). The initial (founding) stockpile is bigger.
			_draw_stockpile(b, is_enemy, top, right, bot, left)
		else:
			# Hearth smoke signals LIFE: only let chimneys smoke when the building is staffed
			# (workers > 0) or it's a dwelling — an idle, empty workshop reads as cold/quiet.
			var active: bool = int(b.get("workers", 0)) > 0 or btype == "hovel"
			BuildingModels.draw_finished(self, btype, cat, w, h, top, right, bot, left,
				wall_col, roof_base, trim_col, Time.get_ticks_msec() * 0.001,
				int(GameState.world.get("season", 2)), int(b.get("id", 0)), active)
			# Painted sprite drawn ON TOP of the procedural model, where hand-painted art
			# exists for this type. Additive only — the procedural building still renders
			# underneath, so a type without a sprite (or a failed load) keeps its old look.
			# Temporarily disabled (DRAW_SPRITE_OVERLAY) — flip back to true to re-enable.
			if DRAW_SPRITE_OVERLAY and BuildingSpriteOverlay.has_sprite(btype):
				BuildingSpriteOverlay.draw(self, btype, top, right, bot, left, int(b.get("id", 0)))
		draw_polyline(PackedVector2Array([top, right, bot, left, top]),
			Color(0, 0, 0, 0.16), 0.6)
	else:
		# ── Under construction: structure rises within the scaffolding ──────────
		var shadow_off := Vector2(3.0, 5.0)
		draw_colored_polygon(PackedVector2Array([
			top + shadow_off, right + shadow_off,
			bot + shadow_off, left + shadow_off,
		]), Color(0.0, 0.0, 0.0, 0.22))

		if prog < 0.12:
			draw_colored_polygon(PackedVector2Array([top, right, bot, left]),
				Color(0.55, 0.52, 0.47))

		if wall_height > 1.0:
			draw_colored_polygon(PackedVector2Array([left, top, top_up, left_up]),
				wall_col.darkened(0.32))
			draw_colored_polygon(PackedVector2Array([top, right, right_up, top_up]),
				wall_col.darkened(0.14))
			var sill: float = -minf(wall_height * 0.16, 4.0)
			draw_line(left + Vector2(0, sill), top + Vector2(0, sill), wall_col.lightened(0.12), 1.2)
			draw_line(top + Vector2(0, sill), right + Vector2(0, sill), wall_col.lightened(0.18), 1.2)
			draw_polyline(PackedVector2Array([left, top, top_up, left_up, left]), Color(0, 0, 0, 0.35), 0.5)
			draw_polyline(PackedVector2Array([top, right, right_up, top_up, top]), Color(0, 0, 0, 0.35), 0.5)

		if show_roof:
			ridge_h = clampf(full_height * 0.40, 8.0, 24.0)
			var ridge_apex: Vector2 = (top_up + bot_up) * 0.5 + Vector2(0, -ridge_h)
			draw_colored_polygon(PackedVector2Array([top_up, right_up, bot_up, left_up]), roof_base.darkened(0.10))
			draw_colored_polygon(PackedVector2Array([left_up, bot_up, ridge_apex]), roof_base.darkened(0.12))
			draw_colored_polygon(PackedVector2Array([top_up, right_up, ridge_apex]), roof_base.lightened(0.10))
		elif wall_height > 1.0:
			draw_colored_polygon(PackedVector2Array([top_up, right_up, bot_up, left_up]),
				Color(0.18, 0.15, 0.12, 0.85))

		var wood := Color(0.64, 0.46, 0.25, 0.95)
		var sh: float = full_height + 5.0
		for corner in [top, right, bot, left]:
			draw_line(corner, corner + Vector2(0, -sh), wood, 1.3)
		for band in [0.45, 0.85]:
			var by: float = -full_height * band
			draw_line(top + Vector2(0, by), right + Vector2(0, by), wood, 1.0)
			draw_line(right + Vector2(0, by), bot + Vector2(0, by), wood, 1.0)
			draw_line(bot + Vector2(0, by), left + Vector2(0, by), wood, 1.0)
			draw_line(left + Vector2(0, by), top + Vector2(0, by), wood, 1.0)
		draw_line(left, top + Vector2(0, -full_height), wood.darkened(0.1), 0.9)

		draw_polyline(PackedVector2Array([top, right, bot, left, top]),
			Color.WHITE.darkened(0.4), 0.8)

		# ── Builder activity cue ───────────────────────────────────────────────
		# Little puffs of dust/sawdust drift up off the worksite so a site that's being worked
		# reads as ACTIVE (people on the job), not an abandoned shell.
		var dt: float = Time.get_ticks_msec() * 0.001
		var dust_base: Vector2 = left.lerp(bot, 0.5) + Vector2(2.0, 0.0)
		for di in range(2):
			var rise: float = fmod(dt * 9.0 + float(di) * 7.0, 14.0)
			var dsway: float = sin(dt * 2.2 + float(di) * 1.7) * 2.5
			var da: float = clampf(0.22 - rise / 90.0, 0.0, 0.22)
			draw_circle(dust_base + Vector2(dsway, -2.0 - rise), 2.0 + rise * 0.12,
				Color(0.74, 0.68, 0.56, da))

		# ── On-site progress bar + materials cue ───────────────────────────────
		# So a site reads as ACTIVELY building (not stalled): a green bar fills with the
		# labour done, and (if it needs hauling) the timber/stone delivered vs required.
		var bar_w: float = 42.0
		var bar_h: float = 8.0
		# Sit clear above the footprint even for FLAT field sites (orchards/farms), where
		# full_height is tiny — floor the lift so the bar never collapses onto the ground.
		var bar_c: Vector2 = center + Vector2(0.0, -maxf(full_height, 14.0) - 18.0)
		var bl: Vector2 = bar_c + Vector2(-bar_w * 0.5, 0.0)
		draw_rect(Rect2(bl - Vector2(1, 1), Vector2(bar_w + 2, bar_h + 2)), Color(0.04, 0.03, 0.02, 0.92))
		# Bright, high-contrast fill with a lighter top sheen so progress reads at a glance.
		draw_rect(Rect2(bl, Vector2(bar_w * prog, bar_h)), Color(0.46, 0.86, 0.30, 0.98))
		draw_rect(Rect2(bl, Vector2(bar_w * prog, bar_h * 0.45)), Color(0.70, 0.96, 0.50, 0.85))
		draw_rect(Rect2(bl, Vector2(bar_w, bar_h)), Color(0.0, 0.0, 0.0, 0.6), false, 1.0)
		var mtot: int = int(b.get("build_mat_total", 0))
		var ptxt: String = "%d%%" % int(prog * 100.0)
		if mtot > 0:
			# Show the actual delivered/needed resource by name (e.g. "8/8 timber"), never a
			# bare clipped "mat" — reads as a real supply line, not a typo.
			ptxt = "%d/%d %s" % [int(b.get("build_mat_delivered", 0)), mtot, _cost_word(btype)]
		# Dark plate behind the text so it stays legible over any terrain/scaffold.
		var ptp: Vector2 = bar_c + Vector2(-bar_w * 0.5, -3.0)
		var pfont := ThemeDB.fallback_font
		var psz: int = 9
		var pw: float = pfont.get_string_size(ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, psz).x
		draw_rect(Rect2(ptp.x - 2.0, ptp.y - psz - 1.0, pw + 4.0, psz + 4.0), Color(0.05, 0.04, 0.03, 0.72))
		draw_string(pfont, ptp + Vector2(1, 1), ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, psz, Color(0, 0, 0, 0.6))
		draw_string(pfont, ptp, ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, psz, Color(0.96, 0.98, 0.86))

	# ── Label ─────────────────────────────────────────────────────────────────
	var name_str: String = defn.get("name", btype).left(12)
	# Slight outline for legibility over varied terrain, then the label.
	var label_pos: Vector2 = center + Vector2(-22, -wall_height - ridge_h + 6)
	draw_string(ThemeDB.fallback_font, label_pos + Vector2(1, 1),
		name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0, 0.5))
	draw_string(ThemeDB.fallback_font, label_pos,
		name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

	# ── No-worker alert icon ───────────────────────────────────────────────────
	if max_w > 0 and int(b.get("workers", 0)) == 0 and b.get("is_active", true):
		draw_string(ThemeDB.fallback_font, center + Vector2(-5, -wall_height - ridge_h - 2),
			"!", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.65, 0.1, 0.9))

	# ── HP bar ────────────────────────────────────────────────────────────────
	var hp_ratio: float = vs.get("hp_bar", 1.0)
	if hp_ratio < 0.99:
		var bar_w: float = float(w) * HALF_W * 2.0
		var bar_x: float = center.x - bar_w * 0.5
		var bar_y: float = top_up.y - 6.0
		draw_rect(Rect2(bar_x, bar_y, bar_w, 4.0), Color(0.3, 0.1, 0.1))
		var hp_col: Color = (
			Color(0.1, 0.9, 0.2).lerp(Color(0.95, 0.85, 0.05), 1.0 - clampf(hp_ratio * 2.0 - 1.0, 0.0, 1.0))
			if hp_ratio > 0.5
			else Color(0.95, 0.85, 0.05).lerp(Color(0.95, 0.15, 0.1), 1.0 - clampf(hp_ratio * 2.0, 0.0, 1.0))
		)
		draw_rect(Rect2(bar_x, bar_y, bar_w * hp_ratio, 4.0), hp_col)

	# ── Fire indicator (animated flicker + rising smoke) ─────────────────────
	# Made bold + smoky (iter304): fire is the ONLY thing that drains a building's HP with no attacker
	# on the field, so a burning building MUST read unmistakably as fire — not an "invisible attack".
	if vs.get("show_fire", false):
		var t: float       = Time.get_ticks_msec() * 0.001
		var f1: float      = 0.70 + 0.30 * sin(t * 7.3)
		var f2: float      = 0.80 + 0.20 * sin(t * 11.7 + 1.2)
		# Engulf the WHOLE building, anchored at its base, so a blaze reads unmistakably as a
		# building on fire (not a small torch on the roof) — visible even at play zoom.
		var base_c: Vector2 = center + Vector2(0, wall_height * 0.10)
		var span: float = maxf(14.0, abs(right.x - left.x) * 0.55)   # roughly the building's footprint width
		# Warm ground glow licking the base.
		draw_circle(base_c, span * 1.15, Color(1.0, 0.35, 0.05, 0.20))
		# Rising smoke column — bigger, darker, taller; the long-range tell.
		for i in range(5):
			var rise: float = fmod(t * 20.0 + float(i) * 11.0, 46.0)
			var sway: float = sin(t * 2.0 + float(i)) * 6.0
			var puff_a: float = clampf(0.40 - rise / 110.0, 0.0, 0.40)
			draw_circle(base_c + Vector2(sway, -wall_height * 0.7 - rise), 6.0 + rise * 0.30, Color(0.16, 0.14, 0.13, puff_a))
		# A row of flame tongues climbing the building face — several across the width so the
		# whole structure looks ablaze, each a stacked deep-red → orange → yellow → white-hot core.
		var tongues: int = maxi(3, int(span / 7.0))
		for k in range(tongues):
			var fx: float = lerpf(-span * 0.8, span * 0.8, float(k) / float(maxi(1, tongues - 1)))
			var ph: float = t * 9.0 + float(k) * 1.7
			var lick: float = 0.75 + 0.25 * sin(ph)
			var fc: Vector2 = base_c + Vector2(fx, 0)
			var hgt: float = wall_height * (0.55 + 0.30 * lick)
			draw_circle(fc, 7.5 * f1, Color(0.85, 0.12, 0.0, 0.50))                                  # deep red base
			draw_circle(fc + Vector2(sin(ph) * 2.0, -hgt * 0.30), 6.0 * f2, Color(1.0, 0.40, 0.0, 0.92))    # orange
			draw_circle(fc + Vector2(sin(ph * 1.5) * 2.0, -hgt * 0.62), 4.2 * f2, Color(1.0, 0.75, 0.10, 0.95)) # yellow
			draw_circle(fc + Vector2(sin(ph * 2.1) * 1.4, -hgt * 0.92), 2.4 * f1, Color(1.0, 1.0, 0.72, 0.95)) # white-hot tip

# Natural material palette (wall / roof / trim) per building, so structures read
# like the trees and rocks rather than flat category swatches.
func _materials(cat: int, btype: String, is_enemy: bool, fac_key: int = 0) -> Dictionary:
	if is_enemy:
		# Clearly-SOLID enemy stone-and-timber (lightened up from the old muddy near-black, which
		# read as a translucent ghost), with a per-faction roof/trim hue so rival houses look
		# distinct from each other — yet all stay recognisably "not the player" via the warm walls.
		var hue: float = float(int(abs(fac_key)) % 6) / 6.0   # 0..1 around the wheel, deterministic
		var roof := Color.from_hsv(fmod(0.02 + hue * 0.92, 1.0), 0.46, 0.52)
		var trim := Color.from_hsv(fmod(0.02 + hue * 0.92, 1.0), 0.40, 0.34)
		return {"wall": Color(0.70, 0.58, 0.50), "roof": roof, "trim": trim}
	match btype:
		"village_hall":
			return {"wall": Color(0.82, 0.77, 0.66), "roof": Color(0.74, 0.34, 0.24), "trim": Color(0.45, 0.32, 0.20)}
		"keep", "castle":
			return {"wall": Color(0.70, 0.69, 0.66), "roof": Color(0.40, 0.42, 0.50), "trim": Color(0.34, 0.33, 0.32)}
		"church", "cathedral":
			return {"wall": Color(0.84, 0.80, 0.72), "roof": Color(0.46, 0.48, 0.56), "trim": Color(0.50, 0.40, 0.26)}
		"well":
			return {"wall": Color(0.66, 0.64, 0.60), "roof": Color(0.50, 0.38, 0.24), "trim": Color(0.34, 0.30, 0.26)}
	match cat:
		0: return {"wall": Color(0.80, 0.76, 0.66), "roof": Color(0.72, 0.36, 0.26), "trim": Color(0.45, 0.32, 0.20)}  # CIVIC — stone + tile
		1: return {"wall": Color(0.58, 0.43, 0.28), "roof": Color(0.46, 0.37, 0.22), "trim": Color(0.34, 0.24, 0.14)}  # HARVEST — timber + thatch
		2: return {"wall": Color(0.80, 0.68, 0.48), "roof": Color(0.84, 0.69, 0.34), "trim": Color(0.46, 0.34, 0.20)}  # FOOD — wattle + golden thatch
		3: return {"wall": Color(0.50, 0.38, 0.30), "roof": Color(0.42, 0.44, 0.50), "trim": Color(0.30, 0.22, 0.16)}  # MILITARY — dark timber + slate
		4: return {"wall": Color(0.66, 0.64, 0.60), "roof": Color(0.52, 0.52, 0.55), "trim": Color(0.40, 0.39, 0.37)}  # DEFENSE — stone
	return {"wall": Color(0.72, 0.70, 0.64), "roof": Color(0.55, 0.45, 0.35), "trim": Color(0.40, 0.30, 0.20)}

# Human-readable name for the PRIMARY material a building is hauled together from, read off its
# BuildingRegistry cost dict — so the on-site supply line says "8 timber" / "stone" rather than the
# clipped "mat". Picks the largest-quantity resource; "materials" only when several are tied/mixed.
const _RES_WORDS := {"wood": "timber", "stone": "stone", "gold": "gold", "iron": "iron"}
func _cost_word(btype: String) -> String:
	var cost: Dictionary = BuildingRegistry.lookup(btype).get("cost", {})
	var best: String = ""
	var best_amt: int = -1
	var second_amt: int = -1
	for k in cost.keys():
		var amt: int = int(cost[k])
		if amt > best_amt:
			second_amt = best_amt
			best_amt = amt
			best = str(k)
		elif amt > second_amt:
			second_amt = amt
	if best == "":
		return "materials"
	# If two resources are needed in comparable amounts, it's a mixed haul.
	if second_amt > 0 and second_amt >= best_amt:
		return "materials"
	return _RES_WORDS.get(best, "materials")

# A door on the front-right face and a couple of lit windows on the front-left face.
func _draw_wall_details(top: Vector2, right: Vector2, left: Vector2, wall_height: float, trim: Color) -> void:
	var edir: Vector2 = right - top
	if edir.length() > 0.001:
		edir = edir.normalized()
		var door_base: Vector2 = top.lerp(right, 0.5)
		var dh: float = minf(wall_height * 0.70, 14.0)
		var dw: float = 3.2
		var dark := Color(0.16, 0.10, 0.06)
		draw_colored_polygon(PackedVector2Array([
			door_base - edir * dw, door_base + edir * dw,
			door_base + edir * dw + Vector2(0, -dh), door_base - edir * dw + Vector2(0, -dh),
		]), dark)
		draw_circle(door_base + Vector2(0, -dh), dw, dark)  # arched lintel
	if wall_height > 12.0:
		var lit := Color(0.98, 0.85, 0.45)
		for fwin in [0.32, 0.68]:
			var wc: Vector2 = left.lerp(top, fwin) + Vector2(0, -wall_height * 0.55)
			draw_rect(Rect2(wc.x - 1.9, wc.y - 2.2, 3.8, 4.4), lit)
			draw_line(Vector2(wc.x, wc.y - 2.2), Vector2(wc.x, wc.y + 2.2), trim, 0.6)

# Distinctive per-building-type features drawn on top of the base massing, so
# each building type reads at a glance (church cross, keep flag, farm furrows…).
func _draw_building_topper(btype: String, cat: int, w: int, h: int, base_color: Color,
		top: Vector2, right: Vector2, bot: Vector2, left: Vector2,
		top_up: Vector2, right_up: Vector2, bot_up: Vector2, left_up: Vector2,
		ridge_apex: Vector2, center: Vector2) -> void:
	match btype:
		"church", "cathedral":
			var c: Vector2 = ridge_apex + Vector2(0, -4.0)
			draw_line(c, c + Vector2(0, -13.0), Color(0.96, 0.92, 0.62), 2.0)
			draw_line(c + Vector2(-4.0, -8.0), c + Vector2(4.0, -8.0), Color(0.96, 0.92, 0.62), 2.0)
		"village_hall", "keep":
			var ph: float = 17.0 if btype == "keep" else 12.0
			draw_line(ridge_apex, ridge_apex + Vector2(0, -ph), Color(0.42, 0.32, 0.20), 1.5)
			var fb: Vector2 = ridge_apex + Vector2(0, -ph)
			draw_colored_polygon(PackedVector2Array([fb, fb + Vector2(13.0, 4.0), fb + Vector2(0, 8.0)]),
				Color(0.78, 0.18, 0.18))
		"barracks", "siege_workshop":
			var bn: Vector2 = (top_up + right_up) * 0.5
			draw_rect(Rect2(bn.x - 3.0, bn.y - 2.0, 6.0, 14.0), Color(0.70, 0.18, 0.18))
			draw_colored_polygon(PackedVector2Array([
				Vector2(bn.x - 3.0, bn.y + 12.0), Vector2(bn.x + 3.0, bn.y + 12.0), Vector2(bn.x, bn.y + 16.0),
			]), Color(0.70, 0.18, 0.18))
		"granary", "stockpile":
			draw_circle(ridge_apex + Vector2(0, 2.0), 6.0, base_color.lightened(0.25))
			draw_arc(ridge_apex + Vector2(0, 2.0), 6.0, PI, TAU, 8, Color(0, 0, 0, 0.3), 1.0)
		"well":
			draw_circle(center, 5.0, Color(0.10, 0.20, 0.32))
			draw_arc(center + Vector2(0, -8.0), 7.0, PI, TAU, 8, Color(0.42, 0.32, 0.20), 2.0)
		"market", "trading_post":
			for i in range(4):
				var a: Vector2 = left_up.lerp(bot_up, float(i) / 4.0)
				var b: Vector2 = left_up.lerp(bot_up, float(i + 1) / 4.0)
				var col: Color = Color(0.86, 0.82, 0.76) if i % 2 == 0 else Color(0.76, 0.26, 0.20)
				draw_colored_polygon(PackedVector2Array([a, b, b + Vector2(0, 5.0), a + Vector2(0, 5.0)]), col)
		"apple_orchard", "wheat_farm", "hops_farm", "pig_farm", "dairy_farm", "mill", "bakery", "brewery", "inn":
			for i in range(1, 4):
				var t: float = float(i) / 4.0
				draw_line(top_up.lerp(left_up, t), right_up.lerp(bot_up, t), base_color.darkened(0.22), 0.8)
		_:
			if cat == 4 or cat == 3:  # walls / towers / military — crenellation merlons
				var steps: int = mini(4, w + h + 1)
				for i in range(steps):
					var mp: Vector2 = left_up.lerp(bot_up, (float(i) + 0.5) / float(steps))
					draw_rect(Rect2(mp.x - 3.0, mp.y - 5.0, 6.0, 5.0), base_color.lightened(0.3))
			elif cat == 1:  # harvesting — a small chimney/marker
				draw_rect(Rect2(ridge_apex.x - 2.0, ridge_apex.y - 6.0, 4.0, 8.0), Color(0.30, 0.25, 0.20))

# A stockpile is a blank plank platform; GOODS PILES sit on it in proportion to the realm's
# stored raw stock (none when empty, filling up as stock arrives, gone when it's drawn down).
# The founding ("initial") stockpile is built taller/bigger with a banner so it reads as the
# primary store the AI delivers to.
func _draw_stockpile(b: Dictionary, is_enemy: bool, top: Vector2, right: Vector2, bot: Vector2, left: Vector2) -> void:
	var initial: bool = b.get("initial", false)
	var deck_h: float = 9.0 if initial else 5.0
	var deck: Color = Color(0.50, 0.40, 0.26) if not is_enemy else Color(0.46, 0.32, 0.30)
	var c: PackedVector2Array = BuildingModels._box(self, top, right, bot, left, deck_h, deck, BuildingModels.TEX_PLANK)
	var tu: Vector2 = c[0]; var ru: Vector2 = c[1]; var bu: Vector2 = c[2]; var lu: Vector2 = c[3]
	if initial:
		# corner banner post marking the primary store
		draw_line(lu, lu + Vector2(0, -15), Color(0.40, 0.30, 0.18), 2.0)
		draw_colored_polygon(PackedVector2Array([lu + Vector2(0, -15), lu + Vector2(9, -12), lu + Vector2(0, -9)]), Color(0.70, 0.20, 0.18))
	# Fill ratio from the realm's shared raw-goods pool.
	var ratio: float = 0.0
	if not is_enemy and GameState.players.size() > 0:
		var p: Dictionary = GameState.players[0]
		ratio = clampf(float(StorageSystem.get_stored(p)) / maxf(1.0, float(StorageSystem.get_capacity(p))), 0.0, 1.0)
	var uv: Array = [Vector2(0.3,0.3), Vector2(0.7,0.3), Vector2(0.3,0.7), Vector2(0.7,0.7),
		Vector2(0.5,0.5), Vector2(0.5,0.28), Vector2(0.28,0.5), Vector2(0.72,0.5), Vector2(0.5,0.72)]
	var slots: int = uv.size() if initial else 6
	var n: int = mini(int(round(ratio * float(slots))), slots)
	var goods: Array = [Color(0.60,0.45,0.25), Color(0.64,0.62,0.56), Color(0.72,0.60,0.36)]  # wood / stone / sacks
	for i in range(n):
		var sp: Vector2 = _bilerp(tu, ru, bu, lu, uv[i].x, uv[i].y)
		var s: float = 1.3 if initial else 1.0
		var col: Color = goods[i % goods.size()]
		draw_colored_polygon(PackedVector2Array([sp+Vector2(-5*s,1*s), sp+Vector2(5*s,1*s), sp+Vector2(3*s,-4*s), sp+Vector2(-3*s,-4*s)]), col)
		draw_colored_polygon(PackedVector2Array([sp+Vector2(-3*s,-4*s), sp+Vector2(3*s,-4*s), sp+Vector2(0,-7*s)]), col.lightened(0.12))

func _bilerp(tu: Vector2, ru: Vector2, bu: Vector2, lu: Vector2, u: float, v: float) -> Vector2:
	return tu*(1.0-u)*(1.0-v) + ru*u*(1.0-v) + bu*u*v + lu*(1.0-u)*v

# Draw a plank deck spanning the bridge's deck cells (anchor→…→anchor). Direction is read
# off the points themselves, so it works for the live preview and the placed bridge alike.
func _bridge_span(deck: Array, deck_col: Color, rail_col: Color, seam_col: Color) -> void:
	if deck.is_empty():
		return
	var pts := PackedVector2Array()
	for c in deck:
		pts.append(Vector2((int(c[0]) - int(c[1])) * HALF_W, (int(c[0]) + int(c[1])) * HALF_H))
	if pts.size() == 1:
		var p: Vector2 = pts[0]
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -HALF_H), p + Vector2(HALF_W, 0),
			p + Vector2(0, HALF_H), p + Vector2(-HALF_W, 0)]), deck_col)
		return
	var sdir: Vector2 = (pts[pts.size() - 1] - pts[0]).normalized()
	var perp := Vector2(-sdir.y, sdir.x)
	var hw: float = 15.0
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for p in pts:
		left.append(p - perp * hw)
		right.append(p + perp * hw)
	# Deck ribbon (left edge forward, right edge back) — a straight bridge stays convex.
	var poly := PackedVector2Array()
	for p in left:
		poly.append(p)
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	draw_colored_polygon(poly, deck_col)
	# Cross-plank seams and side rails.
	for i in range(pts.size()):
		draw_line(pts[i] - perp * hw, pts[i] + perp * hw, seam_col, 1.5)
	draw_polyline(left, rail_col, 2.0)
	draw_polyline(right, rail_col, 2.0)

func _draw_ghost() -> void:
	# Steady, clean translucency (no pulsing) — reads as a placement preview, not an editor gizmo.
	var tint: Color  = Color(0.40, 1.0, 0.45) if _ghost_valid else Color(1.0, 0.32, 0.32)

	# Bridge preview: the full computed span, green when it reaches the far bank, red when not.
	if _ghost_type == "bridge":
		var deck_c := Color(tint.r, tint.g, tint.b, 0.45)
		var rail_c := Color(tint.r * 0.7, tint.g * 0.7, tint.b * 0.7, 0.85)
		_bridge_span(_ghost_bridge, deck_c, rail_c, rail_c)
		return

	var defn: Dictionary  = BuildingRegistry.lookup(_ghost_type)
	var w: int            = defn.get("width",  1)
	var h: int            = defn.get("height", 1)
	var cat: int          = defn.get("category", 0)
	var base: Color       = CAT_COLORS[mini(cat, CAT_COLORS.size() - 1)]
	var gc: Color         = base.lerp(tint, 0.55)

	var cx: float  = (_ghost_gx - _ghost_gy) * HALF_W
	var cy: float  = (_ghost_gx + _ghost_gy) * HALF_H

	var top:   Vector2 = Vector2(cx,                    cy - HALF_H)
	var right: Vector2 = Vector2(cx + w * HALF_W,       cy + (w - 1) * HALF_H)
	var bot:   Vector2 = Vector2(cx + (w - h) * HALF_W, cy + (w + h - 1) * HALF_H)
	var left:  Vector2 = Vector2(cx - h * HALF_W,       cy + (h - 1) * HALF_H)
	var wall_h: float  = 18.0 + (w + h) * 4.0
	var top_up:   Vector2 = top   + Vector2(0, -wall_h)
	var right_up: Vector2 = right + Vector2(0, -wall_h)
	var bot_up:   Vector2 = bot   + Vector2(0, -wall_h)
	var left_up:  Vector2 = left  + Vector2(0, -wall_h)

	# Field types (orchard/farm) preview as a flat planted plot with neat row marks instead of
	# a tall box (they have no real walls).
	var is_field: bool = BuildingRegistry.is_field(_ghost_type)
	if is_field:
		draw_colored_polygon(PackedVector2Array([top, right, bot, left]),
			Color(gc.r, gc.g, gc.b, 0.30))
		for i in range(1, 4):
			var f: float = float(i) / 4.0
			draw_line(top.lerp(left, f), right.lerp(bot, f),
				Color(tint.r, tint.g, tint.b, 0.45), 1.0)
		draw_polyline(PackedVector2Array([top, right, bot, left, top]),
			Color(tint.r, tint.g, tint.b, 0.85), 1.4)
	else:
		# Floor
		draw_colored_polygon(PackedVector2Array([top, right, bot, left]),
			Color(gc.r, gc.g, gc.b, 0.28))
		# Left wall
		draw_colored_polygon(PackedVector2Array([left, top, top_up, left_up]),
			Color(gc.r * 0.70, gc.g * 0.70, gc.b * 0.70, 0.40))
		# Right wall
		draw_colored_polygon(PackedVector2Array([top, right, right_up, top_up]),
			Color(gc.r * 0.85, gc.g * 0.85, gc.b * 0.85, 0.40))
		# Roof
		draw_colored_polygon(PackedVector2Array([top_up, right_up, bot_up, left_up]),
			Color(gc.r, gc.g, gc.b, 0.46))
		# Outline edges
		var ol := Color(tint.r, tint.g, tint.b, 0.85)
		draw_polyline(PackedVector2Array([top, right, bot, left, top]), ol, 1.5)
		draw_polyline(PackedVector2Array([top_up, right_up, bot_up, left_up, top_up]), ol, 1.0)
		draw_polyline(PackedVector2Array([left, left_up]), ol, 0.8)
		draw_polyline(PackedVector2Array([top, top_up]),   ol, 0.8)
		draw_polyline(PackedVector2Array([right, right_up]), ol, 0.8)

	# Upright, readable name label above the footprint, on a small dark plate.
	var nm: String = defn.get("name", _ghost_type)
	var lift: float = 8.0 if is_field else wall_h + 8.0
	var lc: Vector2 = (top + bot) * 0.5 + Vector2(0, -lift)
	var font := ThemeDB.fallback_font
	var fs: int = 11
	var tw: float = font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var lp: Vector2 = lc + Vector2(-tw * 0.5, -2.0)
	draw_rect(Rect2(lp.x - 3.0, lp.y - fs - 1.0, tw + 6.0, fs + 5.0), Color(0.04, 0.03, 0.02, 0.70))
	draw_string(font, lp + Vector2(1, 1), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
	draw_string(font, lp, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(0.75, 1.0, 0.78) if _ghost_valid else Color(1.0, 0.74, 0.74))
