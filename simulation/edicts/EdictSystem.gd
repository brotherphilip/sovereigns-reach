extends RefCounted
# GDD §7 — The Royal Edict System
# 20 edicts across 4 policy categories. Players activate edicts using edict_points.
# Passive edicts apply continuously; active edicts last a fixed number of ticks.

enum EdictType { PASSIVE, ACTIVE }
enum PolicyCategory { ECONOMY, MILITARY, LOGISTICS, CAPITAL }

# Cooldown and duration in game-ticks (240 ticks = 1 game-day).
# GDD §7.1.4: Actives last 12–24 hours real time, but here we use game-days for determinism.
const TICKS_PER_GAME_DAY: int = 240

const EDICTS: Dictionary = {
	# ── §7.2 Economy Policies ─────────────────────────────────────────────
	"agrarian_subsidies": {
		"name": "Agrarian Subsidies",
		"category": PolicyCategory.ECONOMY, "type": EdictType.PASSIVE,
		"cost_points": 2,
		"duration_ticks": 0,   # 0 = permanent while active
		"cooldown_ticks": 0,
		"modifiers": {"orchard_yield_bonus": 0.15},
		"requires_tech": "royal_edicts",
		"description": "Apple Orchards produce 15% more. GDD §7.2.1.",
	},
	"iron_tariffs": {
		"name": "Iron Tariffs",
		"category": PolicyCategory.ECONOMY, "type": EdictType.PASSIVE,
		"cost_points": 3,
		"duration_ticks": 0, "cooldown_ticks": 0,
		"modifiers": {"trade_income_bonus": 0.3},
		"requires_tech": "royal_edicts",
		"description": "Trading posts generate 30% more gold. GDD §7.2.2.",
	},
	"taxation_bumps": {
		"name": "Taxation Bumps",
		"category": PolicyCategory.ECONOMY, "type": EdictType.ACTIVE,
		"cost_points": 4,
		"duration_ticks": TICKS_PER_GAME_DAY,  # 1 game-day
		"cooldown_ticks": TICKS_PER_GAME_DAY * 5,
		"modifiers": {"tax_multiplier": 2.0, "popularity_delta": -15},
		"requires_tech": "royal_edicts",
		"description": "Doubles tax income for 1 day. Massively drops popularity. GDD §7.2.3.",
	},
	"ration_controls": {
		"name": "Ration Controls",
		"category": PolicyCategory.ECONOMY, "type": EdictType.PASSIVE,
		"cost_points": 3,
		"duration_ticks": 0, "cooldown_ticks": 0,
		"modifiers": {"food_consumption_reduction": 0.1},
		"requires_tech": "royal_edicts",
		"description": "Peasants eat 10% less food. No popularity penalty. GDD §7.2.4.",
	},
	"trade_boosts": {
		"name": "Trade Boosts",
		"category": PolicyCategory.ECONOMY, "type": EdictType.ACTIVE,
		"cost_points": 5,
		"duration_ticks": TICKS_PER_GAME_DAY * 2,   # 2 game-days
		"cooldown_ticks": TICKS_PER_GAME_DAY * 10,
		"modifiers": {"market_sell_price_bonus": 0.5},
		"requires_tech": "diplomacy",
		"description": "Market sell prices locked at 50% premium for 2 days. GDD §7.2.5.",
	},

	# ── §7.3 Military Policies ────────────────────────────────────────────
	"forced_march": {
		"name": "Forced March",
		"category": PolicyCategory.MILITARY, "type": EdictType.ACTIVE,
		"cost_points": 5,
		"duration_ticks": TICKS_PER_GAME_DAY * 3,   # 3 game-days (~12 real hours proxy)
		"cooldown_ticks": TICKS_PER_GAME_DAY * 10,
		"modifiers": {"army_speed_multiplier": 2.0},
		"requires_tech": "army_logistics",
		"description": "All allied armies move twice as fast for 3 game-days. GDD §7.3.1.",
	},
	"levy_summons": {
		"name": "Levy Summons",
		"category": PolicyCategory.MILITARY, "type": EdictType.ACTIVE,
		"cost_points": 6,
		"duration_ticks": 1,   # Applied instantly on activation tick
		"cooldown_ticks": TICKS_PER_GAME_DAY * 48,  # 48 game-days = long cooldown
		"modifiers": {"summon_peasants": 50, "popularity_delta": -50},
		"requires_tech": "army_logistics",
		"description": "Instantly summons 50 Armed Peasants. Costs 50 popularity. GDD §7.3.2.",
	},
	"defensive_zeal": {
		"name": "Defensive Zeal",
		"category": PolicyCategory.MILITARY, "type": EdictType.PASSIVE,
		"cost_points": 4,
		"duration_ticks": 0, "cooldown_ticks": 0,
		"modifiers": {"recruitment_cost_reduction": 0.25},
		"requires_tech": "unit_unlocks",
		"description": "Your people answer the call to arms — units cost 25% less gold to recruit. GDD §7.3.3.",
	},
	"siege_repairs": {
		"name": "Siege Repairs",
		"category": PolicyCategory.MILITARY, "type": EdictType.ACTIVE,
		"cost_points": 5,
		"duration_ticks": 1,
		"cooldown_ticks": TICKS_PER_GAME_DAY * 3,
		"modifiers": {"wall_repair_amount": 500},
		"requires_tech": "advanced_masonry",
		"description": "Instantly heals all stone walls. Requires massive stone reserve. GDD §7.3.4.",
	},
	"training_surges": {
		"name": "Training Surges",
		"category": PolicyCategory.MILITARY, "type": EdictType.PASSIVE,
		"cost_points": 5,
		"duration_ticks": 0, "cooldown_ticks": 0,
		"modifiers": {"army_speed_multiplier": 1.5},
		"requires_tech": "training_speed",
		"description": "Drilled troops respond to orders faster — army movement speed ×1.5. GDD §7.3.5.",
	},

	# ── §7.4 Logistics Policies ───────────────────────────────────────────
	"cart_speed": {
		"name": "Cart Speed",
		"category": PolicyCategory.LOGISTICS, "type": EdictType.PASSIVE,
		"cost_points": 2,
		"duration_ticks": 0, "cooldown_ticks": 0,
		"modifiers": {"trade_income_bonus": 0.2},
		"requires_tech": "transport_logistics",
		"description": "Trading posts generate 20% more gold. Stacks with Iron Tariffs. GDD §7.4.1.",
	},
	"storage_expansions": {
		"name": "Storage Expansions",
		"category": PolicyCategory.LOGISTICS, "type": EdictType.PASSIVE,
		"cost_points": 3,
		"duration_ticks": 0, "cooldown_ticks": 0,
		"modifiers": {"storage_capacity_bonus": 0.2, "granary_capacity_bonus": 0.2},
		"requires_tech": "storage_capacity",
		"description": "Granaries hold 20% more food. GDD §7.4.2.",
	},
	"worker_speed": {
		"name": "Worker Speed",
		"category": PolicyCategory.LOGISTICS, "type": EdictType.ACTIVE,
		"cost_points": 4,
		"duration_ticks": TICKS_PER_GAME_DAY * 1,   # 1 game-day (≈ 6 hours proxy)
		"cooldown_ticks": TICKS_PER_GAME_DAY * 5,
		"modifiers": {"food_production_bonus": 0.2},
		"requires_tech": "transport_logistics",
		"description": "Peasants work the fields harder for 1 day — food production +20%. GDD §7.4.3.",
	},
	"weather_resistance": {
		"name": "Weather Resistance",
		"category": PolicyCategory.LOGISTICS, "type": EdictType.PASSIVE,
		"cost_points": 3,
		"duration_ticks": 0, "cooldown_ticks": 0,
		"modifiers": {"rain_movement_penalty": 0.0, "fire_risk_reduction": 1.0},
		"requires_tech": "scouting_vision",
		"description": "Nullifies rain movement penalties. Stops lightning fires. GDD §7.4.4.",
	},
	"border_expansion": {
		"name": "Border Expansion",
		"category": PolicyCategory.LOGISTICS, "type": EdictType.PASSIVE,
		"cost_points": 4,
		"duration_ticks": 0, "cooldown_ticks": 0,
		"modifiers": {"market_sell_price_bonus": 0.2},
		"requires_tech": "diplomacy",
		"description": "Wider trade routes attract better buyers — sell prices +20%. GDD §7.4.5.",
	},

	# ── Additional Edicts (filling the GDD §7 "20 Edicts" count) ──────────
	"festival_decree": {
		"name": "Festival Decree",
		"category": PolicyCategory.ECONOMY, "type": EdictType.ACTIVE,
		"cost_points": 3,
		"duration_ticks": 1,
		"cooldown_ticks": TICKS_PER_GAME_DAY * 7,
		"modifiers": {"popularity_delta": 8},
		"requires_tech": "royal_edicts",
		"description": "Decrees a day of feasting — instantly grants +8 popularity. GDD §3.5.2.",
	},
	"royal_harvest": {
		"name": "Royal Harvest",
		"category": PolicyCategory.ECONOMY, "type": EdictType.ACTIVE,
		"cost_points": 4,
		"duration_ticks": TICKS_PER_GAME_DAY,
		"cooldown_ticks": TICKS_PER_GAME_DAY * 14,
		"modifiers": {"food_production_bonus": 1.0},
		"requires_tech": "farming_speed",
		"description": "All food buildings produce double for 1 game-day.",
	},
	"iron_conscription": {
		"name": "Iron Conscription",
		"category": PolicyCategory.MILITARY, "type": EdictType.ACTIVE,
		"cost_points": 4,
		"duration_ticks": TICKS_PER_GAME_DAY * 3,
		"cooldown_ticks": TICKS_PER_GAME_DAY * 14,
		"modifiers": {"recruitment_cost_reduction": 0.5},
		"requires_tech": "unit_unlocks",
		"description": "Military recruitment gold cost −50% for 3 game-days.",
	},
	"grain_reserves": {
		"name": "Grain Reserves",
		"category": PolicyCategory.ECONOMY, "type": EdictType.PASSIVE,
		"cost_points": 3,
		"duration_ticks": 0, "cooldown_ticks": 0,
		"modifiers": {"food_consumption_reduction": 0.1},
		"requires_tech": "storage_capacity",
		"description": "Food consumption −10%. Stacks with Ration Controls.",
	},
	"diplomatic_tribute": {
		"name": "Diplomatic Tribute",
		"category": PolicyCategory.ECONOMY, "type": EdictType.ACTIVE,
		"cost_points": 6,
		"duration_ticks": 1,
		"cooldown_ticks": TICKS_PER_GAME_DAY * 30,
		"modifiers": {"instant_gold_bonus": 200},
		"requires_tech": "diplomacy",
		"description": "Receive 200 gold as diplomatic tribute. Long cooldown.",
	},
}

# ── Accessors ────────────────────────────────────────────────────────────────

static func lookup(edict_id: String) -> Dictionary:
	return EDICTS.get(edict_id, {})

# Returns true if the player currently has this edict active.
static func is_active(player: Dictionary, edict_id: String) -> bool:
	for edict in player.get("active_edicts", []):
		if edict is Dictionary and edict.get("id", "") == edict_id:
			return true
	return false

# Returns true if the edict is on cooldown for this player.
static func is_on_cooldown(player: Dictionary, edict_id: String, current_tick: int) -> bool:
	var cooldown_key: String = "edict_cooldown_" + edict_id
	var cooldown_until: int = player.get(cooldown_key, 0)
	return current_tick < cooldown_until

# ── Activation ───────────────────────────────────────────────────────────────

# Returns {ok, reason} — whether the player can activate this edict.
static func can_activate(player: Dictionary, edict_id: String, current_tick: int) -> Dictionary:
	var defn: Dictionary = EDICTS.get(edict_id, {})
	if defn.is_empty():
		return {"ok": false, "reason": "Unknown edict: %s" % edict_id}
	var req_tech: String = defn.get("requires_tech", "")
	if req_tech != "" and req_tech not in player.get("tech_unlocks", []):
		return {"ok": false, "reason": "Requires tech: %s" % req_tech}
	var cost: int = defn.get("cost_points", 0)
	if player.get("edict_points", 0) < cost:
		return {"ok": false, "reason": "Insufficient edict points (need %d)" % cost}
	if is_active(player, edict_id):
		return {"ok": false, "reason": "Edict already active"}
	if is_on_cooldown(player, edict_id, current_tick):
		return {"ok": false, "reason": "Edict on cooldown"}
	return {"ok": true, "reason": ""}

# Activates an edict. Deducts edict_points, creates active edict entry, starts cooldown.
# Returns {ok, reason, modifiers}.
static func activate(player: Dictionary, edict_id: String, current_tick: int) -> Dictionary:
	var check: Dictionary = can_activate(player, edict_id, current_tick)
	if not check["ok"]:
		return {"ok": false, "reason": check["reason"]}
	var defn: Dictionary = EDICTS[edict_id]
	player["edict_points"] -= defn.get("cost_points", 0)
	var expires_at: int = current_tick + defn.get("duration_ticks", 0)
	var cooldown_until: int = current_tick + defn.get("cooldown_ticks", 0)
	var entry: Dictionary = {
		"id": edict_id,
		"activated_at": current_tick,
		"expires_at": expires_at,
		"type": defn.get("type", EdictType.PASSIVE),
	}
	var active_edicts: Array = player.get("active_edicts", [])
	active_edicts.append(entry)
	player["active_edicts"] = active_edicts
	if cooldown_until > current_tick:
		player["edict_cooldown_" + edict_id] = cooldown_until
	return {"ok": true, "reason": "", "modifiers": defn.get("modifiers", {})}

# Deactivate an edict by removing it from active_edicts.
static func deactivate(player: Dictionary, edict_id: String) -> bool:
	var active_edicts: Array = player.get("active_edicts", [])
	for i in range(active_edicts.size()):
		if active_edicts[i] is Dictionary and active_edicts[i].get("id", "") == edict_id:
			active_edicts.remove_at(i)
			return true
	return false

# ── Tick ─────────────────────────────────────────────────────────────────────

# Called every tick. Expires active edicts and applies instant-effects.
# Returns Array of expired edict IDs.
static func tick(player: Dictionary, current_tick: int) -> Array:
	var expired: Array = []
	var active_edicts: Array = player.get("active_edicts", [])
	var i: int = active_edicts.size() - 1
	while i >= 0:
		var entry = active_edicts[i]
		if not entry is Dictionary:
			active_edicts.remove_at(i)
			i -= 1
			continue
		var dur: int = EDICTS.get(entry.get("id", ""), {}).get("duration_ticks", 0)
		if dur > 0 and current_tick >= entry.get("expires_at", 0):
			expired.append(entry.get("id", ""))
			active_edicts.remove_at(i)
		i -= 1
	player["active_edicts"] = active_edicts
	return expired

# Returns merged modifier dict for all currently active edicts.
static func get_active_modifiers(player: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for entry in player.get("active_edicts", []):
		if not entry is Dictionary:
			continue
		var edict_id: String = entry.get("id", "")
		var defn: Dictionary = EDICTS.get(edict_id, {})
		for key in defn.get("modifiers", {}):
			var val = defn["modifiers"][key]
			if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
				result[key] = result.get(key, 0.0) + float(val)
			else:
				result[key] = val
	return result
