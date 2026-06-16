extends SceneTree
# Verifies every tracked pop-up has a loadable narration clip, and the WAV loader works.
# Run: godot --headless --script tests/TestNarration.gd

const WavLoad        = preload("res://simulation/audio/WavLoad.gd")
const MilestoneSystem = preload("res://simulation/core/MilestoneSystem.gd")
const WorldEventSystem = preload("res://simulation/world/WorldEventSystem.gd")

const DIR := "res://audio/narration/"
var _pass := 0
var _fail := 0

func _init() -> void:
	_test_every_milestone_has_voice()
	_test_every_world_event_has_voice()
	_test_fixed_clips()
	_test_all_clips_have_signal()
	_test_loader_is_robust()
	print("\n=== Narration Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _loads(key: String) -> bool:
	var s = WavLoad.load_wav(DIR + key + ".wav")
	return s is AudioStreamWAV and s.data.size() > 0 and s.format == AudioStreamWAV.FORMAT_16_BITS

# Every milestone the game can award must have a matching narration clip (key parity).
func _test_every_milestone_has_voice() -> void:
	print("\n[Every milestone has a narration clip]")
	for mid in MilestoneSystem.DEFINITIONS.keys():
		ok("milestone_%s.wav loads" % mid, _loads("milestone_" + str(mid)))

# Every world event the realm can surface is a pop-up, so it must have a voice too
# (NarrationPlayer speaks event_<id> on EventBus.world_event). Key parity vs the content.
func _test_every_world_event_has_voice() -> void:
	print("\n[Every world event has a narration clip]")
	for ev in WorldEventSystem.EVENTS:
		var eid: String = str(ev.get("id", ""))
		ok("event_%s.wav loads" % eid, _loads("event_" + eid))

# The other fixed-trigger pop-ups.
func _test_fixed_clips() -> void:
	print("\n[Fixed-trigger clips]")
	ok("reign_day100.wav loads", _loads("reign_day100"))
	ok("siege_incoming.wav loads", _loads("siege_incoming"))
	# Generic stings for dynamic-text pop-ups (iter80).
	ok("edict_proclaimed.wav loads", _loads("edict_proclaimed"))
	ok("edict_lapsed.wav loads", _loads("edict_lapsed"))
	ok("objective_updated.wav loads", _loads("objective_updated"))
	ok("popularity_critical.wav loads", _loads("popularity_critical"))
	# Win/loss capstones (iter93).
	ok("kingdom_fallen.wav loads", _loads("kingdom_fallen"))
	ok("realm_fallen.wav loads", _loads("realm_fallen"))
	ok("victory.wav loads", _loads("victory"))
	ok("keep_fallen.wav loads", _loads("keep_fallen"))
	ok("unit_trained.wav loads", _loads("unit_trained"))
	ok("siege_held.wav loads", _loads("siege_held"))
	ok("siege_breached.wav loads", _loads("siege_breached"))
	ok("game_saved.wav loads", _loads("game_saved"))
	ok("game_loaded.wav loads", _loads("game_loaded"))

# Peak absolute 16-bit sample amplitude (0..32768) — 0 ≈ silence, a real voice clip peaks high.
func _peak16(s: AudioStreamWAV) -> int:
	var data: PackedByteArray = s.data
	var peak: int = 0
	var n: int = data.size()
	var i: int = 0
	while i + 1 < n:
		var v: int = data[i] | (data[i + 1] << 8)
		if v >= 32768:
			v -= 65536
		var a: int = absi(v)
		if a > peak:
			peak = a
		i += 2
	return peak

# Every shipped clip must contain ACTUAL audio, not just a valid-but-silent WAV — a guard
# against a broken/garbled render pipeline (the clips can't be auditioned headlessly).
const _SIGNAL_FLOOR: int = 800   # real takes peak in the thousands; silence ≈ 0
func _test_all_clips_have_signal() -> void:
	print("\n[Every clip carries real audio signal]")
	var dir := DirAccess.open(DIR)
	if dir == null:
		ok("narration dir opens", false)
		return
	var checked: int = 0
	var silent: Array = []
	for f in dir.get_files():
		if not f.ends_with(".wav"):
			continue
		checked += 1
		var s = WavLoad.load_wav(DIR + f)
		if not (s is AudioStreamWAV) or _peak16(s) < _SIGNAL_FLOOR:
			silent.append(f)
	ok("found a healthy set of clips to check (>= 60)", checked >= 60)
	ok("no silent/empty clips among %d (silent: %s)" % [checked, str(silent)], silent.is_empty())

# A missing key must fail gracefully (null), so unknown events stay silent.
func _test_loader_is_robust() -> void:
	print("\n[Loader robustness]")
	ok("missing clip returns null (silent, no crash)", WavLoad.load_wav(DIR + "does_not_exist.wav") == null)
