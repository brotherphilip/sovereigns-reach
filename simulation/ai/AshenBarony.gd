extends RefCounted
# GDD §8.4 — The Ashen Barony (Lord Malakor).
# Mid-to-late game threat. Controls the Southern Reach.
# Capital: Highwatch — triple-thick stone walls, labyrinth gatehouses, ballistas on every tower.
# Sends diplomatic demands for Ale and Iron before military action.
# Supplies its army via external logging villages (cutting supply lines stops repairs).
# Fills moats with dirt, flanks with trebuchets, dumps boiling oil.

const AIFaction    = preload("res://simulation/ai/AIFaction.gd")
const UnitRegistry = preload("res://simulation/units/UnitRegistry.gd")
const CombatSystem = preload("res://simulation/combat/CombatSystem.gd")

const CAPITAL_NAME: String = "Highwatch"
const DEMAND_RESOURCE_1: String = "ale"
const DEMAND_RESOURCE_2: String = "iron"
const DEMAND_COOLDOWN_DAYS: int = 14    # days between tribute demands
const TRIBUTE_ALE_AMOUNT: int   = 50
const TRIBUTE_IRON_AMOUNT: int  = 30

# GDD §8.4: flanks with trebuchets, boiling oil, then heavy infantry
const ARMY_WEIGHTS: Dictionary = {
	"swordsman": 4,
	"pikeman": 2,
	"trebuchet": 2,
	"battering_ram": 1,
	"crossbowman": 1,
}

# Supply lines: if any supply line is active the faction repairs walls faster.
# (In the simulation, supply lines are tracked as booleans.)
const SUPPLY_LINE_WOOD_DAILY: int = 30

static func make(id: int, capital_x: int, capital_y: int) -> Dictionary:
	var f: Dictionary = AIFaction.make_faction(id, "The Ashen Barony", AIFaction.ARCHETYPE_ASHEN_BARONY, capital_x, capital_y)
	f["capital_name"] = CAPITAL_NAME
	f["resources"]["stone"] = 500
	f["resources"]["iron"] = 300
	f["gold"] = 1200
	f["daily_income_iron"] = 20
	f["daily_income_wood"] = 20
	f["daily_income_gold"] = 50
	f["tech_unlocks"] = ["unit_unlocks", "armor_forging", "siege_engines", "scouting_vision"]
	f["supply_lines_active"] = true
	f["last_demand_day"] = 0
	return f

static func tick(faction: Dictionary, players: Array, _world: Dictionary, tick: int) -> Array:
	var events: Array = AIFaction.tick(faction, _world, tick)
	if not faction.get("is_alive", false):
		return events

	if tick > 0 and tick % AIFaction.TICKS_PER_DAY == 0:
		var day: int = faction.get("days_alive", 0)

		# S15: a player who fields a stronger army than the barony interdicts its
		# logging routes, cutting the supply lines (stops the repair/wood bonus).
		if faction.get("supply_lines_active", false):
			var barony_power: int = CombatSystem.get_army_value(faction.get("units", []))
			for p in players:
				if p is Dictionary and p.get("is_alive", false):
					if CombatSystem.get_army_value(p.get("units", [])) > barony_power and barony_power > 0:
						cut_supply_lines(faction)
						events.append("ashen_supply_cut")
						break

		# Supply line income bonus (GDD §8.4.4)
		if faction.get("supply_lines_active", false):
			faction["resources"]["wood"] = faction["resources"].get("wood", 0) + SUPPLY_LINE_WOOD_DAILY

		# Diplomatic demands every 14 days (GDD §8.4.2)
		if day > 0 and day - faction.get("last_demand_day", 0) >= DEMAND_COOLDOWN_DAYS:
			_send_demands(faction, players, tick)
			events.append("ashen_tribute_demanded")

		# Recruit mixed army
		_recruit_barony(faction)

		# Attack decision
		var attack_info: Dictionary = AIFaction.should_attack(faction, players)
		if attack_info.get("attack", false):
			AIFaction.start_siege(faction, attack_info["target_player_id"],
				_get_player_x(players, attack_info["target_player_id"]),
				_get_player_y(players, attack_info["target_player_id"]))
			events.append("ashen_siege_started")

	return events

static func _send_demands(faction: Dictionary, players: Array, tick: int) -> void:
	var deadline: int = tick + AIFaction.TICKS_PER_DAY * 7  # 7-day deadline
	for p in players:
		if not (p is Dictionary and p.get("is_alive", false)):
			continue
		var scale: float = clampf(AIFaction.assess_player_strength(p) / 50.0, 0.5, 3.0)
		AIFaction.send_tribute_demand(faction, p.get("id", -1), DEMAND_RESOURCE_1, int(TRIBUTE_ALE_AMOUNT * scale), deadline)
		AIFaction.send_tribute_demand(faction, p.get("id", -1), DEMAND_RESOURCE_2, int(TRIBUTE_IRON_AMOUNT * scale), deadline)
	faction["last_demand_day"] = faction.get("days_alive", 0)

static func _recruit_barony(faction: Dictionary) -> void:
	var budget: int = mini(300, faction.get("gold", 0) / 2)
	var spent: int = 0
	var next_uid: int = faction.get("id", 0) * 10000 + faction.get("units", []).size() + 1
	while spent < budget:
		var roll: int = (next_uid + spent) % 10
		var utype: String = "swordsman"
		if roll >= 4 and roll < 6:
			utype = "pikeman"
		elif roll >= 6 and roll < 8:
			utype = "trebuchet"
		elif roll == 8:
			utype = "battering_ram"
		elif roll == 9:
			utype = "crossbowman"
		var cost: int = UnitRegistry.lookup(utype).get("cost_gold", 60)
		if spent + cost > budget or faction.get("gold", 0) < cost:
			break
		AIFaction.recruit_unit(faction, utype, next_uid)
		next_uid += 1
		spent += cost

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

# Returns true if the barony's supply lines to logging villages are still active.
# Cutting them (GDD §8.4.4) prevents wall repairs.
static func has_supply_lines(faction: Dictionary) -> bool:
	return faction.get("supply_lines_active", false)

# Simulate cutting supply lines (e.g. player destroys logging village).
static func cut_supply_lines(faction: Dictionary) -> void:
	faction["supply_lines_active"] = false
