extends RefCounted
# GDD §3.1 — Food Variables (ΔF)
# Manages granary capacity, food distribution, variety tracking, and spoilage.
# ResourceTick handles production; FoodSystem handles storage and consumption accounting.

# Food drain multipliers per ration level (units of food consumed per peasant per day)
const DifficultySystem = preload("res://simulation/core/DifficultySystem.gd")
const TechTree         = preload("res://simulation/tech/TechTree.gd")
const EdictSystem      = preload("res://simulation/edicts/EdictSystem.gd")

const FOOD_DRAIN_PER_PEASANT: Dictionary = {
	0: 0.0,    # No rations — starvation risk (zero drain because no food issued)
	1: 0.5,    # Low rations
	2: 1.0,    # Normal
	3: 1.5,    # Extra
	4: 2.0,    # Double
}

# Order in which food types are consumed (cheapest first — GDD §3.1.2)
const FOOD_CONSUMPTION_ORDER: Array = ["apples", "bread", "cheese", "meat"]

# Returns the total food units a player has across all food types
static func get_total_food(player: Dictionary) -> int:
	var total: int = 0
	for v in player.get("food", {}).values():
		total += maxi(0, v)
	return total

# Returns the player's total granary storage capacity (sum across all granary buildings)
static func get_granary_capacity(player: Dictionary) -> int:
	var cap: int = 0
	for building in player.get("buildings", []):
		if not building is Dictionary:
			continue
		if building.get("type", "") == "granary" and building.get("is_active", true):
			cap += building.get("storage_max", 0)
	if cap == 0:
		cap = 200  # default capacity even without a granary
	var granary_bonus: float = TechTree.get_all_modifiers(player).get("granary_capacity_bonus", 0.0) + EdictSystem.get_active_modifiers(player).get("granary_capacity_bonus", 0.0)
	if granary_bonus > 0.0:
		cap = int(ceil(float(cap) * (1.0 + granary_bonus)))
	return cap

# Applies food consumption at a day boundary.
# Deducts food from granary in FOOD_CONSUMPTION_ORDER.
# Returns a dict with "food_consumed", "food_shortage", "starving" keys.
static func tick(player: Dictionary, tick: int) -> Dictionary:
	if tick == 0 or tick % 240 != 0:
		return {}

	var ration: int = player.get("food_ration", 2)
	var population: int = player.get("population", 0)
	var drain_per_cap: float = FOOD_DRAIN_PER_PEASANT.get(ration, 1.0)
	var total_to_consume: int = int(float(population) * drain_per_cap * DifficultySystem.get_mod("food_consumption"))

	if total_to_consume <= 0:
		# Zero rations: trigger starvation flag but no food deducted
		if ration == 0 and population > 0:
			player["is_starving"] = true
		return {"food_consumed": 0, "food_shortage": 0, "starving": ration == 0 and population > 0}

	var remaining: int = total_to_consume
	var food: Dictionary = player.get("food", {})
	for ftype in FOOD_CONSUMPTION_ORDER:
		if remaining <= 0:
			break
		var stock: int = food.get(ftype, 0)
		if stock <= 0:
			continue
		var take: int = mini(stock, remaining)
		food[ftype] = stock - take
		remaining -= take

	var shortage: int = remaining  # Food we couldn't provide
	var starving: bool = shortage > 0 or get_total_food(player) <= 0
	player["is_starving"] = starving

	return {
		"food_consumed": total_to_consume - shortage,
		"food_shortage": shortage,
		"starving": starving,
	}

# Enforces granary cap: any food above capacity is discarded (spoilage).
# Call after production tick.
static func apply_granary_cap(player: Dictionary) -> void:
	var cap: int = get_granary_capacity(player)
	var food: Dictionary = player.get("food", {})
	var total: int = get_total_food(player)
	if total <= cap:
		return
	# Spill the cheapest food types first
	var overflow: int = total - cap
	for ftype in FOOD_CONSUMPTION_ORDER:
		if overflow <= 0:
			break
		var stock: int = food.get(ftype, 0)
		var spill: int = mini(stock, overflow)
		food[ftype] = stock - spill
		overflow -= spill

# Returns how many distinct food types the player has in stock (for variety bonus calculation)
static func get_food_variety_count(player: Dictionary) -> int:
	var count: int = 0
	for v in player.get("food", {}).values():
		if v > 0:
			count += 1
	return count
