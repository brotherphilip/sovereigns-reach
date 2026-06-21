extends RefCounted
# GDD §2.5 — Combat & Transition Instancing
# Handles damage calculations, army-level combat resolution, and siege targeting priorities.
# All inputs and outputs are plain Dictionaries/Arrays for determinism and serializability.

const UnitRegistry = preload("res://simulation/units/UnitRegistry.gd")
const UnitState    = preload("res://simulation/units/UnitState.gd")

# Siege target priority map (GDD §2.5.2):
#   - AI burns farms first → priority "farm"
#   - Rams hit gates       → priority "gatehouse"
#   - Trebuchets hit towers → priority "great_tower" / "lookout_tower"
#   - Swordsmen rush the keep → priority "keep"
const SIEGE_PRIORITIES: Dictionary = {
	"battering_ram": "gatehouse",
	"trebuchet":     "great_tower",
	"catapult":      "farm",
	"swordsman":     "keep",
	"archer":        "farm",
	"armed_peasant": "farm",
	"tunneler":      "stone_wall",
	"ladderman":     "stone_wall",
}

# ── Single-unit damage ────────────────────────────────────────────────────────

# Calculate how much damage attacker deals to defender.
# Returns {damage: int, kills: bool, remaining_hp: int}.
# Delegates to UnitState._damage_multiplier for the type table.
static func calculate_damage(attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var raw: int     = attacker.get("attack", 0)
	var atk_type: String = attacker.get("attack_type", UnitRegistry.ATTACK_NONE)
	# Halberdier anti-armor bonus (GDD §6.3.5)
	var anti_armor: float = UnitRegistry.lookup(attacker.get("type", "")).get("anti_armor_bonus", 0.0)
	if anti_armor > 0.0 and defender.get("armor_type", "") == UnitRegistry.ARMOR_HEAVY:
		raw = int(float(raw) * (1.0 + anti_armor))
	# Arrow-immune siege engines (the battering ram, GDD §6.4.1) shrug off PIERCE attacks. Driven by
	# the registry's `immune_to_arrows` flag rather than a hard-coded type, so flagging a NEW unit (a
	# mantlet / siege tower) immune actually takes effect — the flag was previously declared on the
	# ram but never read, and the type was hard-coded. (Key is "killed" to match every other return
	# path and all callers — it was a stray "kills" here.) (iter285)
	if atk_type == UnitRegistry.ATTACK_PIERCE \
			and UnitRegistry.lookup(defender.get("type", "")).get("immune_to_arrows", false):
		return {"killed": false, "damage": 0, "remaining_hp": defender.get("hp", 0)}
	return UnitState.apply_damage(defender, raw, atk_type)

# ── Captain morale buff ───────────────────────────────────────────────────────

# Returns the total morale attack bonus granted by any captain in the army.
# GDD §6.3.4: +10 attack to all adjacent allies.
static func get_morale_attack_bonus(army: Array) -> int:
	for unit in army:
		if unit is Dictionary and unit.get("type", "") == "captain" and unit.get("is_alive", false):
			return UnitRegistry.lookup("captain").get("morale_buff", 0)
	return 0

# ── Army-level combat resolution ─────────────────────────────────────────────

# Resolve one round of combat between two armies.
# Returns the most-damaged unit in pool (lowest HP ratio). Falls back to random when all are full.
static func _pick_target(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	var best: Dictionary = pool[0]
	var best_ratio: float = float(best.get("hp", 1)) / float(maxi(best.get("max_hp", 1), 1))
	for u in pool:
		var r: float = float(u.get("hp", 1)) / float(maxi(u.get("max_hp", 1), 1))
		if r < best_ratio:
			best_ratio = r
			best = u
	return best if best_ratio < 1.0 else pool[rng.randi() % pool.size()]

# Each alive attacker unit deals damage to a random alive defender unit (and vice versa).
# Returns {attacker_casualties: int, defender_casualties: int}.
# Both attacker_army and defender_army arrays are mutated in-place (hp reduced, is_alive set).
static func resolve_combat(attacker_army: Array, defender_army: Array, rng: RandomNumberGenerator) -> Dictionary:
	var atk_morale: int = get_morale_attack_bonus(attacker_army)
	var def_morale: int = get_morale_attack_bonus(defender_army)
	var atk_casualties: int = 0
	var def_casualties: int = 0

	# Attackers deal damage to random defender
	var alive_defenders: Array = attacker_army.filter(func(u): return false)  # will rebuild
	alive_defenders = []
	for u in defender_army:
		if u is Dictionary and u.get("is_alive", false):
			alive_defenders.append(u)

	for attacker in attacker_army:
		if not (attacker is Dictionary and attacker.get("is_alive", false)):
			continue
		if alive_defenders.is_empty():
			break
		var target: Dictionary = _pick_target(alive_defenders, rng)
		var boosted: Dictionary = attacker.duplicate()
		boosted["attack"] = attacker.get("attack", 0) + atk_morale
		var result: Dictionary = calculate_damage(boosted, target)
		if result.get("killed", false):
			def_casualties += 1
			alive_defenders.erase(target)

	# Defenders retaliate
	var alive_attackers: Array = []
	for u in attacker_army:
		if u is Dictionary and u.get("is_alive", false):
			alive_attackers.append(u)

	for defender in defender_army:
		if not (defender is Dictionary and defender.get("is_alive", false)):
			continue
		if alive_attackers.is_empty():
			break
		var target: Dictionary = _pick_target(alive_attackers, rng)
		var boosted: Dictionary = defender.duplicate()
		boosted["attack"] = defender.get("attack", 0) + def_morale
		var result: Dictionary = calculate_damage(boosted, target)
		if result.get("killed", false):
			atk_casualties += 1
			alive_attackers.erase(target)

	return {"attacker_casualties": atk_casualties, "defender_casualties": def_casualties}

# ── Siege targeting ───────────────────────────────────────────────────────────

# Returns the building type string that this unit type should prioritize attacking.
# Falls back to "keep" for any melee heavy infantry not listed.
static func get_siege_priority(unit_type: String) -> String:
	if SIEGE_PRIORITIES.has(unit_type):
		return SIEGE_PRIORITIES[unit_type]
	var defn: Dictionary = UnitRegistry.lookup(unit_type)
	if defn.get("category", "") == UnitRegistry.CAT_HEAVY_INF:
		return "keep"
	return "farm"

# ── Army value (for AI threat level estimation) ───────────────────────────────

# Approximate combat power of an army as a single int.
static func get_army_value(army: Array) -> int:
	var total: int = 0
	for unit in army:
		if unit is Dictionary and unit.get("is_alive", false):
			total += unit.get("attack", 0) + unit.get("defense", 0) + unit.get("hp", 0)
	return total
