extends Node

enum SoundEvent {
	BUILDING_PLACED,
	BUILDING_DEMOLISHED,
	UNIT_KILLED,
	UNIT_HIT,
	UNIT_DEATH,
	SIEGE_INCOMING,
	WEATHER_CHANGED,
	POPULARITY_CRITICAL,
	PRESTIGE_GAINED,
	EDICT_ACTIVATED,
	UI_CLICK,         # keep existing values stable
	WOOD_CHOP,        # axe biting a tree
	HAMMER_HIT,       # builder's hammer on timber
	TREE_FALL         # appended last — a felled tree slamming the ground (played positionally)
}

const SfxGen = preload("res://simulation/audio/SfxGen.gd")

var _audio_prev_hp: Dictionary = {}
# Per-event tuning: gain (dB) and a min gap (sec) so frequent events don't machine-gun.
const _GAIN_DB: Dictionary = {
	"UNIT_HIT": -10.0, "UNIT_DEATH": -7.0, "UNIT_KILLED": -7.0,
	"BUILDING_PLACED": -5.0, "BUILDING_DEMOLISHED": -6.0, "WEATHER_CHANGED": -9.0,
	"SIEGE_INCOMING": -3.0, "POPULARITY_CRITICAL": -4.0, "PRESTIGE_GAINED": -6.0,
	"EDICT_ACTIVATED": -5.0, "UI_CLICK": -16.0, "WOOD_CHOP": -9.0, "HAMMER_HIT": -10.0,
	"TREE_FALL": -6.0,
}
const _MIN_GAP: Dictionary = {"UNIT_HIT": 0.12, "UNIT_DEATH": 0.10, "UNIT_KILLED": 0.10, "UI_CLICK": 0.04, "WOOD_CHOP": 0.14}
var _last_play: Dictionary = {}

func play(event: SoundEvent) -> void:
	var player_name = SoundEvent.keys()[event]
	# Throttle high-frequency events (e.g. a flurry of hits) so audio doesn't buzz.
	var gap: float = float(_MIN_GAP.get(player_name, 0.0))
	if gap > 0.0:
		var now: float = float(Time.get_ticks_msec()) / 1000.0
		if now - float(_last_play.get(player_name, -999.0)) < gap:
			return
		_last_play[player_name] = now
	var player = get_node_or_null(player_name)
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = player_name
		# Synthesize the effect once and cache it on the player (zero asset files).
		player.stream = SfxGen.for_event(player_name)
		player.volume_db = float(_GAIN_DB.get(player_name, -6.0))
		# Route to the SFX bus (player-controllable, separate from Music/Master) when it exists.
		if AudioServer.get_bus_index("SFX") >= 0:
			player.bus = "SFX"
		add_child(player)

	if player.stream != null:
		player.play()

func _check_combat_sounds() -> void:
	var all_units: Array = []
	for player in GameState.players:
		if player is Dictionary:
			all_units.append_array(player.get("units", []))
	for fac in GameState.ai_factions:
		if fac is Dictionary:
			all_units.append_array(fac.get("units", []))
	var got_hit: bool = false
	var got_death: bool = false
	for unit in all_units:
		if not unit is Dictionary: continue
		var uid: int = unit.get("id", -1)
		if uid < 0: continue
		var cur_hp: int = int(unit.get("hp", 0))
		if _audio_prev_hp.has(uid):
			if cur_hp < _audio_prev_hp[uid]:
				if unit.get("is_alive", false):
					got_hit = true
				else:
					got_death = true
		_audio_prev_hp[uid] = cur_hp
	if got_hit:
		play(SoundEvent.UNIT_HIT)
	if got_death:
		play(SoundEvent.UNIT_DEATH)

func _ready():
	# Connect all the real EventBus signals
	EventBus.connect("building_placed", func(_player_id, _building_type, _grid_x, _grid_y, _building_id):
		play(SoundEvent.BUILDING_PLACED)
	)

	EventBus.connect("building_demolished", func(_player_id, _building_id):
		play(SoundEvent.BUILDING_DEMOLISHED)
	)

	EventBus.connect("weather_changed", func(_new_weather, _duration_ticks):
		play(SoundEvent.WEATHER_CHANGED)
	)

	EventBus.connect("edict_activated", func(_player_id, _edict_id, _duration_ticks):
		play(SoundEvent.EDICT_ACTIVATED)
	)

	EventBus.connect("popularity_changed", func(_player_id, _old_value, _new_value):
		if _new_value < 20:
			play(SoundEvent.POPULARITY_CRITICAL)
	)

	# Prestige drips in every game-day, which made the cue beep once per day (annoying).
	# Only sound a real, earned jump (milestones/edicts/events ≈ +10 or more), not the drip.
	EventBus.connect("prestige_changed", func(_player_id, old_value, new_value):
		if new_value - old_value >= 10.0:
			play(SoundEvent.PRESTIGE_GAINED)
	)

	EventBus.connect("unit_killed", func(_unit_id, _killer_id, _cause):
		play(SoundEvent.UNIT_KILLED)
	)

	EventBus.connect("ai_siege_assembling", func(_faction_id, _target_player_id, _eta_ticks):
		play(SoundEvent.SIEGE_INCOMING)
	)

	EventBus.connect("simulation_tick", func(_tick):
		_check_combat_sounds()
	)

	# Give EVERY button a click, everywhere, without touching each call site: watch the
	# tree for new BaseButtons and wire their `pressed` to a soft UI click. Autoloads
	# ready before any scene, so node_added catches the whole UI as it's built.
	get_tree().node_added.connect(_wire_button_click)
	for n in get_tree().root.get_children():
		_wire_button_click(n)   # catch anything already present

func _wire_button_click(node: Node) -> void:
	if node is BaseButton and not node.pressed.is_connected(_on_ui_button_pressed):
		node.pressed.connect(_on_ui_button_pressed)

func _on_ui_button_pressed() -> void:
	play(SoundEvent.UI_CLICK)
