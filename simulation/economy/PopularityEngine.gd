extends RefCounted
# Calculates the Popularity Engine formula from GDD §3:
#
#   P = ΔF + ΔA + ΔR − T ± E
#
# ΔF  = Food score    (ration quantity × food variety bonus)
# ΔA  = Ale score     (inn coverage × ration setting)
# ΔR  = Religion score (church/cathedral radius coverage)
# T   = Tax burden    (-3 to +3 slider scaled to popularity delta)
# E   = External events (sieges, disease, weather, edicts)
#
# Popularity is clamped to [0, 100].
# Below 20: peasant desertion risk (GDD §3.5.1 mentions mid-battle desertion)
# Above 80: prestige bonus multiplier

# Food ration multipliers (GDD §3.1.1)
const FOOD_RATION_POPULARITY: Dictionary = {
	0: -15,  # No rations — starvation
	1: -5,   # Low rations
	2: 0,    # Normal rations (neutral)
	3: 5,    # Extra rations
	4: 10,   # Double rations
}

# Ale ration multipliers (GDD §3.2.3)
const ALE_RATION_POPULARITY: Dictionary = {
	0: -8,   # No ale
	1: 0,    # Low (neutral)
	2: 5,    # Normal
	3: 10,   # Extra
	4: 16,   # Double — huge boost
}

# Food variety bonuses (GDD §3.1.2) — each food type present adds to score
const FOOD_VARIETY_BONUS: Dictionary = {
	"apples": 2,
	"cheese": 3,
	"meat":   5,
	"bread":  8,
}

# Tax rate popularity deltas (GDD §3.4.1)
const TAX_POPULARITY_DELTA: Dictionary = {
	-3: 10,   # Bribe — costly but loved
	-2: 6,
	-1: 3,
	0:  0,    # Neutral
	1: -3,
	2: -6,
	3: -12,   # Heavy tax — deeply unpopular
}

# External event modifiers (GDD §3.5)
const EVENT_POPULARITY_DELTA: Dictionary = {
	"active_siege":       -12,  # Being attacked
	"disease_outbreak":   -10,
	"blizzard":           -5,
	"storm":              -2,
	"rain":               -1,
	"drought":            -3,
	"festival":           +8,   # Royal Edict bonus (fired via instant_event)
	"wedding_event":      +4,   # Church random event
}

# Returns the full popularity delta for one game-day tick.
# Does NOT modify player state — caller applies the result.
static func calculate_delta(player: Dictionary, events: Array) -> float:
	var food_score: float    = _food_score(player)
	var ale_score: float     = _ale_score(player)
	var religion_score: float = player.get("religion_coverage", 0.0) * 10.0
	var tax_delta: float     = TAX_POPULARITY_DELTA.get(player.get("tax_rate", 0), 0)
	var event_delta: float   = _event_delta(events)

	# TAX_POPULARITY_DELTA already encodes sign: negative for positive tax rates, positive for bribes.
	# The GDD formula P = ΔF + ΔA + ΔR − T ± E treats T as a burden; here tax_delta IS that signed value.
	return food_score + ale_score + religion_score + tax_delta + event_delta

static func _food_score(player: Dictionary) -> float:
	var ration_level: int = player.get("food_ration", 2)
	var base: float = FOOD_RATION_POPULARITY.get(ration_level, 0)

	# Variety bonus — GDD §3.1.2: multiple food types stack
	var food: Dictionary = player.get("food", {})
	var variety_bonus: float = 0.0
	for food_type in FOOD_VARIETY_BONUS:
		if food.get(food_type, 0) > 0:
			variety_bonus += FOOD_VARIETY_BONUS[food_type]

	# Starvation override — if no food AT ALL, ignore ration level
	var total_food: int = 0
	for f in food.values():
		total_food += f
	if total_food <= 0:
		return -20.0  # Hard starvation penalty

	return base + variety_bonus

static func _ale_score(player: Dictionary) -> float:
	var ration: int = player.get("ale_ration", 1)
	var base: float = ALE_RATION_POPULARITY.get(ration, 0)
	# Inn coverage scales the ale effect (0.0–1.0 coverage ratio)
	var coverage: float = player.get("inn_coverage", 0.0)
	return base * coverage

static func _event_delta(events: Array) -> float:
	var total: float = 0.0
	for event in events:
		total += EVENT_POPULARITY_DELTA.get(event, 0.0)
	return total

# Apply popularity delta to a player dictionary (mutates in place).
# Returns the new popularity value.
static func apply_tick(player: Dictionary, events: Array) -> float:
	var delta: float = calculate_delta(player, events)
	var new_pop: float = clampf(player.get("popularity", 50) + delta * 0.05, 0.0, 100.0)
	player["popularity"] = new_pop
	return new_pop

# Check if the player is at desertion risk (GDD §3.5.1)
static func is_desertion_risk(player: Dictionary) -> bool:
	return player.get("popularity", 50) < 20.0

# Prestige multiplier from high popularity (GDD §4.1.3)
static func get_prestige_multiplier(player: Dictionary) -> float:
	var pop: float = player.get("popularity", 50)
	if pop >= 80:
		return 1.5
	elif pop >= 60:
		return 1.2
	elif pop >= 40:
		return 1.0
	elif pop >= 20:
		return 0.7
	else:
		return 0.0  # Stalled prestige during crisis
