extends Node2D
# Renders & animates the living people of a settlement from GameState.citizens.
#
# Every figure is an ARTICULATED little person: two-segment arms and legs that bend
# at elbow and knee, a shaded torso, neck, hands, feet, a head with hair and a hint
# of a face. Motion is physical, not a flip-book:
#   • Walk  — opposite-phase limbs, weight bob, a lean into travel and lifting feet,
#             with stride length & cadence scaled by actual speed.
#   • Idle  — varied per-person behaviours (weight-shift, breathing, looking about,
#             the occasional stretch) so a standing crowd never freezes in lockstep.
#   • Work  — the tool reaches to the ACTUAL thing being worked (the tree it fells,
#             the anvil/building it strikes, the fruit it picks) and throws impact
#             effects — wood chips, sparks, dust, falling fruit, grain — on each blow.
#
# All effects live in a small transient particle list ticked in _process (so _draw
# stays a pure function of state).

const WorkerJobs = preload("res://simulation/world/WorkerJobs.gd")
const PeopleSystem = preload("res://simulation/world/PeopleSystem.gd")
const SeasonSystem = preload("res://simulation/world/SeasonSystem.gd")

const HALF_W: float = 32.0
const HALF_H: float = 16.0

const SKIN  := Color(0.86, 0.70, 0.55)   # fallback for profile-less pawns
const STEEL := Color(0.74, 0.77, 0.82)
const STEEL_DK := Color(0.42, 0.45, 0.52)
const WOOD  := Color(0.45, 0.30, 0.16)
const WOOD_DK := Color(0.30, 0.20, 0.10)
const OUTLINE := Color(0.12, 0.09, 0.07, 0.38)
# Muted, period-appropriate peasant tunic palette — browns, tans, ochre, dull green/blue,
# faded rust, grey. Indexed per-citizen by id so a village reads as varied folk, not a
# uniform cohort (mirrors the iter175 building-roof diversification, for people).
const PEASANT_TUNICS: Array = [
	Color(0.45, 0.34, 0.22), Color(0.38, 0.30, 0.20), Color(0.60, 0.50, 0.32),
	Color(0.36, 0.42, 0.26), Color(0.31, 0.40, 0.34), Color(0.56, 0.34, 0.28),
	Color(0.36, 0.42, 0.52), Color(0.47, 0.45, 0.42), Color(0.52, 0.41, 0.25),
	Color(0.42, 0.32, 0.30),
]

# People are drawn a little smaller than buildings so the architecture reads at a realistic
# scale. Nudged up (0.82 → 0.92) once buildings became large hand-painted sprites: at the old
# size the villagers felt lost against them; +12% gives them presence while still reading as
# clearly smaller than the buildings. (Detail on the figures doesn't pay off at play zoom —
# they're ~16px — so PRESENCE, not detail, is the lever here. Tune via _PawnShowcase.tscn.)
const PAWN_SCALE: float = 0.92

# ── Transient impact effects ─────────────────────────────────────────────────
# Each: {pos:Vector2, vel:Vector2, life:float, max:float, col:Color, r:float, grav:float, kind:String}
var _fx: Array = []
# Per-worker strike bookkeeping so we spawn one burst per swing, not per frame.
var _strike_cycle: Dictionary = {}     # citizen id -> last completed swing cycle

const SfxGen = preload("res://simulation/audio/SfxGen.gd")
const SFX_POOL: int = 14
var _sfx_pool: Array = []           # reusable AudioStreamPlayer2D for positional strikes
var _sfx_streams: Dictionary = {}   # name -> AudioStream (synthesised once)
var _sfx_next: int = 0

# Night readability: cached once per _draw() so every pawn agrees on the same darkness.
# 0 by day → 1 at deep night; drives a faint cool rim/halo so silhouettes stay readable.
var _night: float = 0.0

# Animation clock — advances with REAL time but SCALED by the game speed, so when the
# player runs at 2×/5× the people (and their tool strikes + chop/hammer sounds) speed up
# to match the faster world, and freeze when paused. Accumulated so speed changes glide.
var _anim_time: float = 0.0

func _speed_mult() -> float:
	return float(SimulationClock.SPEED_MULTIPLIERS.get(SimulationClock.game_speed, 1.0))

# ── Performance: viewport culling + level-of-detail ───────────────────────────
# The articulated figure costs dozens of draw primitives per pawn EVERY frame, and a
# living world has hundreds of people (every AI town included). Two savers:
#   • Cull — only pawns whose feet fall inside the visible screen rect are drawn (or
#     scanned for tool-strikes). Most of the roster is off-screen at play zoom.
#   • LOD  — below LOD_ZOOM, OR when more than CROWD_LIMIT pawns are visible, the figures
#     are sub-detail / an illegible mass, so each is drawn as ONE batched MultiMesh glyph
#     (a tunic-tinted little figure) instead of ~80 draw calls. A few draw calls for the
#     whole crowd → thousands of villagers stay smooth. Camera injected via set_camera().
const LOD_ZOOM: float = 0.5
const CROWD_LIMIT: int = 60
var _camera: Camera2D = null
var _lod_active: bool = false   # last frame's detail decision (zoom or crowd); gates strike FX

const CrowdGlyphs = preload("res://view/micro/CrowdGlyphs.gd")
# Batched villager: a two-layer little person — a tunic-coloured BODY (white mesh tinted per
# instance by the pawn's tunic) and a skin HEAD (skin baked in, pushed white). Two draw calls
# for the whole visible crowd, but it reads as a person, not a flat shape.
const SKIN_GLYPH := Color(0.84, 0.68, 0.53)
var _crowd: CrowdGlyphs = null

func set_camera(cam: Camera2D) -> void:
	_camera = cam

# This node's LOCAL-space rectangle currently on screen, grown by `margin` px so a
# figure straddling the edge isn't popped. Derived from the live canvas transform, so
# it's correct under any camera pan/zoom and node nesting.
func _visible_rect(margin: float) -> Rect2:
	var inv := get_global_transform_with_canvas().affine_inverse()
	var vp: Vector2 = get_viewport_rect().size
	var p0 := inv * Vector2(0, 0)
	var p1 := inv * Vector2(vp.x, 0)
	var p2 := inv * Vector2(0, vp.y)
	var p3 := inv * Vector2(vp.x, vp.y)
	var minx: float = minf(minf(p0.x, p1.x), minf(p2.x, p3.x)) - margin
	var maxx: float = maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x)) + margin
	var miny: float = minf(minf(p0.y, p1.y), minf(p2.y, p3.y)) - margin
	var maxy: float = maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y)) + margin
	return Rect2(minx, miny, maxx - minx, maxy - miny)

func _ready() -> void:
	# A pool of POSITIONAL players: each strike plays from its world spot, so the yard
	# becomes a 3D-ish soundscape — chops pan left/right and fade with distance/zoom off
	# the active camera, and many tools at once layer naturally.
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	for i in range(SFX_POOL):
		var p := AudioStreamPlayer2D.new()
		p.bus = bus
		p.max_distance = 800.0      # tighter earshot — only nearby work is heard
		p.attenuation = 1.8
		p.panning_strength = 1.5
		add_child(p)
		_sfx_pool.append(p)
	_crowd = CrowdGlyphs.new()
	_crowd.setup(self, {
		"body": CrowdGlyphs.poly_mesh(PackedVector2Array([
			Vector2(-2.1,-11), Vector2(2.1,-11), Vector2(2.0,-1),
			Vector2(0,0.4), Vector2(-2.0,-1)])),                          # white → tinted by tunic
		"head": CrowdGlyphs.poly_mesh(CrowdGlyphs.ellipse_poly(2.0, 2.2, Vector2(0,-13.4), 7), SKIN_GLYPH),
	})

# Play a synthesised effect AT a world position through the next free pooled 2D player.
func _play_at(stream_name: String, world_pos: Vector2, gain_db: float) -> void:
	if _sfx_pool.is_empty():
		return
	if not _sfx_streams.has(stream_name):
		_sfx_streams[stream_name] = SfxGen.for_event(stream_name)
	# Prefer a free (not-playing) player; else round-robin steal the oldest.
	var pick: AudioStreamPlayer2D = null
	for p in _sfx_pool:
		if not p.playing:
			pick = p
			break
	if pick == null:
		pick = _sfx_pool[_sfx_next]
		_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	pick.stream = _sfx_streams[stream_name]
	pick.global_position = world_pos
	pick.volume_db = gain_db
	pick.pitch_scale = randf_range(0.94, 1.07)   # slight variance so repeats don't sound canned
	pick.play()

func _process(delta: float) -> void:
	_anim_time += delta * _speed_mult()
	_tick_strikes()
	_tick_fx(delta)
	queue_redraw()

func _to_screen(tx: float, ty: float) -> Vector2:
	return Vector2((tx - ty) * HALF_W, (tx + ty) * HALF_H)

# ── Effects: spawn on strike, advance, draw ──────────────────────────────────

# Watch every working pawn's swing and emit an impact burst once per cycle, at the
# point its tool meets the work (the real node/building, projected to screen).
func _tick_strikes() -> void:
	# Tool swings aren't drawn at LOD (zoomed out OR a big crowd), so don't scan/emit them
	# either — this drops the per-frame whole-roster strike scan entirely in those cases.
	if _lod_active or (_camera != null and _camera.zoom.x < LOD_ZOOM):
		if not _strike_cycle.is_empty():
			_strike_cycle.clear()
		return
	var now: float = _anim_time
	var live: Dictionary = {}
	# A touch wider than the draw cull so a chop just off the edge still chips/sounds.
	var vis := _visible_rect(60.0)
	for c in GameState.citizens:
		if not (c is Dictionary and c.get("is_alive", false)):
			continue
		if not vis.has_point(_to_screen(c["x"], c["y"])):
			continue
		var cid: int = int(c.get("id", 0))
		var info := _strike_info(c)     # {"anim":..., "freq":...} or {}
		if info.is_empty():
			continue
		var anim: String = info["anim"]
		var freq: float = info["freq"]
		var tw: float = now + float(cid) * 0.6
		var cyc: int = int(floor(tw * freq / TAU))
		live[cid] = true
		if not _strike_cycle.has(cid):
			_strike_cycle[cid] = cyc
		elif _strike_cycle[cid] != cyc:
			_strike_cycle[cid] = cyc
			_spawn_impact(c, anim)
			_play_strike_sound(c, anim)
	# Forget pawns no longer striking so a later cycle re-arms cleanly.
	for k in _strike_cycle.keys():
		if not live.has(k):
			_strike_cycle.erase(k)

# The strike anim + swing frequency for a pawn actively working a tool, or {} if it
# isn't striking. Covers job workers (chop/mine/hammer/…) AND builders hammering a site.
func _strike_info(c: Dictionary) -> Dictionary:
	if c.get("role", "") == "worker":
		var phase: String = c.get("work_phase", "")
		var hauling: bool = phase == "haul_in" or phase == "haul_out"
		var vmoving: bool = absf(c.get("vx", 0.0)) + absf(c.get("vy", 0.0)) > 0.002
		if c.get("state", "") != "work" or hauling or vmoving:
			return {}
		var anim: String = String(c.get("work_anim", ""))
		var f: float = _strike_freq(anim)
		return {"anim": anim, "freq": f} if f > 0.0 else {}
	# Builders hammering a construction site (matches the 9.0 swing in _draw_citizen).
	if c.get("state", "") == "build":
		return {"anim": "build", "freq": 9.0}
	return {}

# Positional strike sound, played from the pawn's impact point so it pans/attenuates.
func _play_strike_sound(c: Dictionary, anim: String) -> void:
	var at := _impact_point(c)
	match anim:
		"chop":   _play_at("WOOD_CHOP", at, -8.0)
		"hammer": _play_at("HAMMER_HIT", at, -11.0)   # smith / wright at the anvil
		"build":  _play_at("HAMMER_HIT", at, -8.0)    # builder raising a structure

func _strike_freq(anim: String) -> float:
	match anim:
		"chop":   return 7.0
		"mine":   return 6.0
		"hammer": return 8.0
		"scythe": return 4.0
		"pick":   return 4.5
		"build":  return 9.0
	return 0.0

# Where the strike lands, in screen space: the actual worked object (act_x/act_y),
# nudged toward the pawn so chips fly off the contact face rather than the tile centre.
func _impact_point(c: Dictionary) -> Vector2:
	var feet := _to_screen(c["x"], c["y"])
	if c.has("act_x"):
		var tgt := _to_screen(c["act_x"], c["act_y"])
		var d := tgt - feet
		if d.length() > 1.0:
			# Contact a touch short of the object centre, lifted to working height.
			return feet + d.normalized() * minf(d.length(), 14.0) + Vector2(0, -9.0)
	var face: float = c.get("facing", 1.0)
	return feet + Vector2(face * 10.0, -9.0)

func _spawn_impact(c: Dictionary, anim: String) -> void:
	var p := _impact_point(c)
	var face: float = c.get("facing", 1.0)
	match anim:
		"chop":   # pale wood chips spraying + a couple of dark splinters (sound: WOOD_CHOP)
			for i in range(5):
				_emit(p, Vector2(face * randf_range(0.5, 2.6), randf_range(-2.4, -0.4)),
					randf_range(0.30, 0.55), Color(0.80, 0.64, 0.40).lerp(WOOD, randf()), randf_range(0.7, 1.3), 9.0, "chip")
		"build":  # builder's hammer on timber — sawdust puff + a flying offcut (sound: HAMMER_HIT)
			for i in range(4):
				_emit(p, Vector2(face * randf_range(0.3, 1.8), randf_range(-1.8, -0.2)),
					randf_range(0.25, 0.5), Color(0.78, 0.66, 0.46), randf_range(0.6, 1.1), 5.0, "dust")
			_emit(p, Vector2(face * randf_range(0.8, 2.0), randf_range(-1.6, -0.4)),
				0.4, WOOD.lightened(0.2), 1.0, 9.0, "chip")
		"mine":   # grey rock dust + a few sparks where steel bites stone
			for i in range(6):
				_emit(p, Vector2(randf_range(-1.6, 1.6), randf_range(-2.2, -0.2)),
					randf_range(0.25, 0.5), Color(0.62, 0.60, 0.58), randf_range(0.6, 1.2), 7.0, "dust")
			for i in range(2):
				_emit(p, Vector2(face * randf_range(0.4, 1.8), randf_range(-1.4, 0.2)),
					randf_range(0.12, 0.22), Color(1.0, 0.82, 0.4), 0.7, 0.0, "spark")
		"hammer": # bright forge sparks arcing off the work
			var hot: bool = WorkerJobs.style(c.get("job_type", "")).get("sparks", false)
			var n: int = 7 if hot else 3
			for i in range(n):
				_emit(p, Vector2(face * randf_range(0.6, 3.0), randf_range(-2.0, 0.4)),
					randf_range(0.18, 0.4), Color(1.0, randf_range(0.7, 0.92), 0.35), randf_range(0.6, 1.0), 3.0, "spark")
		"scythe": # straw / wheat fluff puffing up
			for i in range(5):
				_emit(p, Vector2(face * randf_range(0.3, 1.8), randf_range(-1.6, -0.2)),
					randf_range(0.4, 0.7), Color(0.85, 0.74, 0.42), randf_range(0.8, 1.4), 2.5, "leaf")
		"pick":   # a picked fruit drops to the basket
			_emit(p, Vector2(randf_range(-0.4, 0.4), randf_range(-0.6, 0.2)),
				0.6, Color(0.82, 0.22, 0.18), 1.4, 11.0, "fruit")

func _emit(pos: Vector2, vel: Vector2, life: float, col: Color, r: float, grav: float, kind: String) -> void:
	if _fx.size() > 260:
		return
	_fx.append({"pos": pos, "vel": vel, "life": life, "max": life, "col": col, "r": r, "grav": grav, "kind": kind})

func _tick_fx(delta: float) -> void:
	var dt: float = minf(delta, 0.05) * 60.0   # advance in frame-units, clamp hitches
	var keep: Array = []
	for e in _fx:
		var life: float = float(e["life"]) - delta
		if life <= 0.0:
			continue
		var v: Vector2 = e["vel"]
		v.y += float(e["grav"]) * 0.02 * dt
		e["vel"] = v
		e["pos"] = Vector2(e["pos"]) + v * dt
		e["life"] = life
		keep.append(e)
	_fx = keep

func _draw_fx() -> void:
	for e in _fx:
		var a: float = clampf(e.life / maxf(e.max, 0.001), 0.0, 1.0)
		var col: Color = e.col
		col.a *= a
		if e.kind == "spark":
			draw_line(e.pos, e.pos - e.vel * 0.9, col, maxf(0.7, e.r * 0.8))
		else:
			draw_circle(e.pos, e.r * (0.5 + 0.5 * a), col)

# ── Per-person look ───────────────────────────────────────────────────────────

# A stable pseudo-random value in [-1, 1] for a citizen id + salt. Deterministic every
# frame (no RNG state), so each pawn's variation is fixed for its whole life.
func _id_rand(cid: int, salt: int) -> float:
	var h: int = (cid * 73856093) ^ (salt * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return float(((h % 2000) + 2000) % 2000) / 1000.0 - 1.0   # -1.0 .. ~1.0

func _appearance(c: Dictionary) -> Dictionary:
	var cid: int = int(c.get("id", 0))
	var stage: String = c.get("stage", "adult")
	var s: float = 1.0
	match stage:
		"baby":       s = 0.42
		"child":      s = 0.62
		"adolescent": s = 0.82
		"old":        s = 0.92
		_:            s = 1.0
	s *= PAWN_SCALE
	# Per-pawn height jitter (±~6%), seeded by id — folk aren't all the same height.
	s *= 1.0 + _id_rand(cid, 11) * 0.06
	var skin: Color = PeopleSystem.skin_color(float(c.get("skin", 0.6))) if c.has("skin") else SKIN
	var hair: Color = c.get("hair_color", Color(0.22, 0.14, 0.08))
	if stage == "old":
		hair = hair.lerp(Color(0.84, 0.84, 0.88), 0.7)
	# Subtle per-citizen tint variation on skin & hair (±~8% value/hue) so a crowd reads
	# as individuals, not clones. Deterministic by id; kept gentle to stay natural.
	skin = _tint_vary(skin, _id_rand(cid, 23) * 0.08, _id_rand(cid, 31) * 0.05)
	hair = _tint_vary(hair, _id_rand(cid, 41) * 0.08, _id_rand(cid, 53) * 0.06)
	var female: bool = c.get("sex", "m") == "f"
	var grown: bool = stage in ["adolescent", "adult", "midlife", "old"]
	# Deterministic per-person "look" — headwear, beard, apron, shawl, hairstyle. Drives the clear
	# male/female read AND individual variety. Stable for the citizen's whole life (id-seeded).
	var head := ""
	var beard := ""
	var apron := false
	var shawl := false
	var hstyle := int(c.get("hair_style", 0))
	if female and grown:
		var hk: float = absf(_id_rand(cid, 103))
		if stage == "old" and hk < 0.6: head = "wimple"        # matrons cover up
		elif hk < 0.30: head = "kerchief"
		elif hk < 0.46: head = "coif"
		# else bareheaded — braid/bun/loose hair shows
		apron = absf(_id_rand(cid, 131)) < 0.62
		shawl = stage == "old" or absf(_id_rand(cid, 137)) < 0.28
		hstyle = int((absf(_id_rand(cid, 149)) * 3.0)) % 3   # 0 loose, 1 braid, 2 bun
	elif not female and grown:
		var hk2: float = absf(_id_rand(cid, 107))
		if hk2 < 0.26: head = "coif"
		elif hk2 < 0.46: head = "cap"
		elif hk2 < 0.58: head = "hood"
		# else bareheaded
		if stage in ["adult", "midlife", "old"]:
			var bk: float = absf(_id_rand(cid, 113))
			if bk < 0.26: beard = "full"
			elif bk < 0.42: beard = "long"
			elif bk < 0.60: beard = "stubble"
	# Dev override hooks (used by _PawnShowcase to curate the gallery; harmless in-game).
	if c.has("force_head"): head = String(c["force_head"])
	if c.has("force_beard"): beard = String(c["force_beard"])
	if c.has("force_hstyle"): hstyle = int(c["force_hstyle"])
	if c.has("force_apron"): apron = bool(c["force_apron"])
	if c.has("force_shawl"): shawl = bool(c["force_shawl"])
	return {"scale": s, "female": female, "skin": skin, "hair": hair, "stage": stage, "grown": grown,
		"cid": cid, "head": head, "beard": beard, "apron": apron, "shawl": shawl, "hstyle": hstyle}

# Nudge a colour's value (brightness) and hue by small signed amounts, clamped to a
# sane range so variation reads as natural human difference, not a colour glitch.
func _tint_vary(col: Color, dv: float, dh: float) -> Color:
	var h: float = fposmod(col.h + dh, 1.0)
	var sat: float = clampf(col.s, 0.0, 1.0)
	var v: float = clampf(col.v * (1.0 + dv), 0.0, 1.0)
	return Color.from_hsv(h, sat, v, col.a)

# ── Main loop ─────────────────────────────────────────────────────────────────

func _draw() -> void:
	# Refresh the shared night factor for the whole roster this frame.
	_night = SeasonSystem.night_factor(SimulationClock.current_tick)
	# Cull to the visible rect (margin covers the figure's height/width above the feet),
	# collecting just the on-screen people. Then pick detail level: batched glyphs when zoomed
	# out OR when the visible crowd is too large for full art to be legible/affordable.
	var vis := _visible_rect(40.0)
	var shown: Array = []
	for c in GameState.citizens:
		if not (c is Dictionary and c.get("is_alive", false)):
			continue
		if c.get("state", "") == "inside":
			continue
		var sx: float = (c["x"] - c["y"]) * HALF_W
		var sy: float = (c["x"] + c["y"]) * HALF_H
		if not vis.has_point(Vector2(sx, sy)):
			continue
		shown.append([sx, sy, c])
	var lod: bool = (_camera != null and _camera.zoom.x < LOD_ZOOM) or shown.size() > CROWD_LIMIT
	_lod_active = lod
	if lod:
		# Batched little people: a tunic-tinted body + a skin head per pawn — 2 draw calls.
		if _crowd != null:
			_crowd.begin()
			for e in shown:
				var gs: float = _glyph_scale(e[2])
				var p := Vector2(e[0], e[1])
				_crowd.push("body", p, gs, _glyph_color(e[2]))
				_crowd.push("head", p, gs, Color.WHITE)
			_crowd.flush()
	else:
		if _crowd != null:
			_crowd.clear()
		for e in shown:
			var ex: float = e[0]
			var ey: float = e[1]
			var c: Dictionary = e[2]
			if c.get("role", "") == "worker":
				_draw_worker(ex, ey, c)
			else:
				_draw_citizen(ex, ey, c)
	_draw_fx()

# Tunic/role colour for a pawn's crowd glyph (worker job tunic, builder blue, else peasant).
func _glyph_color(c: Dictionary) -> Color:
	if c.get("role", "") == "worker":
		return WorkerJobs.style(c.get("job_type", "")).get("tunic", Color(0.5, 0.4, 0.28))
	if c.get("role", "") == "builder":
		return Color(0.30, 0.42, 0.55)
	return PEASANT_TUNICS[int(c.get("id", 0)) % PEASANT_TUNICS.size()]

# Children/elders read a touch smaller, like the full figure does.
func _glyph_scale(c: Dictionary) -> float:
	match String(c.get("stage", "adult")):
		"baby":       return 0.5
		"child":      return 0.68
		"adolescent": return 0.86
		_:            return 1.0

# ── Articulated figure ─────────────────────────────────────────────────────────
# Draws legs + shaded torso + head and returns the joints a caller needs to hang a
# tool or load on. Handles walk, idle and work poses from one physical model.
#
# Returns {sh:Vector2 (shoulder centre), hip:Vector2, hand:Vector2 (free/forward),
#          back_hand:Vector2, head:Vector2, head_r:float, lean:float}
func _draw_figure(sx: float, sy: float, c: Dictionary, ap: Dictionary,
		tunic: Color, t: float, moving: bool, working: bool) -> Dictionary:
	var s: float = ap.scale
	var skin: Color = ap.skin
	var face: float = c.get("facing", 1.0)
	var female: bool = ap.female
	var dark: Color = tunic.darkened(0.28)
	var lit: Color = tunic.lightened(0.20)

	var speed01: float = clampf((absf(c.get("vx", 0.0)) + absf(c.get("vy", 0.0))) / 0.06, 0.0, 1.0) if moving else 0.0
	var cadence: float = 6.0 + speed01 * 7.0
	var gait_t: float = t * cadence
	var gait: float = sin(gait_t) if moving else 0.0

	# Idle behaviour: choose a per-person archetype, blended subtly.
	var cid: int = int(c.get("id", 0))
	var idle_kind: int = cid % 4
	# Per-pawn phase offset + frequency/amplitude jitter so a standing crowd doesn't breathe
	# and sway in lockstep. Deterministic by id (stable every frame).
	var iph: float = float(cid % 11) * 0.571                  # 0..~5.7 rad phase spread
	var ifreq: float = 1.0 + _id_rand(cid, 67) * 0.18         # ±18% cadence
	var iamp: float = 1.0 + _id_rand(cid, 71) * 0.30          # ±30% amplitude
	var breathe: float = sin((t + iph) * 1.5 * ifreq) * 0.6 * iamp
	var sway: float = 0.0
	var head_turn: float = 0.0
	var idle_arm: float = 0.0
	if not moving and not working:
		if c.get("state", "") == "chat":
			# Conversational gesture: gesticulate and nod. Phase split by id-parity so a pair
			# talks in turns — one's hands move while the other listens — not in lockstep.
			var ph: float = t * 1.5 + float(cid % 2) * PI
			idle_arm = maxf(0.0, sin(ph)) * 3.4                  # a hand lifts while "speaking"
			head_turn = sin(ph * 0.9) * 1.0                      # nodding / emphasis
			sway = sin(t * 0.7) * 0.7
			breathe += sin(t * 1.5) * 0.3
		else:
			match idle_kind:
				0: sway = sin((t + iph) * 0.8 * ifreq) * 1.3 * iamp        # weight-shift hips
				1: head_turn = sin((t + iph) * 0.6 * ifreq) * 1.2 * iamp   # glancing about
				2: breathe = sin((t + iph) * 1.1 * ifreq) * 1.0 * iamp     # deeper, slower breath
				3: idle_arm = maxf(0.0, sin((t + iph) * 0.45 * ifreq)) * 3.0 * iamp  # occasional stretch
			breathe += sin((t + iph) * 1.5 * ifreq) * 0.3

	# Vertical bob: two per stride when walking, gentle breath otherwise.
	var bob: float = (absf(sin(gait_t)) * 2.0 * speed01) if moving else (breathe * 0.4)
	# Lean into the direction of travel (or a small idle list).
	var lean: float = (face * 1.6 * speed01) + sway * 0.4
	var work_crouch: float = 1.4 if working else 0.0

	var feet_y: float = sy
	var hip := Vector2(sx + lean * 0.5, feet_y - 8.0 * s - bob)
	var sh := Vector2(sx + lean, feet_y - 16.0 * s - bob + work_crouch * 0.5)
	var head := Vector2(sh.x + head_turn + lean * 0.2, sh.y - 4.6 * s)
	var head_r: float = 2.9 * s

	# Night rim/halo — a faint cool glow BEHIND the body so the silhouette separates from
	# the dark ground after dusk. Invisible by day (gated on _night), gentle at deep night
	# (low alpha, never a lamp). Drawn first so the figure sits on top of it.
	if _night > 0.12:
		var glow: float = clampf((_night - 0.12) / 0.88, 0.0, 1.0)
		var body_mid := Vector2(sh.x, (sh.y + hip.y) * 0.5)
		var halo := Color(0.62, 0.72, 0.92, 0.10 * glow)   # cool, low-alpha moonlight
		draw_circle(body_mid, 7.0 * s, halo)
		draw_circle(head, head_r + 2.4 * s, Color(0.62, 0.72, 0.92, 0.12 * glow))

	# Ground shadow — squashes a touch when the body bobs up.
	var sh_w: float = (5.0 - bob * 0.4) * s
	draw_circle(Vector2(sx, feet_y + 1.0), sh_w, Color(0, 0, 0, 0.20))

	# Garment geometry differs by sex so men and women read apart at a glance: women get narrow
	# shoulders + a full floor-length A-line gown; men broad shoulders + two hosed legs and a short
	# belted tunic. `shoulders`/`hips_w` are reused by the arm-pose below.
	var worker: bool = c.get("role", "") == "worker"
	var shoulders: float = ((2.3 if female else 2.95) + (0.25 if worker else 0.0)) * s
	var hips_w: float = (2.7 if female else 2.4) * s
	var belt := Color(0.28, 0.19, 0.11)
	var hose: Color = tunic.darkened(0.36).lerp(Color(0.33, 0.29, 0.24), 0.45)

	# ── Lower body ─────────────────────────────────────────────────────────────
	if female:
		# A full A-line GOWN, waist to floor — the unmistakable female silhouette.
		var hemswing: float = gait * 1.4 * s
		var waist := Vector2(hip.x, hip.y - 1.0 * s)
		var hemL := Vector2(sx - 5.8 * s + hemswing * 0.7, feet_y)
		var hemR := Vector2(sx + 5.8 * s + hemswing, feet_y)
		draw_colored_polygon(PackedVector2Array([waist + Vector2(-hips_w, 0), waist + Vector2(hips_w, 0), hemR, hemL]), tunic)
		draw_colored_polygon(PackedVector2Array([waist, waist + Vector2(face * hips_w, 0),
			Vector2(sx + face * 5.8 * s + hemswing, feet_y), Vector2(sx + hemswing * 0.5, feet_y)]), lit)   # lit panel
		for fx in [-0.5, 0.0, 0.5]:
			draw_line(waist + Vector2(hips_w * fx, 0), Vector2(sx + 5.8 * s * fx + hemswing * 0.7, feet_y), dark, 0.6 * s)
		draw_line(hemL, hemR, tunic.lightened(0.28), 1.1 * s)   # hem band
		if ap.apron:
			var ap_col := Color(0.83, 0.79, 0.69)
			draw_colored_polygon(PackedVector2Array([waist + Vector2(-hips_w * 0.55, 0.5), waist + Vector2(hips_w * 0.55, 0.5),
				Vector2(sx + 3.4 * s + hemswing * 0.6, feet_y - 0.4), Vector2(sx - 3.0 * s + hemswing * 0.6, feet_y - 0.4)]), ap_col)
			draw_line(waist + Vector2(-hips_w * 0.55, 0.5), waist + Vector2(hips_w * 0.55, 0.5), ap_col.darkened(0.16), 0.6 * s)
		draw_circle(Vector2(sx - 1.6 * s + hemswing * 0.7, feet_y), 1.1 * s, Color(0.30, 0.22, 0.16))   # shoe tips
		draw_circle(Vector2(sx + 1.8 * s + hemswing, feet_y), 1.1 * s, Color(0.30, 0.22, 0.16))
	else:
		# Two hosed legs (articulated walk), then a short flared belted tunic over the thighs.
		var stride: float = 2.6 * s * (0.4 + speed01)
		var lift_a: float = maxf(0.0, gait) * 2.2 * s * speed01
		var lift_b: float = maxf(0.0, -gait) * 2.2 * s * speed01
		var splay: float = 0.0 if moving else (1.4 * s + absf(sway) * 0.3)
		var foot_a := Vector2(sx + face * gait * stride - splay, feet_y - lift_a)
		var foot_b := Vector2(sx - face * gait * stride + splay, feet_y - lift_b)
		_limb2(hip, foot_b, face * (1.0 + lift_b), hose, 2.3 * s)
		_foot(foot_b, face, hose.darkened(0.2), s)
		_limb2(hip, foot_a, face * (1.0 + lift_a), hose.lightened(0.06), 2.3 * s)
		_foot(foot_a, face, hose.darkened(0.2), s)
		var hemY: float = hip.y + 4.0 * s
		var hemsw: float = gait * 0.8 * s
		draw_colored_polygon(PackedVector2Array([Vector2(hip.x - hips_w, hip.y - 1.0 * s), Vector2(hip.x + hips_w, hip.y - 1.0 * s),
			Vector2(hip.x + hips_w + 1.0 * s + hemsw, hemY), Vector2(hip.x - hips_w - 1.0 * s + hemsw, hemY)]), tunic)
		draw_line(Vector2(hip.x - hips_w - 1.0 * s + hemsw, hemY), Vector2(hip.x + hips_w + 1.0 * s + hemsw, hemY), dark, 0.7 * s)

	# ── Torso / garment top (lit leading half, shaded trailing) ─────────────────
	var tw: float = shoulders
	var torso := PackedVector2Array([
		Vector2(hip.x - hips_w * 0.9, hip.y), Vector2(hip.x + hips_w * 0.9, hip.y),
		Vector2(sh.x + tw, sh.y), Vector2(sh.x - tw, sh.y)])
	draw_colored_polygon(torso, tunic)
	draw_colored_polygon(PackedVector2Array([Vector2(hip.x, hip.y), Vector2(hip.x + face * hips_w * 0.9, hip.y),
		Vector2(sh.x + face * tw, sh.y), Vector2(sh.x, sh.y)]), lit)
	draw_line(Vector2(hip.x - face * hips_w * 0.9, hip.y), Vector2(sh.x - face * tw, sh.y), dark, 1.0 * s)
	_outline_poly(torso)
	if female:
		for k in range(3):                                   # bodice lacing
			var ly: float = sh.y + (hip.y - sh.y) * (0.28 + 0.2 * float(k))
			draw_line(Vector2(sh.x - 0.9 * s, ly), Vector2(sh.x + 0.9 * s, ly + 0.7 * s), dark, 0.5 * s)
		draw_arc(Vector2(sh.x, sh.y + 0.8 * s), 1.4 * s, PI * 0.12, PI * 0.88, 5, skin.darkened(0.05), 0.8 * s)   # neckline
		if ap.shawl:
			draw_colored_polygon(PackedVector2Array([Vector2(sh.x - tw - 0.6 * s, sh.y - 0.3 * s), Vector2(sh.x + tw + 0.6 * s, sh.y - 0.3 * s),
				Vector2(sh.x + tw * 0.5, sh.y + 3.6 * s), Vector2(sh.x - tw * 0.5, sh.y + 3.6 * s)]), tunic.darkened(0.2))
	else:
		draw_line(Vector2(sh.x - 1.2 * s, sh.y + 0.5 * s), Vector2(sh.x + 1.2 * s, sh.y + 0.5 * s), dark, 0.7 * s)   # collar
		draw_line(Vector2(hip.x - hips_w * 0.9, hip.y - 0.6 * s), Vector2(hip.x + hips_w * 0.9, hip.y - 0.6 * s), belt, 1.3 * s)
		draw_rect(Rect2(hip.x - 0.7 * s, hip.y - 1.3 * s, 1.4 * s, 1.5 * s), Color(0.78, 0.66, 0.30))   # buckle
	# Neck.
	draw_line(Vector2(sh.x, sh.y), Vector2(head.x, head.y + head_r * 0.6), skin.darkened(0.12), 1.8 * s)

	# ── Head + hair + face + headwear ───────────────────────────────────────────
	draw_circle(head, head_r + 0.5, OUTLINE)
	draw_circle(head, head_r, skin)
	draw_circle(head + Vector2(-face * head_r * 0.5, head_r * 0.15), head_r * 0.55, skin.darkened(0.12))   # cheek shadow
	_draw_hair(head, head_r, face, ap, c)
	_draw_face(head, head_r, face, ap)
	_draw_headwear(head, head_r, face, ap)

	# Arm pose. Arms hang from the SHOULDER EDGES (not the body centre) so they drop near-vertically
	# at the sides instead of splaying into a wide skin "A". Walking arms swing fore/aft opposite the
	# legs. Sleeves (upper arm in garment colour) are drawn by the caller via _arm.
	var shw: float = shoulders * 0.82
	var sh_lead := Vector2(sh.x + face * shw, sh.y + 0.6 * s)
	var sh_back := Vector2(sh.x - face * shw, sh.y + 0.6 * s)
	var arm_swing: float = -gait * 2.2 * s
	var hand: Vector2
	var back_hand: Vector2
	var arm_bend: float = 0.0
	var back_bend: float = 0.0
	if moving:
		hand = Vector2(sh_lead.x + face * 0.6 * s + arm_swing, hip.y + 1.4 * s)
		back_hand = Vector2(sh_back.x - face * 0.4 * s - arm_swing, hip.y + 1.6 * s)
		arm_bend = -face * 0.7; back_bend = face * 0.7      # elbow fore/aft
	else:
		hand = Vector2(sh_lead.x + face * 0.5 * s, hip.y + 3.0 * s)
		back_hand = Vector2(sh_back.x - face * 0.2 * s, hip.y + 3.0 * s)
		arm_bend = -face * 0.45; back_bend = face * 0.45    # slight natural elbow
		if idle_kind == 3:    # an occasional one-arm stretch overhead
			hand = Vector2(sh.x + face * (2.0 + idle_arm * 0.4) * s, sh.y - idle_arm * 1.8 * s)
	return {"sh": sh, "sh_lead": sh_lead, "sh_back": sh_back, "sleeve": tunic, "hip": hip,
		"hand": hand, "back_hand": back_hand, "arm_bend": arm_bend,
		"back_bend": back_bend, "head": head, "head_r": head_r, "lean": lean, "skin": skin,
		"s": s, "face": face, "gait": gait, "speed01": speed01, "working": working}

# Two-segment limb with a bend at the mid-joint, drawn with a soft outline + a
# rounded joint so limbs read as articulated rather than as straws.
func _limb2(a: Vector2, b: Vector2, bend: float, col: Color, w: float) -> void:
	var dir := b - a
	var L := dir.length()
	if L < 0.01:
		draw_circle(a, w * 0.5, col)
		return
	var n := Vector2(-dir.y, dir.x) / L
	var knee := (a + b) * 0.5 + n * bend
	draw_line(a, knee, OUTLINE, w + 0.7)
	draw_line(knee, b, OUTLINE, w + 0.7)
	draw_line(a, knee, col, w)
	draw_line(knee, b, col.lightened(0.05), w)
	draw_circle(knee, w * 0.5, col)
	draw_circle(b, w * 0.52, col.lightened(0.08))   # hand/foot cap

# A sleeved arm: a two-segment limb whose UPPER arm is the garment sleeve and FOREARM is bare skin,
# with a cuff at the elbow and a hand cap — so the arms read as clothed limbs, not a bare-skin "A".
func _arm(a: Vector2, b: Vector2, bend: float, sleeve: Color, skin: Color, w: float) -> void:
	var dir := b - a
	var L := dir.length()
	if L < 0.01:
		draw_circle(a, w * 0.5, skin)
		return
	var n := Vector2(-dir.y, dir.x) / L
	var elbow := (a + b) * 0.5 + n * bend
	draw_line(a, elbow, OUTLINE, w + 0.7)
	draw_line(elbow, b, OUTLINE, w + 0.7)
	draw_line(a, elbow, sleeve, w)                  # upper arm — sleeve
	draw_line(elbow, b, skin, w * 0.85)             # forearm — bare skin
	draw_circle(elbow, w * 0.5, sleeve.darkened(0.12))   # cuff
	draw_circle(b, w * 0.5, skin.lightened(0.05))        # hand

func _foot(p: Vector2, face: float, col: Color, s: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-1.0 * s, 0), p + Vector2(face * 2.4 * s, 0),
		p + Vector2(face * 2.4 * s, 1.0 * s), p + Vector2(-1.0 * s, 1.2 * s)]), col.darkened(0.15))

func _draw_face(head: Vector2, r: float, face: float, ap: Dictionary) -> void:
	if ap.stage == "baby":
		draw_circle(head + Vector2(face * r * 0.3, 0), maxf(0.5, r * 0.16), Color(0.18, 0.12, 0.10))
		return
	var ink := Color(0.15, 0.10, 0.09)
	# Brow on the leading side.
	draw_line(head + Vector2(face * r * 0.10, -r * 0.36), head + Vector2(face * r * 0.66, -r * 0.24), ap.hair.darkened(0.05), maxf(0.7, r * 0.16))
	# Two eyes (a bigger leading one + a smaller far one) → reads as a face, not a dot.
	var eye := head + Vector2(face * r * 0.42, -r * 0.04)
	draw_circle(eye, maxf(0.6, r * 0.18), ink)
	draw_circle(eye + Vector2(face * 0.5, -0.5), maxf(0.2, r * 0.07), Color(0.96, 0.96, 0.96, 0.85))
	draw_circle(head + Vector2(face * r * 0.02, -r * 0.02), maxf(0.45, r * 0.12), ink)
	# Nose nub on the profile edge, then a small mouth.
	draw_line(head + Vector2(face * r * 0.92, r * 0.06), head + Vector2(face * r * 1.12, r * 0.26), ap.skin.darkened(0.22), maxf(0.8, r * 0.3))
	draw_line(head + Vector2(face * r * 0.22, r * 0.52), head + Vector2(face * r * 0.62, r * 0.48), Color(0.52, 0.28, 0.24), maxf(0.5, r * 0.14))
	# Rosy cheek for women & children; a wrinkle hint for elders.
	if ap.female or ap.stage == "child":
		draw_circle(head + Vector2(face * r * 0.48, r * 0.26), r * 0.26, Color(0.93, 0.55, 0.50, 0.26))
	if ap.stage == "old":
		draw_line(head + Vector2(face * r * 0.2, -r * 0.52), head + Vector2(face * r * 0.7, -r * 0.44), ap.skin.darkened(0.22), 0.5)

func _draw_hair(head: Vector2, r: float, face: float, ap: Dictionary, c: Dictionary) -> void:
	var hair: Color = ap.hair
	if ap.stage == "baby":
		draw_arc(head + Vector2(0, -r * 0.4), r * 0.55, PI * 1.1, TAU * 0.95, 6, hair, maxf(1.0, r * 0.5))
		return
	var covered: bool = String(ap.head) in ["coif", "wimple", "hood"]   # full-cover headwear hides the hair
	var hst: int = int(ap.hstyle)
	if not covered:
		draw_arc(head + Vector2(0, -r * 0.12), r * 1.06, PI * 0.86, TAU * 1.06, 10, hair, maxf(1.8, r * 1.05))   # crown
		draw_line(head + Vector2(-face * r * 0.8, -r * 0.4), head + Vector2(-face * r * 0.3, -r * 0.72), hair, maxf(1.2, r * 0.5))
		draw_line(head + Vector2(face * r * 0.2, -r * 0.72), head + Vector2(face * r * 0.66, -r * 0.5), hair, maxf(1.0, r * 0.4))
	if ap.female:
		if covered:
			pass
		elif hst == 2:
			draw_circle(head + Vector2(-face * r * 0.72, -r * 0.5), r * 0.56, hair)          # bun
			draw_circle(head + Vector2(-face * r * 0.72, -r * 0.5), r * 0.56, hair.darkened(0.15), false, 0.6)
		elif hst == 1:
			var bx := head + Vector2(face * r * 0.55, r * 0.4)                                # braid over shoulder
			for k in range(5):
				draw_circle(bx + Vector2(face * float(k) * 0.32 * r, r * 0.6 + float(k) * r * 0.66), r * (0.44 - float(k) * 0.06), hair)
		else:
			draw_line(head + Vector2(-r * 0.95, -r * 0.1), head + Vector2(-r * 1.05, r * 3.0), hair, maxf(1.6, r * 0.85))   # loose
			draw_line(head + Vector2(r * 0.95, -r * 0.1), head + Vector2(r * 1.05, r * 3.0), hair, maxf(1.6, r * 0.85))
	else:
		if not covered and hst == 2:
			draw_line(head + Vector2(-r * 0.95, -r * 0.1), head + Vector2(-r * 0.95, r * 1.4), hair, maxf(1.3, r * 0.6))   # long-ish
		match String(ap.beard):
			"full":
				draw_circle(head + Vector2(face * r * 0.18, r * 0.85), r * 0.74, hair.lerp(ap.skin, 0.16))
				draw_circle(head + Vector2(-face * r * 0.3, r * 0.68), r * 0.5, hair.lerp(ap.skin, 0.16))
			"long":
				draw_colored_polygon(PackedVector2Array([head + Vector2(-face * r * 0.5, r * 0.5), head + Vector2(face * r * 0.72, r * 0.5),
					head + Vector2(face * r * 0.5, r * 2.2), head + Vector2(-face * r * 0.3, r * 2.0)]), hair.lerp(ap.skin, 0.13))
			"stubble":
				draw_circle(head + Vector2(face * r * 0.22, r * 0.7), r * 0.62, Color(hair.r, hair.g, hair.b, 0.30))

# Hats, hoods, coifs & headscarves — drawn over the hair, as a face-framing band so the eyes/nose
# still read. A primary lever for the male/female distinction (men: cap/hood/coif; women: kerchief/
# coif/wimple). Order: hair → face → headwear (the band frames the face, never hides the features).
func _draw_headwear(head: Vector2, r: float, face: float, ap: Dictionary) -> void:
	var hd: String = String(ap.head)
	if hd == "":
		return
	var oc: float = 0.0 if face > 0.0 else PI            # the face-opening centre angle (leading side)
	var gap: float = PI * 0.34
	match hd:
		"coif":
			var col := Color(0.88, 0.86, 0.78)
			draw_arc(head + Vector2(0, -r * 0.10), r * 0.92, oc + gap, oc + TAU - gap, 14, col, maxf(2.2, r * 0.92))
			draw_arc(head + Vector2(0, r * 0.05), r * 1.0, oc + PI * 0.5, oc + TAU - PI * 0.5, 6, col.darkened(0.1), maxf(1.0, r * 0.35))
		"kerchief":
			var kc := Color(0.74, 0.42, 0.34)
			draw_arc(head + Vector2(0, -r * 0.10), r * 0.92, oc + gap, oc + TAU - gap, 14, kc, maxf(2.2, r * 0.92))
			draw_circle(head + Vector2(-face * r * 0.95, -r * 0.05), r * 0.4, kc.darkened(0.12))   # knot at back
		"wimple":
			var lin := Color(0.90, 0.89, 0.84)
			draw_arc(head + Vector2(0, -r * 0.10), r * 0.95, oc + gap * 0.7, oc + TAU - gap * 0.7, 14, lin, maxf(2.4, r * 1.0))
			draw_colored_polygon(PackedVector2Array([head + Vector2(-r * 1.0, r * 0.3), head + Vector2(r * 1.0, r * 0.3),
				head + Vector2(r * 1.2, r * 2.4), head + Vector2(-r * 1.2, r * 2.4)]), lin)   # neck/shoulder drape
		"cap":
			var cap := Color(0.38, 0.30, 0.20)
			draw_colored_polygon(PackedVector2Array([head + Vector2(-r * 1.05, -r * 0.18), head + Vector2(r * 1.05, -r * 0.18),
				head + Vector2(face * r * 0.25, -r * 1.2)]), cap)
			draw_line(head + Vector2(-r * 1.05, -r * 0.18), head + Vector2(r * 1.05, -r * 0.18), cap.darkened(0.22), maxf(0.8, r * 0.3))
		"hood":
			var hudc := Color(0.34, 0.31, 0.27)
			draw_colored_polygon(PackedVector2Array([head + Vector2(-r * 1.15, r * 0.6), head + Vector2(r * 1.15, r * 0.6),
				head + Vector2(r * 0.85, -r * 0.9), head + Vector2(-face * r * 0.2, -r * 1.35), head + Vector2(-r * 0.85, -r * 0.9)]), hudc)
			draw_arc(head + Vector2(0, -r * 0.05), r * 0.86, oc + gap, oc + TAU - gap, 12, hudc.darkened(0.12), maxf(1.2, r * 0.5))   # rim shadow

func _outline_poly(pts: PackedVector2Array) -> void:
	for i in range(pts.size()):
		draw_line(pts[i], pts[(i + 1) % pts.size()], OUTLINE, 1.0)

# ── Villagers & builders ────────────────────────────────────────────────────────

func _draw_citizen(sx: float, sy: float, c: Dictionary) -> void:
	var st: String = c.get("state", "idle")
	var builder: bool = c.get("role", "") == "builder"
	var t: float = _anim_time + float(c.get("id", 0)) * 0.55
	var vmoving: bool = absf(c.get("vx", 0.0)) + absf(c.get("vy", 0.0)) > 0.002
	var moving: bool = st == "walk" or st == "wander" or vmoving
	var building: bool = st == "build"

	var ap := _appearance(c)
	# Per-person tunic from a muted peasant palette (deterministic by id) so a crowd reads
	# as varied individuals, not one uniform pink/olive cohort. Builders keep a distinct
	# blue-grey so they're identifiable at a glance while working a site.
	var tunic: Color
	if builder:
		tunic = Color(0.30, 0.42, 0.55)
	else:
		tunic = PEASANT_TUNICS[int(c.get("id", 0)) % PEASANT_TUNICS.size()]
		if ap.female:
			tunic = tunic.lerp(Color(0.64, 0.40, 0.44), 0.22)   # a touch warmer/rosier for women

	var j := _draw_figure(sx, sy, c, ap, tunic, t, moving and not building, building)
	var s: float = j.s
	var face: float = j.face
	var skin: Color = j.skin

	if building:
		# Both arms drive a hammer toward the actual building (act target).
		var aim := _aim_dir(c, j.sh)
		var dn: float = _swing01(t, 9.0)                      # 0 up … 1 down-strike (fast down)
		var reach: float = (3.0 + dn * 3.5) * s
		var shp: Vector2 = j.sh
		var hand: Vector2 = shp + aim * reach + Vector2(0, -3.0 * s + dn * 4.5 * s)
		_limb2(shp, hand, -face * 1.4, skin, 1.9 * s)
		# Hammer: handle then a steel head, swung along the aim.
		var hhead: Vector2 = hand + aim * 4.5 * s + Vector2(0, dn * 2.0 * s)
		draw_line(hand, hhead, WOOD, 1.6 * s)
		draw_rect(Rect2(hhead.x - 2.0 * s, hhead.y - 1.6 * s, 4.0 * s, 3.2 * s), STEEL)
		draw_rect(Rect2(hhead.x - 2.0 * s, hhead.y - 1.6 * s, 4.0 * s, 3.2 * s), STEEL_DK, false, 0.8)
	else:
		# Two sleeved arms hanging from the shoulders; back arm first so the lead overlaps it.
		_arm(j.sh_back, j.back_hand, j.back_bend, j.sleeve, skin, 1.7 * s)
		_arm(j.sh_lead, j.hand, j.arm_bend, j.sleeve, skin, 1.7 * s)
		if builder:
			# Shoulder the hammer while walking so the trade still reads.
			var sp: Vector2 = Vector2(j.sh) + Vector2(-face * 4.5 * s, -5.0 * s)
			draw_line(j.sh, sp, WOOD, 1.5 * s)
			draw_rect(Rect2(sp.x - face * 1.5 * s - 1.0, sp.y - 1.2 * s, 3.2 * s, 2.6 * s), STEEL)

# ── Job workers ───────────────────────────────────────────────────────────────

func _draw_worker(sx: float, sy: float, c: Dictionary) -> void:
	var style: Dictionary = WorkerJobs.style(c.get("job_type", ""))
	var ap := _appearance(c)
	var anim: String = c.get("work_anim", style.get("anim", "carry"))
	var tunic: Color = style.get("tunic", Color(0.5, 0.4, 0.28))
	var st: String = c.get("state", "idle")
	var phase: String = c.get("work_phase", "")
	var hauling: bool = phase == "haul_in" or phase == "haul_out"
	var vmoving: bool = absf(c.get("vx", 0.0)) + absf(c.get("vy", 0.0)) > 0.002
	var working: bool = st == "work" and not hauling and not vmoving
	var moving: bool = st == "walk" or st == "wander" or vmoving
	var t: float = _anim_time + float(c.get("id", 0)) * 0.6

	# Robe jobs (priest) override the legs with a cassock — handled inside the figure
	# via the female/dress path would be wrong, so draw robe separately when set.
	var robe: bool = style.get("robe", false)

	var j := _draw_figure(sx, sy, c, ap, tunic, t, moving, working and not hauling)
	var s: float = j.s
	var face: float = j.face
	var skin: Color = j.skin

	if robe:
		# A long cassock over the legs.
		draw_colored_polygon(PackedVector2Array([
			Vector2(j.sh.x - 2.6 * s, j.sh.y + 1.0), Vector2(j.sh.x + 2.6 * s, j.sh.y + 1.0),
			Vector2(sx + 3.6 * s, sy), Vector2(sx - 3.6 * s, sy)]), tunic.darkened(0.05))

	if working:
		_draw_job(c, j, anim, style, t)
	elif hauling:
		if String(c.get("carry_mode", "")) == "barrow":
			# Trundling a loaded wheelbarrow: both arms reach down-forward to the handles.
			_draw_barrow(sx, sy, j, s, face, skin, c.get("carry", ""))
		else:
			_limb2(j.sh, Vector2(j.sh.x + face * 3.0 * s, j.hip.y + 1.0 * s), face * 1.0, skin, 1.7 * s)
			_draw_carry_load(j.sh.x, j.sh.y, s, c.get("carry", ""))
	else:
		_arm(j.sh_back, j.back_hand, j.back_bend, j.sleeve, skin, 1.7 * s)
		_arm(j.sh_lead, j.hand, j.arm_bend, j.sleeve, skin, 1.7 * s)
		_draw_shouldered_tool(j.sh.x, j.sh.y, s, face, anim, style)

	# Headgear over the figure's own hair.
	if style.get("helmet", false):
		draw_arc(j.head + Vector2(0, -0.5 * s), 3.3 * s, PI, TAU, 8, STEEL, 1.5 * s)
		draw_circle(j.head + Vector2(face * 1.3 * s, -1.3 * s), 0.9 * s, Color(1.0, 0.95, 0.5))  # lamp
	elif robe:
		draw_colored_polygon(PackedVector2Array([
			j.head + Vector2(-3.3 * s, 1.2 * s), j.head + Vector2(3.3 * s, 1.2 * s),
			j.head + Vector2(2.0 * s, -3.0 * s), j.head + Vector2(-2.0 * s, -3.0 * s)]), tunic.darkened(0.12))

# Animated tool + working arm aimed at the real worked object. j holds the joints.
func _draw_job(c: Dictionary, j: Dictionary, anim: String, style: Dictionary, t: float) -> void:
	var shp: Vector2 = j.sh
	var sx: float = shp.x
	var sh: float = shp.y
	var hip: float = Vector2(j.hip).y
	var gy: float = sx_feet(c)
	var s: float = j.s
	var face: float = j.face
	var skin: Color = j.skin
	var aim: Vector2 = _aim_dir(c, shp)        # unit dir from shoulder toward the worked object

	match anim:
		"chop":   # axe swings down along the aim into the trunk
			var sw: float = _swing01(t, 7.0)                    # 0 raised … 1 struck (fast down)
			# Reach most of the way to the actual trunk so the blade lands ON the tree, not in
			# mid-air beside it (the worker stands a tile off the impassable forest tile).
			var trunk_d: float = 6.0 * s
			if c.has("act_x"):
				trunk_d = clampf((_to_screen(c["act_x"], c["act_y"]) - shp).length() - 4.0 * s, 6.0 * s, 22.0 * s)
			var reach: float = (3.0 * s) + sw * (trunk_d - 3.0 * s)
			var hand: Vector2 = shp + aim * reach + Vector2(0, -4.0 * s + sw * 5.0 * s)
			_limb2(shp, hand, -face * 1.2, skin, 1.8 * s)
			var bit: Vector2 = hand + aim * 5.0 * s + Vector2(0, sw * 2.5 * s)
			draw_line(hand, bit, WOOD, 1.6 * s)                  # haft
			# Axe head, broad blade facing the cut.
			draw_colored_polygon(PackedVector2Array([
				bit, bit + aim.rotated(PI * 0.5) * 2.4 * s, bit + aim * 2.6 * s + aim.rotated(PI * 0.5) * 1.0 * s,
				bit + aim * 2.6 * s - aim.rotated(PI * 0.5) * 1.0 * s, bit - aim.rotated(PI * 0.5) * 2.4 * s]), STEEL)
		"mine":   # pick driven overhead-down into the rock face
			var dn: float = _swing01(t, 6.0)
			var reach2: float = (2.6 + dn * 3.0) * s
			var hand2: Vector2 = shp + aim * reach2 + Vector2(0, -5.0 * s + dn * 7.0 * s)
			_limb2(shp, hand2, -face * 1.2, skin, 1.8 * s)
			var tip: Vector2 = hand2 + aim * 5.0 * s + Vector2(0, -1.0 * s + dn * 3.0 * s)
			draw_line(hand2 - aim * 2.0 * s + Vector2(0, -2.0 * s), tip, WOOD, 1.5 * s)
			draw_arc(tip, 3.0 * s, PI * 0.8, PI * 1.7, 6, STEEL, 1.7 * s)
		"hammer": # smith/wright strikes the anvil/work toward the building
			var dn2: float = _swing01(t, 8.0)
			var anvil: Vector2 = shp + aim * 5.0 * s + Vector2(0, 8.0 * s)
			draw_rect(Rect2(anvil.x - 2.6 * s, anvil.y - 2.0 * s, 5.2 * s, 2.6 * s), Color(0.28, 0.28, 0.32))
			var hand4: Vector2 = shp + aim * 3.4 * s + Vector2(0, -4.0 * s + dn2 * 6.5 * s)
			_limb2(shp, hand4, -face * 1.2, skin, 1.8 * s)
			var hh: Vector2 = hand4 + aim * 3.0 * s + Vector2(0, dn2 * 2.0 * s)
			draw_line(hand4, hh, WOOD, 1.4 * s)
			draw_rect(Rect2(hh.x - 1.8 * s, hh.y - 1.4 * s, 3.6 * s, 2.8 * s), STEEL)
		"scythe": # low sweeping cut across the rows
			var sweep: float = sin(t * 4.0)
			var grip: Vector2 = shp + Vector2(face * 3.0 * s, 2.0 * s)
			_limb2(shp, grip, face * 1.0, skin, 1.7 * s)
			var sc_end: Vector2 = grip + Vector2(face * (6.0 + sweep * 3.0) * s, 5.0 * s)
			draw_line(grip, sc_end, WOOD, 1.5 * s)
			draw_arc(sc_end, 4.2 * s, -PI * 0.2 + sweep * 0.5, PI * 0.6 + sweep * 0.5, 8, STEEL, 1.5 * s)
		"pick":   # reach up to pull fruit/hops, drop into the belt basket
			var up: float = (sin(t * 4.5) * 0.5 + 0.5)
			var hand3: Vector2 = shp + aim * 3.0 * s + Vector2(0, -2.0 * s - up * 7.0 * s)
			_limb2(shp, hand3, -face * 1.0, skin, 1.7 * s)
			draw_circle(hand3, 1.3 * s, Color(0.85, 0.2, 0.18))
			draw_rect(Rect2(sx - face * 3.6 * s - 2.0, hip - 3.0 * s, 4.0 * s, 4.0 * s), WOOD)
		"stir":
			var a: float = t * 5.0
			var bowl := Vector2(sx + face * 4.0 * s, hip)
			draw_circle(bowl, 2.7 * s, Color(0.36, 0.28, 0.2))
			var hand5 := bowl + Vector2(cos(a) * 1.7 * s, -3.0 * s + sin(a) * 1.0 * s)
			_limb2(j.sh, hand5, face * 0.8, skin, 1.7 * s)
			draw_line(hand5, bowl + Vector2(cos(a) * 1.3 * s, 0), WOOD, 1.3 * s)
		"tend":
			var bobv: float = sin(t * 4.0) * 1.5 * s
			var hand6 := Vector2(sx + face * 4.0 * s, hip + 2.0 * s + bobv)
			_limb2(j.sh, hand6, face * 1.2, skin, 1.7 * s)
			draw_rect(Rect2(hand6.x - 1.5 * s, hand6.y, 3.0 * s, 3.0 * s), Color(0.7, 0.7, 0.72))
		"serve":
			var bobv2: float = sin(t * 3.0) * 1.2 * s
			var hand7 := Vector2(sx + face * 5.0 * s, sh + 1.0 * s + bobv2)
			_limb2(j.sh, hand7, face * 1.0, skin, 1.6 * s)
			draw_rect(Rect2(hand7.x - 1.0 * s, hand7.y - 2.0 * s, 2.5 * s, 3.0 * s), Color(0.8, 0.66, 0.3))
		"pray":
			var sway2: float = sin(t * 2.0) * 0.6 * s
			_limb2(j.sh, Vector2(sx + 3.0 * s + sway2, sh - 5.0 * s), 0.6, skin, 1.5 * s)
			_limb2(j.sh, Vector2(sx - 3.0 * s + sway2, sh - 5.0 * s), -0.6, skin, 1.5 * s)
			draw_rect(Rect2(sx - 1.5 * s, sh + 1.0 * s, 3.0 * s, 2.2 * s), Color(0.7, 0.6, 0.3))
		"guard":
			_limb2(j.sh, Vector2(sx + face * 2.0 * s, hip), face * 1.0, skin, 1.6 * s)
			draw_line(Vector2(sx + face * 3.0 * s, gy), Vector2(sx + face * 3.0 * s, sh - 9.0 * s), WOOD, 1.4 * s)
			draw_colored_polygon(PackedVector2Array([
				Vector2(sx + face * 3.0 * s, sh - 9.0 * s), Vector2(sx + face * 2.0 * s, sh - 7.0 * s),
				Vector2(sx + face * 4.0 * s, sh - 7.0 * s)]), STEEL)
		_:
			# Unknown work anim: just drop a relaxed arm at the side. Never draw a held box —
			# the old fallback rect read as a missing-texture square floating over the face.
			_limb2(j.sh, Vector2(sx + face * 2.5 * s, hip + 1.0 * s), face * 1.0, skin, 1.6 * s)

# Feet screen-Y for a citizen (the figure draws relative to it).
func sx_feet(c: Dictionary) -> float:
	return (c["x"] + c["y"]) * HALF_H

# A real tool stroke: a slow, eased RAISE for most of the cycle, then a SUDDEN
# down-strike. Returns 0 = fully raised … 1 = struck (impact at the cycle boundary,
# which is where the FX burst is timed). `freq` matches _strike_freq.
func _swing01(t: float, freq: float) -> float:
	var u: float = fposmod(t * freq, TAU) / TAU      # 0..1 cycle progress
	if u < 0.7:
		return 1.0 - smoothstep(0.0, 1.0, u / 0.7)   # struck → raised, slow & eased
	return smoothstep(0.0, 1.0, (u - 0.7) / 0.3)     # raised → struck, fast (compressed)

# Unit direction from a shoulder point toward the worked object, in screen space.
func _aim_dir(c: Dictionary, sh: Vector2) -> Vector2:
	if c.has("act_x"):
		var tgt := _to_screen(c["act_x"], c["act_y"])
		var d := tgt - sh
		if d.length() > 0.5:
			return d.normalized()
	var face: float = c.get("facing", 1.0)
	return Vector2(face, 0.1).normalized()

func _draw_carry_load(sx: float, sh: float, s: float, good: String) -> void:
	var col: Color
	match good:
		"wood", "firewood", "raw": col = Color(0.50, 0.36, 0.20)
		"stone":                   col = Color(0.60, 0.60, 0.64)
		"iron", "ore":             col = Color(0.45, 0.40, 0.36)
		"apples", "wheat", "hops", "flour", "bread": col = Color(0.78, 0.66, 0.34)
		_:                         col = Color(0.66, 0.54, 0.34)
	var top := sh + 1.0 * s
	draw_rect(Rect2(sx - 3.0 * s, top, 6.0 * s, 5.0 * s), col)
	draw_rect(Rect2(sx - 3.0 * s, top, 6.0 * s, 5.0 * s), col.darkened(0.3), false, 0.8)

# A pushed wheelbarrow piled with logs, ahead of the pawn in its facing direction. Both hands
# grip the handles. A small jolt makes it look heavy (the worker struggles, but keeps pace).
func _draw_barrow(sx: float, sy: float, j: Dictionary, s: float, face: float, skin: Color, good: String) -> void:
	var jolt: float = sin(_anim_time * 9.0) * 0.6 * s
	var fwd: float = face * 9.0 * s
	var wheel := Vector2(sx + fwd + face * 3.0 * s, sy + 1.0 * s + jolt)
	var tray := Vector2(sx + fwd, sy - 4.0 * s + jolt)
	# Wheel.
	draw_circle(wheel, 2.6 * s, Color(0.20, 0.16, 0.12))
	draw_circle(wheel, 1.1 * s, Color(0.40, 0.30, 0.20))
	# Tray (a slanted wooden tub) + leg.
	draw_colored_polygon(PackedVector2Array([
		tray + Vector2(-face * 4.5 * s, -1.0 * s), tray + Vector2(face * 4.5 * s, -1.0 * s),
		tray + Vector2(face * 3.0 * s, 4.0 * s), tray + Vector2(-face * 3.0 * s, 4.0 * s)]),
		Color(0.46, 0.33, 0.19))
	draw_line(tray + Vector2(-face * 3.0 * s, 4.0 * s), tray + Vector2(-face * 3.0 * s, 8.0 * s), Color(0.34, 0.24, 0.14), 1.4 * s)
	# Logs heaped in the tub.
	var logc := Color(0.50, 0.36, 0.20) if good != "stone" else Color(0.60, 0.60, 0.64)
	for i in range(3):
		var lx: float = tray.x + (float(i) - 1.0) * 2.4 * s
		draw_circle(Vector2(lx, tray.y - 1.6 * s), 1.7 * s, logc)
		draw_circle(Vector2(lx, tray.y - 1.6 * s), 0.7 * s, logc.lightened(0.25))
	# Handles back to the hands.
	var handle := Vector2(sx + face * 3.0 * s, j.hip.y + 1.0 * s)
	draw_line(handle, tray + Vector2(-face * 3.5 * s, 0.0), Color(0.40, 0.29, 0.17), 1.4 * s)
	_limb2(j.sh, handle, face * 0.8, skin, 1.7 * s)

func _draw_shouldered_tool(sx: float, sh: float, s: float, face: float, anim: String, style: Dictionary) -> void:
	match anim:
		"chop":
			draw_line(Vector2(sx - face * 2.0 * s, sh + 2.0 * s), Vector2(sx - face * 5.0 * s, sh - 6.0 * s), WOOD, 1.5 * s)
			draw_line(Vector2(sx - face * 5.0 * s, sh - 6.0 * s), Vector2(sx - face * 6.5 * s, sh - 5.0 * s), STEEL, 2.0 * s)
		"mine", "hammer":
			draw_line(Vector2(sx - face * 2.0 * s, sh + 2.0 * s), Vector2(sx - face * 5.0 * s, sh - 6.0 * s), WOOD, 1.5 * s)
			draw_arc(Vector2(sx - face * 5.0 * s, sh - 6.0 * s), 2.4 * s, PI * 0.7, PI * 1.6, 5, STEEL, 1.5 * s)
		"scythe":
			draw_line(Vector2(sx - face * 2.0 * s, sh + 2.0 * s), Vector2(sx - face * 5.5 * s, sh - 7.0 * s), WOOD, 1.5 * s)
			draw_arc(Vector2(sx - face * 5.5 * s, sh - 7.0 * s), 3.0 * s, 0, PI * 0.8, 6, STEEL, 1.4 * s)
		"pick", "carry":
			draw_rect(Rect2(sx - face * 3.6 * s - 2.0, sh - 1.0 * s, 4.0 * s, 4.5 * s), Color(0.6, 0.48, 0.28))
		"guard":
			draw_line(Vector2(sx + face * 2.0 * s, sh + 3.0 * s), Vector2(sx + face * 2.0 * s, sh - 9.0 * s), WOOD, 1.4 * s)
		_:
			pass
