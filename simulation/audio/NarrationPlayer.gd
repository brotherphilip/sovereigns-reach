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
#   edict_activated             → edict_proclaimed     (generic sting; edict name is dynamic)
#   edict_expired               → edict_lapsed
#   objective_updated           → objective_updated     (generic; the goal text is dynamic)
#   popularity_changed (<crit)  → popularity_critical   (edge-triggered with hysteresis)
#   popularity_changed (<10)    → realm_fallen          (once; the revolt defeat capstone)
#   ai_faction_defeated         → kingdom_fallen, or victory if it was the LAST rival
#   building_destroyed (seat)   → keep_fallen           (the player's hall/keep razed = defeat)
#   unit_spawned (player unit)  → unit_trained          (a soldier finishes training)
#   ai_siege_struck             → siege_held / siege_breached  (by the defended flag)
#   save_completed / load_completed → game_saved / game_loaded  (the realm's chronicle)
#   TutorialSystem.tutorial_hint    → tutorial_hint        (generic; the onboarding text is dynamic)

const WavLoad = preload("res://simulation/audio/WavLoad.gd")
const DIR := "res://audio/narration/"

# Popularity VO alert: fire once when it crosses DOWN past _POP_CRIT, and don't re-arm
# until it recovers past _POP_SAFE — so a hovering-low popularity doesn't nag every tick.
const _POP_CRIT := 20.0
const _POP_SAFE := 25.0

var _player: AudioStreamPlayer
var _cache: Dictionary = {}
var _pop_low := false
var _realm_fallen_said := false  # the revolt defeat line fires at most once

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
	if EventBus.has_signal("edict_activated"):
		EventBus.edict_activated.connect(func(_pid, _eid, _dur): say("edict_proclaimed"))
	if EventBus.has_signal("edict_expired"):
		EventBus.edict_expired.connect(func(_pid, _eid): say("edict_lapsed"))
	if EventBus.has_signal("objective_updated"):
		EventBus.objective_updated.connect(func(_i, _t, _txt): say("objective_updated"))
	if EventBus.has_signal("popularity_changed"):
		EventBus.popularity_changed.connect(_on_popularity_changed)
	if EventBus.has_signal("ai_faction_defeated"):
		EventBus.ai_faction_defeated.connect(_on_ai_faction_defeated)
	if EventBus.has_signal("building_destroyed"):
		EventBus.building_destroyed.connect(_on_building_destroyed)
	if EventBus.has_signal("unit_spawned"):
		EventBus.unit_spawned.connect(func(unit): if unit is Dictionary and int(unit.get("owner_id", -1)) == 0: say("unit_trained"))
	if EventBus.has_signal("ai_siege_struck"):
		EventBus.ai_siege_struck.connect(func(_f, _t, defended, _d): say("siege_held" if defended else "siege_breached"))
	if EventBus.has_signal("save_completed"):
		EventBus.save_completed.connect(func(_path): say("game_saved"))
	if EventBus.has_signal("load_completed"):
		EventBus.load_completed.connect(func(success): if success: say("game_loaded"))
	# TutorialSystem loads AFTER us (see project.godot autoload order), so its node isn't in the
	# tree yet — defer the hookup. Its hint TEXT is dynamic, so (like edicts/objectives) a single
	# generic instructional sting voices every onboarding pop-up: welcome, defence warning, etc.
	call_deferred("_connect_tutorial")

func _connect_tutorial() -> void:
	var ts = get_node_or_null("/root/TutorialSystem")
	if ts != null and ts.has_signal("tutorial_hint"):
		ts.tutorial_hint.connect(_on_tutorial_hint)

# Tutorial pop-ups carry dynamic text, so play the clip that actually READS this hint
# (matched by a stable keyword) rather than a generic sting. Falls back to the generic
# tutorial_hint clip if a hint isn't recognised.
const _TUTORIAL_VO: Array = [
	["Welcome, commander",         "tut_hall"],
	["Your Village Hall stands",   "tut_farm"],
	["Now store your food",        "tut_granary"],
	["Grow your population",       "tut_housing"],
	["Trade with your neighbours", "tut_market"],
	["Guard your people's health", "tut_apothecary"],
	["Raise a fighting force",     "tut_barracks"],
	["Fortify your seat",          "tut_defense"],
	["ceasefire ends",             "tut_defense"],
	["Issue an Edict",             "tut_edict"],
	["Research new advances",      "tut_research"],
	["Tutorial complete",          "tut_done"],
	["demanding tribute",          "tut_tribute"],
	["Approval is critically low", "tut_low_pop"],
	["outbreak is spreading",      "tut_disease"],
]

func _on_tutorial_hint(msg: String) -> void:
	for pair in _TUTORIAL_VO:
		if String(msg).find(String(pair[0])) != -1:
			say(String(pair[1]))
			return
	say("tutorial_hint")  # fallback for any unrecognised hint

# The player's seat (Village Hall / Keep) was razed — that's the run-ending defeat. Only the
# human player's seat speaks (not an AI's), and only the seat (not every lost building).
func _on_building_destroyed(player_id: int, building_id: int, _cause: String) -> void:
	if player_id != 0:
		return
	var gs = get_node_or_null("/root/GameState")
	if gs == null or gs.players.size() == 0:
		return
	for b in gs.players[0].get("buildings", []):
		if b is Dictionary and int(b.get("id", -1)) == building_id:
			if String(b.get("type", "")) in ["village_hall", "keep"]:
				say("keep_fallen")
			return

# A rival kingdom fell. If it was the LAST one, that's outright victory; otherwise it's
# one more enemy crown broken.
func _on_ai_faction_defeated(_faction_id: int) -> void:
	var gs = get_node_or_null("/root/GameState")
	var any_alive := false
	if gs != null:
		for fac in gs.ai_factions:
			if fac is Dictionary and fac.get("is_alive", false):
				any_alive = true
				break
	say("victory" if (gs != null and not any_alive and gs.ai_factions.size() > 0) else "kingdom_fallen")

# Popularity dipped: warn once on the downward crossing, re-arm only after recovery.
# At the revolt floor (<10) the realm falls — speak the defeat capstone once.
func _on_popularity_changed(_pid: int, _old: float, new_value: float) -> void:
	if not _pop_low and new_value < _POP_CRIT:
		_pop_low = true
		say("popularity_critical")
	elif _pop_low and new_value >= _POP_SAFE:
		_pop_low = false
	if not _realm_fallen_said and new_value < 10.0:
		_realm_fallen_said = true
		say("realm_fallen")

# Speak a narration key. Latest line wins (a new one cuts off any still playing, so two
# heralds never talk over each other). Unknown/missing keys are silently ignored.
func say(key: String) -> void:
	var stream: AudioStream = _stream_for(key)
	if stream == null:
		return
	_player.stream = stream
	_player.play()

# True while the herald is actively speaking — MusicPlayer polls this to duck the music bed
# under narration so the voice stays clear.
func is_speaking() -> bool:
	return _player != null and _player.playing

func _stream_for(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	var s: AudioStream = WavLoad.load_wav(DIR + key + ".wav")
	_cache[key] = s
	return s
