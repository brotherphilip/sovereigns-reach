extends RefCounted
# GDD §2.3 — Unit visual state mapper (View layer, read-only).
# Pure static functions: UnitState dict → sprite/animation data dict.
# No Node inheritance; no scene tree dependency.

const UnitRegistry = preload("res://simulation/units/UnitRegistry.gd")
const UnitState    = preload("res://simulation/units/UnitState.gd")

# Returns a sprite-info dict for one unit:
#   animation   : String  — "idle" | "walk" | "attack" | "die"
#   health_bar  : float   — 0.0–1.0
#   color_tint  : String  — "player_0" … "player_7" | "enemy" | "ally" | "dead"
#   label       : String  — display name
#   facing_dir  : String  — "n" | "s" | "e" | "w" (from last move direction)
#   is_alive    : bool
static func get_sprite_info(unit: Dictionary) -> Dictionary:
	if not unit.get("is_alive", false):
		return {
			"animation": "die", "health_bar": 0.0,
			"color_tint": "dead", "label": unit.get("type", ""),
			"facing_dir": "s", "is_alive": false,
		}
	return {
		"animation": _order_to_animation(unit.get("order", UnitState.ORDER_IDLE)),
		"health_bar": _get_health_bar(unit),
		"color_tint": _get_color_tint(unit),
		"label": UnitRegistry.lookup(unit.get("type", "")).get("name", unit.get("type", "")),
		"facing_dir": _get_facing(unit),
		"is_alive": true,
	}

# Returns 0.0–1.0 health ratio.
static func get_health_bar(unit: Dictionary) -> float:
	return _get_health_bar(unit)

# Returns the animation key for the unit's current order.
static func order_to_animation(order: String) -> String:
	return _order_to_animation(order)

# Returns the color tint string (used for team color overlay).
static func get_color_tint(unit: Dictionary) -> String:
	return _get_color_tint(unit)

# ── Internal ─────────────────────────────────────────────────────────────────

static func _order_to_animation(order: String) -> String:
	match order:
		UnitState.ORDER_MOVE:     return "walk"
		UnitState.ORDER_ATTACK:   return "attack"
		UnitState.ORDER_PATROL:   return "walk"
		UnitState.ORDER_GARRISON: return "idle"
		UnitState.ORDER_TRAINING: return "idle"
	return "idle"

static func _get_health_bar(unit: Dictionary) -> float:
	var hp: int     = unit.get("hp", 0)
	var max_hp: int = unit.get("max_hp", 1)
	if max_hp <= 0:
		return 1.0
	return clampf(float(hp) / float(max_hp), 0.0, 1.0)

static func _get_color_tint(unit: Dictionary) -> String:
	var owner_id: int = unit.get("owner_id", 0)
	if owner_id < 0:
		return "enemy"   # AI faction units
	return "player_%d" % owner_id

static func _get_facing(unit: Dictionary) -> String:
	# Derive facing from movement direction; default south
	var dx: int = unit.get("target_x", unit.get("pos_x", 0)) - unit.get("pos_x", 0)
	var dy: int = unit.get("target_y", unit.get("pos_y", 0)) - unit.get("pos_y", 0)
	if absf(float(dx)) >= absf(float(dy)):
		return "e" if dx >= 0 else "w"
	return "s" if dy >= 0 else "n"
