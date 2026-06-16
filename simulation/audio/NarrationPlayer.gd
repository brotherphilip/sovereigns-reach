extends Node
# Spoken narration ("grim war herald" voice) for the game's key pop-ups. When a tracked
# event fires, the matching clip in res://audio/narration/<key>.wav is played. Clips are
# pre-rendered (Vocalis/Chatterbox + herald post-FX) and loaded at runtime via WavLoad,
# so the set grows by simply dropping in more files — no code change, no import step.
#
# Trigger → key mapping:
#   milestone_earned(id)        → milestone_<id>
#   sovereign_reign_reached     → reign_day100
#   ai_siege_assembling         → siege_incoming
#   world_event(data.id)        → event_<id>      (silent until those files are added)

const WavLoad = preload("res://simulation/audio/WavLoad.gd")
const DIR := "res://audio/narration/"

var _player: AudioStreamPlayer
var _cache: Dictionary = {}

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "NarrationVoice"
	_player.volume_db = -1.0
	add_child(_player)
	if EventBus.has_signal("milestone_earned"):
		EventBus.milestone_earned.connect(func(_pid, id, _bonus): say("milestone_" + str(id)))
	if EventBus.has_signal("sovereign_reign_reached"):
		EventBus.sovereign_reign_reached.connect(func(_day): say("reign_day100"))
	if EventBus.has_signal("ai_siege_assembling"):
		EventBus.ai_siege_assembling.connect(func(_f, _t, _e): say("siege_incoming"))
	if EventBus.has_signal("world_event"):
		EventBus.world_event.connect(func(data): say("event_" + str(data.get("id", ""))))

# Speak a narration key. Latest line wins (a new one cuts off any still playing, so two
# heralds never talk over each other). Unknown/missing keys are silently ignored.
func say(key: String) -> void:
	var stream: AudioStream = _stream_for(key)
	if stream == null:
		return
	_player.stream = stream
	_player.play()

func _stream_for(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	var s: AudioStream = WavLoad.load_wav(DIR + key + ".wav")
	_cache[key] = s
	return s
