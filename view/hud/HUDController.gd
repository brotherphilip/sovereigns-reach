extends RefCounted
# GDD §2.2.5 / §3 — HUD data extraction and command generation.
# All static functions read from player/world Dicts; no autoload calls here.
# Runtime instance (Node subclass) wraps these for EventBus signal connections.
# "No logic here — view reads state only." Commands are issued via CommandQueue.

# Popularity tier thresholds matching PopularityEngine (GDD §3.5)
const TIER_REVOLT:    float = 20.0
const TIER_POOR:      float = 40.0
const TIER_FAIR:      float = 60.0
const TIER_GOOD:      float = 80.0

# Ration level labels (GDD §3.1.1)
const RATION_LABELS: Array = ["None", "Half", "Normal", "Extra", "Double"]
const TAX_LABELS: Array    = ["Bribe ×3", "Bribe ×2", "Bribe ×1", "Free", "Tax ×1", "Tax ×2", "Tax ×3"]

# ── Data extraction (pure static, testable) ───────────────────────────────────

# Returns a complete HUD data dict for a player state dict + weather + tick.
static func get_hud_data(player: Dictionary, weather: Dictionary, current_tick: int) -> Dictionary:
	var pop: float = player.get("popularity", 50.0)
	return {
		"gold": player.get("gold", 0),
		"prestige": player.get("prestige", 0),
		"popularity": pop,
		"popularity_tier": get_popularity_tier(pop),
		"popularity_color": get_popularity_color(get_popularity_tier(pop)),
		"tax_rate": player.get("tax_rate", 0),
		"tax_label": get_tax_label(player.get("tax_rate", 0)),
		"food_ration": player.get("food_ration", 2),
		"food_ration_label": get_ration_label(player.get("food_ration", 2)),
		"ale_ration": player.get("ale_ration", 1),
		"ale_ration_label": get_ration_label(player.get("ale_ration", 1)),
		"population": player.get("population", 0),
		"military_strength": player.get("military_strength", 0),
		"food_total": get_total_food(player),
		"is_starving": player.get("is_starving", false),
		"weather_name": weather.get("current_name", "Clear"),
		"weather_popularity_delta": weather.get("popularity_delta", 0.0),
		"game_day": current_tick / 240,
		"edict_points": player.get("edict_points", 0),
		"inn_coverage": player.get("inn_coverage", 0.0),
		"religion_coverage": player.get("religion_coverage", 0.0),
	}

# Returns the popularity tier string from a popularity float.
static func get_popularity_tier(pop: float) -> String:
	if pop < TIER_REVOLT: return "revolt"
	if pop < TIER_POOR:   return "poor"
	if pop < TIER_FAIR:   return "fair"
	if pop < TIER_GOOD:   return "good"
	return "excellent"

# Returns a CSS-style hex color string for the given popularity tier.
static func get_popularity_color(tier: String) -> String:
	match tier:
		"revolt":    return "#e94560"
		"poor":      return "#ff9800"
		"fair":      return "#ffd700"
		"good":      return "#8bc34a"
		"excellent": return "#4caf50"
	return "#888888"

# Returns the display label for a ration level (0–4).
static func get_ration_label(level: int) -> String:
	if level < 0 or level >= RATION_LABELS.size():
		return "?"
	return RATION_LABELS[level]

# Returns the display label for a tax rate (-3 to +3).
static func get_tax_label(rate: int) -> String:
	var idx: int = clampi(rate + 3, 0, TAX_LABELS.size() - 1)
	return TAX_LABELS[idx]

# Returns the total food across all food types.
static func get_total_food(player: Dictionary) -> int:
	var total: int = 0
	for key in player.get("food", {}):
		total += int(player["food"][key])
	return total

# Returns the resource summary dict for the HUD resource bar.
static func get_resource_summary(player: Dictionary) -> Dictionary:
	return player.get("resources", {}).duplicate()

# Returns true if the player is at revolt risk (popularity below threshold).
static func is_revolt_risk(player: Dictionary) -> bool:
	return player.get("popularity", 50.0) < TIER_REVOLT

# Returns formatted time string from ticks (e.g. "Day 5, Tick 120").
static func format_tick_time(tick: int) -> String:
	var day: int = tick / 240
	var t_in_day: int = tick % 240
	return "Day %d (%d/240)" % [day, t_in_day]
