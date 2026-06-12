extends RefCounted
# Runtime state for a single placed building instance.
# Stores all mutable per-building data. Entirely JSON-serializable.

const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

var _next_id: int = 1  # Class-level counter (shared across instances for test convenience)

# Creates a new building instance state dictionary
static func create(
		building_type: String,
		player_id: int,
		grid_x: int,
		grid_y: int,
		building_id: int = -1
) -> Dictionary:
	var defn: Dictionary = BuildingRegistry.lookup(building_type)
	if defn.is_empty():
		return {}
	return {
		"id": building_id,
		"type": building_type,
		"player_id": player_id,
		"grid_x": grid_x,
		"grid_y": grid_y,

		# Operational state
		"workers": 0,
		"max_workers": defn.get("max_workers", 0),
		"is_active": true,      # False = demolished / under repair
		"is_on_fire": false,
		"hp": defn.get("hp", 100),
		"max_hp": defn.get("hp", 100),

		# Production tracking
		"production_ticks": 0,  # Cumulative production ticks for this instance
		"terrain_yield": 1.0,   # Set by PlacementValidator based on terrain
		"storage_used": 0,
		"storage_max": defn.get("storage_capacity", 0),

		# Coverage state (inns, churches, apothecaries)
		"coverage_radius": defn.get("coverage_radius", 0),
		"coverage_active": defn.get("coverage_radius", 0) > 0,

		# Gate state
		"is_open": defn.get("is_open", true),

		# Upgrades / tech bonuses applied
		"upgrade_level": 0,
		"applied_bonuses": {},
	}

# Returns the worker efficiency ratio (0.0–1.0) based on distance from keep.
# Efficiency degrades at 1%/tile beyond 10 tiles (GDD §2.4.5)
static func worker_efficiency(building: Dictionary, keep_x: int, keep_y: int) -> float:
	var dx: float = building.get("grid_x", 0) - keep_x
	var dy: float = building.get("grid_y", 0) - keep_y
	var dist: float = sqrt(dx * dx + dy * dy)
	var penalty: float = maxf(0.0, dist - 10.0) * 0.01
	return clampf(1.0 - penalty, 0.1, 1.0)

# Deals damage to a building. Returns true if it was destroyed.
static func take_damage(building: Dictionary, amount: int) -> bool:
	building["hp"] = maxi(0, building["hp"] - amount)
	if building["hp"] == 0:
		building["is_active"] = false
		return true
	return false

# Repairs HP (e.g. from Siege Repairs edict)
static func repair(building: Dictionary, amount: int) -> void:
	building["hp"] = mini(building["max_hp"], building["hp"] + amount)
	if building["hp"] > 0:
		building["is_active"] = true

# Sets fire to a building if it's flammable
static func ignite(building: Dictionary) -> bool:
	var defn: Dictionary = BuildingRegistry.lookup(building.get("type", ""))
	if defn.get("immune_to_fire", false):
		return false
	if defn.get("fire_risk", 0.0) > 0.0:
		building["is_on_fire"] = true
		return true
	return false

# Fire spread tick — returns true if building was destroyed by fire this tick
static func tick_fire(building: Dictionary) -> bool:
	if not building.get("is_on_fire", false):
		return false
	var fire_damage: int = 8  # HP lost per tick while burning
	if building.get("type", "") == "pitch_rig" or building.get("type", "") == "armory":
		fire_damage = 40  # Pitch and armory burn fast and explode
	return take_damage(building, fire_damage)
