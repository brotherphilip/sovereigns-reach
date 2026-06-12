extends RefCounted
# GDD §3.4 — Taxation
# Centralizes all gold collection logic that was previously in GameState._collect_taxes().
# Called at day boundaries (tick % 240 == 0).

# Gold collected per peasant per day per tax level (magnitude)
const GOLD_PER_PEASANT_LEVEL: float = 0.5

# Returns the gold delta for one game-day.
# Positive = gold collected; negative = bribe paid.
# Incorporates shire tax modifier if shire data is available.
static func calculate_daily_gold(player: Dictionary, world: Dictionary) -> int:
	var tax_rate: int = player.get("tax_rate", 0)
	if tax_rate == 0:
		return 0

	var population: int = player.get("population", 0)
	var gold_per_peasant: float = abs(tax_rate) * GOLD_PER_PEASANT_LEVEL
	var base_delta: int = int(float(population) * gold_per_peasant)

	# Apply shire tax rate modifier if player is in a shire
	var modifier: float = _get_shire_tax_modifier(player, world)
	base_delta = int(float(base_delta) * (1.0 + modifier))

	return base_delta if tax_rate > 0 else -base_delta

# Applies the daily gold calculation to the player dict. Call at tick%240==0.
# Returns dict with "old_gold", "new_gold", "delta".
static func tick(player: Dictionary, world: Dictionary, tick: int) -> Dictionary:
	if tick == 0 or tick % 240 != 0:
		return {}

	var delta: int = calculate_daily_gold(player, world)
	if delta == 0:
		return {}

	var old_gold: int = player.get("gold", 0)
	player["gold"] = maxi(0, old_gold + delta)
	return {"old_gold": old_gold, "new_gold": player["gold"], "delta": delta}

# Returns the shire tax rate modifier (-0.3 to +0.3) based on shire biome.
static func _get_shire_tax_modifier(player: Dictionary, world: Dictionary) -> float:
	var shire_id: int = player.get("shire_id", -1)
	if shire_id < 0:
		return 0.0
	for shire in world.get("shires", []):
		if shire.get("id", -1) == shire_id:
			return shire.get("tax_rate_modifier", 0.0)
	return 0.0
