extends SceneTree
# Proof harness for procedural SFX (SfxGen) + AudioManager wiring.
# Run: godot --headless --script tests/TestAudio.gd

const SfxGen = preload("res://simulation/audio/SfxGen.gd")
# Mirrors AudioManager.SoundEvent (preloading AudioManager here would drag in the
# GameState/EventBus autoload globals, which aren't compile-time identifiers under
# --script). Keep this list in sync with the enum.
const EVENT_NAMES: Array = [
	"BUILDING_PLACED", "BUILDING_DEMOLISHED", "UNIT_KILLED", "UNIT_HIT", "UNIT_DEATH",
	"SIEGE_INCOMING", "WEATHER_CHANGED", "POPULARITY_CRITICAL", "PRESTIGE_GAINED", "EDICT_ACTIVATED",
	"UI_CLICK",
]

var _pass := 0
var _fail := 0

func _init() -> void:
	_test_every_event_synthesizes()
	_test_streams_are_audible()
	print("\n=== Audio Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

# Every SoundEvent must produce a well-formed 16-bit mono WAV of a sane length.
func _test_every_event_synthesizes() -> void:
	print("\n[Every SoundEvent synthesizes a valid stream]")
	var keys: Array = EVENT_NAMES
	ok("there are SoundEvents to cover", keys.size() >= 8)
	for name in keys:
		var w = SfxGen.for_event(name)
		var is_wav: bool = w is AudioStreamWAV
		ok("%s → AudioStreamWAV" % name, is_wav)
		if not is_wav:
			continue
		ok("%s is 16-bit mono" % name, w.format == AudioStreamWAV.FORMAT_16_BITS and not w.stereo)
		var bytes: int = w.data.size()
		# 16-bit → even byte count; sane SFX length (≈0.02s..1.0s).
		var samples: int = bytes / 2
		var dur: float = float(samples) / float(w.mix_rate)
		ok("%s has even, sane-length PCM (%.2fs)" % [name, dur], bytes > 0 and bytes % 2 == 0 and dur > 0.02 and dur < 1.0)

# An unknown event still returns a usable fallback (never null).
func _test_streams_are_audible() -> void:
	print("\n[Streams carry real signal + safe fallback]")
	var w = SfxGen.for_event("PRESTIGE_GAINED")
	# Confirm the buffer isn't pure silence — at least one sample well off zero.
	var loud: bool = false
	var data: PackedByteArray = w.data
	for i in range(0, data.size() - 1, 2):
		var lo: int = data[i]
		var hi: int = data[i + 1]
		var v: int = lo | (hi << 8)
		if v >= 32768:
			v -= 65536            # interpret as signed int16
		if abs(v) > 2000:
			loud = true
			break
	ok("a synthesized chime carries real signal (not silence)", loud)
	var fb = SfxGen.for_event("NOT_A_REAL_EVENT")
	ok("unknown event falls back to a valid stream (never null)", fb is AudioStreamWAV and fb.data.size() > 0)
