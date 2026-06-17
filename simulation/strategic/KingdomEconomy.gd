extends RefCounted
# Strategic economy: a kingdom's daily income, army upkeep, and city development.
# "City growth / management / building" is modelled here at the strategic scale —
# develop_city() is the shared primitive both the AI brain and the player's
# DEVELOP_CITY command call, so growth is symmetric.
#
# Pure simulation — operates on world.world_map dicts; no Godot scene imports.

const CampaignMap = preload("res://simulation/strategic/CampaignMap.gd")

# Player holdings earn this multiple of the passive AI per-province gold income, so a
# player who develops their seat can fund an early conquest (see tick_day note).
const PLAYER_INCOME_MULT: float = 4.0

# Settled holdings rebuild their garrison toward the cap by this much per day, so conquered
# land becomes defensible over time instead of being trivially retaken the next day (iter145).
const GARRISON_REGEN_PER_DAY: int = 2

# ── Daily tick ─────────────────────────────────────────────────────────────────

# Collect income from every owned city, pay army upkeep, and decay occupation
# unrest. Returns event strings for telemetry. Deterministic (no RNG).
static func tick_day(world: Dictionary, kingdom: Dictionary, _tick: int) -> Array:
	var events: Array = []
	if not kingdom.get("is_alive", false):
		return events
	var fid: int = kingdom.get("id", -1)

	var gold_gain: int = 0
	var wood_gain: int = 0
	var stone_gain: int = 0
	var iron_gain: int = 0
	var food_gain: int = 0

	for cid in CampaignMap.faction_city_ids(world, fid):
		var c: Dictionary = CampaignMap.city_by_id(world, cid)
		if c.is_empty():
			continue
		var dev: int = c.get("development", c.get("tier", 0))
		var cap_bonus: int = 1 if c.get("is_capital", false) else 0
		# Unrest (recent conquest) suppresses output until it decays.
		var unrest: float = c.get("unrest", 0.0)
		var eff: float = clampf(1.0 - unrest, 0.25, 1.0)
		gold_gain  += int(ceil(float(2 + dev * 2 + cap_bonus * 3) * eff))
		wood_gain  += int(ceil(float(1 + dev) * eff))
		food_gain  += int(ceil(float(2 + dev) * eff))
		stone_gain += int(ceil(float(dev) * 0.5 * eff))
		iron_gain  += int(ceil(float(dev) * 0.34 * eff))
		# Decay unrest toward 0.
		if unrest > 0.0:
			c["unrest"] = maxf(0.0, unrest - 0.1)
		# Garrison slowly rebuilds toward the cap (a settled holding raises militia), so held
		# territory firms up rather than staying at the thin capture-remnant level. PLAYER-only:
		# this makes the player's conquests durable WITHOUT hardening AI/independent targets
		# (which over-throttled the player's own expansion when applied to everyone — iter145).
		if kingdom.get("is_player", false):
			var gcap: int = CampaignMap.garrison_cap(c)
			var gnow: int = c.get("garrison", 0)
			if gnow < gcap:
				c["garrison"] = mini(gcap, gnow + GARRISON_REGEN_PER_DAY)

	# The PLAYER actively develops their seat (the city-view economy), so their holdings
	# yield more strategic gold than a passive AI province. Without this the lone-village
	# player earned only ~2 gold/day and could never fund a first conquest before the AI
	# ate the nearby independents (iter143 evidence). Player-only — AI balance unchanged.
	if kingdom.get("is_player", false):
		gold_gain = int(ceil(float(gold_gain) * PLAYER_INCOME_MULT))

	kingdom["treasury"] = kingdom.get("treasury", 0) + gold_gain
	var res: Dictionary = kingdom.get("resources", {})
	res["wood"]  = res.get("wood", 0)  + wood_gain
	res["stone"] = res.get("stone", 0) + stone_gain
	res["iron"]  = res.get("iron", 0)  + iron_gain
	res["food"]  = res.get("food", 0)  + food_gain
	kingdom["resources"] = res

	# Army upkeep: 1 gold per 4 soldiers per day. If the treasury can't cover it,
	# unpaid armies suffer attrition (desertion) — mirrors the player's gold crunch.
	var total_size: int = 0
	for a in kingdom.get("armies", []):
		if a is Dictionary:
			total_size += a.get("size", 0)
	var upkeep: int = total_size / 4
	if upkeep > 0:
		if kingdom.get("treasury", 0) >= upkeep:
			kingdom["treasury"] = kingdom["treasury"] - upkeep
		else:
			kingdom["treasury"] = 0
			_apply_attrition(kingdom)
			events.append("army_attrition")

	return events

# Unpaid armies bleed ~10% of their strength.
static func _apply_attrition(kingdom: Dictionary) -> void:
	for a in kingdom.get("armies", []):
		if a is Dictionary:
			a["size"] = maxi(0, int(float(a.get("size", 0)) * 0.9))

# ── City development (the build/grow/manage primitive) ──────────────────────────

# Cost to raise a city from its current development level to the next.
static func development_cost(level: int) -> Dictionary:
	return {
		"gold": 30 + level * 20,
		"wood": 20 + level * 10,
		"stone": 10 + level * 8,
	}

static func can_develop(world: Dictionary, kingdom: Dictionary, city_id: int) -> bool:
	var c: Dictionary = CampaignMap.city_by_id(world, city_id)
	if c.is_empty():
		return false
	if CampaignMap.owner_of(c) != kingdom.get("id", -1):
		return false
	var level: int = c.get("development", c.get("tier", 0))
	if level >= CampaignMap.MAX_DEVELOPMENT:
		return false
	var cost: Dictionary = development_cost(level)
	var res: Dictionary = kingdom.get("resources", {})
	return kingdom.get("treasury", 0) >= cost["gold"] \
		and res.get("wood", 0) >= cost["wood"] \
		and res.get("stone", 0) >= cost["stone"]

# Invest in a city: raises development by 1, bumps its visual tier, and grows its
# garrison toward the new (higher) cap. Returns true on success.
static func develop_city(world: Dictionary, kingdom: Dictionary, city_id: int) -> bool:
	if not can_develop(world, kingdom, city_id):
		return false
	var c: Dictionary = CampaignMap.city_by_id(world, city_id)
	var level: int = c.get("development", c.get("tier", 0))
	var cost: Dictionary = development_cost(level)
	kingdom["treasury"] = kingdom.get("treasury", 0) - cost["gold"]
	var res: Dictionary = kingdom.get("resources", {})
	res["wood"]  = res.get("wood", 0)  - cost["wood"]
	res["stone"] = res.get("stone", 0) - cost["stone"]
	kingdom["resources"] = res

	c["development"] = level + 1
	# Visual tier tracks development (0..3 band used by the renderer).
	c["tier"] = clampi(maxi(c.get("tier", 0), 1 + (level + 1) / 3), 0, 3)
	# Growing a city also raises its population and trains some defenders.
	c["population"] = c.get("population", 0) + 150
	var cap: int = CampaignMap.garrison_cap(c)
	c["garrison"] = mini(cap, c.get("garrison", 0) + 4)
	return true

# The kingdom's least-developed owned city (ties broken by lowest id) — the
# natural next investment so growth spreads across the realm.
static func lowest_dev_city(world: Dictionary, kingdom: Dictionary) -> int:
	var best_id: int = -1
	var best_dev: int = CampaignMap.MAX_DEVELOPMENT + 1
	for cid in CampaignMap.faction_city_ids(world, kingdom.get("id", -1)):
		var c: Dictionary = CampaignMap.city_by_id(world, cid)
		if c.is_empty():
			continue
		var dev: int = c.get("development", c.get("tier", 0))
		if dev < best_dev:
			best_dev = dev
			best_id = cid
	return best_id

# Total development across all cities a faction owns — used by tests/telemetry to
# show the realm is being built up.
static func total_development(world: Dictionary, faction_id: int) -> int:
	var sum: int = 0
	for cid in CampaignMap.faction_city_ids(world, faction_id):
		var c: Dictionary = CampaignMap.city_by_id(world, cid)
		sum += c.get("development", 0)
	return sum
