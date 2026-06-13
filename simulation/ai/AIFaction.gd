extends RefCounted
# GDD §8 — AI Faction base logic.
# All four archetypes share this state shape and tick() interface.
# Archetype-specific behaviour is in subfiles (BanditKing, MerchantPrince, etc.)
# that call the static helpers here via composition rather than inheritance.

const UnitRegistry  = preload("res://simulation/units/UnitRegistry.gd")
const UnitState     = preload("res://simulation/units/UnitState.gd")
const CombatSystem  = preload("res://simulation/combat/CombatSystem.gd")
const DifficultySystem = preload("res://simulation/core/DifficultySystem.gd")

const TICKS_PER_DAY: int = 240

# Valid archetype strings
const ARCHETYPE_BANDIT       = "bandit_king"
const ARCHETYPE_MERCHANT     = "merchant_prince"
const ARCHETYPE_IRONHAND     = "ironhand"
const ARCHETYPE_ASHEN_BARONY = "ashen_barony"

# Siege tent assembly: 48 game-days (GDD §1.1.4)
const SIEGE_ASSEMBLY_TICKS: int = TICKS_PER_DAY * 48

# ── Factory ───────────────────────────────────────────────────────────────────

static func make_faction(id: int, name: String, archetype: String,
		capital_x: int, capital_y: int) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"archetype": archetype,
		"is_alive": true,
		"capital_x": capital_x,
		"capital_y": capital_y,
		"gold": 500,
		"prestige": 100,
		"resources": {
			"wood": 200, "stone": 50, "iron": 0,
			"pitch": 0, "hops": 0, "wheat": 100,
		},
		"food": {"apples": 100, "bread": 0, "meat": 0, "ale": 0},
		"units": [],
		"buildings": [],
		"tech_unlocks": [],
		"active_edicts": [],
		"shire_ids": [],
		"days_alive": 0,
		"threat_level": 0.0,      # 0–100; rises as faction grows
		"siege_assembly": {},      # populated when assembling a siege tent
		"tribute_demands": [],     # Array of {player_id, resource, amount, deadline_tick}
		"last_attack_tick": 0,
		"population": 100,
		# Economy sim bookkeeping
		"daily_income_gold": 0,
		"daily_income_wood": 0,
		"daily_income_iron": 0,
	}

# ── Tick ─────────────────────────────────────────────────────────────────────

# Base tick: called every tick by GameState.simulate_tick() when an archetype
# tick returns. Handles shared daily bookkeeping.
# Returns Array of event strings: ["siege_assembled", "tribute_sent", ...].
static func tick(faction: Dictionary, world: Dictionary, tick: int) -> Array:
	var events: Array = []
	if not faction.get("is_alive", false):
		return events

	# Day boundary only for most logic
	if tick > 0 and tick % TICKS_PER_DAY == 0:
		faction["days_alive"] = faction.get("days_alive", 0) + 1

		# Accumulate resources based on archetype income rates
		_process_economy(faction)

		# Advance siege assembly
		if not faction["siege_assembly"].is_empty():
			var asm: Dictionary = faction["siege_assembly"]
			asm["ticks_elapsed"] = asm.get("ticks_elapsed", 0) + TICKS_PER_DAY
			faction["siege_assembly"] = asm
			if asm["ticks_elapsed"] >= SIEGE_ASSEMBLY_TICKS:
				events.append("siege_assembled")
				faction["last_siege_player_id"] = asm.get("target_player_id", -1)
				faction["siege_assembly"] = {}
				faction["last_attack_tick"] = tick

		# Threat level grows with time and resources
		_update_threat_level(faction)

	return events

# ── Economy simulation ────────────────────────────────────────────────────────

static func _process_economy(faction: Dictionary) -> void:
	# Simple flat income — archetypes override by modifying daily_income_* before calling this
	var arch: String = faction.get("archetype", "")
	var wood_rate:  int = faction.get("daily_income_wood", 0)
	var iron_rate:  int = faction.get("daily_income_iron", 0)
	var gold_rate:  int = faction.get("daily_income_gold", 0)

	# Defaults if archetype hasn't overridden
	if wood_rate == 0 and iron_rate == 0 and gold_rate == 0:
		match arch:
			ARCHETYPE_BANDIT:
				wood_rate = 30; gold_rate = 10
			ARCHETYPE_MERCHANT:
				gold_rate = 80; wood_rate = 10; iron_rate = 5
			ARCHETYPE_IRONHAND:
				iron_rate = 25; wood_rate = 15; gold_rate = 30
			ARCHETYPE_ASHEN_BARONY:
				iron_rate = 20; wood_rate = 20; gold_rate = 50

	faction["resources"]["wood"]  = faction["resources"].get("wood",  0) + wood_rate
	faction["resources"]["iron"]  = faction["resources"].get("iron",  0) + iron_rate
	faction["gold"] = faction.get("gold", 0) + gold_rate

# ── Threat level ──────────────────────────────────────────────────────────────

static func _update_threat_level(faction: Dictionary) -> void:
	var army_value: int = CombatSystem.get_army_value(faction.get("units", []))
	var gold: int       = faction.get("gold", 0)
	var days: int       = faction.get("days_alive", 0)
	# Threat = (army power / 10) + (gold / 100) + (days_alive / 5), capped at 100
	var threat: float = float(army_value) / 10.0 + float(gold) / 100.0 + float(days) / 5.0
	threat *= DifficultySystem.get_mod("ai_threat")
	faction["threat_level"] = minf(100.0, threat)

# ── Siege assembly ────────────────────────────────────────────────────────────

# Begin assembling a siege tent targeting a player's position.
# GDD §1.1.4: visible on macro map, 48h setup time.
static func start_siege(faction: Dictionary, target_player_id: int,
		target_x: int, target_y: int) -> void:
	faction["siege_assembly"] = {
		"target_player_id": target_player_id,
		"target_x": target_x,
		"target_y": target_y,
		"ticks_elapsed": 0,
	}

# ── Attack decision ───────────────────────────────────────────────────────────

# Returns true if the faction should initiate an attack on a player.
# Each archetype can set different thresholds.
static func should_attack(faction: Dictionary, players: Array) -> Dictionary:
	if not faction.get("is_alive", false):
		return {"attack": false, "target_player_id": -1}
	if not faction.get("siege_assembly", {}).is_empty():
		return {"attack": false, "target_player_id": -1}  # already assembling

	var arch: String = faction.get("archetype", "")
	var threat: float = faction.get("threat_level", 0.0)
	var threshold: float = 20.0   # default

	match arch:
		ARCHETYPE_BANDIT:     threshold = 15.0  # attacks early and often
		ARCHETYPE_MERCHANT:   threshold = 60.0  # rarely attacks
		ARCHETYPE_IRONHAND:   threshold = 50.0  # methodical, attacks when ready
		ARCHETYPE_ASHEN_BARONY: threshold = 40.0

	if threat < threshold or players.is_empty():
		return {"attack": false, "target_player_id": -1}

	# Target the player with the lowest military strength (or lowest prestige)
	var best_target: int = -1
	var lowest_strength: float = INF
	for p in players:
		if not (p is Dictionary and p.get("is_alive", false)):
			continue
		var strength: float = assess_player_strength(p)
		if strength < lowest_strength:
			lowest_strength = strength
			best_target = p.get("id", -1)

	if best_target == -1:
		return {"attack": false, "target_player_id": -1}
	return {"attack": true, "target_player_id": best_target}

# ── Recruit units ─────────────────────────────────────────────────────────────

# Composite strength score for a player (higher = stronger / harder target).
# Used by archetypes to choose targets and scale aggression adaptively.
static func assess_player_strength(player: Dictionary) -> float:
	var alive_units: int = 0
	for u in player.get("units", []):
		if u is Dictionary and u.get("is_alive", true):
			alive_units += 1
	var buildings: int = player.get("buildings", []).size()
	var gold: int = player.get("gold", 0)
	var population: int = player.get("population", 0)
	var popularity: float = player.get("popularity", 50.0)
	return float(alive_units) * 2.0 + float(buildings) * 0.5 + float(gold) * 0.01 + float(population) * 0.1 + popularity * 0.1

# Recruit one unit of the given type into the faction's army (no armory check for AI).
static func recruit_unit(faction: Dictionary, unit_type: String, next_uid: int) -> bool:
	var defn: Dictionary = UnitRegistry.lookup(unit_type)
	if defn.is_empty():
		return false
	var cost: int = defn.get("cost_gold", 0)
	if faction.get("gold", 0) < cost:
		return false
	faction["gold"] = faction.get("gold", 0) - cost
	var cx: int = faction.get("capital_x", 0)
	var cy: int = faction.get("capital_y", 0)
	var unit: Dictionary = UnitState.create(unit_type, faction.get("id", -1), cx, cy, next_uid)
	faction["units"].append(unit)
	return true

# ── Tribute demands (Ashen Barony, GDD §8.4.2) ───────────────────────────────

static func send_tribute_demand(faction: Dictionary, player_id: int,
		resource: String, amount: int, deadline_tick: int) -> void:
	faction["tribute_demands"].append({
		"player_id": player_id,
		"resource": resource,
		"amount": amount,
		"deadline_tick": deadline_tick,
		"fulfilled": false,
	})

static func get_pending_demands(faction: Dictionary, player_id: int) -> Array:
	var result: Array = []
	for d in faction.get("tribute_demands", []):
		if d.get("player_id", -1) == player_id and not d.get("fulfilled", false):
			result.append(d)
	return result
