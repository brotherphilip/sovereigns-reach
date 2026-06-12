extends RefCounted
# Models the weather system from GDD §1.1.3.
# Weather affects movement speed, crop yields, popularity, and army logistics.
# State is stored in GameState.weather (plain Dictionary).

enum WeatherType {
	CLEAR   = 0,
	RAIN    = 1,
	DROUGHT = 2,
	SNOW    = 3,
	FOG     = 4,
	STORM   = 5,  # Severe rain + lightning (fire risk)
}

# Minimum and maximum duration in game days per weather event
const WEATHER_DURATIONS: Dictionary = {
	WeatherType.CLEAR:   {"min": 3,  "max": 10},
	WeatherType.RAIN:    {"min": 1,  "max": 4},
	WeatherType.DROUGHT: {"min": 5,  "max": 14},
	WeatherType.SNOW:    {"min": 2,  "max": 7},
	WeatherType.FOG:     {"min": 1,  "max": 2},
	WeatherType.STORM:   {"min": 1,  "max": 3},
}

# Transition probability table [current] -> {next: weight}
# Weights are relative — higher = more likely
const WEATHER_TRANSITIONS: Dictionary = {
	WeatherType.CLEAR:   {WeatherType.CLEAR: 50, WeatherType.RAIN: 25, WeatherType.FOG: 10, WeatherType.DROUGHT: 10, WeatherType.SNOW: 5},
	WeatherType.RAIN:    {WeatherType.CLEAR: 40, WeatherType.RAIN: 30, WeatherType.STORM: 20, WeatherType.FOG: 10},
	WeatherType.DROUGHT: {WeatherType.DROUGHT: 30, WeatherType.CLEAR: 50, WeatherType.RAIN: 20},
	WeatherType.SNOW:    {WeatherType.SNOW: 30, WeatherType.CLEAR: 40, WeatherType.RAIN: 20, WeatherType.FOG: 10},
	WeatherType.FOG:     {WeatherType.CLEAR: 60, WeatherType.RAIN: 30, WeatherType.FOG: 10},
	WeatherType.STORM:   {WeatherType.RAIN: 40, WeatherType.CLEAR: 40, WeatherType.STORM: 20},
}

# Effects per weather type
# movement_penalty: fraction of base speed (0.0 = blocked, 1.0 = normal)
# farm_yield_mult: multiplier on crop production
# food_drain_per_day: extra food units consumed per peasant
# popularity_delta: daily popularity change
# fog_army_ui: whether the macro map army UI is hidden (GDD §1.1.3)
# fire_risk: extra fire chance per turn (for storm lightning)
const WEATHER_EFFECTS: Dictionary = {
	WeatherType.CLEAR:   {
		"movement_penalty": 1.0, "farm_yield_mult": 1.0,
		"food_drain": 0.0, "popularity_delta": 0,
		"fog_army_ui": false, "fire_risk": 0.0,
	},
	WeatherType.RAIN:    {
		"movement_penalty": 0.7, "farm_yield_mult": 1.1,
		"food_drain": 0.0, "popularity_delta": -1,
		"fog_army_ui": false, "fire_risk": 0.0,
	},
	WeatherType.DROUGHT: {
		"movement_penalty": 1.0, "farm_yield_mult": 0.0,  # Kills wheat
		"food_drain": 0.5, "popularity_delta": -3,
		"fog_army_ui": false, "fire_risk": 0.02,
	},
	WeatherType.SNOW:    {
		"movement_penalty": 0.5, "farm_yield_mult": 0.0,
		"food_drain": 2.0, "popularity_delta": -5,  # Snow drains food (GDD §1.1.3)
		"fog_army_ui": false, "fire_risk": 0.0,
	},
	WeatherType.FOG:     {
		"movement_penalty": 0.8, "farm_yield_mult": 1.0,
		"food_drain": 0.0, "popularity_delta": 0,
		"fog_army_ui": true,   # Fog hides army UI (GDD §1.1.3)
		"fire_risk": 0.0,
	},
	WeatherType.STORM:   {
		"movement_penalty": 0.4, "farm_yield_mult": 0.5,
		"food_drain": 0.5, "popularity_delta": -2,
		"fog_army_ui": false, "fire_risk": 0.05,
	},
}

# Initializes a fresh weather state dictionary
static func make_state(rng: RandomNumberGenerator = null) -> Dictionary:
	return {
		"current": WeatherType.CLEAR,
		"duration_ticks": 240 * 5,  # Starts with 5 clear days
		"ticks_remaining": 240 * 5,
		"effects": WEATHER_EFFECTS[WeatherType.CLEAR].duplicate(),
		"is_army_ui_hidden": false,
	}

# Advance weather by one tick. Returns a weather_changed event dict if
# the weather transitioned, or empty dict if no change.
static func tick(weather: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	weather["ticks_remaining"] -= 1
	if weather["ticks_remaining"] > 0:
		return {}
	return _transition(weather, rng)

static func _transition(weather: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var current: int = weather["current"]
	var transitions: Dictionary = WEATHER_TRANSITIONS.get(current, {})

	# Weighted random selection
	var total_weight: int = 0
	for w in transitions.values():
		total_weight += w
	var roll: int = rng.randi_range(0, total_weight - 1)
	var cumulative: int = 0
	var next_weather: int = WeatherType.CLEAR
	for weather_type in transitions:
		cumulative += transitions[weather_type]
		if roll < cumulative:
			next_weather = weather_type
			break

	var durations: Dictionary = WEATHER_DURATIONS.get(next_weather, {"min": 3, "max": 5})
	var days: int = rng.randi_range(durations["min"], durations["max"])
	var duration_ticks: int = days * 240

	var old_weather: int = weather["current"]
	weather["current"] = next_weather
	weather["duration_ticks"] = duration_ticks
	weather["ticks_remaining"] = duration_ticks
	weather["effects"] = WEATHER_EFFECTS[next_weather].duplicate()
	weather["is_army_ui_hidden"] = WEATHER_EFFECTS[next_weather]["fog_army_ui"]

	return {
		"event": "weather_changed",
		"old_weather": old_weather,
		"new_weather": next_weather,
		"duration_ticks": duration_ticks,
	}

# Get current movement penalty (1.0 = full speed, 0.5 = half speed)
static func get_movement_penalty(weather: Dictionary) -> float:
	return weather.get("effects", {}).get("movement_penalty", 1.0)

# Get current farm yield multiplier
static func get_farm_yield_mult(weather: Dictionary) -> float:
	return weather.get("effects", {}).get("farm_yield_mult", 1.0)

# Get daily popularity delta from weather
static func get_popularity_delta(weather: Dictionary) -> float:
	return weather.get("effects", {}).get("popularity_delta", 0.0)

# Get extra food drain per peasant per day
static func get_food_drain(weather: Dictionary) -> float:
	return weather.get("effects", {}).get("food_drain", 0.0)

# Returns human-readable name
static func weather_name(weather_type: int) -> String:
	match weather_type:
		WeatherType.CLEAR:   return "Clear"
		WeatherType.RAIN:    return "Rain"
		WeatherType.DROUGHT: return "Drought"
		WeatherType.SNOW:    return "Snow"
		WeatherType.FOG:     return "Fog"
		WeatherType.STORM:   return "Storm"
		_: return "Unknown"
