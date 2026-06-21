extends RefCounted
const EdictSystem      = preload("res://simulation/edicts/EdictSystem.gd")
const TechTree         = preload("res://simulation/tech/TechTree.gd")
const SeasonSystem     = preload("res://simulation/world/SeasonSystem.gd")
const BuildingRegistry = preload("res://simulation/buildings/BuildingRegistry.gd")
const DifficultySystem = preload("res://simulation/core/DifficultySystem.gd")
# Handles per-tick resource production and consumption for all buildings.
# Called from GameState.simulate_tick() once per simulation tick.
# GDD §5.2–5.4 (Building Roster), §4.2–4.4 (Tech Tree production bonuses).
#
# Production model:
#   Each building has a production interval (ticks between outputs).
#   When current_tick % interval == 0, the building produces its output.
#   Workers must be assigned; output scales linearly with worker count.

# Production intervals at 1× speed (ticks between producing 1 unit of output)
# 20 ticks = 1 second at normal speed; 240 ticks = 1 game day
const PRODUCTION_INTERVALS: Dictionary = {
	"woodcutter_camp":   30,   # ~1.5s per wood
	"stone_quarry":      120,  # 6s per stone (slow — needs ox tethers)
	"iron_mine":         180,  # 9s per iron
	"pitch_rig":         60,   # 3s per pitch
	"apple_orchard":     150,  # the no-tech staple — must feed the early village
	"pig_farm":          360,  # meat (animal husbandry)
	"dairy_farm":        300,  # cheese (animal husbandry)
	"hops_farm":         360,  # 18s per hops
	"wheat_farm":        360,  # 18s per wheat (bread chain reward)
	"mill":              120,  # 6s per flour (converts wheat)
	"bakery":            180,  # 9s per bread (converts flour)
	"brewery":           240,  # 12s per ale (converts hops)
	"fletcher":          90,   # 4.5s per bow
	"poleturner":        60,   # 3s per pike
	"blacksmith":        300,  # 15s per sword (slow — iron required)
	"tannery":           240,  # 12s per leather armour (from leather)
	"armorer":           360,  # 18s per plate armour (slow — iron required)
	"crossbow_workshop": 300,  # 15s per crossbow (wood + iron)
	"trading_post":      480,  # once per game day (24s) — gold income from caravans
}

# Resource input requirements (what each producer CONSUMES to make output)
const PRODUCTION_INPUTS: Dictionary = {
	"mill":        {"wheat": 1},
	"bakery":      {"flour": 1},
	"brewery":     {"hops": 1},
	"blacksmith":  {"iron": 2},
	"fletcher":    {"wood": 1},
	"poleturner":  {"wood": 1},
	"tannery":     {"leather": 1},
	"armorer":     {"iron": 2},
	"crossbow_workshop": {"wood": 1, "iron": 1},
}

# Resource outputs per production tick
const PRODUCTION_OUTPUTS: Dictionary = {
	"woodcutter_camp":   {"wood": 1},
	"stone_quarry":      {"stone": 1},
	"iron_mine":         {"iron": 1},
	"pitch_rig":         {"pitch": 1},
	"apple_orchard":     {"apples": 10},  # staple early food — sized so ONE staffed orchard reliably feeds the founding village even with long hauls to a far-placed granary (hauling throughput is distance-sensitive; a new player shouldn't slowly starve just for spreading buildings out)
	"pig_farm":          {"meat": 1, "leather": 1},   # pigs yield meat + hides (leather source)
	"dairy_farm":        {"cheese": 1},
	"hops_farm":         {"hops": 2},
	"wheat_farm":        {"wheat": 3},
	"mill":              {"flour": 1},
	"bakery":            {"bread": 1},
	"brewery":           {"ale": 2},
	"fletcher":          {"bows": 1},
	"poleturner":        {"pikes": 1},
	"blacksmith":        {"swords": 1},
	"tannery":           {"leather_armor": 1},
	"armorer":           {"plate_armor": 1},
	"crossbow_workshop": {"crossbows": 1},
	"trading_post":      {"gold": 3},
}

# Farm buildings (terrain/weather/season sensitive).
const FARM_TYPES: Array = ["apple_orchard", "wheat_farm", "hops_farm", "pig_farm", "dairy_farm"]

const _TICKS_PER_DAY: int = 240

# A building's daily OUTPUT at standard rates, scaled by the number of workers staffing
# it (default = full staff). The same per-worker production the player's buildings get —
# used by the AI's building economy, so an UNSTAFFED building produces nothing.
static func daily_output(btype: String, workers: int = -1) -> Dictionary:
	return _daily_amounts(PRODUCTION_OUTPUTS.get(btype, {}), btype, workers)

# A building's daily INPUT consumption (processors), scaled by staffing.
static func daily_input(btype: String, workers: int = -1) -> Dictionary:
	return _daily_amounts(PRODUCTION_INPUTS.get(btype, {}), btype, workers)

static func _daily_amounts(table: Dictionary, btype: String, workers: int = -1) -> Dictionary:
	var interval: int = PRODUCTION_INTERVALS.get(btype, 0)
	if table.is_empty() or interval <= 0:
		return {}
	var max_w: int = maxi(1, BuildingRegistry.lookup(btype).get("max_workers", 1))
	var w: int = max_w if workers < 0 else clampi(workers, 0, max_w)
	if w <= 0:
		return {}   # no workers → no production
	var cycles: float = float(_TICKS_PER_DAY) / float(interval)
	var result: Dictionary = {}
	for res in table:
		result[res] = maxi(1, int(round(float(table[res]) * float(w) * cycles)))
	return result

# A "chain" building is one whose goods are now produced by physical haul trips
# (gather/fetch → process → deliver) rather than abstract interval ticks. Everything in
# PRODUCTION_OUTPUTS except trading_post (gold caravans stay interval-based income).
static func is_chain(btype: String) -> bool:
	return PRODUCTION_OUTPUTS.has(btype) and btype != "trading_post"

# Output ONE worker delivers per completed haul trip, with the same yield multipliers
# the old interval production applied (terrain, tech, edict, season, weather farm mult).
# Used by the hauler at the deposit step — the only place chain output is credited.
static func per_worker_output(building: Dictionary, player: Dictionary, season: int = 0, farm_mult: float = 1.0) -> Dictionary:
	var btype: String = building.get("type", "")
	var outputs: Dictionary = PRODUCTION_OUTPUTS.get(btype, {})
	if outputs.is_empty():
		return {}
	var edict_mods: Dictionary = EdictSystem.get_active_modifiers(player)
	var food_bonus: float = edict_mods.get("food_production_bonus", 0.0)
	var orchard_yield_bonus: float = edict_mods.get("orchard_yield_bonus", 0.0)
	var tech_mods: Dictionary = TechTree.get_all_modifiers(player)
	var farm_yield_bonus: float = tech_mods.get("farm_yield_bonus", 0.0)
	var mining_rate_bonus: float = tech_mods.get("mining_rate_bonus", 0.0)
	var season_mult: float = SeasonSystem.harvest_yield_mult(btype, season)
	var result: Dictionary = {}
	for res in outputs:
		var amount: float = float(outputs[res])   # per worker, per trip
		if btype in ["apple_orchard", "wheat_farm", "hops_farm"]:
			amount *= building.get("terrain_yield", 1.0)
		if food_bonus > 0.0 and res in ["apples", "meat", "cheese", "wheat", "hops", "flour", "bread"]:
			amount *= (1.0 + food_bonus)
		if farm_yield_bonus > 0.0 and btype in FARM_TYPES:
			amount *= (1.0 + farm_yield_bonus)
		if orchard_yield_bonus > 0.0 and btype == "apple_orchard":
			amount *= (1.0 + orchard_yield_bonus)
		if mining_rate_bonus > 0.0 and btype in ["stone_quarry", "iron_mine"]:
			amount *= (1.0 + mining_rate_bonus)
		if season_mult != 1.0:
			amount *= season_mult
		if farm_mult != 1.0 and btype in FARM_TYPES:
			amount *= farm_mult
		var amt: int = int(ceil(amount))
		if amt > 0:
			result[res] = amt
	return result

# Per-tick food consumption per peasant (GDD §3.1.3 granary distribution)
const FOOD_CONSUMPTION_PER_PEASANT_PER_DAY: float = 0.5

# Ration multipliers for food consumption
const RATION_CONSUMPTION_MULTIPLIERS: Dictionary = {
	0: 0.0,   # No rations — peasants starve
	1: 0.5,
	2: 1.0,   # Normal
	3: 1.5,
	4: 2.0,
}

# Tick a single building's production. Returns a Dictionary of resource changes.
# building: Dictionary from GameState players[i].buildings
# player: Dictionary of player state (for checking input resources)
# current_tick: int
static func tick_building(building: Dictionary, player: Dictionary, current_tick: int) -> Dictionary:
	var changes: Dictionary = {}
	if not building.get("built", true):
		return changes   # still under construction — no output yet
	var btype: String = building.get("type", "")
	var interval: int = PRODUCTION_INTERVALS.get(btype, 0)
	if interval == 0:
		return changes

	if current_tick == 0 or current_tick % interval != 0:
		return changes

	var workers: int = building.get("workers", 0)
	if workers == 0:
		return changes

	# Check if required input resources are available
	var inputs: Dictionary = PRODUCTION_INPUTS.get(btype, {})
	for res in inputs:
		var required: int = inputs[res] * workers
		if player["resources"].get(res, 0) < required:
			return changes  # Not enough input material

	# Consume inputs
	for res in inputs:
		changes[res] = -(inputs[res] * workers)

	# Produce outputs, scaled by worker count and terrain yield for farms
	var outputs: Dictionary = PRODUCTION_OUTPUTS.get(btype, {})
	var edict_mods: Dictionary = EdictSystem.get_active_modifiers(player)
	var food_bonus: float = edict_mods.get("food_production_bonus", 0.0)
	var orchard_yield_bonus: float = edict_mods.get("orchard_yield_bonus", 0.0)
	var tech_mods: Dictionary = TechTree.get_all_modifiers(player)
	var farm_yield_bonus: float = tech_mods.get("farm_yield_bonus", 0.0)
	var mining_rate_bonus: float = tech_mods.get("mining_rate_bonus", 0.0)
	# Crops only fruit & get picked in their harvest season; off-season the field is
	# tended (workers still animate) but yields nothing. Year-round producers (animals,
	# industry) are unaffected. Stacks with weather (drought/snow already zero yields).
	var season: int = SeasonSystem.season_at_tick(current_tick)
	var season_mult: float = SeasonSystem.harvest_yield_mult(btype, season)
	for res in outputs:
		var amount: int = outputs[res] * workers
		if btype in ["apple_orchard", "wheat_farm", "hops_farm"]:
			var yield_mult: float = building.get("terrain_yield", 1.0)
			amount = int(ceil(amount * yield_mult))
		if season_mult != 1.0:
			amount = int(ceil(float(amount) * season_mult))
		if food_bonus > 0.0 and res in ["apples", "meat", "cheese", "wheat", "hops", "flour", "bread"]:
			amount = int(ceil(float(amount) * (1.0 + food_bonus)))
		if farm_yield_bonus > 0.0 and btype in ["apple_orchard", "wheat_farm", "hops_farm", "pig_farm", "dairy_farm"]:
			amount = int(ceil(float(amount) * (1.0 + farm_yield_bonus)))
		if orchard_yield_bonus > 0.0 and btype == "apple_orchard":
			amount = int(ceil(float(amount) * (1.0 + orchard_yield_bonus)))
		if mining_rate_bonus > 0.0 and btype in ["stone_quarry", "iron_mine"]:
			amount = int(ceil(float(amount) * (1.0 + mining_rate_bonus)))
		if res == "gold" and btype == "trading_post":
			var trade_bonus: float = tech_mods.get("trade_income_bonus", 0.0) + edict_mods.get("trade_income_bonus", 0.0) + tech_mods.get("cart_capacity_bonus", 0.0)
			if trade_bonus > 0.0:
				amount = int(ceil(float(amount) * (1.0 + trade_bonus)))
		if changes.has(res):
			changes[res] += amount
		else:
			changes[res] = amount

	return changes

# Apply food consumption for the entire village each game day.
# Returns a Dictionary of food deltas (negative values).
static func tick_food_consumption(player: Dictionary, current_tick: int) -> Dictionary:
	if current_tick % 240 != 0:  # Only on day boundaries
		return {}

	var population: int = player.get("population", 0)
	if population == 0:
		return {}

	var ration: int = player.get("food_ration", 2)
	var mult: float = RATION_CONSUMPTION_MULTIPLIERS.get(ration, 1.0)
	var daily_demand: float = population * FOOD_CONSUMPTION_PER_PEASANT_PER_DAY * mult
	var _consumption_mods: Dictionary = EdictSystem.get_active_modifiers(player)
	var _tech_mods: Dictionary = TechTree.get_all_modifiers(player)
	var total_food_reduction: float = _consumption_mods.get("food_consumption_reduction", 0.0) + _tech_mods.get("army_food_cost_reduction", 0.0)
	daily_demand *= maxf(0.0, 1.0 - total_food_reduction)
	# Difficulty scales hunger (PEACEFUL 0.7 … SIEGE_LORD 1.5; NORMAL=1.0). This is the LIVE food path;
	# the modifier was previously only honoured by the dead FoodSystem.tick, so difficulty silently did
	# not affect food consumption in the real game (iter297). NORMAL leaves default play unchanged.
	daily_demand *= DifficultySystem.get_mod("food_consumption")

	var changes: Dictionary = {}
	var food: Dictionary = player.get("food", {})
	var remaining: float = daily_demand

	# Distribute consumption across food types (peasants eat all available)
	for food_type in ["apples", "bread", "cheese", "meat"]:  # cheapest first — GDD §3.1.2
		var available: int = food.get(food_type, 0)
		if available <= 0 or remaining <= 0:
			continue
		var consumed: int = mini(available, int(ceil(remaining)))
		changes[food_type] = -consumed
		remaining -= consumed

	return changes

# Apply all resource changes from a changes dict to a player's state.
# Returns True if any resources went negative (starvation/shortage signal).
static func apply_changes(player: Dictionary, changes: Dictionary) -> bool:
	var shortage: bool = false
	for res in changes:
		var delta: int = changes[res]
		if res in player["resources"]:
			player["resources"][res] = maxi(0, player["resources"][res] + delta)
			if delta < 0 and player["resources"][res] == 0:
				shortage = true
		elif res in player["food"]:
			player["food"][res] = maxi(0, player["food"][res] + delta)
			if delta < 0 and player["food"][res] == 0:
				shortage = true
		elif res in player["armory"]:
			player["armory"][res] = maxi(0, player["armory"][res] + delta)
		elif res == "gold":
			player["gold"] = player.get("gold", 0) + delta
	return shortage
