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

# Deals damage to a building. Returns true only on the tick it is first destroyed.
static func take_damage(building: Dictionary, amount: int) -> bool:
	var was_alive: bool = building.get("hp", 0) > 0
	building["hp"] = maxi(0, building["hp"] - amount)
	if was_alive and building["hp"] == 0:
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
		building["fire_ticks"] = 0     # burn-clock (self-extinguishes — see tick_fire)
		building["douse"] = 0          # bucket-brigade water delivered so far
		return true
	return false

# HP lost per tick while burning. A fire now smoulders SLOWLY (1/tick) so a blaze is on screen
# for several seconds — long enough to see the flames and for the bucket brigade to reach it —
# instead of deleting a building near-instantly. Explosive stores still go up fast but not in a
# single frame. A fire also BURNS OUT on its own after MAX_FIRE_TICKS: a real fire spends its fuel
# and dies down, leaving the building scorched (damaged) but standing — so one blaze can't level
# the whole town. MAX_FIRE_TICKS (48) is below the smallest building's HP (a 60-HP hovel survives
# at ~12 HP), so an unfought fire scorches rather than razes; the brigade or rain ends it sooner.
const FIRE_DAMAGE_PER_TICK: int = 1     # applied every OTHER tick → a slow ~0.5 HP/tick smoulder
const FIRE_DAMAGE_EXPLOSIVE: int = 10   # pitch/armory still burn fast (they "explode"), but visibly
const MAX_FIRE_TICKS: int = 70

# Fire tick — advances the burn clock, self-extinguishes when the fire burns out, and applies
# (slow) damage otherwise. Returns true only if the building was DESTROYED by fire this tick.
static func tick_fire(building: Dictionary) -> bool:
	if not building.get("is_on_fire", false):
		return false
	building["fire_ticks"] = int(building.get("fire_ticks", 0)) + 1
	if int(building["fire_ticks"]) >= MAX_FIRE_TICKS:
		building["is_on_fire"] = false   # burned out — the fire has spent itself
		return false
	# Explosive stores go up every tick; ordinary buildings smoulder (damage every other tick)
	# so over the whole 70-tick burn an unfought fire scorches (~34 HP) without razing — a 60-HP
	# hovel survives, and the bucket brigade has a real window to save it sooner.
	if building.get("type", "") == "pitch_rig" or building.get("type", "") == "armory":
		return take_damage(building, FIRE_DAMAGE_EXPLOSIVE)
	if int(building["fire_ticks"]) % 2 == 0:
		return take_damage(building, FIRE_DAMAGE_PER_TICK)
	return false

# A load of water thrown on the blaze by a firefighter who ran it from the well. A delivered
# load puts the fire out (the trip itself — fill at the well, carry, throw — is the time cost,
# so a brigade with a near well beats the burn-out and saves the building with less damage).
# Returns true if this douse extinguished the fire.
static func douse(building: Dictionary) -> bool:
	if not building.get("is_on_fire", false):
		return false
	building["is_on_fire"] = false
	building["douse"] = 0
	building["fire_ticks"] = 0
	repair(building, 8)   # the brigade saved it — a little structure recovered
	return true
