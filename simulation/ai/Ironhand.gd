extends RefCounted
# GDD §8.3 — The Ironhand archetype.
# Late-game industrial fortress. Methodical expansion, perfect supply chains.
# Army: hundreds of Swordsmen, Trebuchets, armored Rams.
# Attacks rarely but sieges are devastating. Uses Tunnelers on walls.

const AIFaction    = preload("res://simulation/ai/AIFaction.gd")
const UnitRegistry = preload("res://simulation/units/UnitRegistry.gd")

# GDD §8.3.4: heavy infantry + siege engines
const ARMY_WEIGHTS: Dictionary = {
	"swordsman": 5,
	"pikeman": 2,
	"battering_ram": 1,
	"trebuchet": 1,
	"tunneler": 1,
}

const IRON_STOCKPILE_TARGET: int = 500   # maxes iron (GDD §8.3.2)
const STONE_STOCKPILE_TARGET: int = 500
const ARMY_SIZE_TARGET: int = 50         # builds large armies before attacking

static func make(id: int, capital_x: int, capital_y: int) -> Dictionary:
	var f: Dictionary = AIFaction.make_faction(id, "The Ironhand", AIFaction.ARCHETYPE_IRONHAND, capital_x, capital_y)
	f["resources"]["iron"] = 200
	f["resources"]["stone"] = 300
	f["gold"] = 800
	f["daily_income_iron"] = 25
	f["daily_income_wood"] = 15
	f["daily_income_gold"] = 30
	f["tech_unlocks"] = ["unit_unlocks", "armor_forging", "siege_engines"]
	return f

static func tick(faction: Dictionary, players: Array, _world: Dictionary, tick: int) -> Array:
	var events: Array = AIFaction.tick(faction, _world, tick)
	if not faction.get("is_alive", false):
		return events

	if tick > 0 and tick % AIFaction.TICKS_PER_DAY == 0:
		# Build army methodically (GDD §8.3.4)
		_recruit_industrial(faction)

		# Only attacks once army is large enough (GDD §8.3.5: attacks rarely)
		var army_size: int = _alive_unit_count(faction)
		# Adaptive: strike sooner if the weakest player is weak (punish weakness)
		var weakest: float = _weakest_player_strength(players)
		var gate: int = 30 if weakest < 25.0 else ARMY_SIZE_TARGET
		if army_size >= gate:
			var attack_info: Dictionary = AIFaction.should_attack(faction, players)
			if attack_info.get("attack", false):
				AIFaction.start_siege(faction, attack_info["target_player_id"],
					_get_player_x(players, attack_info["target_player_id"]),
					_get_player_y(players, attack_info["target_player_id"]))
				events.append("ironhand_siege_started")

	return events

static func _recruit_industrial(faction: Dictionary) -> void:
	var gold: int = faction.get("gold", 0)
	# Invest up to 200 gold/day in army
	var budget: int = mini(200, gold / 2)
	var spent: int = 0
	var next_uid: int = faction.get("id", 0) * 10000 + faction.get("units", []).size() + 1
	while spent < budget:
		var roll: int = (next_uid + spent) % 10
		var utype: String = "swordsman"
		if roll >= 5 and roll < 7:
			utype = "pikeman"
		elif roll == 7:
			utype = "battering_ram"
		elif roll == 8:
			utype = "trebuchet"
		elif roll == 9:
			utype = "tunneler"
		var cost: int = UnitRegistry.lookup(utype).get("cost_gold", 60)
		if spent + cost > budget or faction.get("gold", 0) < cost:
			break
		AIFaction.recruit_unit(faction, utype, next_uid)
		next_uid += 1
		spent += cost

static func _alive_unit_count(faction: Dictionary) -> int:
	var count: int = 0
	for u in faction.get("units", []):
		if u is Dictionary and u.get("is_alive", false):
			count += 1
	return count

static func _get_player_x(players: Array, pid: int) -> int:
	for p in players:
		if p is Dictionary and p.get("id", -1) == pid:
			return p.get("keep_x", 0)
	return 0

static func _get_player_y(players: Array, pid: int) -> int:
	for p in players:
		if p is Dictionary and p.get("id", -1) == pid:
			return p.get("keep_y", 0)
	return 0

# Returns true if Ironhand will target this building type with tunnelers first.
# GDD §8.3.5: uses tunnelers on stone walls.
static func tunneler_target(building_type: String) -> bool:
	return building_type in ["stone_wall", "great_tower", "lookout_tower"]

static func _weakest_player_strength(players: Array) -> float:
	var lowest: float = INF
	for p in players:
		if p is Dictionary and p.get("is_alive", false):
			lowest = minf(lowest, AIFaction.assess_player_strength(p))
	return lowest if lowest != INF else 999.0
