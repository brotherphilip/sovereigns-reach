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
		"BUILDING_COMPLETED":  return _chime()
		"BUILDING_DEMOLISHED": return _crumble()
		"UNIT_HIT":            return _tink()
		"UNIT_DEATH":          return _thud()
		"UNIT_KILLED":         return _thud()
		"SIEGE_INCOMING":      return _war_drum()
		"WEATHER_CHANGED":     return _airy()
		"POPULARITY_CRITICAL": return _alarm()
		"PRESTIGE_GAINED":     return _chime()
		"EDICT_ACTIVATED":     return _ding()
		"UI_CLICK":            return _click()
		"WOOD_CHOP":           return _wood_chop()
		"HAMMER_HIT":          return _hammer_hit()
		"TREE_FALL":           return _tree_fall()
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
# A hollow "choonk thud" — an axe biting into a tree trunk: a sharp noisy bite at the
# front, over a low woody resonant body that drops a touch in pitch as it lands.
static func _wood_chop() -> AudioStreamWAV:
	var buf := PackedByteArray()
	var rng := RandomNumberGenerator.new(); rng.seed = 13
	var n: int = int(0.17 * MIX)
	for i in range(n):
		var t: float = float(i) / MIX
		# Axe cracking into the wood — a short noise transient, very fast decay.
		var bite: float = rng.randf_range(-1.0, 1.0) * exp(-t * 95.0) * 0.55
		# Hollow body resonance with a slight downward "thunk".
		var pitch: float = 180.0 - 45.0 * (1.0 - exp(-t * 14.0))
		var body_env: float = exp(-t * 21.0)
		var body: float = sin(TAU * pitch * t) + 0.45 * sin(TAU * pitch * 1.5 * t) + 0.28 * sin(TAU * pitch * 0.5 * t)
		_push(buf, (bite + body * body_env) * 0.5)
	return _new_wav(buf)

# Timber! A felled tree slamming the ground — a sharp splintering crack, a heavy low boom
# as the trunk lands, and a leafy rustle settling out. Played at the moment of impact.
static func _tree_fall() -> AudioStreamWAV:
	var buf := PackedByteArray()
	var rng := RandomNumberGenerator.new(); rng.seed = 41
	var n: int = int(0.55 * MIX)
	for i in range(n):
		var t: float = float(i) / MIX
		# Splintering crack at the very front (fast, bright noise transient).
		var crack: float = rng.randf_range(-1.0, 1.0) * exp(-t * 42.0) * 0.6
		# Heavy low boom of the trunk hitting the earth (two close low tones).
		var boom: float = sin(TAU * 56.0 * t) * exp(-t * 11.0)
		var boom2: float = 0.4 * sin(TAU * 37.0 * t) * exp(-t * 8.0)
		# Leafy rustle tail — soft noise that fades slower than the boom.
		var rustle: float = rng.randf_range(-1.0, 1.0) * (0.32 + 0.22 * sin(TAU * 28.0 * t)) * exp(-t * 5.0) * 0.4
		_push(buf, (crack + boom + boom2 + rustle) * 0.5)
	return _new_wav(buf)

# A builder's hammer landing on timber — a crisp knock with a short woody/iron ring.
# Higher and tighter than the axe's chop, so the two read apart in a busy yard.
static func _hammer_hit() -> AudioStreamWAV:
	var buf := PackedByteArray()
	var rng := RandomNumberGenerator.new(); rng.seed = 29
	var n: int = int(0.11 * MIX)
	for i in range(n):
		var t: float = float(i) / MIX
		# Sharp strike transient (the head landing).
		var bite: float = rng.randf_range(-1.0, 1.0) * exp(-t * 150.0) * 0.5
		# Short bright ring of the str+ timber.
		var ring: float = (sin(TAU * 330.0 * t) + 0.5 * sin(TAU * 540.0 * t) + 0.3 * sin(TAU * 800.0 * t)) * exp(-t * 34.0)
		_push(buf, (bite + ring * 0.4) * 0.5)
	return _new_wav(buf)

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

# A crisp, tiny click — a UI button press. Very short + quiet so it never fatigues.
static func _click() -> AudioStreamWAV:
	var buf := PackedByteArray()
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var n: int = int(0.028 * MIX)
	for i in range(n):
		var t: float = float(i) / MIX
		var env: float = exp(-t * 120.0)
		var s: float = sin(TAU * 1500.0 * t) + 0.5 * rng.randf_range(-1.0, 1.0)
		_push(buf, s * env * 0.5)
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
