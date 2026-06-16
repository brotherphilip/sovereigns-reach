extends RefCounted
# GDD §8 — AI Faction base logic.
# All four archetypes share this state shape and tick() interface.
# Archetype-specific behaviour is in subfiles (BanditKing, MerchantPrince, etc.)
# that call the static helpers here via composition rather than inheritance.

const UnitRegistry  = preload("res://simulation/units/UnitRegistry.gd")
const UnitState     = preload("res://simulation/units/UnitState.gd")
const CombatSystem  = preload("res://simulation/combat/CombatSystem.gd")
const DifficultySystem = preload("res://simulation/core/DifficultySystem.gd")
const ResourceTick     = preload("res://simulation/economy/ResourceTick.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")

# Order in which each archetype erects production buildings (cycled). The AI earns
# ONLY from these, at the same per-building rates the player gets — no free income.
# Includes hovels (housing — its workforce can't grow without homes) and food farms
# (it must feed that workforce), so a rival builds a balanced economy like the player.
const BUILD_PRIORITY: Dictionary = {
	"bandit_king":   ["apple_orchard", "woodcutter_camp", "hovel", "wheat_farm", "trading_post", "hovel", "woodcutter_camp"],
	"merchant_prince": ["apple_orchard", "trading_post", "hovel", "woodcutter_camp", "market", "hovel", "wheat_farm"],
	"ironhand":      ["apple_orchard", "woodcutter_camp", "hovel", "iron_mine", "stone_quarry", "hovel", "blacksmith", "trading_post"],
	"ashen_barony":  ["apple_orchard", "woodcutter_camp", "hovel", "iron_mine", "trading_post", "hovel", "stone_quarry"],
}
const MAX_FACTION_BUILDINGS: int = 22

# Food/gold routing for abstract faction stores.
const _FOOD_GOODS: Array = ["apples", "bread", "cheese", "meat", "ale"]

# Workforce / housing economy (abstract mirror of the player's).
const FOOD_PER_CAPITA: float = 0.5     # food units eaten per worker per day
const BASE_HOUSING: int = 8            # the faction's keep shelters this many
const HOVEL_ROOMS: int = 4
const START_WORKFORCE: int = 10

const TICKS_PER_DAY: int = 240

# Valid archetype strings
const ARCHETYPE_BANDIT       = "bandit_king"
const ARCHETYPE_MERCHANT     = "merchant_prince"
const ARCHETYPE_IRONHAND     = "ironhand"
const ARCHETYPE_ASHEN_BARONY = "ashen_barony"

# Siege tent assembly: 48 game-days (GDD §1.1.4)
const SIEGE_ASSEMBLY_TICKS: int = TICKS_PER_DAY * 48

# "King's Peace" — establishment grace. A freshly-arrived faction will not launch
# a siege against a player for its first PLAYER_GRACE_DAYS (≈ the first 6 real
# minutes of a new game at NORMAL speed). This is the window in which a new ruler
# raises farms, walls and a first garrison before the warlords are allowed to march.
# Long-lived world factions are unaffected (their days_alive is far past this).
const PLAYER_GRACE_DAYS: int = 30

# Diplomacy depth: refusing a tribute demand adds a PERSISTENT grievance that raises
# the faction's threat (escalating toward a siege) and cools slowly; paying tribute
# buys a guaranteed peace window and soothes grievance — so the choice has real stakes.
const GRIEVANCE_ON_REFUSE: float = 18.0   # threat added per refusal (persistent)
const GRIEVANCE_ON_ACCEPT: float = 25.0   # grievance soothed by paying tribute
const GRIEVANCE_DECAY: float = 1.0        # grievance cooled per game-day
const TRIBUTE_PEACE_DAYS: int = 14        # days of guaranteed peace bought by paying

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
		"next_unit_id": id * 10000 + 1,  # monotonic per-faction unit id counter
		"tribute_demands": [],     # Array of {player_id, resource, amount, deadline_tick}
		"last_attack_tick": 0,
		"population": START_WORKFORCE,
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

		# Erect a production building if affordable, then earn only from what's built.
		_build_economy(faction)
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

		# Purge fulfilled or expired tribute demands so the array doesn't grow unbounded
		var live_demands: Array = []
		for d in faction.get("tribute_demands", []):
			if d is Dictionary and not d.get("fulfilled", false) and d.get("deadline_tick", 0) >= tick:
				live_demands.append(d)
		faction["tribute_demands"] = live_demands

		# Purge dead units so the army array doesn't grow unbounded over long campaigns
		var live_units: Array = []
		for u in faction.get("units", []):
			if u is Dictionary and u.get("is_alive", false):
				live_units.append(u)
		faction["units"] = live_units

	return events

# ── Economy simulation ────────────────────────────────────────────────────────

# A faction earns ONLY from production buildings that are STAFFED by its workforce, at
# the same per-worker rates the player gets. Workers are assigned building-by-building
# until the workforce runs out — so unstaffed buildings produce nothing, and a rival
# that hasn't grown a workforce (needs housing + food) earns little. Buildings produce
# nothing while their input is short, and the workforce is then fed and may grow.
static func _process_economy(faction: Dictionary) -> void:
	var res: Dictionary = faction.get("resources", {})
	var food: Dictionary = faction.get("food", {})
	var pool: int = int(faction.get("population", 0))   # workers available today
	for b in faction.get("buildings", []):
		var btype: String = b if b is String else (b.get("type", "") if b is Dictionary else "")
		if btype == "" or not ResourceTick.PRODUCTION_OUTPUTS.has(btype):
			continue   # not a producer (hovel, market…) — no goods, no worker draw
		if pool <= 0:
			break      # no workers left — remaining buildings stand idle
		var maxw: int = maxi(1, int(BuildingRegistry.lookup(btype).get("max_workers", 1)))
		var staff: int = mini(maxw, pool)
		# Processors can't run without their input (scaled to the crew on hand).
		var inputs: Dictionary = ResourceTick.daily_input(btype, staff)
		var short: bool = false
		for r in inputs:
			if int(res.get(r, 0)) < int(inputs[r]):
				short = true
				break
		if short:
			continue   # idle for lack of materials — keep the workers free
		pool -= staff
		for r in inputs:
			res[r] = int(res.get(r, 0)) - int(inputs[r])
		for g in ResourceTick.daily_output(btype, staff):
			var amt: int = int(ResourceTick.daily_output(btype, staff)[g])
			if g == "gold":
				faction["gold"] = faction.get("gold", 0) + amt
			elif g in _FOOD_GOODS:
				food[g] = int(food.get(g, 0)) + amt
			else:
				res[g] = int(res.get(g, 0)) + amt
	faction["resources"] = res
	faction["food"] = food
	_feed_and_grow(faction)

# The workforce eats daily; if fed and there's a free room it grows, otherwise it
# starves and shrinks — the same housing+food pressure the player's population faces.
static func _feed_and_grow(faction: Dictionary) -> void:
	var pop: int = int(faction.get("population", 0))
	var food: Dictionary = faction.get("food", {})
	var remaining: int = int(ceil(float(pop) * FOOD_PER_CAPITA))
	for ft in ["apples", "bread", "cheese", "meat"]:
		if remaining <= 0:
			break
		var take: int = mini(int(food.get(ft, 0)), remaining)
		food[ft] = int(food.get(ft, 0)) - take
		remaining -= take
	faction["food"] = food
	if remaining > 0:
		faction["population"] = maxi(1, pop - maxi(1, remaining / 2))   # famine
	elif pop < _ai_housing_cap(faction):
		faction["population"] = pop + 1                                  # housed & fed → grow

static func _ai_housing_cap(faction: Dictionary) -> int:
	var cap: int = BASE_HOUSING
	for b in faction.get("buildings", []):
		var btype: String = b if b is String else (b.get("type", "") if b is Dictionary else "")
		if btype == "hovel":
			cap += HOVEL_ROOMS
	return cap

# Erect one production building per day if affordable, following the archetype's
# priority cycle. Buildings cost the standard BuildingRegistry resources.
static func _build_economy(faction: Dictionary) -> void:
	var blds: Array = faction.get("buildings", [])
	if blds.size() >= MAX_FACTION_BUILDINGS:
		return
	var order: Array = BUILD_PRIORITY.get(faction.get("archetype", ""), [])
	if order.is_empty():
		return
	var btype: String = order[blds.size() % order.size()]
	var cost: Dictionary = BuildingRegistry.lookup(btype).get("cost", {})
	var res: Dictionary = faction.get("resources", {})
	for r in cost:
		var have: int = faction.get("gold", 0) if r == "gold" else int(res.get(r, 0))
		if have < int(cost[r]):
			return  # can't afford yet — wait until production allows it
	for r in cost:
		if r == "gold":
			faction["gold"] = faction.get("gold", 0) - int(cost[r])
		else:
			res[r] = int(res.get(r, 0)) - int(cost[r])
	faction["resources"] = res
	blds.append(btype)
	faction["buildings"] = blds

# ── Threat level ──────────────────────────────────────────────────────────────

static func _update_threat_level(faction: Dictionary) -> void:
	var army_value: int = CombatSystem.get_army_value(faction.get("units", []))
	var gold: int       = faction.get("gold", 0)
	var days: int       = faction.get("days_alive", 0)
	# Threat = (army power / 10) + (gold / 100) + (days_alive / 5), capped at 100
	var threat: float = float(army_value) / 10.0 + float(gold) / 100.0 + float(days) / 5.0
	threat *= DifficultySystem.get_mod("ai_threat")
	# Persistent diplomatic grievance (refused tribute) escalates the threat, then cools
	# slowly — so a refusal has lasting weight instead of being wiped next tick.
	threat += faction.get("grievance", 0.0)
	faction["grievance"] = maxf(0.0, faction.get("grievance", 0.0) - GRIEVANCE_DECAY)
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
static func should_attack(faction: Dictionary, players: Array, tick: int = 0) -> Dictionary:
	if not faction.get("is_alive", false):
		return {"attack": false, "target_player_id": -1}
	if not faction.get("siege_assembly", {}).is_empty():
		return {"attack": false, "target_player_id": -1}  # already assembling
	# King's Peace: no sieges against the player during a fresh faction's grace window.
	if faction.get("days_alive", 0) < PLAYER_GRACE_DAYS:
		return {"attack": false, "target_player_id": -1}
	# Tribute recently paid buys peace — an appeased faction won't besiege you yet.
	if tick > 0 and tick < int(faction.get("tribute_peace_until", 0)):
		return {"attack": false, "target_player_id": -1}

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
# The unit id comes from a monotonic per-faction counter so ids are never reused
# after dead units are purged (the legacy size()-based id collided). The optional
# next_uid argument is retained for caller compatibility but no longer sets the id.
static func recruit_unit(faction: Dictionary, unit_type: String, _next_uid: int = -1) -> bool:
	var defn: Dictionary = UnitRegistry.lookup(unit_type)
	if defn.is_empty():
		return false
	var cost: int = defn.get("cost_gold", 0)
	if faction.get("gold", 0) < cost:
		return false
	faction["gold"] = faction.get("gold", 0) - cost
	var cx: int = faction.get("capital_x", 0)
	var cy: int = faction.get("capital_y", 0)
	var uid: int = faction.get("next_unit_id", faction.get("id", 0) * 10000 + 1)
	faction["next_unit_id"] = uid + 1
	var unit: Dictionary = UnitState.create(unit_type, faction.get("id", -1), cx, cy, uid)
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
