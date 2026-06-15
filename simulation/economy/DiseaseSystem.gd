extends RefCounted
# GDD §3.5.3 — Public Health & Disease
# Health is a derived 0–100 score (sanitation from apothecaries + wells, minus
# crowding, winter cold and malnutrition). Low health risks a disease outbreak.
# Disease is no longer binary: it carries a severity (0–100) that spreads while
# sanitation is poor and is driven down by apothecary care. Deaths and the
# popularity hit scale with severity, and the plague is cured when severity
# reaches zero. player.disease_active stays in sync (severity > 0) for the view
# and tutorial layers.

const WeatherSystem = preload("res://simulation/world/WeatherSystem.gd")

const CROWDING_THRESHOLD: int = 5            # hovels before crowding is assessed
const COVERAGE_TILES_PER_HOVEL: float = 6.0  # how many hovels one apothecary/well serves

# Sanitation weighting: an apothecary (active cure) counts fully; a well is a
# cheaper passive sanitation source worth half.
const WELL_SANITATION_WEIGHT: float = 0.5

# Outbreak: per-day chance when crowded, scaled by how unhealthy the realm is.
const OUTBREAK_BASE_PROBABILITY: float = 0.12

# Severity dynamics (0–100).
const SEVERITY_START: float = 25.0
const SEVERITY_SPREAD: float = 15.0   # added/day, scaled by (1 − sanitation)
const SEVERITY_CURE: float   = 30.0   # removed/day, scaled by apothecary coverage
const DEATH_FACTOR: float    = 0.04   # peasants lost/day = pop × severity% × this

# Health penalties / weighting.
const WINTER_HEALTH_PENALTY: float = 15.0
const MALNUTRITION_PENALTY: float  = 15.0
const HEALTH_SANITATION_WEIGHT: float = 60.0
# Base health of a settlement with no sanitation works yet. Moderate (not 40) so a
# brand-new village — which can't build wells/apothecaries on day 1 — reads as "okay,
# improvable" (~50) instead of an alarming, unfixable crisis (was 25). Wells/apothecaries
# still carry it to 100.
const HEALTH_BASE: float = 50.0

# ── Coverage helpers ──────────────────────────────────────────────────────────

static func _count(player: Dictionary, btype: String, needs_worker: bool) -> int:
	var n: int = 0
	for b in player.get("buildings", []):
		if not b is Dictionary or not b.get("is_active", true):
			continue
		if b.get("type", "") == btype and (not needs_worker or b.get("workers", 0) > 0):
			n += 1
	return n

static func _hovels(player: Dictionary) -> int:
	return _count(player, "hovel", false)

# Apothecary-only coverage (active cure capacity).
static func compute_apothecary_coverage(player: Dictionary) -> float:
	var hovels: int = _hovels(player)
	if hovels == 0:
		return 0.0
	return clampf(float(_count(player, "apothecary", true)) * COVERAGE_TILES_PER_HOVEL / float(hovels), 0.0, 1.0)

# Well-only coverage (passive sanitation; wells need no staffing).
static func compute_well_coverage(player: Dictionary) -> float:
	var hovels: int = _hovels(player)
	if hovels == 0:
		return 0.0
	return clampf(float(_count(player, "well", false)) * COVERAGE_TILES_PER_HOVEL / float(hovels), 0.0, 1.0)

# Combined sanitation (0–1): apothecaries plus weighted wells.
static func sanitation_coverage(player: Dictionary) -> float:
	return clampf(compute_apothecary_coverage(player) + WELL_SANITATION_WEIGHT * compute_well_coverage(player), 0.0, 1.0)

# Count of distinct staple foods currently stocked.
static func _food_variety(player: Dictionary) -> int:
	var v: int = 0
	var food: Dictionary = player.get("food", {})
	for ft in ["apples", "bread", "cheese", "meat"]:
		if int(food.get(ft, 0)) > 0:
			v += 1
	return v

# Public health score 0–100.
static func compute_health(player: Dictionary, weather: Dictionary = {}) -> float:
	var h: float = HEALTH_BASE + HEALTH_SANITATION_WEIGHT * sanitation_coverage(player)
	if int(weather.get("current", -1)) == WeatherSystem.WeatherType.SNOW:
		h -= WINTER_HEALTH_PENALTY
	# Malnutrition = literally NO food (variety 0). A founding village living on a single
	# staple (apples) is simple, not malnourished — penalising variety<2 from day 1 (when
	# every other food is tech-gated and unreachable) just pinned health at an unfixable 25.
	if _food_variety(player) < 1 and player.get("population", 0) > 0:
		h -= MALNUTRITION_PENALTY
	return clampf(h, 0.0, 100.0)

# Crowded AND under-sanitised — ripe for an outbreak.
static func is_crowding_risk(player: Dictionary) -> bool:
	if _hovels(player) < CROWDING_THRESHOLD:
		return false
	return sanitation_coverage(player) < 0.5

# ── Daily tick ────────────────────────────────────────────────────────────────

# Updates health/severity once per game-day; may start, spread, or cure disease.
# Returns event strings for PopularityEngine (e.g. ["disease_outbreak"]).
static func tick(player: Dictionary, rng: RandomNumberGenerator, tick: int, weather: Dictionary = {}) -> Array:
	if tick == 0 or tick % 240 != 0:
		return []

	var events: Array = []
	var health: float = compute_health(player, weather)
	player["health"] = health
	var sani: float = sanitation_coverage(player)
	var apoth: float = compute_apothecary_coverage(player)
	var severity: float = float(player.get("disease_severity", 0.0))

	# Active plague (severity > 0, or a legacy disease_active flag with no severity).
	if severity > 0.0 or player.get("disease_active", false):
		if severity <= 0.0:
			severity = SEVERITY_START   # initialise legacy / flag-only outbreaks
		events.append("disease_outbreak")
		var pop: int = player.get("population", 0)
		var deaths: int = int(ceil(float(pop) * (severity / 100.0) * DEATH_FACTOR)) if pop > 0 else 0
		player["population"] = maxi(0, pop - deaths)
		# Spread vs cure for next day.
		severity = clampf(severity + SEVERITY_SPREAD * (1.0 - sani) - SEVERITY_CURE * apoth, 0.0, 100.0)
		player["disease_severity"] = severity
		player["disease_active"] = severity > 0.0
		return events

	# No active disease — a low-health, crowded realm may suffer an outbreak.
	if is_crowding_risk(player):
		var chance: float = OUTBREAK_BASE_PROBABILITY * (1.0 - health / 100.0)
		if rng.randf() < chance:
			player["disease_severity"] = SEVERITY_START
			player["disease_active"] = true
			events.append("disease_outbreak")
	return events
