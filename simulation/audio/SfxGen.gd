extends RefCounted
# Procedural sound effects — synthesised as short AudioStreamWAV buffers entirely in
# code, so the game has audio feedback WITHOUT shipping any binary sound assets (the
# repo stays text-only). Each effect is a brief, modest blip with a soft envelope so
# the feedback is pleasant, not fatiguing. AudioManager caches one stream per event.

const MIX: int = 22050   # plenty for short SFX; keeps buffers tiny

# Build the stream for a SoundEvent name (AudioManager passes SoundEvent.keys()[event]).
static func for_event(name: String) -> AudioStreamWAV:
	match name:
		"BUILDING_PLACED":     return _wood_thock()
		"BUILDING_DEMOLISHED": return _crumble()
		"UNIT_HIT":            return _tink()
		"UNIT_DEATH":          return _thud()
		"UNIT_KILLED":         return _thud()
		"SIEGE_INCOMING":      return _war_drum()
		"WEATHER_CHANGED":     return _airy()
		"POPULARITY_CRITICAL": return _alarm()
		"PRESTIGE_GAINED":     return _chime()
		"EDICT_ACTIVATED":     return _ding()
		_:                     return _ding()

# ── sample plumbing ──────────────────────────────────────────────────────────────
static func _new_wav(buf: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX
	w.stereo = false
	w.data = buf
	return w

static func _push(buf: PackedByteArray, s: float) -> void:
	var v: int = clampi(int(clampf(s, -1.0, 1.0) * 32767.0), -32768, 32767)
	buf.push_back(v & 0xFF)
	buf.push_back((v >> 8) & 0xFF)

# ── effects ──────────────────────────────────────────────────────────────────────
# A soft wooden knock — a building set down.
static func _wood_thock() -> AudioStreamWAV:
	var buf := PackedByteArray()
	var n: int = int(0.13 * MIX)
	for i in range(n):
		var t: float = float(i) / MIX
		var env: float = exp(-t * 26.0)
		var s: float = sin(TAU * 190.0 * t) + 0.5 * sin(TAU * 95.0 * t)
		_push(buf, s * env * 0.5)
	return _new_wav(buf)

# A descending crumble of noise — a building torn down.
static func _crumble() -> AudioStreamWAV:
	var buf := PackedByteArray()
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var n: int = int(0.32 * MIX)
	for i in range(n):
		var t: float = float(i) / MIX
		var env: float = exp(-t * 9.0)
		var s: float = rng.randf_range(-1.0, 1.0) * (0.6 + 0.4 * sin(TAU * 40.0 * t))
		_push(buf, s * env * 0.45)
	return _new_wav(buf)

# A short metallic tink — a blow lands.
static func _tink() -> AudioStreamWAV:
	var buf := PackedByteArray()
	var n: int = int(0.07 * MIX)
	for i in range(n):
		var t: float = float(i) / MIX
		var env: float = exp(-t * 55.0)
		var s: float = sin(TAU * 1180.0 * t) + 0.4 * sin(TAU * 1760.0 * t)
		_push(buf, s * env * 0.34)
	return _new_wav(buf)

# A low body-thud — a fighter falls.
static func _thud() -> AudioStreamWAV:
	var buf := PackedByteArray()
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	var n: int = int(0.20 * MIX)
	for i in range(n):
		var t: float = float(i) / MIX
		var env: float = exp(-t * 16.0)
		var s: float = sin(TAU * 90.0 * t) + 0.25 * rng.randf_range(-1.0, 1.0)
		_push(buf, s * env * 0.5)
	return _new_wav(buf)

# Two heavy low drum beats — a siege musters.
static func _war_drum() -> AudioStreamWAV:
	var buf := PackedByteArray()
	var total: int = int(0.5 * MIX)
	for i in range(total):
		var t: float = float(i) / MIX
		# Two strikes at t=0 and t=0.26.
		var e1: float = exp(-t * 12.0)
		var e2: float = exp(-maxf(t - 0.26, 0.0) * 12.0) if t >= 0.26 else 0.0
		var env: float = e1 + e2
		var s: float = sin(TAU * 72.0 * t)
		_push(buf, s * env * 0.5)
	return _new_wav(buf)

# A soft airy swell — the weather turns.
static func _airy() -> AudioStreamWAV:
	var buf := PackedByteArray()
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	var n: int = int(0.45 * MIX)
	for i in range(n):
		var t: float = float(i) / MIX
		var env: float = sin(PI * clampf(t / 0.45, 0.0, 1.0))   # gentle swell in/out
		var s: float = rng.randf_range(-1.0, 1.0) * 0.5 + 0.3 * sin(TAU * 320.0 * t)
		_push(buf, s * env * 0.22)
	return _new_wav(buf)

# A descending two-tone — popularity is dangerously low.
static func _alarm() -> AudioStreamWAV:
	var buf := PackedByteArray()
	var notes: Array = [440.0, 330.0]
	for f in notes:
		var n: int = int(0.16 * MIX)
		for i in range(n):
			var t: float = float(i) / MIX
			var env: float = exp(-t * 6.0)
			_push(buf, sin(TAU * float(f) * t) * env * 0.4)
	return _new_wav(buf)

# A bright rising chime — prestige earned / something good.
static func _chime() -> AudioStreamWAV:
	var buf := PackedByteArray()
	var notes: Array = [659.25, 880.0]   # E5 → A5
	for f in notes:
		var n: int = int(0.12 * MIX)
		for i in range(n):
			var t: float = float(i) / MIX
			var env: float = exp(-t * 7.0)
			var s: float = sin(TAU * float(f) * t) + 0.15 * sin(TAU * float(f) * 2.0 * t)
			_push(buf, s * env * 0.4)
	return _new_wav(buf)

# A short confirming ding — an edict is proclaimed.
static func _ding() -> AudioStreamWAV:
	var buf := PackedByteArray()
	var n: int = int(0.16 * MIX)
	for i in range(n):
		var t: float = float(i) / MIX
		var env: float = exp(-t * 9.0)
		var s: float = sin(TAU * 988.0 * t) + 0.2 * sin(TAU * 1976.0 * t)
		_push(buf, s * env * 0.4)
	return _new_wav(buf)
