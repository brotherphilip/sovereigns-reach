extends RefCounted
const WeatherSystem = preload("res://simulation/world/WeatherSystem.gd")
const SeasonSystem  = preload("res://simulation/world/SeasonSystem.gd")

# Day/night phase + seasonal calendar for the HUD clock. Phase is the time of day
# (Day/Dusk/Night/Dawn); season/year/day key off the day/night calendar so they agree.
static func get_day_phase(tick: int) -> Dictionary:
	var phase: String = SeasonSystem.phase_name(tick)
	var icon: String = {"Day": "☀", "Dusk": "🌆", "Night": "🌙", "Dawn": "🌅"}.get(phase, "☀")
	return {
		"phase": phase,
		"icon": icon,
		"season": SeasonSystem.season_name(SeasonSystem.season_at_tick(tick)),
		"year": SeasonSystem.year_of(tick) + 1,
		"day_in_year": SeasonSystem.sky_day_in_year(tick) + 1,
		"days_per_year": SeasonSystem.SKY_DAYS_PER_YEAR,
	}
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
		"weather_name": WeatherSystem.weather_name(weather.get("current", 0)),
		"weather_popularity_delta": weather.get("effects", {}).get("popularity_delta", 0.0),
		"game_day": current_tick / 240,
		"edict_points": player.get("edict_points", 0),
		"inn_coverage": player.get("inn_coverage", 0.0),
		"religion_coverage": player.get("religion_coverage", 0.0),
		"faith": player.get("faith", 0.0),
		"faith_cap": player.get("faith_cap", 0.0),
		"blessing_active": int(player.get("blessing_until", 0)) > current_tick,
		"health": player.get("health", 100.0),
		"disease_active": player.get("disease_active", false),
		"disease_severity": player.get("disease_severity", 0.0),
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

# Honest descriptor for the ale-ration row's popularity effect.
# Ale only sways popularity once an Inn is actually serving it (inn_coverage > 0),
# and even then level 1 ("Low") is the neutral baseline (base 0) — so labelling the
# default as "½ bonus" with no inn was doubly misleading. Returns {text, tone}
# where tone is "good" | "bad" | "neutral" (HUD maps tone → colour).
static func get_ale_ration_effect(ale_ration: int, inn_coverage: float) -> Dictionary:
	const ALE_POP: Dictionary = {0: -8, 1: 0, 2: 5, 3: 10, 4: 16}
	if inn_coverage <= 0.001:
		return {"text": "no inn", "tone": "neutral"}
	var base: int = int(ALE_POP.get(ale_ration, 0))
	if base < 0:
		return {"text": "↓pop", "tone": "bad"}
	elif base == 0:
		return {"text": "neutral", "tone": "neutral"}
	return {"text": "↑pop", "tone": "good"}

# Returns the display label for a tax rate (-3 to +3).
static func get_tax_label(rate: int) -> String:
	var idx: int = clampi(rate + 3, 0, TAX_LABELS.size() - 1)
	return TAX_LABELS[idx]

# Returns the total food across all food types (ale excluded — shown separately).
static func get_total_food(player: Dictionary) -> int:
	var total: int = 0
	var food: Dictionary = player.get("food", {})
	for key in ["apples", "bread", "cheese", "meat"]:
		total += int(food.get(key, 0))
	return total

# Returns the resource summary dict for the HUD resource bar.
static func get_resource_summary(player: Dictionary) -> Dictionary:
	return player.get("resources", {}).duplicate()

# Returns true if the player is at revolt risk (popularity below threshold).
static func is_revolt_risk(player: Dictionary) -> bool:
	return player.get("popularity", 50.0) < TIER_REVOLT

# Returns Array of resource name strings that are critically low.
static func get_critical_resources(player: Dictionary) -> Array:
	var crit: Array = []
	var res: Dictionary = player.get("resources", {})
	if int(player.get("gold", 0)) < 50:    crit.append("gold")
	if int(res.get("wood",  0)) < 50:      crit.append("wood")
	if int(res.get("stone", 0)) < 20:      crit.append("stone")
	if int(res.get("iron",  0)) < 10:      crit.append("iron")
	if get_total_food(player) < 30:        crit.append("food")
	return crit

# Returns the total food variety popularity bonus (mirrors PopularityEngine §3.1.2).
static func get_food_variety_bonus(player: Dictionary) -> int:
	const VARIETY: Dictionary = {"apples": 2, "cheese": 3, "meat": 5, "bread": 8}
	var food: Dictionary = player.get("food", {})
	var total: int = 0
	for ft in VARIETY:
		if int(food.get(ft, 0)) > 0:
			total += VARIETY[ft]
	return total

# Returns list of food type names currently contributing a variety bonus.
static func get_food_variety_types(player: Dictionary) -> Array:
	const VARIETY: Dictionary = {"apples": 2, "cheese": 3, "meat": 5, "bread": 8}
	var food: Dictionary = player.get("food", {})
	var types: Array = []
	for ft in VARIETY:
		if int(food.get(ft, 0)) > 0:
			types.append(ft)
	return types

# Returns ↑ / ↓ / → trend arrow for a market resource vs its base price.
static func get_market_trend(resource: String, world: Dictionary) -> String:
	const BASE: Dictionary = {
		"wood": 3, "stone": 5, "iron": 8, "pitch": 6, "hops": 4,
		"wheat": 3, "flour": 5, "leather": 7, "apples": 2, "cheese": 4,
		"meat": 6, "bread": 5, "ale": 8, "bows": 12, "pikes": 10, "swords": 18,
	}
	var prices: Dictionary = world.get("market_prices", {})
	if not prices.has(resource) or not BASE.has(resource):
		return "→"
	var cur: int = int(prices[resource])
	var base: int = BASE[resource]
	if cur > int(float(base) * 1.1): return "↑"
	if cur < int(float(base) * 0.9): return "↓"
	return "→"

# Returns current buy and sell price strings for a market resource.
static func get_market_prices(resource: String, world: Dictionary) -> Dictionary:
	var prices: Dictionary = world.get("market_prices", {})
	var base_price: int = int(prices.get(resource, 0))
	if base_price == 0:
		return {"buy": "?", "sell": "?"}
	return {
		"buy":  "%dg" % ceili(float(base_price) * 1.2),
		"sell": "%dg" % base_price,
	}

# Returns formatted time string from ticks (e.g. "Day 5, Tick 120").
static func format_tick_time(tick: int) -> String:
	var day: int = tick / 240
	var t_in_day: int = tick % 240
	return "Day %d (%d/240)" % [day, t_in_day]

# Returns a multi-line tooltip showing market price history for a resource (last ≤5 snapshots).
static func get_market_history_tooltip(resource: String, world: Dictionary) -> String:
	var history: Array = world.get("market_price_history", {}).get(resource, [])
	if history.is_empty():
		return "No price history yet (updates every 10 days)"
	var bars: String = ""
	var base: int = {"wood":3,"stone":5,"iron":8,"pitch":6,"hops":4,"wheat":3,"flour":5,
		"leather":7,"apples":2,"cheese":4,"meat":6,"bread":5,"ale":8,"bows":12,"pikes":10,"swords":18
		}.get(resource, 1)
	for p in history:
		var ratio: float = float(p) / float(base)
		bars += "▲" if ratio > 1.05 else ("▼" if ratio < 0.95 else "─")
		bars += "%dg " % p
	return "Price history (oldest→newest):\n  %s" % bars.strip_edges()

# Returns a multi-line tooltip breaking down each popularity component.
static func get_popularity_breakdown_tooltip(player: Dictionary) -> String:
	const FOOD_POP: Dictionary = {0: -15, 1: -5, 2: 0, 3: 5, 4: 10}
	const ALE_POP:  Dictionary = {0: -8,  1: 0,  2: 5, 3: 10, 4: 16}
	const TAX_POP:  Dictionary = {-3: 10, -2: 6, -1: 3, 0: 0, 1: -3, 2: -6, 3: -12}
	const VARIETY:  Dictionary = {"apples": 2, "cheese": 3, "meat": 5, "bread": 8}
	var food_ration: int = player.get("food_ration", 2)
	var ale_ration:  int = player.get("ale_ration", 1)
	var tax_rate:    int = player.get("tax_rate", 0)
	var religion:    float = player.get("religion_coverage", 0.0) * 10.0
	var food_delta:  int = FOOD_POP.get(food_ration, 0)
	var ale_delta:   float = float(ALE_POP.get(ale_ration, 0)) * player.get("inn_coverage", 0.0)
	var tax_delta:   int = TAX_POP.get(tax_rate, 0)
	var variety_bonus: int = 0
	var food: Dictionary = player.get("food", {})
	for ft in VARIETY:
		if int(food.get(ft, 0)) > 0:
			variety_bonus += VARIETY[ft]
	var total: float = float(food_delta + variety_bonus + tax_delta) + ale_delta + religion
	var lines: Array = [
		"Popularity components (daily):",
		"  ΔFood ration:  %+d" % food_delta,
		"  ΔFood variety: %+d" % variety_bonus,
		"  ΔAle ration:   %+.0f" % ale_delta,
		"  ΔReligion:     %+.0f" % religion,
		"  ΔTax:          %+d" % tax_delta,
		"  ─────────────────",
		"  Net/day:       %+.0f" % total,
	]
	return "\n".join(lines)

# Returns a multi-line tooltip showing daily gold income/expense breakdown.
static func get_gold_tooltip(player: Dictionary, world: Dictionary) -> String:
	var tax_rate: int  = player.get("tax_rate", 0)
	var population: int = player.get("population", 0)
	var lines: Array = ["Gold per day (approx):"]
	if tax_rate == 0:
		lines.append("  Tax: 0 g/day (no tax)")
	else:
		var daily: int = int(float(population) * abs(tax_rate) * 0.5)
		if tax_rate > 0:
			lines.append("  Tax income: +%d g/day" % daily)
		else:
			lines.append("  Bribe cost:  -%d g/day" % daily)
	lines.append("  Population: %d" % population)
	return "\n".join(lines)

# Returns a text icon for the current weather type.
static func get_weather_icon(weather: Dictionary) -> String:
	const ICONS: Dictionary = {0: "☼", 1: "~", 2: "△", 3: "*", 4: "≈", 5: "!"}
	return ICONS.get(weather.get("current", 0), "?")

# Returns a tooltip string describing the active weather effects.
static func get_weather_tooltip(weather: Dictionary) -> String:
	var effects: Dictionary = weather.get("effects", {})
	var pop: float  = effects.get("popularity_delta", 0.0)
	var food: float = effects.get("food_drain", 0.0)
	var speed: float = effects.get("movement_penalty", 1.0)
	var farm: float = effects.get("farm_yield_mult", 1.0)
	var lines: Array = ["Weather: %s" % WeatherSystem.weather_name(weather.get("current", 0))]
	if pop != 0.0:
		lines.append("Popularity: %+.0f/day" % pop)
	if food != 0.0:
		lines.append("Extra food drain: %.1f/day" % food)
	if speed != 1.0:
		lines.append("Movement speed: ×%.1f" % speed)
	if farm != 1.0:
		lines.append("Farm yield: ×%.1f" % farm)
	if lines.size() == 1:
		lines.append("No ill effects")
	return "\n".join(lines)

# Returns a tooltip string explaining the tax rate's popularity impact.
static func get_tax_tooltip(tax_rate: int) -> String:
	const POP_DELTA: Dictionary = {-3: 10, -2: 6, -1: 3, 0: 0, 1: -3, 2: -6, 3: -12}
	const LABELS: Dictionary = {
		-3: "Bribe ×3 — heavily subsidised",
		-2: "Bribe ×2 — generous subsidy",
		-1: "Bribe ×1 — small subsidy",
		0:  "Free — no tax collected",
		1:  "Tax ×1 — light taxation",
		2:  "Tax ×2 — moderate taxation",
		3:  "Tax ×3 — heavy taxation",
	}
	var delta: int = POP_DELTA.get(tax_rate, 0)
	var label: String = LABELS.get(tax_rate, "Unknown")
	var delta_str: String = "%+d pop/day" % delta if delta != 0 else "no popularity effect"
	return "%s\n%s" % [label, delta_str]
