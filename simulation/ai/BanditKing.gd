extends RefCounted
# GDD §8.1 — The Bandit King archetype.
# Chaotic swarm harasser. Expands fast into neutral territory, builds cheap wooden forts,
# fields mass Armed Peasants + Archers, constantly harasses player outskirts.

const AIFaction    = preload("res://simulation/ai/AIFaction.gd")
const UnitRegistry = preload("res://simulation/units/UnitRegistry.gd")

# Bandit King unit composition weights (GDD §8.1.4):
#   50% Armed Peasants, 40% Archers, 10% Militia
const ARMY_WEIGHTS: Dictionary = {
	"armed_peasant": 5,
	"archer": 4,
	"militia": 1,
}

# GDD §8.1.2: focuses on wood and food, ignores stone
const PRIORITIES_RESOURCES: Array = ["wood", "wheat"]
const IGNORES_RESOURCES: Array    = ["stone", "iron"]

static func make(id: int, capital_x: int, capital_y: int) -> Dictionary:
	var f: Dictionary = AIFaction.make_faction(id, "The Bandit King", AIFaction.ARCHETYPE_BANDIT, capital_x, capital_y)
	# Bandit starts with extra wood, less gold, no stone
	f["resources"]["wood"] = 400
	f["resources"]["stone"] = 0
	f["gold"] = 200
	# Fast income on wood/food; gold from raiding events
	f["daily_income_wood"] = 40
	f["daily_income_gold"] = 10
	return f

# Archetype tick: called each game-day via GameState.
# Returns Array of event strings for EventBus.
static func tick(faction: Dictionary, players: Array, _world: Dictionary, tick: int) -> Array:
	var events: Array = AIFaction.tick(faction, _world, tick)
	if not faction.get("is_alive", false):
		return events

	if tick > 0 and tick % AIFaction.TICKS_PER_DAY == 0:
		# Spend gold on cheap units aggressively (GDD §8.1.4)
		_recruit_army(faction, tick)

		# Decision: harass players if army is above minimal size
		var army_size: int = _alive_unit_count(faction)
		# Adaptive: harass sooner when the weakest player is vulnerable
		var weakest: float = _weakest_player_strength(players)
		var harass_gate: int = 3 if weakest < 25.0 else 5
		if army_size >= harass_gate:
			var attack_info: Dictionary = AIFaction.should_attack(faction, players)
			if attack_info.get("attack", false):
				AIFaction.start_siege(faction, attack_info["target_player_id"],
					_get_player_x(players, attack_info["target_player_id"]),
					_get_player_y(players, attack_info["target_player_id"]))
				events.append("bandit_raid_started")

	return events

static func _recruit_army(faction: Dictionary, _tick: int) -> void:
	var budget: int = faction.get("gold", 0)
	# Bandit is not strategic — spends half its gold each day on units
	var spend: int = budget / 2
	var spent: int = 0
	var next_uid: int = _next_uid(faction)
	while spent < spend:
		# Random weighted selection from ARMY_WEIGHTS
		var roll: int = (next_uid + spent) % 10
		var utype: String = "armed_peasant"
		if roll >= 5 and roll < 9:
			utype = "archer"
		elif roll >= 9:
			utype = "militia"
		var defn: Dictionary = UnitRegistry.lookup(utype)
		var cost: int = defn.get("cost_gold", 5)
		if spent + cost > spend or faction.get("gold", 0) < cost:
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

static func _next_uid(faction: Dictionary) -> int:
	return faction.get("id", 0) * 10000 + faction.get("units", []).size() + 1

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

static func _weakest_player_strength(players: Array) -> float:
	var lowest: float = INF
	for p in players:
		if p is Dictionary and p.get("is_alive", false):
			lowest = minf(lowest, AIFaction.assess_player_strength(p))
	return lowest if lowest != INF else 999.0
