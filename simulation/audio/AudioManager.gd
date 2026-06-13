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
	EDICT_ACTIVATED
}

var _audio_prev_hp: Dictionary = {}

func play(event: SoundEvent) -> void:
	var player_name = SoundEvent.keys()[event]
	var player = get_node_or_null(player_name)
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = player_name
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

	EventBus.connect("prestige_changed", func(_player_id, _old_value, _new_value):
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
