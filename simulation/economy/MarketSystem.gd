extends RefCounted
const EdictSystem = preload("res://simulation/edicts/EdictSystem.gd")
const TechTree    = preload("res://simulation/tech/TechTree.gd")
# GDD §5.1.3 — Market
# Handles BUY_RESOURCE and SELL_RESOURCE commands.
# Prices are stored in world["market_prices"] and fluctuate over time.

# Base gold prices per unit (GDD §5.1.3 — "server-wide fluctuating prices")
const BASE_PRICES: Dictionary = {
	# Raw materials
	"wood":    3,
	"stone":   5,
	"iron":    8,
	"pitch":   6,
	"hops":    4,
	"wheat":   3,
	"flour":   5,
	"leather": 7,
	# Food
	"apples":  2,
	"cheese":  4,
	"meat":    6,
	"bread":   5,
	"ale":     8,
	# Armory
	"bows":         12,
	"crossbows":    20,
	"pikes":        10,
	"swords":       18,
	"leather_armor": 15,
	"plate_armor":   25,
}

# Price fluctuation range (±30% around base)
const PRICE_VARIANCE: float = 0.3

# Initializes market prices in world dict. Call from setup_world().
static func initialize_prices(world: Dictionary) -> void:
	if not world.has("market_prices"):
		world["market_prices"] = BASE_PRICES.duplicate()

# Fluctuate prices. Call occasionally (e.g. every 10 game-days) to simulate supply/demand.
static func tick_prices(world: Dictionary, rng: RandomNumberGenerator, tick: int) -> void:
	if tick == 0 or tick % 2400 != 0:  # Every 10 game-days
		return
	var prices: Dictionary = world.get("market_prices", {})
	var history: Dictionary = world.get("market_price_history", {})
	for resource in BASE_PRICES:
		var cur: int = prices.get(resource, BASE_PRICES[resource])
		if not history.has(resource):
			history[resource] = []
		var arr: Array = history[resource]
		arr.append(cur)
		if arr.size() > 5:
			arr = arr.slice(arr.size() - 5)
		history[resource] = arr
		var base: int = BASE_PRICES[resource]
		var variance: float = rng.randf_range(-PRICE_VARIANCE, PRICE_VARIANCE)
		prices[resource] = maxi(1, int(float(base) * (1.0 + variance)))
	world["market_prices"] = prices
	world["market_price_history"] = history

# Returns current buy price (player pays this; buying costs slightly more)
static func get_buy_price(resource: String, world: Dictionary) -> int:
	var base: int = world.get("market_prices", {}).get(resource, BASE_PRICES.get(resource, 5))
	return ceili(float(base) * 1.2)  # 20% markup to buy (ceili ensures buy > sell for all prices)

# Returns current sell price (player receives this)
static func get_sell_price(resource: String, world: Dictionary) -> int:
	return world.get("market_prices", {}).get(resource, BASE_PRICES.get(resource, 5))

# Returns true if the player is embargoed by any AI faction (prices rise).
# Looks the GameState autoload up at runtime via the scene tree instead of
# referencing it as a compile-time global identifier — that keeps this helper
# compilable when preloaded in isolation (e.g. headless unit tests where the
# autoload singleton is not yet registered). See audit item S12.
static func is_embargoed(player: Dictionary) -> bool:
	for f in _get_ai_factions():
		if f is Dictionary and f.get("is_alive", false):
			if player.get("id", 0) in f.get("embargoed_players", []):
				return true
	return false

# Resolves GameState.ai_factions at runtime; returns [] if the autoload is absent.
static func _get_ai_factions() -> Array:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		var gs: Node = (loop as SceneTree).root.get_node_or_null("GameState")
		if gs != null:
			return gs.ai_factions
	return []

# Executes a BUY_RESOURCE transaction. Returns dict with "ok", "message", "cost".
# Requires player to have gold and a market building.
static func buy(player: Dictionary, resource: String, quantity: int, world: Dictionary) -> Dictionary:
	if quantity <= 0:
		return {"ok": false, "message": "Invalid quantity"}
	if not _has_market(player):
		return {"ok": false, "message": "No market building"}

	var unit_price: int = get_buy_price(resource, world)
	var fee_reduction: float = TechTree.get_all_modifiers(player).get("market_buy_fee_reduction", 0.0)
	if fee_reduction > 0.0:
		unit_price = maxi(1, int(floor(float(unit_price) * (1.0 - fee_reduction))))
	if is_embargoed(player):
		unit_price = ceili(float(unit_price) * 1.40)
	var total_cost: int = unit_price * quantity
	if player.get("gold", 0) < total_cost:
		return {"ok": false, "message": "Insufficient gold (need %d)" % total_cost}

	player["gold"] -= total_cost
	_add_resource(player, resource, quantity)
	return {"ok": true, "message": "", "cost": total_cost}

# Executes a SELL_RESOURCE transaction. Returns dict with "ok", "message", "earned".
static func sell(player: Dictionary, resource: String, quantity: int, world: Dictionary) -> Dictionary:
	if quantity <= 0:
		return {"ok": false, "message": "Invalid quantity"}
	if not _has_market(player):
		return {"ok": false, "message": "No market building"}

	var available: int = _get_resource_amount(player, resource)
	if available < quantity:
		return {"ok": false, "message": "Not enough %s (have %d)" % [resource, available]}

	var unit_price: int = get_sell_price(resource, world)
	var sell_mods: Dictionary = EdictSystem.get_active_modifiers(player)
	var sell_bonus: float = sell_mods.get("market_sell_price_bonus", 0.0)
	if sell_bonus > 0.0:
		unit_price = ceili(float(unit_price) * (1.0 + sell_bonus))
	var earned: int = unit_price * quantity
	_deduct_resource(player, resource, quantity)
	player["gold"] = player.get("gold", 0) + earned
	return {"ok": true, "message": "", "earned": earned}

static func _has_market(player: Dictionary) -> bool:
	for building in player.get("buildings", []):
		if building is Dictionary and building.get("type", "") == "market" and building.get("is_active", true):
			return true
	return false

static func _get_resource_amount(player: Dictionary, resource: String) -> int:
	if resource in player.get("food", {}):
		return player["food"].get(resource, 0)
	if resource in player.get("resources", {}):
		return player["resources"].get(resource, 0)
	if resource in player.get("armory", {}):
		return player["armory"].get(resource, 0)
	return 0

static func _add_resource(player: Dictionary, resource: String, quantity: int) -> void:
	if resource in player.get("food", {}):
		player["food"][resource] = player["food"].get(resource, 0) + quantity
	elif resource in player.get("armory", {}):
		player["armory"][resource] = player["armory"].get(resource, 0) + quantity
	else:
		var resources: Dictionary = player.get("resources", {})
		resources[resource] = resources.get(resource, 0) + quantity

static func _deduct_resource(player: Dictionary, resource: String, quantity: int) -> void:
	if resource in player.get("food", {}):
		player["food"][resource] = maxi(0, player["food"].get(resource, 0) - quantity)
	elif resource in player.get("armory", {}):
		player["armory"][resource] = maxi(0, player["armory"].get(resource, 0) - quantity)
	else:
		var resources: Dictionary = player.get("resources", {})
		resources[resource] = maxi(0, resources.get(resource, 0) - quantity)
