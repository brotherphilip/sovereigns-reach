extends RefCounted
# Static registry of all building type definitions from GDD §5.
# Immutable data — no instance state. All gameplay-relevant stats live here.
# BuildingState.gd holds the runtime per-building instance data.

# Building categories matching GDD structure
enum Category {
	CIVIC,       # §5.1 — Village Hall, Hovels, Market, Apothecary, Guildhall
	HARVESTING,  # §5.2 — Woodcutter, Quarry, Iron Mine, Pitch Rig, Stockpile
	FOOD,        # §5.3 — Orchard, Livestock, Wheat Chain, Ale Chain, Granary
	MILITARY,    # §5.4 — Barracks, Armory, Fletcher, Poleturner, Blacksmith
	DEFENSE,     # §5.5 — Palisade, Stone Wall, Gatehouse, Tower, Traps
}

# Terrain requirements for placement (bitmask of allowed WorldGrid.Terrain values)
# 0 = any buildable terrain
const TERRAIN_ANY:     int = 0
const TERRAIN_GRASS:   int = 1 << 0   # WorldGrid.Terrain.GRASS = 0
const TERRAIN_FOREST:  int = 1 << 1
const TERRAIN_ROCK:    int = 1 << 5
const TERRAIN_ORE:     int = 1 << 6
const TERRAIN_VALLEY:  int = 1 << 7
const TERRAIN_MARSH:   int = 1 << 4
const TERRAIN_FLAT:    int = (1 << 0) | (1 << 7) | (1 << 8) | (1 << 9)  # grass|valley|coastal|road

# Full building definition dictionary
# Keys: type, name, category, width, height, cost, max_workers, worker_slots,
#       terrain_req, fire_risk, hp, requires_tech, produces, consumes,
#       coverage_radius, description
const BUILDINGS: Dictionary = {
	# ── Infrastructure ────────────────────────────────────────────────────────
	# A path is not a real structure: placing it paints a ROAD tile (units travel it
	# at 2× speed and the pathfinder prefers it). Handled specially in GameState.
	"path": {
		"name": "Path", "category": Category.CIVIC,
		"width": 1, "height": 1, "is_path": true,
		"cost": {"wood": 1},
		"max_workers": 0, "worker_slots": 0,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.0, "hp": 1,
		"requires_tech": [], "produces": {}, "consumes": {},
		"coverage_radius": 0,
		"description": "A paved track. Units walk it twice as fast and prefer it.",
	},
	# ── §5.1 Civic ──────────────────────────────────────────────────────────
	"village_hall": {
		"name": "Village Hall", "category": Category.CIVIC,
		"width": 3, "height": 3,
		"cost": {"wood": 0},  # Starting building — no cost
		"max_workers": 0, "worker_slots": 0,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.02, "hp": 500,
		"requires_tech": [], "produces": {}, "consumes": {},
		"coverage_radius": 0,
		"unique": true,       # Only one per village
		"description": "Heart of the village. Spawns peasants. Destruction ends village.",
	},
	"keep": {
		"name": "Keep", "category": Category.CIVIC,
		"width": 3, "height": 3,
		"cost": {"stone": 150, "wood": 80, "gold": 100},
		"max_workers": 0, "worker_slots": 0,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.0, "hp": 1000,
		"requires_tech": ["advanced_masonry"], "produces": {"population_cap": 30}, "consumes": {},
		"coverage_radius": 0,
		"unique": true, "immune_to_fire": true,
		"description": "Fortified heart of a great realm — a late-game upgrade of the Village Hall. GDD §5.1.",
	},
	"hovel": {
		"name": "Hovel", "category": Category.CIVIC,
		"width": 2, "height": 2,
		"cost": {"wood": 8},
		"max_workers": 0, "worker_slots": 0,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.04, "hp": 60,
		"requires_tech": [], "produces": {"population_cap": 8}, "consumes": {},
		"rooms": 4,   # houses families — total rooms cap how many people can be born
		"coverage_radius": 0,
		"description": "A family home (4 rooms). Build more to let the population grow.",
	},
	"market": {
		"name": "Market", "category": Category.CIVIC,
		"width": 2, "height": 2,
		"cost": {"wood": 20, "gold": 10},
		"max_workers": 2, "worker_slots": 2,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.01, "hp": 100,
		"requires_tech": [], "produces": {}, "consumes": {},
		"coverage_radius": 0,
		"description": "Allows resource trading. Cart spawns here.",
	},
	"well": {
		"name": "Well", "category": Category.CIVIC,
		"width": 1, "height": 1,
		"cost": {"wood": 6, "stone": 4},
		"max_workers": 0, "worker_slots": 0,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.0, "hp": 80,
		"requires_tech": [], "produces": {}, "consumes": {},
		"coverage_radius": 8,
		"description": "Clean water raises sanitation, lowering disease risk. Cheap, needs no staff. GDD §3.5.3.",
	},
	"apothecary": {
		"name": "Apothecary", "category": Category.CIVIC,
		"width": 1, "height": 1,
		"cost": {"wood": 10, "gold": 5},
		"max_workers": 1, "worker_slots": 1,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.01, "hp": 80,
		"requires_tech": [], "produces": {}, "consumes": {},
		"coverage_radius": 12,
		"description": "Prevents disease. Cures sick peasants in radius.",
	},
	"guildhall": {
		"name": "Guildhall", "category": Category.CIVIC,
		"width": 2, "height": 2,
		"cost": {"wood": 25, "gold": 20},
		"max_workers": 2, "worker_slots": 4,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.01, "hp": 120,
		"requires_tech": ["transport_logistics"], "produces": {}, "consumes": {},
		"coverage_radius": 0,
		"description": "Houses merchants. Manages trade carts. Upgrades add carts.",
	},
	# ── §5.2 Harvesting ─────────────────────────────────────────────────────
	"woodcutter_camp": {
		"name": "Woodcutter's Camp", "category": Category.HARVESTING,
		"width": 1, "height": 1,
		"cost": {"wood": 4},
		"max_workers": 3, "worker_slots": 3,
		"terrain_req": TERRAIN_FOREST, "fire_risk": 0.03, "hp": 50,
		"requires_tech": [], "produces": {"wood": 1}, "consumes": {},
		"coverage_radius": 0,
		"description": "Harvests timber. Must be near trees.",
	},
	"stone_quarry": {
		"name": "Stone Quarry", "category": Category.HARVESTING,
		"width": 2, "height": 2,
		"cost": {"wood": 15},
		"max_workers": 4, "worker_slots": 4,
		"terrain_req": TERRAIN_ROCK, "fire_risk": 0.0, "hp": 120,
		"requires_tech": ["resource_unlocks"], "produces": {"stone": 1}, "consumes": {},
		"coverage_radius": 0,
		"description": "Mines stone blocks. Requires Ox Tethers to move output.",
	},
	"iron_mine": {
		"name": "Iron Mine", "category": Category.HARVESTING,
		"width": 2, "height": 2,
		"cost": {"wood": 20, "stone": 10},
		"max_workers": 4, "worker_slots": 4,
		"terrain_req": TERRAIN_ORE, "fire_risk": 0.0, "hp": 150,
		"requires_tech": ["resource_unlocks"], "produces": {"iron": 1}, "consumes": {},
		"coverage_radius": 0,
		"description": "Mines raw iron from ore veins.",
	},
	"pitch_rig": {
		"name": "Pitch Rig", "category": Category.HARVESTING,
		"width": 1, "height": 1,
		"cost": {"wood": 8},
		"max_workers": 2, "worker_slots": 2,
		"terrain_req": TERRAIN_MARSH, "fire_risk": 0.08, "hp": 60,
		"requires_tech": [], "produces": {"pitch": 1}, "consumes": {},
		"coverage_radius": 0,
		"description": "Extracts pitch. Highly flammable. Explodes when destroyed.",
	},
	"stockpile": {
		"name": "Stockpile", "category": Category.HARVESTING,
		"width": 1, "height": 1,
		"cost": {"wood": 2},
		"max_workers": 0, "worker_slots": 0,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.01, "hp": 40,
		"requires_tech": [], "produces": {}, "consumes": {},
		"coverage_radius": 0,
		"storage_capacity": 100,
		"expandable": true,   # Placing adjacent doubles capacity
		"description": "Universal raw storage. Expands by placing adjacent.",
	},
	# ── §5.3 Food & Agriculture ──────────────────────────────────────────────
	"apple_orchard": {
		"name": "Apple Orchard", "category": Category.FOOD,
		"width": 2, "height": 2, "field": true,
		"cost": {"wood": 5},
		"max_workers": 2, "worker_slots": 2,
		"terrain_req": TERRAIN_GRASS | TERRAIN_VALLEY, "fire_risk": 0.02, "hp": 40,
		"requires_tech": [], "produces": {"apples": 2}, "consumes": {},
		"coverage_radius": 0,
		"description": "Fast, cheap. Low food yield. Good for early game.",
	},
	"pig_farm": {
		"name": "Pig Farm", "category": Category.FOOD,
		"width": 2, "height": 2, "field": true,
		"cost": {"wood": 10},
		"max_workers": 2, "worker_slots": 2,
		"terrain_req": TERRAIN_GRASS, "fire_risk": 0.02, "hp": 50,
		"requires_tech": ["animal_husbandry"], "produces": {"meat": 1}, "consumes": {},
		"coverage_radius": 0,
		"description": "Livestock farm. Slow cycle but adds food variety.",
	},
	"dairy_farm": {
		"name": "Dairy Farm", "category": Category.FOOD,
		"width": 2, "height": 2, "field": true,
		"cost": {"wood": 10},
		"max_workers": 2, "worker_slots": 2,
		"terrain_req": TERRAIN_GRASS, "fire_risk": 0.01, "hp": 50,
		"requires_tech": ["animal_husbandry"], "produces": {"cheese": 1}, "consumes": {},
		"coverage_radius": 0,
		"description": "Dairy cows produce cheese.",
	},
	"wheat_farm": {
		"name": "Wheat Farm", "category": Category.FOOD,
		"width": 3, "height": 3, "field": true,
		"cost": {"wood": 8},
		"max_workers": 4, "worker_slots": 4,
		"terrain_req": TERRAIN_GRASS | TERRAIN_VALLEY, "fire_risk": 0.04, "hp": 40,
		"requires_tech": ["crop_tiers"], "produces": {"wheat": 2}, "consumes": {},
		"coverage_radius": 0,
		"description": "Grows wheat for the bread chain. Highest food output.",
	},
	"hops_farm": {
		"name": "Hops Farm", "category": Category.FOOD,
		"width": 2, "height": 2, "field": true,
		"cost": {"wood": 8},
		"max_workers": 2, "worker_slots": 2,
		"terrain_req": TERRAIN_GRASS | TERRAIN_VALLEY, "fire_risk": 0.03, "hp": 40,
		"requires_tech": ["crop_tiers"], "produces": {"hops": 2}, "consumes": {},
		"coverage_radius": 0,
		"description": "Grows hops for ale production.",
	},
	"mill": {
		"name": "Mill", "category": Category.FOOD,
		"width": 2, "height": 2,
		"cost": {"wood": 12, "stone": 4},
		"max_workers": 2, "worker_slots": 2,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.01, "hp": 80,
		"requires_tech": [], "produces": {"flour": 1}, "consumes": {"wheat": 1},
		"coverage_radius": 0,
		"description": "Grinds wheat into flour.",
	},
	"bakery": {
		"name": "Bakery", "category": Category.FOOD,
		"width": 2, "height": 2,
		"cost": {"wood": 10},
		"max_workers": 1, "worker_slots": 1,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.04, "hp": 60,
		"requires_tech": [], "produces": {"bread": 1}, "consumes": {"flour": 1},
		"coverage_radius": 0,
		"description": "Bakes bread from flour. Highest food popularity bonus.",
	},
	"brewery": {
		"name": "Brewery", "category": Category.FOOD,
		"width": 2, "height": 2,
		"cost": {"wood": 15},
		"max_workers": 2, "worker_slots": 2,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.03, "hp": 80,
		"requires_tech": [], "produces": {"ale": 2}, "consumes": {"hops": 1},
		"coverage_radius": 0,
		"description": "Brews ale from hops. Major popularity driver.",
	},
	"inn": {
		"name": "Inn", "category": Category.FOOD,
		"width": 2, "height": 2,
		"cost": {"wood": 20},
		"max_workers": 1, "worker_slots": 1,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.02, "hp": 80,
		"requires_tech": [], "produces": {}, "consumes": {"ale": 1},
		"coverage_radius": 8,
		"description": "Distributes ale in radius. Multiple inns stack coverage.",
	},
	"granary": {
		"name": "Granary", "category": Category.FOOD,
		"width": 2, "height": 2,
		"cost": {"wood": 15},
		"max_workers": 1, "worker_slots": 1,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.02, "hp": 100,
		"requires_tech": [], "produces": {}, "consumes": {},
		"coverage_radius": 10,
		"storage_capacity": 200,
		"expandable": true,
		"description": "Stores all food. Controls rationing. Vital to protect.",
	},
	"church": {
		"name": "Church", "category": Category.CIVIC,
		"width": 2, "height": 2,
		"cost": {"stone": 25},
		"max_workers": 2, "worker_slots": 2,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.0, "hp": 200,
		"requires_tech": ["monastic_orders"], "produces": {}, "consumes": {},
		"coverage_radius": 12,
		"immune_to_fire": false,
		"description": "Distributes Faith. Marriage events give popularity spikes.",
	},
	"cathedral": {
		"name": "Cathedral", "category": Category.CIVIC,
		"width": 4, "height": 4,
		"cost": {"stone": 200, "gold": 100},
		"max_workers": 4, "worker_slots": 4,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.0, "hp": 800,
		"requires_tech": ["monastic_orders"], "produces": {}, "consumes": {},
		"coverage_radius": 30,
		"immune_to_fire": true,
		"description": "Massive area of effect. Status symbol. Immune to fire.",
	},
	# ── §5.4 Military Production ─────────────────────────────────────────────
	"barracks": {
		"name": "Barracks", "category": Category.MILITARY,
		"width": 3, "height": 3,
		"cost": {"wood": 20, "stone": 10, "gold": 10},
		"max_workers": 0, "worker_slots": 0,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.01, "hp": 150,
		"requires_tech": [], "produces": {}, "consumes": {},
		"coverage_radius": 0,
		"description": "Converts peasants to soldiers. Requires gold + weapons.",
	},
	"armory": {
		"name": "Armory", "category": Category.MILITARY,
		"width": 2, "height": 2,
		"cost": {"wood": 10, "stone": 5},
		"max_workers": 0, "worker_slots": 0,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.0, "hp": 150,
		"requires_tech": [], "produces": {}, "consumes": {},
		"storage_capacity": 50,
		"expandable": true,
		"explosive": true,    # Highly explosive if ignited (GDD §5.4.2)
		"description": "Stores weapons/armor. Explosive if ignited. Limits army size.",
	},
	"fletcher": {
		"name": "Fletcher", "category": Category.MILITARY,
		"width": 1, "height": 1,
		"cost": {"wood": 12},
		"max_workers": 1, "worker_slots": 1,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.02, "hp": 60,
		"requires_tech": ["weapon_crafting"], "produces": {"bows": 1}, "consumes": {"wood": 1},
		"coverage_radius": 0,
		"description": "Crafts bows/crossbows from wood.",
	},
	"poleturner": {
		"name": "Poleturner", "category": Category.MILITARY,
		"width": 1, "height": 1,
		"cost": {"wood": 8},
		"max_workers": 1, "worker_slots": 1,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.02, "hp": 50,
		"requires_tech": [], "produces": {"pikes": 1}, "consumes": {"wood": 1},
		"coverage_radius": 0,
		"description": "Crafts pikes from wood. Fast and cheap.",
	},
	"blacksmith": {
		"name": "Blacksmith", "category": Category.MILITARY,
		"width": 2, "height": 2,
		"cost": {"wood": 15, "stone": 10},
		"max_workers": 1, "worker_slots": 1,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.01, "hp": 120,
		"requires_tech": ["weapon_crafting"], "produces": {"swords": 1}, "consumes": {"iron": 2},
		"coverage_radius": 0,
		"description": "Crafts swords/armor from iron. Slow but essential late-game.",
	},
	"tannery": {
		"name": "Tannery", "category": Category.MILITARY,
		"width": 1, "height": 1,
		"cost": {"wood": 10},
		"max_workers": 1, "worker_slots": 1,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.03, "hp": 60,
		"requires_tech": ["weapon_crafting"], "produces": {"leather_armor": 1}, "consumes": {"leather": 1},
		"coverage_radius": 0,
		"description": "Cures hides into leather armour for militia. GDD §5.4.",
	},
	"armorer": {
		"name": "Armorer", "category": Category.MILITARY,
		"width": 2, "height": 2,
		"cost": {"wood": 15, "stone": 10},
		"max_workers": 1, "worker_slots": 1,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.01, "hp": 120,
		"requires_tech": ["armor_forging"], "produces": {"plate_armor": 1}, "consumes": {"iron": 2},
		"coverage_radius": 0,
		"description": "Forges iron plate armour for heavy infantry. GDD §5.4.",
	},
	"crossbow_workshop": {
		"name": "Crossbow Workshop", "category": Category.MILITARY,
		"width": 1, "height": 1,
		"cost": {"wood": 14, "iron": 4},
		"max_workers": 1, "worker_slots": 1,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.02, "hp": 60,
		"requires_tech": ["armor_forging"], "produces": {"crossbows": 1}, "consumes": {"wood": 1, "iron": 1},
		"coverage_radius": 0,
		"description": "Builds heavy crossbows from wood and iron. GDD §5.4.",
	},
	# ── §5.5 Defenses ────────────────────────────────────────────────────────
	"wooden_palisade": {
		"name": "Wooden Palisade", "category": Category.DEFENSE,
		"width": 1, "height": 1,
		"cost": {"wood": 2},
		"max_workers": 0, "worker_slots": 0,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.12, "hp": 40,
		"requires_tech": [], "produces": {}, "consumes": {},
		"coverage_radius": 0,
		"is_wall": true, "troop_capacity": 0,
		"description": "Early game walls. Cheap. Burns down easily.",
	},
	"stone_wall": {
		"name": "Stone Wall", "category": Category.DEFENSE,
		"width": 1, "height": 1,
		"cost": {"stone": 5},
		"max_workers": 0, "worker_slots": 0,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.0, "hp": 250,
		"requires_tech": [], "produces": {}, "consumes": {},
		"coverage_radius": 0,
		"is_wall": true, "troop_capacity": 4, "immune_to_fire": true,
		"description": "High HP walls. Troops stand on top. Immune to fire.",
	},
	"gatehouse": {
		"name": "Gatehouse", "category": Category.DEFENSE,
		"width": 1, "height": 2,
		"cost": {"stone": 20},
		"max_workers": 0, "worker_slots": 0,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.0, "hp": 400,
		"requires_tech": [], "produces": {}, "consumes": {},
		"is_gate": true, "is_open": true, "immune_to_fire": true,
		"description": "Primary entry. Can open/close. Contains portcullis.",
	},
	"lookout_tower": {
		"name": "Lookout Tower", "category": Category.DEFENSE,
		"width": 1, "height": 1,
		"cost": {"stone": 10},
		"max_workers": 0, "worker_slots": 4,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.0, "hp": 180,
		"requires_tech": [], "produces": {}, "consumes": {},
		"is_tower": true, "immune_to_fire": true,
		"description": "Lookout tower. Mounts ballistas. Increases archer range.",
	},
	"great_tower": {
		"name": "Great Tower", "category": Category.DEFENSE,
		"width": 2, "height": 2,
		"cost": {"stone": 35},
		"max_workers": 0, "worker_slots": 8,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.0, "hp": 500,
		"requires_tech": ["advanced_masonry"], "produces": {}, "consumes": {},
		"is_tower": true, "immune_to_fire": true,
		"description": "Hard to destroy. Mounts mangonels. Anchors wall corners.",
	},
	"watchtower": {
		"name": "Watchtower", "category": Category.DEFENSE,
		"width": 1, "height": 1,
		"cost": {"wood": 30, "stone": 20},
		"max_workers": 1, "worker_slots": 1,
		"terrain_req": TERRAIN_ANY, "fire_risk": 0.01, "hp": 120,
		"requires_tech": [], "produces": {}, "consumes": {},
		"coverage_radius": 15,
		"description": "Scout post. Reveals surrounding terrain and approaching enemies.",
	},
	"trading_post": {
		"name": "Trading Post", "category": Category.CIVIC,
		"width": 2, "height": 2,
		"cost": {"wood": 40, "gold": 50},
		"max_workers": 2, "worker_slots": 2,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.05, "hp": 100,
		"requires_tech": ["trade_networks"], "produces": {"gold": 3}, "consumes": {},
		"coverage_radius": 0,
		"description": "Generates steady gold income from passing caravans.",
	},
	"siege_workshop": {
		"name": "Siege Workshop", "category": Category.MILITARY,
		"width": 2, "height": 2,
		"cost": {"wood": 60, "iron": 30},
		"max_workers": 3, "worker_slots": 3,
		"terrain_req": TERRAIN_FLAT, "fire_risk": 0.08, "hp": 150,
		"requires_tech": ["siege_engines"], "produces": {}, "consumes": {},
		"coverage_radius": 0,
		"description": "Builds and maintains siege engines for assaults.",
	},
}

# Returns a building definition dict, or empty dict if not found.
# Named "lookup" instead of "get" to avoid conflicting with Object.get() built-in.
static func lookup(building_type: String) -> Dictionary:
	return BUILDINGS.get(building_type, {})

# Returns true if the building_type is a valid registered type
static func is_valid_type(building_type: String) -> bool:
	return BUILDINGS.has(building_type)

# A "field" building (orchard/farm) — its footprint stays occupied for placement
# but is walkable so workers toil among the rows/trees rather than just outside.
static func is_field(building_type: String) -> bool:
	return BUILDINGS.get(building_type, {}).get("field", false)

# A "path" pseudo-building — placing it paints a ROAD tile rather than a structure.
static func is_path(building_type: String) -> bool:
	return BUILDINGS.get(building_type, {}).get("is_path", false)

# Buildings that must keep a gap from each other. Paths and defensive works (walls,
# towers, gatehouses — meant to sit flush in rings) are exempt.
static func needs_spacing(building_type: String) -> bool:
	var d: Dictionary = BUILDINGS.get(building_type, {})
	if d.is_empty() or d.get("is_path", false):
		return false
	return d.get("category", -1) != Category.DEFENSE

# Returns all building types in a given category
static func get_by_category(category: Category) -> Array:
	var result: Array = []
	for btype in BUILDINGS:
		if BUILDINGS[btype]["category"] == category:
			result.append(btype)
	return result

# Returns the gold cost to recruit the given unit_type from barracks
# (Separated here for centralization; unit costs defined in Phase 6 UnitRegistry)
static func get_recruitment_cost(unit_type: String) -> int:
	# Placeholder values until Phase 6 UnitRegistry is implemented
	var costs: Dictionary = {
		"armed_peasant": 3, "archer": 12, "militia": 8,
		"crossbowman": 20, "pikeman": 15, "swordsman": 25,
		"captain": 100, "halberdier": 18,
	}
	return costs.get(unit_type, 0)

# Returns the coverage radius for a building type (0 if not applicable)
static func coverage_radius(building_type: String) -> int:
	return BUILDINGS.get(building_type, {}).get("coverage_radius", 0)

# Returns all building types that require a specific tech unlock
static func requiring_tech(tech_id: String) -> Array:
	var result: Array = []
	for btype in BUILDINGS:
		if tech_id in BUILDINGS[btype].get("requires_tech", []):
			result.append(btype)
	return result
