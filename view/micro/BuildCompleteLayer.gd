extends Node2D
# A brief, satisfying "construction complete!" poof over a freshly-finished PLAYER building: an
# expanding golden ground-ring (the completion pulse), a puff of dust at the base, and a few sparks
# that rise and wink out — plus a soft chime (AudioManager BUILDING_COMPLETED).
#
# Detection is VIEW-side on purpose: it polls the player's buildings (~5×/sec) for one flipping to
# `built`, rather than having the simulation emit a signal. CitizenSystem (where construction finishes)
# is a plain RefCounted preloaded by the headless tests, and referencing an autoload like EventBus from
# it fails to compile in `--script` mode — so the sim stays autoload-free and the view watches instead.
# View-only and transient: each burst lives ~1s and the layer is idle when none are active.

const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const HALF_W: float = 32.0
const HALF_H: float = 16.0
const LIFE: float = 1.05
const POLL: float = 0.2

var _bursts: Array = []         # {pos: Vector2, age: float, seed: int}
var _seen: Dictionary = {}      # building id → true (already built; won't re-poof)
var _primed: bool = false       # after the first scan, only NEWLY-finished buildings poof
var _poll_accum: float = 0.0

func _ready() -> void:
	z_index = 2   # above the world + night wash, below the HUD CanvasLayer
	set_process(true)

func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum >= POLL:
		_poll_accum = 0.0
		_scan()
	if _bursts.is_empty():
		return
	var keep: Array = []
	for b in _bursts:
		b["age"] = float(b["age"]) + delta
		if float(b["age"]) < LIFE:
			keep.append(b)
	_bursts = keep
	queue_redraw()

func _scan() -> void:
	if GameState.players.is_empty():
		return
	for b in GameState.players[0].get("buildings", []):
		if not (b is Dictionary) or not b.get("built", false):
			continue
		var id: int = int(b.get("id", -1))
		if id < 0 or _seen.has(id):
			continue
		_seen[id] = true
		if _primed:   # don't poof everything that was already standing when we started watching
			_spawn(String(b.get("type", "")), int(b.get("grid_x", 0)), int(b.get("grid_y", 0)))
	_primed = true

# Dev hook (SR_BUILDDEMO): fire a burst at a tile without waiting for a real completion.
func dev_burst(gx: int, gy: int) -> void:
	_spawn("village_hall", gx, gy)

func _spawn(btype: String, gx: int, gy: int) -> void:
	var defn: Dictionary = BuildingRegistry.lookup(btype)
	var w: int = maxi(1, int(defn.get("width", 1)))
	var h: int = maxi(1, int(defn.get("height", 1)))
	var cx: float = (gx - gy) * HALF_W + (w - h) * 0.5 * HALF_W
	var cy: float = (gx + gy) * HALF_H + (w + h - 2) * 0.5 * HALF_H - 10.0
	_bursts.append({"pos": Vector2(cx, cy), "age": 0.0, "seed": (gx * 73 + gy * 31) % 997})
	AudioManager.play(AudioManager.SoundEvent.BUILDING_COMPLETED)
	queue_redraw()

func _draw() -> void:
	for b in _bursts:
		_draw_burst(b["pos"], float(b["age"]), int(b["seed"]))

func _draw_burst(c: Vector2, age: float, seed: int) -> void:
	var t: float = clampf(age / LIFE, 0.0, 1.0)
	# Expanding golden ground-ring (the completion pulse) + a softer inner ring just behind it.
	var ring_a: float = (1.0 - t) * 0.70
	if ring_a > 0.01:
		_draw_ring(c, 8.0 + 46.0 * _ease_out(t), Color(1.0, 0.86, 0.42, ring_a), 2.5 * (1.0 - 0.5 * t))
	_draw_ring(c, 4.0 + 30.0 * _ease_out(t), Color(1.0, 0.94, 0.70, (1.0 - t) * 0.32), 1.5)
	# Dust puff at the base — a few expanding tan blobs that settle.
	var dust_t: float = clampf(age / 0.6, 0.0, 1.0)
	var da: float = (1.0 - dust_t) * 0.5
	if da > 0.01:
		for i in range(3):
			var ox: float = (_h(seed, i) - 0.5) * 26.0 * dust_t
			var dr: float = (5.0 + 9.0 * dust_t) * (0.8 + 0.4 * _h(seed, i + 7))
			draw_circle(c + Vector2(ox, 6.0 - 3.0 * dust_t), dr, Color(0.85, 0.81, 0.72, da * 0.7))
	# Rising sparks — gold dots arc up and out, twinkling off.
	for i in range(6):
		var a: float = _h(seed, i + 13) * TAU
		var dist: float = (6.0 + 20.0 * t) * (0.6 + 0.6 * _h(seed, i + 19))
		var rise: float = -34.0 * t * (0.5 + 0.5 * _h(seed, i + 3))
		var sp: Vector2 = c + Vector2(cos(a) * dist, rise - absf(sin(a)) * 4.0)
		var sa: float = (1.0 - t) * (0.5 + 0.5 * sin(age * 26.0 + float(i)))
		if sa > 0.04:
			draw_circle(sp, 1.6 * (1.0 - 0.5 * t), Color(1.0, 0.92, 0.55, sa))

func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 2.2)

func _h(seed: int, i: int) -> float:
	var n: float = sin(float(seed) * 0.071 + float(i) * 12.9898) * 43758.5453
	return n - floor(n)

func _draw_ring(c: Vector2, radius: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var segs: int = 28
	for i in range(segs + 1):
		var a: float = TAU * float(i) / float(segs)
		pts.append(c + Vector2(cos(a) * radius, sin(a) * radius * 0.6))   # iso-squashed → a ground ring
	draw_polyline(pts, col, width)
