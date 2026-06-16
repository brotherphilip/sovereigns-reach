extends RefCounted
# GDD §6 — Per-unit runtime state.
# All fields are plain Dictionary/int/float/bool — fully JSON-serializable.
# No Vector2, no Godot objects. View layer reads these fields for rendering.

const UnitRegistry = preload("res://simulation/units/UnitRegistry.gd")

# Unit order strings
const ORDER_IDLE    = "idle"
const ORDER_MOVE    = "move"
const ORDER_ATTACK  = "attack"
const ORDER_PATROL  = "patrol"
const ORDER_GARRISON = "garrison"
const ORDER_TRAINING = "training"

# Combat stance — how a unit reacts to foes that wander into its aggro radius.
# GUARD: defend the post (auto-acquire, but leashed — return after the fight).
# AGGRESSIVE: pursue any foe freely (no leash), like a player-issued attack.
const STANCE_GUARD      = "guard"
const STANCE_AGGRESSIVE = "aggressive"

static func create(unit_type: String, owner_id: int, x: int, y: int, uid: int) -> Dictionary:
	var defn: Dictionary = UnitRegistry.lookup(unit_type)
	if defn.is_empty():
		return {}
	return {
		"id": uid,
		"type": unit_type,
		"owner_id": owner_id,
		"hp": defn.get("max_hp", 10),
		"max_hp": defn.get("max_hp", 10),
		"attack": defn.get("attack", 0),
		"defense": defn.get("defense", 0),
		"attack_type": defn.get("attack_type", UnitRegistry.ATTACK_NONE),
		"armor_type": defn.get("armor_type", UnitRegistry.ARMOR_NONE),
		"range": defn.get("range", 0),
		"speed": defn.get("speed", 1),
		"morale": 100.0,
		"order": ORDER_IDLE,
		"pos_x": x,
		"pos_y": y,
		"target_x": x,
		"target_y": y,
		"target_id": -1,
		"is_alive": true,
		"ticks_in_training": 0,
		"is_garrisoned": false,
		"stance": STANCE_GUARD,
		"modifiers": {},
	}

# Apply damage to a unit; returns {killed: bool, damage: int, remaining_hp: int}.
# attack_type vs armor_type determines the effective damage multiplier.
static func apply_damage(unit: Dictionary, raw_damage: int, attack_type: String) -> Dictionary:
	if not unit.get("is_alive", false):
		return {"killed": false, "damage": 0, "remaining_hp": 0}
	var armor_type: String = unit.get("armor_type", UnitRegistry.ARMOR_NONE)
	var defense: int = unit.get("defense", 0)
	var mult: float = _damage_multiplier(attack_type, armor_type)
	var effective: int = maxi(1, int(float(raw_damage) * mult) - defense)
	var old_hp: int = unit.get("hp", 0)
	var new_hp: int = maxi(0, old_hp - effective)
	unit["hp"] = new_hp
	var killed: bool = new_hp <= 0
	if killed:
		unit["is_alive"] = false
		unit["order"] = ORDER_IDLE
	return {"killed": killed, "damage": effective, "remaining_hp": new_hp}

# Returns true if this unit fires at range (not melee).
static func is_ranged(unit: Dictionary) -> bool:
	return unit.get("range", 0) > 0

# Returns true if the unit dict looks structurally valid.
static func is_valid(unit: Dictionary) -> bool:
	return unit.has("id") and unit.has("type") and unit.has("hp") and unit.has("is_alive")

# Returns true if the unit is alive and finished training — i.e. it can move,
# fight, and be ordered around. Units still in the barracks queue are excluded.
static func is_deployable(unit: Dictionary) -> bool:
	return unit.get("is_alive", false) and unit.get("order", "") != ORDER_TRAINING

# Set a movement order, clearing any prior target_id.
static func issue_move_order(unit: Dictionary, tx: int, ty: int) -> void:
	unit["order"] = ORDER_MOVE
	unit["target_x"] = tx
	unit["target_y"] = ty
	unit["target_id"] = -1

# Set an attack order on a specific target unit/building id.
static func issue_attack_order(unit: Dictionary, tx: int, ty: int, target_id: int) -> void:
	unit["order"] = ORDER_ATTACK
	unit["target_x"] = tx
	unit["target_y"] = ty
	unit["target_id"] = target_id

# Set a patrol order looping between two waypoints (a = origin, b = far point).
# The unit engages any enemy that strays into its aggro radius, then resumes.
static func issue_patrol_order(unit: Dictionary, ax: int, ay: int, bx: int, by: int) -> void:
	unit["order"] = ORDER_PATROL
	unit["patrol_a"] = [ax, ay]
	unit["patrol_b"] = [bx, by]
	unit["patrol_to_b"] = true
	unit["target_x"] = bx
	unit["target_y"] = by
	unit["target_id"] = -1

# Step the unit one tile along a path (list of [x, y] pairs).
# Returns true if a move happened.
static func advance_along_path(unit: Dictionary, path: Array) -> bool:
	if path.is_empty() or not unit.get("is_alive", false):
		return false
	var next = path[0]
	unit["pos_x"] = next[0]
	unit["pos_y"] = next[1]
	return true

# ── Internal ─────────────────────────────────────────────────────────────────

static func _damage_multiplier(attack_type: String, armor_type: String) -> float:
	# GDD §6: pierce devastates unarmored; siege great vs structures; arrows useless vs walls.
	match attack_type:
		UnitRegistry.ATTACK_MELEE:
			match armor_type:
				UnitRegistry.ARMOR_NONE:      return 1.0
				UnitRegistry.ARMOR_LIGHT:     return 0.8
				UnitRegistry.ARMOR_HEAVY:     return 0.5
				UnitRegistry.ARMOR_STRUCTURE: return 0.1
		UnitRegistry.ATTACK_PIERCE:
			match armor_type:
				UnitRegistry.ARMOR_NONE:      return 1.5   # devastating unarmored
				UnitRegistry.ARMOR_LIGHT:     return 1.0
				UnitRegistry.ARMOR_HEAVY:     return 0.75  # bolts partially pierce iron
				UnitRegistry.ARMOR_STRUCTURE: return 0.05  # useless vs stone walls
		UnitRegistry.ATTACK_SIEGE:
			match armor_type:
				UnitRegistry.ARMOR_NONE:      return 1.0
				UnitRegistry.ARMOR_LIGHT:     return 1.0
				UnitRegistry.ARMOR_HEAVY:     return 1.0
				UnitRegistry.ARMOR_STRUCTURE: return 3.0   # rams/catapults vs buildings
	return 1.0  # ATTACK_NONE or unknown
