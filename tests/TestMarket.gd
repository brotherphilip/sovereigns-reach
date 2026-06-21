extends SceneTree
# Proof harness: the market must never allow riskless SELF-ARBITRAGE — buying a resource and
# immediately re-selling it must never net positive gold, under ANY edict/tech modifier combo.
#
# Regression for the iter261 exploit: the +50% sell-premium edict ("trade_boosts") and the
# +20% premium ("border_expansion") combined with the −10% buy-fee tech ("diplomacy") pushed
# the SELL price above the 20% BUY markup, so buy < sell → buy-low/sell-high → exponential gold.
# Root fix: MarketSystem.buy() clamps the charged unit price strictly above the effective sell
# price, preserving the buy>sell spread invariant under all modifiers.
# Run: godot --headless --script tests/TestMarket.gd

const MarketSystem = preload("res://simulation/economy/MarketSystem.gd")

var _pass := 0
var _fail := 0

func _init() -> void:
	_test_round_trip_never_profits()
	_test_spread_invariant_per_unit()
	print("\n=== Market Results: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func ok(label: String, cond: bool) -> void:
	if cond: _pass += 1; print("  PASS: %s" % label)
	else: _fail += 1; print("  FAIL: %s" % label)

func _player(edicts: Array, techs: Array) -> Dictionary:
	return {
		"id": 0, "gold": 1000000,
		"resources": {"wood": 1000000, "iron": 1000000},
		"food": {"apples": 1000000},
		"armory": {"swords": 1000000},
		"buildings": [{"type": "market", "is_active": true}],
		"active_edicts": edicts, "tech_unlocks": techs,
	}

func _world() -> Dictionary:
	var w: Dictionary = {}
	MarketSystem.initialize_prices(w)
	return w

# Each scenario: a label + the modifier loadout the player carries.
func _scenarios() -> Array:
	return [
		["no modifiers", [], []],
		["+50% sell edict (trade_boosts)", [{"id": "trade_boosts"}], []],
		["+20% sell edict (border_expansion)", [{"id": "border_expansion"}], []],
		["-10% buy-fee tech (diplomacy)", [], ["diplomacy"]],
		["+20% sell edict + buy-fee tech", [{"id": "border_expansion"}], ["diplomacy"]],
		["+50% sell edict + buy-fee tech", [{"id": "trade_boosts"}], ["diplomacy"]],
	]

# Buying N then re-selling N of a resource must NEVER leave the player richer.
func _test_round_trip_never_profits() -> void:
	print("\n[Buy→sell round-trip never nets positive gold]")
	var n: int = 500
	for sc in _scenarios():
		for res in ["wood", "iron", "swords"]:
			var p: Dictionary = _player(sc[1], sc[2])
			var w: Dictionary = _world()
			var g0: int = p["gold"]
			var rb: Dictionary = MarketSystem.buy(p, res, n, w)
			var rs: Dictionary = MarketSystem.sell(p, res, n, w)
			ok("%s: buy %s succeeds" % [sc[0], res], rb.get("ok", false))
			ok("%s: sell %s succeeds" % [sc[0], res], rs.get("ok", false))
			var net: int = p["gold"] - g0
			ok("%s: round-trip %s nets <= 0 (got %d)" % [sc[0], res, net], net <= 0)

# Per-unit: the charged buy price must be strictly greater than the received sell price,
# the spread invariant that makes market self-arbitrage impossible.
func _test_spread_invariant_per_unit() -> void:
	print("\n[Buy unit price > sell unit price under every modifier loadout]")
	for sc in _scenarios():
		for res in ["wood", "iron", "swords"]:
			var p: Dictionary = _player(sc[1], sc[2])
			var w: Dictionary = _world()
			var buy: Dictionary = MarketSystem.buy(p, res, 1, w)
			var sell: Dictionary = MarketSystem.sell(p, res, 1, w)
			var buy_unit: int = int(buy.get("cost", 0))
			var sell_unit: int = int(sell.get("earned", 0))
			ok("%s: buy(%s)=%d > sell=%d" % [sc[0], res, buy_unit, sell_unit], buy_unit > sell_unit)
