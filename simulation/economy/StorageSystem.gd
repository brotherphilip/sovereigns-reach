extends RefCounted
# Capacity model for raw + intermediate goods (the "universal raw" pool held in
# player.resources). Mirrors FoodSystem's granary model: total storage = a small base
# (the keep) + the sum of every built Stockpile's capacity. Haulers refuse to deposit
# once the pool is full (see CitizenSystem) — so production STOPS until more stockpiles
# are built, nothing is wasted. Food is stored separately in the Granary (FoodSystem).

const TechTree    = preload("res://simulation/tech/TechTree.gd")
const EdictSystem = preload("res://simulation/edicts/EdictSystem.gd")

# Goods that live in player.resources and share the stockpile pool.
const RAW_GOODS: Array = ["wood", "firewood", "stone", "iron", "pitch", "hops", "wheat", "flour", "leather"]

# Storage available before any stockpile is built — the keep's own cellar. Sized to
# hold the realm's starting supplies with headroom; stockpiles extend it from there,
# and the cap only bites once a busy economy out-produces this base.
const RAW_BASE: int = 500

# Total raw-goods capacity = base + Σ built stockpile storage_max (+ tech/edict bonus).
static func get_capacity(player: Dictionary) -> int:
	var cap: int = RAW_BASE
	for b in player.get("buildings", []):
		if not b is Dictionary:
			continue
		if b.get("type", "") == "stockpile" and b.get("built", true) and b.get("is_active", true):
			cap += int(b.get("storage_max", 0))
	var bonus: float = TechTree.get_all_modifiers(player).get("storage_capacity_bonus", 0.0) \
		+ EdictSystem.get_active_modifiers(player).get("storage_capacity_bonus", 0.0)
	if bonus > 0.0:
		cap = int(ceil(float(cap) * (1.0 + bonus)))
	return cap

# Total raw goods currently stored.
static func get_stored(player: Dictionary) -> int:
	var total: int = 0
	var res: Dictionary = player.get("resources", {})
	for g in RAW_GOODS:
		total += maxi(0, int(res.get(g, 0)))
	return total

# Free space left in the raw pool.
static func room(player: Dictionary) -> int:
	return maxi(0, get_capacity(player) - get_stored(player))

# Which store a produced good is delivered to: "granary" (food/ale), "armory" (arms),
# or "stockpile" (everything else — the raw pool).
const FOOD_GOODS: Array = ["apples", "bread", "cheese", "meat", "ale"]
const ARMS_GOODS: Array = ["bows", "crossbows", "pikes", "swords", "leather_armor", "plate_armor"]

static func store_for(good: String) -> String:
	if good in FOOD_GOODS:
		return "granary"
	if good in ARMS_GOODS:
		return "armory"
	return "stockpile"
