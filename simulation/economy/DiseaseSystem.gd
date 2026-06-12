extends RefCounted
# GDD §3.5.3 — Disease Outbreaks
# Crowded housing without apothecary coverage triggers disease events.
# Disease kills peasants and plummets popularity until cured.

# Hovels needed to trigger crowding risk check
const CROWDING_THRESHOLD: int = 5

# Apothecary coverage radius (buildings/hovel coverage ratio)
const COVERAGE_TILES_PER_HOVEL: float = 6.0

# Disease kills this many peasants per day when active
const DISEASE_DEATH_RATE: int = 2

# Probability that disease triggers when crowded and no coverage (per day)
const OUTBREAK_PROBABILITY: float = 0.08

# Returns apothecary coverage ratio (0.0–1.0)
static func compute_apothecary_coverage(player: Dictionary) -> float:
	var apothecary_count: int = 0
	var hovel_count: int = 0
	for building in player.get("buildings", []):
		if not building is Dictionary:
			continue
		var btype: String = building.get("type", "")
		if not building.get("is_active", true):
			continue
		if btype == "apothecary" and building.get("workers", 0) > 0:
			apothecary_count += 1
		elif btype == "hovel":
			hovel_count += 1
	if hovel_count == 0:
		return 0.0
	return clampf(float(apothecary_count) * COVERAGE_TILES_PER_HOVEL / float(hovel_count), 0.0, 1.0)

# Returns true if conditions are ripe for a disease outbreak (crowded AND poor coverage)
static func is_crowding_risk(player: Dictionary) -> bool:
	var hovel_count: int = 0
	for building in player.get("buildings", []):
		if building is Dictionary and building.get("type", "") == "hovel":
			hovel_count += 1
	if hovel_count < CROWDING_THRESHOLD:
		return false
	var coverage: float = compute_apothecary_coverage(player)
	return coverage < 0.5  # Less than 50% coverage with hovels present

# Tick disease state at day boundary.
# May trigger a new outbreak, spread existing disease, or cure it.
# Returns an Array of event strings to pass to PopularityEngine (e.g. ["disease_outbreak"]).
static func tick(player: Dictionary, rng: RandomNumberGenerator, tick: int) -> Array:
	if tick == 0 or tick % 240 != 0:
		return []

	var events: Array = []
	var coverage: float = compute_apothecary_coverage(player)

	# Active disease: kill peasants and emit event
	if player.get("disease_active", false):
		events.append("disease_outbreak")
		# Kill peasants
		var pop: int = player.get("population", 0)
		player["population"] = maxi(0, pop - DISEASE_DEATH_RATE)
		# Cure if coverage is now sufficient
		if coverage >= 0.8:
			player["disease_active"] = false
		return events

	# No active disease: maybe trigger
	if is_crowding_risk(player):
		var roll: float = rng.randf()
		if roll < OUTBREAK_PROBABILITY:
			player["disease_active"] = true
			events.append("disease_outbreak")

	return events
