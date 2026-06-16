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

# A missing key must fail gracefully (null), so unknown events stay silent.
func _test_loader_is_robust() -> void:
	print("\n[Loader robustness]")
	ok("missing clip returns null (silent, no crash)", WavLoad.load_wav(DIR + "does_not_exist.wav") == null)
