extends RefCounted
# GDD §6 — The Unit Roster
# Canonical definitions for all mobile unit types: stats, costs, equipment, tech gates.
# Stationary emplacements (ballista, mangonel, boiling oil, pitch ditch, moat) are handled
# by BuildingRegistry since they occupy fixed grid cells.

# Attack types used by CombatSystem damage table
const ATTACK_NONE    = "none"
const ATTACK_MELEE   = "melee"
const ATTACK_PIERCE  = "pierce"   # arrows, bolts — devastating vs unarmored
const ATTACK_SIEGE   = "siege"    # rams, catapults, trebuchets — great vs structures

# Armor types used by CombatSystem damage table
const ARMOR_NONE     = "none"
const ARMOR_LIGHT    = "light"    # leather armor
const ARMOR_HEAVY    = "heavy"    # iron plate armor
const ARMOR_STRUCTURE = "structure" # buildings, walls

# Unit categories
const CAT_CIVILIAN     = "civilian"
const CAT_LIGHT_INF    = "light_infantry"
const CAT_HEAVY_INF    = "heavy_infantry"
const CAT_SIEGE        = "siege"

# Units dictionary: unit_type -> definition dict.
# All cost_* fields denote per-recruitment cost.
# speed: tiles-per-game-day on the macro world map.
# train_ticks: how many ticks in the barracks queue before spawned.
# morale_buff: flat bonus this unit grants adjacent allies (only captain has >0).
const UNITS: Dictionary = {

	# ── §6.1 Civilian & Support ──────────────────────────────────────────────
	"peasant": {
		"name": "Peasant",
		"category": CAT_CIVILIAN,
		"max_hp": 20, "attack": 2, "defense": 0,
		"attack_type": ATTACK_MELEE, "armor_type": ARMOR_NONE,
		"range": 0, "speed": 3,
		"cost_gold": 0, "cost_resources": {},
		"requires_tech": "", "requires_building": "village_hall",
		"train_ticks": 0,
		"morale_buff": 0,
		"description": "Spawns at Village Hall; drives the economy. GDD §6.1.1.",
	},
	"scout": {
		"name": "Scout",
		"category": CAT_CIVILIAN,
		"max_hp": 15, "attack": 0, "defense": 0,
		"attack_type": ATTACK_NONE, "armor_type": ARMOR_NONE,
		"range": 0, "speed": 8,
		"cost_gold": 20, "cost_resources": {},
		"requires_tech": "scouting_vision", "requires_building": "village_hall",
		"train_ticks": 120,
		"morale_buff": 0,
		"description": "Fast world-map unit; clears fog of war. GDD §6.1.2.",
	},
	"monk": {
		"name": "Monk",
		"category": CAT_CIVILIAN,
		"max_hp": 18, "attack": 0, "defense": 0,
		"attack_type": ATTACK_NONE, "armor_type": ARMOR_LIGHT,
		"range": 0, "speed": 2,
		"cost_gold": 40, "cost_resources": {},
		"requires_tech": "monastic_orders", "requires_building": "church",
		"train_ticks": 240,
		"morale_buff": 0,
		"description": "Infiltrates AI capitals; reveals hidden pitch ditches. GDD §6.1.3.",
	},
	"merchant": {
		"name": "Merchant",
		"category": CAT_CIVILIAN,
		"max_hp": 20, "attack": 0, "defense": 0,
		"attack_type": ATTACK_NONE, "armor_type": ARMOR_NONE,
		"range": 0, "speed": 4,
		"cost_gold": 50, "cost_resources": {},
		"requires_tech": "", "requires_building": "market",
		"train_ticks": 240,
		"morale_buff": 0,
		"description": "Automates trade routes between co-op bases. GDD §6.1.4.",
	},
	"settler": {
		"name": "Settler",
		"category": CAT_CIVILIAN,
		"max_hp": 30, "attack": 0, "defense": 0,
		"attack_type": ATTACK_NONE, "armor_type": ARMOR_NONE,
		"range": 0, "speed": 2,
		"cost_gold": 200, "cost_resources": {"wood": 100, "stone": 50},
		"requires_tech": "scouting_vision", "requires_building": "village_hall",
		"train_ticks": 960,
		"morale_buff": 0,
		"description": "Claims new map regions; establishes new village halls. GDD §6.1.5.",
	},

	# ── §6.2 Light Infantry ──────────────────────────────────────────────────
	"armed_peasant": {
		"name": "Armed Peasant",
		"category": CAT_LIGHT_INF,
		"max_hp": 25, "attack": 5, "defense": 0,
		"attack_type": ATTACK_MELEE, "armor_type": ARMOR_NONE,
		"range": 0, "speed": 4,
		"cost_gold": 5, "cost_resources": {},
		"requires_tech": "", "requires_building": "barracks",
		"train_ticks": 60,
		"morale_buff": 0,
		"description": "Pitchfork-wielding cannon fodder; no armor. GDD §6.2.1.",
	},
	"archer": {
		"name": "Archer",
		"category": CAT_LIGHT_INF,
		"max_hp": 30, "attack": 8, "defense": 2,
		"attack_type": ATTACK_PIERCE, "armor_type": ARMOR_NONE,
		"range": 8, "speed": 5,
		"cost_gold": 15, "cost_resources": {"bows": 1},
		"requires_tech": "unit_unlocks", "requires_building": "barracks",
		"train_ticks": 120,
		"morale_buff": 0,
		"description": "Fast and long-range; devastating vs unarmored. GDD §6.2.2.",
	},
	"ladderman": {
		"name": "Ladderman",
		"category": CAT_LIGHT_INF,
		"max_hp": 20, "attack": 4, "defense": 0,
		"attack_type": ATTACK_MELEE, "armor_type": ARMOR_NONE,
		"range": 0, "speed": 3,
		"cost_gold": 8, "cost_resources": {"wood": 2},
		"requires_tech": "unit_unlocks", "requires_building": "barracks",
		"train_ticks": 60,
		"morale_buff": 0,
		"description": "Carries ladders to walls; bypasses gatehouses. GDD §6.2.3.",
	},
	"tunneler": {
		"name": "Tunneler",
		"category": CAT_LIGHT_INF,
		"max_hp": 35, "attack": 6, "defense": 2,
		"attack_type": ATTACK_SIEGE, "armor_type": ARMOR_NONE,
		"range": 0, "speed": 2,
		"cost_gold": 20, "cost_resources": {"wood": 4},
		"requires_tech": "siege_engines", "requires_building": "barracks",
		"train_ticks": 240,
		"morale_buff": 0,
		"description": "Digs under stone walls to collapse them. GDD §6.2.4.",
	},
	"militia": {
		"name": "Militia",
		"category": CAT_LIGHT_INF,
		"max_hp": 45, "attack": 8, "defense": 4,
		"attack_type": ATTACK_MELEE, "armor_type": ARMOR_LIGHT,
		"range": 0, "speed": 4,
		"cost_gold": 20, "cost_resources": {"pikes": 1, "leather_armor": 1},
		"requires_tech": "unit_unlocks", "requires_building": "barracks",
		"train_ticks": 180,
		"morale_buff": 0,
		"description": "Upgraded peasant; spears, light leather armor. GDD §6.2.5.",
	},

	# ── §6.3 Heavy Infantry ──────────────────────────────────────────────────
	"crossbowman": {
		"name": "Crossbowman",
		"category": CAT_HEAVY_INF,
		"max_hp": 60, "attack": 12, "defense": 8,
		"attack_type": ATTACK_PIERCE, "armor_type": ARMOR_HEAVY,
		"range": 10, "speed": 3,
		"cost_gold": 50, "cost_resources": {"crossbows": 1, "plate_armor": 1},
		"requires_tech": "armor_forging", "requires_building": "barracks",
		"train_ticks": 360,
		"morale_buff": 0,
		"description": "Bolts pierce iron armor; dominates wall defense. GDD §6.3.1.",
	},
	"pikeman": {
		"name": "Pikeman",
		"category": CAT_HEAVY_INF,
		"max_hp": 80, "attack": 10, "defense": 15,
		"attack_type": ATTACK_MELEE, "armor_type": ARMOR_HEAVY,
		"range": 0, "speed": 2,
		"cost_gold": 40, "cost_resources": {"pikes": 1, "plate_armor": 1},
		"requires_tech": "armor_forging", "requires_building": "barracks",
		"train_ticks": 360,
		"morale_buff": 0,
		"description": "Ultimate defensive tank; blocks wall breaches. GDD §6.3.2.",
	},
	"swordsman": {
		"name": "Swordsman",
		"category": CAT_HEAVY_INF,
		"max_hp": 70, "attack": 18, "defense": 12,
		"attack_type": ATTACK_MELEE, "armor_type": ARMOR_HEAVY,
		"range": 0, "speed": 3,
		"cost_gold": 60, "cost_resources": {"swords": 1, "plate_armor": 1},
		"requires_tech": "armor_forging", "requires_building": "barracks",
		"train_ticks": 480,
		"morale_buff": 0,
		"description": "High damage and armor; core offensive unit. GDD §6.3.3.",
	},
	"captain": {
		"name": "Captain",
		"category": CAT_HEAVY_INF,
		"max_hp": 100, "attack": 20, "defense": 15,
		"attack_type": ATTACK_MELEE, "armor_type": ARMOR_HEAVY,
		"range": 0, "speed": 4,
		"cost_gold": 200, "cost_resources": {"swords": 1, "plate_armor": 2},
		"requires_tech": "advanced_masonry", "requires_building": "barracks",
		"train_ticks": 720,
		"morale_buff": 10,   # Grants +10 attack to adjacent allies
		"is_hero": true,     # Only one per army
		"description": "Hero unit; captures flags, grants morale buffs. GDD §6.3.4.",
	},
	"halberdier": {
		"name": "Halberdier",
		"category": CAT_HEAVY_INF,
		"max_hp": 65, "attack": 14, "defense": 10,
		"attack_type": ATTACK_MELEE, "armor_type": ARMOR_HEAVY,
		"range": 0, "speed": 4,
		"cost_gold": 45, "cost_resources": {"pikes": 1, "plate_armor": 1},
		"requires_tech": "armor_forging", "requires_building": "barracks",
		"train_ticks": 420,
		"morale_buff": 0,
		"anti_armor_bonus": 0.25,   # +25% attack vs heavy armor (GDD §6.3.5)
		"description": "Mid-tier heavy; good against armor, faster than swordsmen. GDD §6.3.5.",
	},

	# ── §6.4 Mobile Siege Equipment ─────────────────────────────────────────
	"battering_ram": {
		"name": "Battering Ram",
		"category": CAT_SIEGE,
		"max_hp": 150, "attack": 50, "defense": 30,
		"attack_type": ATTACK_SIEGE, "armor_type": ARMOR_HEAVY,
		"range": 0, "speed": 1,
		"cost_gold": 100, "cost_resources": {"wood": 30, "iron": 10},
		"requires_tech": "siege_engines", "requires_building": "siege_tent",
		"train_ticks": 720,
		"morale_buff": 0,
		"target_priority": "gatehouse",   # Rams hit gates (GDD §2.5.2)
		"immune_to_arrows": true,          # GDD §6.4.1
		"description": "Destroys gatehouses; immune to arrows. GDD §6.4.1.",
	},
	"catapult": {
		"name": "Catapult",
		"category": CAT_SIEGE,
		"max_hp": 40, "attack": 40, "defense": 5,
		"attack_type": ATTACK_SIEGE, "armor_type": ARMOR_NONE,
		"range": 12, "speed": 2,
		"cost_gold": 150, "cost_resources": {"wood": 50, "iron": 20},
		"requires_tech": "siege_engines", "requires_building": "siege_tent",
		"train_ticks": 960,
		"morale_buff": 0,
		"splash_radius": 2,
		"description": "Mobile artillery; clears troops and weak walls. GDD §6.4.2.",
	},
	"trebuchet": {
		"name": "Trebuchet",
		"category": CAT_SIEGE,
		"max_hp": 30, "attack": 80, "defense": 5,
		"attack_type": ATTACK_SIEGE, "armor_type": ARMOR_NONE,
		"range": 20, "speed": 1,
		"cost_gold": 250, "cost_resources": {"wood": 80, "stone": 40, "iron": 30},
		"requires_tech": "siege_engines", "requires_building": "siege_tent",
		"train_ticks": 1440,
		"morale_buff": 0,
		"target_priority": "great_tower",   # Trebuchets hit towers (GDD §2.5.2)
		"is_stationary": true,               # Requires setup before firing
		"description": "Massive range; destroys Great Towers. GDD §6.4.3.",
	},
	"siege_tower": {
		"name": "Siege Tower",
		"category": CAT_SIEGE,
		"max_hp": 120, "attack": 0, "defense": 20,
		"attack_type": ATTACK_NONE, "armor_type": ARMOR_HEAVY,
		"range": 0, "speed": 1,
		"cost_gold": 180, "cost_resources": {"wood": 60, "iron": 15},
		"requires_tech": "siege_engines", "requires_building": "siege_tent",
		"train_ticks": 1200,
		"morale_buff": 0,
		"description": "Rolls to walls; drops gangplank for climbing troops. GDD §6.4.4.",
	},
	"mantlet": {
		"name": "Mantlet",
		"category": CAT_SIEGE,
		"max_hp": 50, "attack": 0, "defense": 15,
		"attack_type": ATTACK_NONE, "armor_type": ARMOR_LIGHT,
		"range": 0, "speed": 2,
		"cost_gold": 30, "cost_resources": {"wood": 15},
		"requires_tech": "siege_engines", "requires_building": "siege_tent",
		"train_ticks": 360,
		"morale_buff": 0,
		"description": "Mobile wooden shield protecting advancing archers. GDD §6.4.5.",
	},
}

# ── Accessors ─────────────────────────────────────────────────────────────────

static func lookup(unit_type: String) -> Dictionary:
	return UNITS.get(unit_type, {})

static func is_valid(unit_type: String) -> bool:
	return UNITS.has(unit_type)

static func get_all_types() -> Array:
	return UNITS.keys()

static func get_by_category(category: String) -> Array:
	var result: Array = []
	for utype in UNITS:
		if UNITS[utype].get("category", "") == category:
			result.append(utype)
	return result

static func get_units_for_building(building_type: String) -> Array:
	var result: Array = []
	for utype in UNITS:
		if UNITS[utype].get("requires_building", "") == building_type:
			result.append(utype)
	return result

# Returns true if the player has the tech and building required to recruit this unit.
static func can_recruit(unit_type: String, player: Dictionary) -> Dictionary:
	var defn: Dictionary = UNITS.get(unit_type, {})
	if defn.is_empty():
		return {"ok": false, "reason": "Unknown unit type: %s" % unit_type}
	var req_tech: String = defn.get("requires_tech", "")
	if req_tech != "" and req_tech not in player.get("tech_unlocks", []):
		return {"ok": false, "reason": "Requires tech: %s" % req_tech}
	var req_building: String = defn.get("requires_building", "")
	if req_building != "":
		var has_building: bool = false
		for b in player.get("buildings", []):
			if b is Dictionary and b.get("type", "") == req_building and b.get("is_operational", false):
				has_building = true
				break
		if not has_building:
			return {"ok": false, "reason": "Requires building: %s" % req_building}
	return {"ok": true, "reason": ""}

# Returns true if the player's armory has the required equipment for one unit.
static func has_equipment(unit_type: String, player: Dictionary) -> bool:
	var defn: Dictionary = UNITS.get(unit_type, {})
	var armory: Dictionary = player.get("armory", {})
	for item in defn.get("cost_resources", {}):
		if item in ["wood", "stone", "iron", "pitch", "hops", "wheat", "flour", "leather"]:
			continue  # raw materials come from resources, not armory
		var needed: int = defn["cost_resources"][item]
		if armory.get(item, 0) < needed:
			return false
	return true
