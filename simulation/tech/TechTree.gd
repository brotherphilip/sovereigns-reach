extends RefCounted
# GDD §4 — The Tech Tree
# Static registry of all 20 research techs across 5 branches.
# Prestige is the research currency (GDD §4.1.2).
# Building unlock requirements are already encoded in BuildingRegistry.requires_tech fields.

enum Branch { AGRICULTURE, INDUSTRY, MILITARY, STATECRAFT, PRESTIGE_ECONOMY }

# Full tech definitions.
# Keys: branch, tier (1=early … 4=late), cost_prestige, requires (list of tech_ids),
#       unlocks_buildings, unlocks_units, unlocks_edicts, modifiers (dict of stat keys).
const TECHS: Dictionary = {
	# ── §4.2 Agriculture ──────────────────────────────────────────────────────
	"crop_tiers": {
		"name": "Crop Tiers",
		"branch": Branch.AGRICULTURE, "tier": 1, "cost_prestige": 100,
		"requires": [],
		"unlocks_buildings": ["wheat_farm", "hops_field"],
		"unlocks_units": [], "unlocks_edicts": [],
		"modifiers": {},
		"description": "Unlocks wheat and hops farming chains. Required for bread and ale production.",
	},
	"farming_speed": {
		"name": "Farming Speed",
		"branch": Branch.AGRICULTURE, "tier": 2, "cost_prestige": 200,
		"requires": ["crop_tiers"],
		"unlocks_buildings": [], "unlocks_units": [], "unlocks_edicts": [],
		"modifiers": {"harvest_rate_bonus": 0.2},
		"description": "Harvest rate +20%. Reduces peasant travel time to fields.",
	},
	"storage_capacity": {
		"name": "Storage Capacity",
		"branch": Branch.AGRICULTURE, "tier": 2, "cost_prestige": 200,
		"requires": ["crop_tiers"],
		"unlocks_buildings": [], "unlocks_units": [], "unlocks_edicts": [],
		"modifiers": {"granary_capacity_bonus": 0.5},
		"description": "Granary capacity +50%. Reduces spoilage rates. Enables deep cellars.",
	},
	"animal_husbandry": {
		"name": "Animal Husbandry",
		"branch": Branch.AGRICULTURE, "tier": 3, "cost_prestige": 400,
		"requires": ["crop_tiers"],
		"unlocks_buildings": ["pig_farm", "dairy_farm"],
		"unlocks_units": [], "unlocks_edicts": [],
		"modifiers": {},
		"description": "Unlocks Pig Farms (meat) and Dairy Farms (cheese). Provides leather for armor.",
	},
	"advanced_tools": {
		"name": "Advanced Tools",
		"branch": Branch.AGRICULTURE, "tier": 4, "cost_prestige": 600,
		"requires": ["farming_speed", "animal_husbandry"],
		"unlocks_buildings": [], "unlocks_units": [], "unlocks_edicts": [],
		"modifiers": {"farm_yield_bonus": 0.25},
		"description": "Iron plows and scythes. Farm yield +25%. Requires active blacksmith.",
	},

	# ── §4.3 Industry ────────────────────────────────────────────────────────
	"resource_unlocks": {
		"name": "Resource Unlocks",
		"branch": Branch.INDUSTRY, "tier": 1, "cost_prestige": 150,
		"requires": [],
		"unlocks_buildings": ["stone_quarry", "iron_mine"],
		"unlocks_units": [], "unlocks_edicts": [],
		"modifiers": {},
		"description": "Unlocks Stone Quarries and Iron Mines. Required for fortifications and weapons.",
	},
	"mining_speed": {
		"name": "Mining Speed",
		"branch": Branch.INDUSTRY, "tier": 2, "cost_prestige": 250,
		"requires": ["resource_unlocks"],
		"unlocks_buildings": [], "unlocks_units": [], "unlocks_edicts": [],
		"modifiers": {"mining_rate_bonus": 0.2},
		"description": "Mining rate +20%. Synergizes with Capital Grand Forge buff.",
	},
	"transport_logistics": {
		"name": "Transport Logistics",
		"branch": Branch.INDUSTRY, "tier": 2, "cost_prestige": 200,
		"requires": ["resource_unlocks"],
		"unlocks_buildings": ["guildhall"],
		"unlocks_units": [], "unlocks_edicts": [],
		"modifiers": {"cart_capacity_bonus": 0.5},
		"description": "Unlocks Guildhall. Ox tethers and trade carts. Cart capacity +50%.",
	},
	"refining_processing": {
		"name": "Refining & Processing",
		"branch": Branch.INDUSTRY, "tier": 3, "cost_prestige": 400,
		"requires": ["resource_unlocks"],
		"unlocks_buildings": ["sawmill", "smelter"],
		"unlocks_units": [], "unlocks_edicts": [],
		"modifiers": {},
		"description": "Unlocks Sawmill and Smelter. Required for refined lumber and ingots for advanced weapons.",
	},
	"advanced_masonry": {
		"name": "Advanced Masonry",
		"branch": Branch.INDUSTRY, "tier": 4, "cost_prestige": 800,
		"requires": ["refining_processing", "mining_speed"],
		"unlocks_buildings": ["great_tower"],
		"unlocks_units": [], "unlocks_edicts": [],
		"modifiers": {"wall_hp_bonus": 0.3},
		"description": "Unlocks Great Towers. Thick stone walls and elaborate gatehouses. Wall HP +30%.",
	},

	# ── §4.4 Military ────────────────────────────────────────────────────────
	"weapon_crafting": {
		"name": "Weapon Crafting",
		"branch": Branch.MILITARY, "tier": 1, "cost_prestige": 150,
		"requires": [],
		"unlocks_buildings": ["fletcher", "blacksmith"],
		"unlocks_units": [], "unlocks_edicts": [],
		"modifiers": {},
		"description": "Unlocks Fletcher and Blacksmith. In-house arming bypasses expensive markets.",
	},
	"armor_forging": {
		"name": "Armor Forging",
		"branch": Branch.MILITARY, "tier": 2, "cost_prestige": 300,
		"requires": ["weapon_crafting"],
		"unlocks_buildings": [], "unlocks_units": ["armored_archer", "swordsman"],
		"unlocks_edicts": [],
		"modifiers": {"unit_armor_rating": 0.25},
		"description": "Unlocks leather and iron armor. Required for Swordsmen. Unit armor +25%.",
	},
	"unit_unlocks": {
		"name": "Unit Unlocks",
		"branch": Branch.MILITARY, "tier": 2, "cost_prestige": 250,
		"requires": ["weapon_crafting"],
		"unlocks_buildings": [], "unlocks_units": ["archer", "pikeman", "crossbowman"],
		"unlocks_edicts": [],
		"modifiers": {},
		"description": "Unlocks Archers, Pikemen, and Crossbowmen unit types.",
	},
	"training_speed": {
		"name": "Training Speed",
		"branch": Branch.MILITARY, "tier": 3, "cost_prestige": 500,
		"requires": ["unit_unlocks"],
		"unlocks_buildings": [], "unlocks_units": [], "unlocks_edicts": [],
		"modifiers": {"training_rate_bonus": 0.3},
		"description": "Barracks training +30% faster. Crucial for mid-siege rallying.",
	},
	"siege_engines": {
		"name": "Siege Engines",
		"branch": Branch.MILITARY, "tier": 4, "cost_prestige": 1000,
		"requires": ["unit_unlocks", "refining_processing"],
		"unlocks_buildings": ["siege_tent"],
		"unlocks_units": ["battering_ram", "catapult", "trebuchet"],
		"unlocks_edicts": [],
		"modifiers": {},
		"description": "Unlocks siege weapons. Required to breach AI capitals. Extremely expensive.",
	},

	# ── §4.5 Statecraft ──────────────────────────────────────────────────────
	"scouting_vision": {
		"name": "Scouting & Vision",
		"branch": Branch.STATECRAFT, "tier": 1, "cost_prestige": 100,
		"requires": [],
		"unlocks_buildings": [], "unlocks_units": ["scout"],
		"unlocks_edicts": [],
		"modifiers": {"scout_vision_radius": 5},
		"description": "Unlocks Scouts on macro map. Scout vision radius +5 tiles.",
	},
	"monastic_orders": {
		"name": "Monastic Orders",
		"branch": Branch.STATECRAFT, "tier": 2, "cost_prestige": 200,
		"requires": ["scouting_vision"],
		"unlocks_buildings": ["church", "cathedral"],
		"unlocks_units": ["monk"],
		"unlocks_edicts": [],
		"modifiers": {},
		"description": "Unlocks Church, Cathedral, and Monks. Monks lift AI castle fog and reveal traps.",
	},
	"army_logistics": {
		"name": "Army Logistics",
		"branch": Branch.STATECRAFT, "tier": 3, "cost_prestige": 400,
		"requires": ["scouting_vision"],
		"unlocks_buildings": [], "unlocks_units": [], "unlocks_edicts": [],
		"modifiers": {"army_move_speed_bonus": 0.2, "army_food_cost_reduction": 0.3},
		"description": "Army map speed +20%. Army food consumption −30%. Unlocks Forced March.",
	},
	"royal_edicts": {
		"name": "Royal Edicts",
		"branch": Branch.STATECRAFT, "tier": 3, "cost_prestige": 300,
		"requires": ["scouting_vision"],
		"unlocks_buildings": [], "unlocks_units": [],
		"unlocks_edicts": ["agrarian_subsidies", "iron_tariffs", "taxation_bumps", "ration_controls"],
		"modifiers": {},
		"description": "Unlocks early-tier Economy Edicts. Provides active spell-like abilities.",
	},
	"diplomacy": {
		"name": "Diplomacy",
		"branch": Branch.STATECRAFT, "tier": 4, "cost_prestige": 600,
		"requires": ["royal_edicts"],
		"unlocks_buildings": [], "unlocks_units": [],
		"unlocks_edicts": ["trade_boosts", "border_expansion", "diplomatic_tribute"],
		"modifiers": {"market_buy_fee_reduction": 0.1},
		"description": "Unlocks envoy actions. Market buy fees −10%. Allows AI bribe/truce.",
	},
	"trade_networks": {
		"name": "Trade Networks",
		"branch": Branch.STATECRAFT, "tier": 1, "cost_prestige": 150,
		"requires": [],
		"unlocks_buildings": ["trading_post"],
		"unlocks_units": [], "unlocks_edicts": [],
		"modifiers": {"trade_income_bonus": 0.25},
		"description": "Establishes trade caravans. Unlocks the Trading Post for passive gold income.",
	},
}

# Returns the tech definition dict, or {} if not found.
static func lookup(tech_id: String) -> Dictionary:
	return TECHS.get(tech_id, {})

# Returns true if the player has already researched this tech.
static func is_unlocked(player: Dictionary, tech_id: String) -> bool:
	return tech_id in player.get("tech_unlocks", [])

# Returns {ok, reason} — whether the player CAN research this tech right now.
static func can_research(player: Dictionary, tech_id: String) -> Dictionary:
	var defn: Dictionary = TECHS.get(tech_id, {})
	if defn.is_empty():
		return {"ok": false, "reason": "Unknown tech: %s" % tech_id}
	if is_unlocked(player, tech_id):
		return {"ok": false, "reason": "Already researched"}
	for prereq in defn.get("requires", []):
		if not is_unlocked(player, prereq):
			return {"ok": false, "reason": "Missing prerequisite: %s" % prereq}
	var cost: int = defn.get("cost_prestige", 0)
	if player.get("prestige", 0) < cost:
		return {"ok": false, "reason": "Insufficient prestige (need %d, have %d)" % [cost, int(player.get("prestige", 0))]}
	return {"ok": true, "reason": ""}

# Researches a tech: deducts prestige, adds to player.tech_unlocks.
# Returns {ok, unlocked_buildings, unlocked_units, unlocked_edicts, cost}.
static func research(player: Dictionary, tech_id: String) -> Dictionary:
	var check: Dictionary = can_research(player, tech_id)
	if not check["ok"]:
		return {"ok": false, "reason": check["reason"]}
	var defn: Dictionary = TECHS[tech_id]
	var cost: int = defn.get("cost_prestige", 0)
	player["prestige"] = maxf(0.0, player.get("prestige", 0) - float(cost))
	var unlocks: Array = player.get("tech_unlocks", [])
	unlocks.append(tech_id)
	player["tech_unlocks"] = unlocks
	return {
		"ok": true,
		"cost": cost,
		"unlocked_buildings": defn.get("unlocks_buildings", []),
		"unlocked_units": defn.get("unlocks_units", []),
		"unlocked_edicts": defn.get("unlocks_edicts", []),
	}

# Returns all tech IDs the player could research RIGHT NOW.
static func get_researchable(player: Dictionary) -> Array:
	var result: Array = []
	for tech_id in TECHS:
		if can_research(player, tech_id)["ok"]:
			result.append(tech_id)
	return result

# Returns all techs in a given branch.
static func get_branch(branch: Branch) -> Array:
	var result: Array = []
	for tech_id in TECHS:
		if TECHS[tech_id].get("branch", -1) == branch:
			result.append(tech_id)
	return result

# Returns all buildings unlocked by a specific tech.
static func get_unlocked_buildings(tech_id: String) -> Array:
	return TECHS.get(tech_id, {}).get("unlocks_buildings", [])

# Returns all modifier keys granted by a player's current research.
# Used by other systems to apply research bonuses.
static func get_all_modifiers(player: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for tech_id in player.get("tech_unlocks", []):
		var defn: Dictionary = TECHS.get(tech_id, {})
		for key in defn.get("modifiers", {}):
			result[key] = result.get(key, 0.0) + defn["modifiers"][key]
	return result
