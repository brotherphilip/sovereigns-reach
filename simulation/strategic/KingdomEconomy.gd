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

# ── Honest AI economy (iter204) ──────────────────────────────────────────────────
# Previously AI kingdoms GAINED food/wood/stone/iron every day but only ever SPENT
# gold (upkeep) + wood/stone (development) — so food & iron grew without bound (the
# realm was "getting food for free; people weren't eating"), and wood ballooned past
# what development drew. These constants give AI kingdoms a real consume-and-cap
# economy: their people EAT food daily, and every store is capped to the realm's
# holdings (overflow discarded, exactly like the player's granary/stockpiles). All of
# this is AI-ONLY (gated on `not is_player`) so the verified player King-climb economy
# is untouched.
# Upkeep sits BELOW a settled city's food output (gain = 2 + dev), so a well-governed
# realm keeps a growing surplus (capped) — but a freshly-conquered city's output is
# unrest-suppressed (×0.25–1.0) while its mouths still eat in full, so an over-extended
# conqueror's buffer drains and it starves. Food becomes a brake on reckless expansion,
# not a constant famine.
const FOOD_UPKEEP_BASE: float    = 1.0   # mouths fed per city per day…
const FOOD_UPKEEP_PER_DEV: float = 0.6   # …plus this per development level (bigger city eats more)
# Storage caps scale with how many cities the realm holds (more holdings = more barns).
const FOOD_CAP_BASE: int     = 150
const FOOD_CAP_PER_CITY: int = 60
const RAW_CAP_BASE: int      = 200       # per raw good (wood / stone / iron)
const RAW_CAP_PER_CITY: int  = 80
const RAW_GOODS: Array       = ["wood", "stone", "iron"]

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

	# AI kingdoms run an honest consume-and-cap economy (player strategic stores untouched).
	if not kingdom.get("is_player", false):
		_consume_and_cap(world, kingdom, events)

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

# AI-only: the realm's people EAT (food upkeep scaling with city development), then every
# store is clamped to the realm's holdings-based capacity (overflow discarded, like the
# player's granary/stockpiles). Sets `food_starving` for the brain to read: a realm that
# can't feed itself can't grow and bleeds garrison as people drift away. This bounds the
# runaway food/iron/wood hoards and makes over-expansion (many unrest-suppressed cities)
# a real strain instead of free surplus.
static func _consume_and_cap(world: Dictionary, kingdom: Dictionary, events: Array) -> void:
	var fid: int = kingdom.get("id", -1)
	var res: Dictionary = kingdom.get("resources", {})
	var cids: Array = CampaignMap.faction_city_ids(world, fid)
	var n_cities: int = cids.size()

	# Food upkeep — every city's mouths eat, bigger (more-developed) cities eat more.
	var demand: float = 0.0
	for cid in cids:
		var c: Dictionary = CampaignMap.city_by_id(world, cid)
		demand += FOOD_UPKEEP_BASE + FOOD_UPKEEP_PER_DEV * float(c.get("development", c.get("tier", 0)))
	var food: int = int(res.get("food", 0))
	var need: int = int(ceil(demand))
	if food >= need:
		food -= need
		kingdom["food_starving"] = false
	else:
		# Not enough to feed the realm — eat what there is and starve.
		food = 0
		kingdom["food_starving"] = true
		events.append("kingdom_starving")
		# People drift from the hungriest holding: shed garrison from the least-defended city.
		_shed_starving_garrison(world, fid)
	res["food"] = food

	# Storage caps — stores can't balloon past what the realm can hold; overflow is lost.
	var food_cap: int = FOOD_CAP_BASE + FOOD_CAP_PER_CITY * n_cities
	res["food"] = mini(int(res.get("food", 0)), food_cap)
	var raw_cap: int = RAW_CAP_BASE + RAW_CAP_PER_CITY * n_cities
	for g in RAW_GOODS:
		res[g] = mini(int(res.get(g, 0)), raw_cap)
	kingdom["resources"] = res

# Remove a point of garrison from the realm's least-defended owned city (hunger drives
# people away). Keeps a floor of 0 and never touches other realms.
static func _shed_starving_garrison(world: Dictionary, fid: int) -> void:
	var worst_id: int = -1
	var worst_g: int = 1 << 30
	for cid in CampaignMap.faction_city_ids(world, fid):
		var c: Dictionary = CampaignMap.city_by_id(world, cid)
		var g: int = int(c.get("garrison", 0))
		if g > 0 and g < worst_g:
			worst_g = g
			worst_id = cid
	if worst_id >= 0:
		var c2: Dictionary = CampaignMap.city_by_id(world, worst_id)
		c2["garrison"] = maxi(0, int(c2.get("garrison", 0)) - 1)

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
