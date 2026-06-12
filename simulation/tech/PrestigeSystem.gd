extends RefCounted
# GDD §4.1 — Prestige Economy
# Prestige is earned over time via diverse economy and spent on the tech tree.
# PopularityEngine.get_prestige_multiplier() provides the popularity-based multiplier.

# Base prestige per game-day from maintaining a functional economy
const BASE_PRESTIGE_PER_DAY: float = 5.0

# Bonus prestige per game-day per distinct food type in stock (GDD §4.1.1)
const FOOD_VARIETY_BONUS: float = 2.0

# Prestige bonus per high-tier building category (buildings with max_workers > 0, tier 3+)
const HIGH_TIER_BUILDING_BONUS: float = 1.0

# How much prestige is deducted when a defeat event fires (siege loss, etc.)
const DEFEAT_PRESTIGE_LOSS: float = 50.0

# ── Earning ─────────────────────────────────────────────────────────────────

# Calculates the prestige generated this game-day.
# Returns float delta to add to player.prestige.
static func calculate_daily_prestige(player: Dictionary, world: Dictionary) -> float:
	if not player.get("is_alive", true):
		return 0.0
	# Starvation stalls prestige generation
	if player.get("is_starving", false):
		return 0.0

	var base: float = BASE_PRESTIGE_PER_DAY
	# Food variety bonus (GDD §4.1.1)
	var food: Dictionary = player.get("food", {})
	var variety: int = 0
	for v in food.values():
		if v > 0:
			variety += 1
	base += float(variety) * FOOD_VARIETY_BONUS

	# High-tier building bonus (each active building with workers assigned)
	for building in player.get("buildings", []):
		if not building is Dictionary or not building.get("is_active", true):
			continue
		if building.get("workers", 0) > 0 and building.get("max_workers", 0) >= 2:
			base += HIGH_TIER_BUILDING_BONUS

	# Apply popularity multiplier (high popularity grants multiplier from PopularityEngine)
	var pop_score: float = player.get("popularity", 50.0)
	var multiplier: float = _popularity_multiplier(pop_score)

	# Apply capital prestige multiplier from shire
	multiplier += _capital_multiplier(player, world)

	return base * multiplier

# Tick function: call at day boundary. Updates player.prestige and player.prestige_per_tick.
static func tick(player: Dictionary, world: Dictionary, tick: int) -> Dictionary:
	if tick == 0 or tick % 240 != 0:
		return {}
	var delta: float = calculate_daily_prestige(player, world)
	var old_prestige: float = player.get("prestige", 0.0)
	player["prestige"] = old_prestige + delta
	player["prestige_per_tick"] = delta / 240.0
	return {"old_prestige": old_prestige, "new_prestige": player["prestige"], "delta": delta}

# ── Spending ────────────────────────────────────────────────────────────────

# Returns true if the player can afford the given prestige cost.
static func can_afford(player: Dictionary, cost: float) -> bool:
	return player.get("prestige", 0.0) >= cost

# Deducts prestige. Returns true if successful.
static func spend(player: Dictionary, amount: float) -> bool:
	if not can_afford(player, amount):
		return false
	player["prestige"] = maxf(0.0, player.get("prestige", 0.0) - amount)
	return true

# ── Events ───────────────────────────────────────────────────────────────────

# Apply prestige loss from defeat events (siege loss, village burned).
static func apply_defeat_loss(player: Dictionary) -> float:
	var loss: float = DEFEAT_PRESTIGE_LOSS
	player["prestige"] = maxf(0.0, player.get("prestige", 0.0) - loss)
	return loss

# ── Helpers ──────────────────────────────────────────────────────────────────

static func _popularity_multiplier(popularity: float) -> float:
	if popularity >= 80.0:
		return 1.5
	elif popularity >= 60.0:
		return 1.2
	elif popularity >= 40.0:
		return 1.0
	elif popularity >= 20.0:
		return 0.7
	else:
		return 0.3  # Severely stalled but not zero (unlike PopularityEngine which returns 0.0)

static func _capital_multiplier(player: Dictionary, world: Dictionary) -> float:
	var shire_id: int = player.get("shire_id", -1)
	if shire_id < 0:
		return 0.0
	for shire in world.get("shires", []):
		if shire.get("id", -1) == shire_id:
			var level: int = shire.get("capital_level", 0)
			return float(level) * 0.1  # Each capital level adds 10% prestige multiplier
	return 0.0
