extends Node
# Autoload singleton. The single source of truth for ALL game state.

const WeatherSystem  = preload("res://simulation/world/WeatherSystem.gd")
const PopularityEngine = preload("res://simulation/economy/PopularityEngine.gd")
const ResourceTick   = preload("res://simulation/economy/ResourceTick.gd")
# All fields are plain Dictionary/Array/int/float/bool — JSON-serializable.
# Never stores Godot objects (Vector2, Node, etc.) to ensure network/save readiness.
# The View layer reads from here; it never writes here directly.

var world: Dictionary = {}
var players: Array = []        # Array[Dictionary]
var ai_factions: Array = []    # Array[Dictionary]
var weather: Dictionary = {}
var active_edicts: Array = []  # Array[Dictionary]
var server_config: Dictionary = {}
var milestones: Dictionary = {}

# Phase 2 simulation subsystems (instantiated in _init_default_state)
var _weather_rng: RandomNumberGenerator = null

func _ready() -> void:
	_init_default_state()

func _init_default_state() -> void:
	server_config = {
		"version": 1,
		"tick_rate": SimulationClock.TICK_RATE,
		"map_width": 200,
		"map_height": 200,
		"max_players": 8,
		"difficulty": 1,
		"map_seed": 12345,
	}
	_weather_rng = RandomNumberGenerator.new()
	_weather_rng.seed = server_config["map_seed"]
	weather = WeatherSystem.make_state()
	milestones = {}

# --- Player initialization ---

func initialize_player(player_id: int, player_name: String, start_x: int, start_y: int) -> void:
	while players.size() <= player_id:
		players.append({})
	players[player_id] = _make_player(player_id, player_name, start_x, start_y)

func _make_player(player_id: int, player_name: String, start_x: int, start_y: int) -> Dictionary:
	return {
		"id": player_id,
		"name": player_name,
		"is_alive": true,

		# Economy
		"gold": 200,
		"popularity": 50,        # 0–100; peasants revolt below ~20
		"prestige": 0,
		"prestige_per_tick": 0.0,

		# Sliders (GDD §3 — Popularity Engine inputs)
		"tax_rate": 0,           # -3 (bribe) to +3 (heavy tax)
		"food_ration": 2,        # 0=none, 1=low, 2=normal, 3=extra, 4=double
		"ale_ration": 1,         # 0=none to 4=double

		# Position (stored as plain ints, not Vector2i, for JSON safety)
		"keep_x": start_x,
		"keep_y": start_y,
		"shire_id": -1,

		# Raw material stockpile
		"resources": _make_resources(),

		# Processed food stores (tracked separately for granary logic)
		"food": _make_food_stores(),

		# Military
		"buildings": [],         # Array of building IDs (ints)
		"units": [],             # Array of unit IDs (ints)
		"armory": _make_armory(),

		# Progression
		"tech_unlocks": [],
		"active_edicts": [],
		"edict_points": 0,

		# Vision
		"fog_of_war": {},        # "x,y" -> true for revealed tiles

		# Metrics
		"total_kills": 0,
		"sieges_survived": 0,
	}

func _make_resources() -> Dictionary:
	return {
		"wood": 100,
		"stone": 0,
		"iron": 0,
		"pitch": 0,
		"hops": 0,
		"wheat": 0,
		"flour": 0,
		"leather": 0,
	}

func _make_food_stores() -> Dictionary:
	return {
		"apples": 50,
		"cheese": 0,
		"meat": 0,
		"bread": 0,
		"ale": 0,
	}

func _make_armory() -> Dictionary:
	return {
		"bows": 0,
		"crossbows": 0,
		"pikes": 0,
		"swords": 0,
		"leather_armor": 0,
		"plate_armor": 0,
	}

func _tick_player_economy(player: Dictionary, tick: int) -> void:
	# Collect current weather effects as events for popularity calculation
	var events: Array = []
	var weather_pop_delta: float = WeatherSystem.get_popularity_delta(weather)
	if weather_pop_delta != 0:
		# Map weather effect to event string for popularity engine
		match weather["current"]:
			WeatherSystem.WeatherType.SNOW:     events.append("blizzard")
			WeatherSystem.WeatherType.DROUGHT:  events.append("drought")
			WeatherSystem.WeatherType.STORM:    events.append("blizzard")
			WeatherSystem.WeatherType.RAIN:     pass  # handled via multiplier

	# Tick all buildings for resource production
	for building in player.get("buildings", []):
		if not building is Dictionary:
			continue
		var changes: Dictionary = ResourceTick.tick_building(building, player, tick)
		if not changes.is_empty():
			ResourceTick.apply_changes(player, changes)

	# Food consumption on game-day boundaries
	var food_changes: Dictionary = ResourceTick.tick_food_consumption(player, tick)
	if not food_changes.is_empty():
		ResourceTick.apply_changes(player, food_changes)

	# Popularity update on game-day boundaries
	if tick % SimulationClock.TICKS_PER_GAME_DAY == 0:
		var old_pop: float = player.get("popularity", 50)
		var new_pop: float = PopularityEngine.apply_tick(player, events)
		if old_pop != new_pop:
			EventBus.popularity_changed.emit(player["id"], old_pop, new_pop)

		# Daily tax collection
		_collect_taxes(player)

func _collect_taxes(player: Dictionary) -> void:
	var tax_rate: int = player.get("tax_rate", 0)
	if tax_rate == 0:
		return
	var population: int = player.get("population", 0)
	# Gold per peasant per day based on tax rate
	var gold_per_peasant: float = abs(tax_rate) * 0.5
	var delta: int = int(population * gold_per_peasant)
	var old_gold: int = player.get("gold", 0)
	if tax_rate > 0:
		player["gold"] = old_gold + delta
	else:
		player["gold"] = maxi(0, old_gold - delta)  # Bribe costs gold
	if player["gold"] != old_gold:
		EventBus.gold_changed.emit(player["id"], old_gold, player["gold"])

# --- Command dispatch ---
# apply_command is called by SimulationClock._advance_tick() for every
# command dequeued from CommandQueue. Each handler returns bool success.

func apply_command(command: Dictionary) -> void:
	var success: bool = false
	match command["type"]:
		CommandQueue.CommandType.SET_TAX_RATE:
			success = _cmd_set_tax_rate(command)
		CommandQueue.CommandType.SET_RATION_FOOD:
			success = _cmd_set_food_ration(command)
		CommandQueue.CommandType.SET_RATION_ALE:
			success = _cmd_set_ale_ration(command)
		CommandQueue.CommandType.SET_GAME_SPEED:
			success = _cmd_set_game_speed(command)
		CommandQueue.CommandType.TOGGLE_VIEW_MODE:
			success = _cmd_toggle_view_mode(command)
		CommandQueue.CommandType.ROTATE_VIEW:
			success = _cmd_rotate_view(command)
		CommandQueue.CommandType.SAVE_GAME:
			EventBus.save_requested.emit()
			success = true
		_:
			success = true  # Future phases add more handlers
	EventBus.command_processed.emit(command, success)

# Phase 2: economy + weather tick
func simulate_tick(tick: int) -> void:
	# Tick weather (only processes when ticks_remaining reaches 0)
	var weather_event: Dictionary = WeatherSystem.tick(weather, _weather_rng)
	if not weather_event.is_empty():
		EventBus.weather_changed.emit(
			WeatherSystem.weather_name(weather_event["new_weather"]),
			weather_event["duration_ticks"]
		)

	# Tick each player's economy
	for player in players:
		if not player.get("is_alive", false):
			continue
		_tick_player_economy(player, tick)

# --- Command handlers ---

func _cmd_set_tax_rate(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var rate: int = clampi(cmd["payload"].get("rate", 0), -3, 3)
	players[pid]["tax_rate"] = rate
	return true

func _cmd_set_food_ration(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var level: int = clampi(cmd["payload"].get("level", 2), 0, 4)
	players[pid]["food_ration"] = level
	return true

func _cmd_set_ale_ration(cmd: Dictionary) -> bool:
	var pid: int = cmd["player_id"]
	if not _valid_player(pid):
		return false
	var level: int = clampi(cmd["payload"].get("level", 1), 0, 4)
	players[pid]["ale_ration"] = level
	return true

func _cmd_set_game_speed(cmd: Dictionary) -> bool:
	var speed: int = cmd["payload"].get("speed", SimulationClock.SPEED_NORMAL)
	SimulationClock.set_speed(speed)
	return true

func _cmd_toggle_view_mode(cmd: Dictionary) -> bool:
	var mode: String = cmd["payload"].get("mode", "micro")
	EventBus.view_mode_changed.emit(mode)
	return true

func _cmd_rotate_view(cmd: Dictionary) -> bool:
	var rotation_index: int = cmd["payload"].get("rotation_index", 0)
	EventBus.view_rotated.emit(rotation_index)
	return true

# --- Accessors ---

func get_player(player_id: int) -> Dictionary:
	if _valid_player(player_id):
		return players[player_id]
	return {}

func get_resource(player_id: int, resource: String) -> int:
	if not _valid_player(player_id):
		return 0
	return players[player_id]["resources"].get(resource, 0)

func get_food(player_id: int, food_type: String) -> int:
	if not _valid_player(player_id):
		return 0
	return players[player_id]["food"].get(food_type, 0)

func _valid_player(pid: int) -> bool:
	return pid >= 0 and pid < players.size() and not players[pid].is_empty()

# --- Serialization ---

func serialize() -> Dictionary:
	return {
		"version": 1,
		"world": world.duplicate(true),
		"players": players.duplicate(true),
		"ai_factions": ai_factions.duplicate(true),
		"weather": weather.duplicate(true),
		"active_edicts": active_edicts.duplicate(true),
		"server_config": server_config.duplicate(true),
		"milestones": milestones.duplicate(true),
		"clock": SimulationClock.serialize(),
	}

func deserialize(data: Dictionary) -> void:
	world = data.get("world", {})
	players = data.get("players", [])
	ai_factions = data.get("ai_factions", [])
	weather = data.get("weather", {})
	active_edicts = data.get("active_edicts", [])
	server_config = data.get("server_config", {})
	milestones = data.get("milestones", {})
	if data.has("clock"):
		SimulationClock.deserialize(data["clock"])
