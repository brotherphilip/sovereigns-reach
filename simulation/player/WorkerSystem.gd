extends RefCounted
# Manages peasant → job assignment for all buildings.
# GDD §2.4.5 — Peasant Pathing; §6.1.1 — Peasants.
#
# Peasants are not tracked as individual state objects in Phase 3.
# Population is a scalar; assignment is tracked per-building as worker counts.
# Phase 6 will add individual unit states.

const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

# Assign workers to a building. Returns actual workers assigned.
static func assign_workers(building: Dictionary, count: int, player: Dictionary) -> int:
	var max_w: int = building.get("max_workers", 0)
	if max_w == 0:
		return 0

	var old_count: int = building.get("workers", 0)
	# Include this building's current workers in available so reductions are computed correctly.
	var available: int = _available_workers(player) + old_count
	var to_assign: int = mini(count, min(max_w, available))
	building["workers"] = to_assign
	return to_assign - old_count  # Net change

# Remove all workers from a building (e.g. on demolish or levy)
static func unassign_workers(building: Dictionary, player: Dictionary) -> int:
	var freed: int = building.get("workers", 0)
	building["workers"] = 0
	return freed

# Auto-assign all idle workers to buildings that need them.
# Priority order: food first (prevents starvation), then production, then military.
static func auto_assign(player: Dictionary) -> void:
	var buildings: Array = player.get("buildings", [])
	if buildings.is_empty():
		return

	# Sort buildings by priority category
	var prioritized: Array = _sort_by_priority(buildings)
	for building in prioritized:
		if not building.get("is_active", true):
			continue
		var max_w: int = building.get("max_workers", 0)
		if max_w == 0:
			continue
		var current: int = building.get("workers", 0)
		if current >= max_w:
			continue
		var needed: int = max_w - current
		assign_workers(building, max_w, player)

# Returns total workers currently assigned across all buildings
static func total_assigned(player: Dictionary) -> int:
	var total: int = 0
	for building in player.get("buildings", []):
		total += building.get("workers", 0)
	return total

# Returns workers available for new assignments
static func _available_workers(player: Dictionary) -> int:
	var pop: int = player.get("population", 0)
	var military: int = player.get("military_strength", 0)
	var assigned: int = total_assigned(player)
	return maxi(0, pop - military - assigned)

# Sort buildings by economic priority for auto-assignment
static func _sort_by_priority(buildings: Array) -> Array:
	var priority_order: Array = [
		BuildingRegistry.Category.FOOD,
		BuildingRegistry.Category.HARVESTING,
		BuildingRegistry.Category.CIVIC,
		BuildingRegistry.Category.MILITARY,
		BuildingRegistry.Category.DEFENSE,
	]
	var sorted: Array = buildings.duplicate()
	sorted.sort_custom(func(a, b):
		var defn_a = BuildingRegistry.lookup(a.get("type", ""))
		var defn_b = BuildingRegistry.lookup(b.get("type", ""))
		var cat_a: int = defn_a.get("category", 99)
		var cat_b: int = defn_b.get("category", 99)
		var pri_a: int = priority_order.find(cat_a)
		var pri_b: int = priority_order.find(cat_b)
		if pri_a == -1: pri_a = 99
		if pri_b == -1: pri_b = 99
		return pri_a < pri_b
	)
	return sorted

# Levy: forces 50 peasants from buildings into armed peasant units.
# Returns the number of workers pulled from buildings.
# GDD §7.3.2 — Levy Summons edict.
static func levy_peasants(count: int, player: Dictionary) -> int:
	var levied: int = 0
	for building in player.get("buildings", []):
		if levied >= count:
			break
		var w: int = building.get("workers", 0)
		if w <= 0:
			continue
		var pull: int = mini(w, count - levied)
		building["workers"] -= pull
		levied += pull
	return levied

# Calculate inn coverage for a given player's layout.
# Returns 0.0–1.0 ratio of hovels within any inn's radius.
# This is a simplified scalar for the PopularityEngine.
static func calculate_inn_coverage(player: Dictionary, buildings: Array) -> float:
	var inn_count: int = 0
	var hovel_count: int = 0
	for building in buildings:
		var btype: String = building.get("type", "")
		if btype == "inn" and building.get("is_active", true) and building.get("workers", 0) > 0:
			inn_count += 1
		elif btype == "hovel":
			hovel_count += 1
	if hovel_count == 0:
		return 0.0
	# Each inn covers approximately 4 hovels in range at full capacity
	return clampf(float(inn_count * 4) / float(hovel_count), 0.0, 1.0)

# Calculate church/cathedral coverage similarly
static func calculate_religion_coverage(buildings: Array) -> float:
	var coverage_sum: float = 0.0
	var hovel_count: int = 0
	for building in buildings:
		var btype: String = building.get("type", "")
		if btype in ["church", "cathedral"] and building.get("is_active", true):
			var radius: int = BuildingRegistry.coverage_radius(btype)
			coverage_sum += radius * 0.5
		elif btype == "hovel":
			hovel_count += 1
	if hovel_count == 0:
		return 0.0
	return clampf(coverage_sum / float(hovel_count), 0.0, 1.0)
