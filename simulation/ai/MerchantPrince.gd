extends RefCounted
# GDD §8.2 — The Merchant Prince archetype.
# Economic defender. Expands slowly, targeting high-value coastal nodes.
# Maintains massive gold reserves; small elite army of Crossbowmen + Mercenaries.
# Defends aggressively but rarely initiates sieges.
# Punishes player economic weakness by bribing bandits and imposing embargoes.

const AIFaction      = preload("res://simulation/ai/AIFaction.gd")
const UnitRegistry   = preload("res://simulation/units/UnitRegistry.gd")
const DiplomacySystem = preload("res://simulation/ai/DiplomacySystem.gd")

# GDD §8.2.4: small elite army — crossbowmen, heavy infantry
const ARMY_WEIGHTS: Dictionary = {
	"crossbowman": 6,
	"swordsman": 2,
	"pikeman": 2,
}

const GOLD_RESERVE_TARGET: int = 2000  # hoards gold (GDD §8.2.2)
const EMBARGO_GOLD_THRESHOLD: int = 50 # attacks player economically if player is poor

static func make(id: int, capital_x: int, capital_y: int) -> Dictionary:
	var f: Dictionary = AIFaction.make_faction(id, "The Merchant Prince", AIFaction.ARCHETYPE_MERCHANT, capital_x, capital_y)
	f["gold"] = 1500
	f["resources"]["stone"] = 200
	f["daily_income_gold"] = 80
	f["daily_income_wood"] = 10
	f["daily_income_iron"] = 5
	f["embargoed_players"] = []
	return f

static func tick(faction: Dictionary, players: Array, _world: Dictionary, tick: int) -> Array:
	var events: Array = AIFaction.tick(faction, _world, tick)
	if not faction.get("is_alive", false):
		return events

	if tick > 0 and tick % AIFaction.TICKS_PER_DAY == 0:
		# Only recruit elite troops when we have surplus gold beyond reserve
		var surplus: int = faction.get("gold", 0) - GOLD_RESERVE_TARGET
		if surplus > 0:
			_recruit_elite(faction, surplus / 2)

		# Embargo weak players (GDD §8.2.5)
		_apply_embargoes(faction, players)

		# Rarely initiates — only at very high threat
		var attack_info: Dictionary = AIFaction.should_attack(faction, players)
		if attack_info.get("attack", false):
			AIFaction.start_siege(faction, attack_info["target_player_id"],
				_get_player_x(players, attack_info["target_player_id"]),
				_get_player_y(players, attack_info["target_player_id"]))
			events.append("merchant_siege_started")

	return events

static func _recruit_elite(faction: Dictionary, budget: int) -> void:
	var spent: int = 0
	var next_uid: int = faction.get("id", 0) * 10000 + faction.get("units", []).size() + 1
	while spent < budget:
		var roll: int = (next_uid + spent) % 10
		var utype: String = "crossbowman"
		if roll >= 6 and roll < 8:
			utype = "swordsman"
		elif roll >= 8:
			utype = "pikeman"
		var cost: int = UnitRegistry.lookup(utype).get("cost_gold", 50)
		if spent + cost > budget or faction.get("gold", 0) < cost:
			break
		AIFaction.recruit_unit(faction, utype, next_uid)
		next_uid += 1
		spent += cost

static func _apply_embargoes(faction: Dictionary, players: Array) -> void:
	var embargoed: Array = faction.get("embargoed_players", [])
	for p in players:
		if not (p is Dictionary and p.get("is_alive", false)):
			continue
		var pid: int = p.get("id", -1)
		# Embargo players that are economically OR militarily weak (GDD §8.2.5)
		var weak: bool = AIFaction.assess_player_strength(p) < 30.0
		if (p.get("gold", 0) <= EMBARGO_GOLD_THRESHOLD or weak) and pid not in embargoed:
			embargoed.append(pid)
	faction["embargoed_players"] = embargoed

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

# Returns true if the given player is currently embargoed.
# Delegates to the canonical DiplomacySystem check (single source of truth).
static func is_embargoed(faction: Dictionary, player_id: int) -> bool:
	return DiplomacySystem.is_embargoed(faction, player_id)
