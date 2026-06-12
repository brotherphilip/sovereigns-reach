extends RefCounted
# GDD §3.3 — Religion Coverage (ΔR)
# Church and Cathedral coverage radius determines religious satisfaction bonus.
# Both types require the "monastic_orders" tech unlock.
# PopularityEngine reads player.religion_coverage (0.0–1.0) set by this system.

# Max ΔR bonus granted at 100% coverage (GDD §3.3)
const MAX_RELIGION_DELTA: float = 10.0

# Approximate tiles of influence per coverage unit (used to convert radius to hovel coverage)
const TILES_PER_HOVEL: float = 4.0

# Returns the religion coverage ratio (0.0–1.0).
# Coverage = sum of church/cathedral influence / hovel count.
# Each church has coverage_radius 12; each cathedral has 30.
static func compute_religion_coverage(player: Dictionary) -> float:
	var coverage_sum: float = 0.0
	var hovel_count: int = 0
	for building in player.get("buildings", []):
		if not building is Dictionary:
			continue
		var btype: String = building.get("type", "")
		if not building.get("is_active", true):
			continue
		if btype == "church" or btype == "cathedral":
			var radius: int = building.get("coverage_radius", 0)
			# Each radius unit can serve TILES_PER_HOVEL hovels
			coverage_sum += float(radius) / TILES_PER_HOVEL
		elif btype == "hovel":
			hovel_count += 1

	if hovel_count == 0:
		return 0.0
	return clampf(coverage_sum / float(hovel_count), 0.0, 1.0)

# Returns the raw religion popularity bonus given current coverage.
# This is the ΔR that PopularityEngine will see via player.religion_coverage.
static func coverage_to_popularity_delta(coverage: float) -> float:
	return coverage * MAX_RELIGION_DELTA

# Called every tick: updates player.religion_coverage.
# Returns the new coverage value.
static func tick(player: Dictionary) -> float:
	var coverage: float = compute_religion_coverage(player)
	player["religion_coverage"] = coverage
	return coverage
