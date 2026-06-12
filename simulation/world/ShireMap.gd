extends RefCounted
# Manages Shire ownership, borders, and tax zones.
# GDD §1.2 — Regional Capitals; §2.1.5 — Boundary Lines.
#
# The macro map is divided into Shires. Each Shire contains one Capital.
# Capturing a Capital flips region ownership. Taxes are calculated
# based on which Shire a player's village sits in.

const MAX_SHIRES: int = 60
const UNCLAIMED_SHIRE: int = 255

# Biome traits per shire (matched to GDD §1.2.1)
enum BiomeTrait {
	PLAINS,     # Fertile, farming-focused
	HIGHLAND,   # Industrial, mining-rich
	COAST,      # Trade-oriented, Merchant Prince territory
	FOREST,     # Timber-rich, Bandit King territory
	TUNDRA,     # Harsh, high food drain
}

var shires: Array = []  # Array[Dictionary]

func _init() -> void:
	pass

func initialize(shire_definitions: Array) -> void:
	shires.clear()
	for defn in shire_definitions:
		shires.append(_make_shire(
			defn["id"],
			defn["name"],
			defn.get("biome", BiomeTrait.PLAINS),
			defn.get("capital_x", 50),
			defn.get("capital_y", 50),
			defn.get("owner_id", -1)
		))

func generate_default(map_width: int, map_height: int, count: int = 8) -> void:
	shires.clear()
	var biomes: Array = [BiomeTrait.PLAINS, BiomeTrait.HIGHLAND, BiomeTrait.COAST,
	                     BiomeTrait.FOREST, BiomeTrait.TUNDRA]
	var names: Array = [
		"Ironvale", "Stonereach", "Greymoor", "Ashfield",
		"Hollowhaven", "Thornwick", "Coldwater", "Emberveil",
		"Ravensmere", "Coldspire", "Saltmarsh", "Duskholm",
		"Fenwallow", "Ironpeak", "Amberveil", "Silvercliff",
		"Dawnsward", "Mirefall", "Stonegate", "Ashcroft",
		"Bramblewood", "Cresthollow", "Deepwater", "Elmhurst",
		"Farrow", "Grimstone", "Hartwick", "Ivywood",
		"Jadecliff", "Kestrel", "Longmere", "Mistfall",
		"Nighthollow", "Oakenshield", "Pineholt", "Quarrystone",
		"Redmoor", "Sandgate", "Thistlewood", "Umbridge",
		"Valewatch", "Wolfden", "Yelford", "Zephyrcliff",
		"Aldgate", "Bridgemere", "Copperhill", "Dunmore",
		"Eastmarch", "Frostgate", "Goldvale", "Highbury",
		"Ironwall", "Jasperfield", "Kingsholm", "Leatherbridge",
		"Millhaven", "Northwatch", "Oldcastle", "Pebbleton",
		"Queensgate", "Rookmere",
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(min(count, names.size())):
		shires.append(_make_shire(
			i,
			names[i],
			biomes[i % biomes.size()],
			rng.randi_range(20, map_width - 20),
			rng.randi_range(20, map_height - 20),
			-1
		))

func _make_shire(
		id: int,
		name: String,
		biome: BiomeTrait,
		cap_x: int,
		cap_y: int,
		owner_id: int
) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"biome": biome,
		"owner_id": owner_id,           # -1 = unclaimed, >=0 = player/AI faction
		"capital_x": cap_x,
		"capital_y": cap_y,
		"capital_level": 0,             # 0–5 upgrade tiers (GDD §7.5.4)
		"capital_resources_donated": {},# player_id -> total donated
		"active_buffs": [],             # Array of buff IDs from capital upgrades
		"tax_rate_modifier": 0.0,       # Shire-level tax bonus/penalty
		"influence_radius": 30,         # Tiles around capital under shire control

		# Biome trait modifiers
		"farm_yield_bonus": _biome_farm_bonus(biome),
		"mining_speed_bonus": _biome_mining_bonus(biome),
		"trade_fee_bonus": _biome_trade_bonus(biome),
	}

func _biome_farm_bonus(biome: BiomeTrait) -> float:
	match biome:
		BiomeTrait.PLAINS:  return 0.25
		BiomeTrait.TUNDRA:  return -0.3
		_: return 0.0

func _biome_mining_bonus(biome: BiomeTrait) -> float:
	match biome:
		BiomeTrait.HIGHLAND: return 0.3
		BiomeTrait.FOREST:   return 0.1
		_: return 0.0

func _biome_trade_bonus(biome: BiomeTrait) -> float:
	match biome:
		BiomeTrait.COAST: return 0.2
		_: return 0.0

# --- Ownership ---

func get_shire(shire_id: int) -> Dictionary:
	if shire_id >= 0 and shire_id < shires.size():
		return shires[shire_id]
	return {}

func set_owner(shire_id: int, owner_id: int) -> void:
	if shire_id >= 0 and shire_id < shires.size():
		shires[shire_id]["owner_id"] = owner_id

func get_owner(shire_id: int) -> int:
	if shire_id >= 0 and shire_id < shires.size():
		return shires[shire_id]["owner_id"]
	return -1

func get_shires_owned_by(owner_id: int) -> Array:
	var result: Array = []
	for s in shires:
		if s["owner_id"] == owner_id:
			result.append(s)
	return result

# --- Capital upgrades (GDD §7.5) ---

func upgrade_capital(shire_id: int) -> bool:
	if shire_id < 0 or shire_id >= shires.size():
		return false
	var s: Dictionary = shires[shire_id]
	if s["capital_level"] >= 5:
		return false
	s["capital_level"] += 1
	_apply_capital_level_buffs(s)
	return true

func _apply_capital_level_buffs(shire: Dictionary) -> void:
	# Each level adds a prestige multiplier buff (GDD §7.5.4)
	shire["active_buffs"] = []
	for lvl in range(shire["capital_level"]):
		shire["active_buffs"].append("prestige_multiplier_%d" % (lvl + 1))

func donate_to_capital(shire_id: int, player_id: int, amount: int, resource: String) -> void:
	if shire_id < 0 or shire_id >= shires.size():
		return
	var key: String = "%d_%s" % [player_id, resource]
	var s: Dictionary = shires[shire_id]
	if not s["capital_resources_donated"].has(key):
		s["capital_resources_donated"][key] = 0
	s["capital_resources_donated"][key] += amount

# --- Tax calculations (GDD §1.2.1, §3.4) ---

func get_tax_modifier(shire_id: int) -> float:
	if shire_id < 0 or shire_id >= shires.size():
		return 0.0
	return shires[shire_id]["tax_rate_modifier"]

# --- Serialization ---

func serialize() -> Dictionary:
	return {"shires": shires.duplicate(true)}

func deserialize(data: Dictionary) -> void:
	shires = data.get("shires", [])
