extends RefCounted
# The strategic brain for an AI kingdom. Each game-day it makes the same kinds of
# decisions a human player makes through the strategic commands: invest in city
# development (growth/build/manage), raise armies, launch campaigns against the
# weakest reachable enemy city, and conduct diplomacy (extract tribute / make
# truce). Choices are weighted by the kingdom's personality so factions feel
# distinct, and every random draw is seeded for determinism.
#
# Pure simulation — operates on world.world_map dicts; no Godot scene imports.

const CampaignMap    = preload("res://simulation/strategic/CampaignMap.gd")
const KingdomEconomy = preload("res://simulation/strategic/KingdomEconomy.gd")
const CampaignSystem = preload("res://simulation/strategic/CampaignSystem.gd")

const TICKS_PER_DAY: int = 240
const TRIBUTE_COOLDOWN_DAYS: int = 12

# Decide and enact this kingdom's strategic actions for the day. Returns events.
static func decide(world: Dictionary, kingdom: Dictionary, players: Array, tick: int) -> Array:
	var events: Array = []
	if not kingdom.get("is_alive", false) or kingdom.get("is_player", false):
		return events  # the player drives their own kingdom via commands

	var p: Dictionary = kingdom.get("personality", CampaignMap.DEFAULT_PERSONALITY)
	var rng := RandomNumberGenerator.new()
	rng.seed = (tick * 2246822519) ^ (kingdom.get("id", 0) * 3266489917)

	# 1) Economy — invest in development. Richer/more-economic factions invest more.
	var invest_budget: int = int(80.0 * (1.3 - p.get("economy", 0.6)))
	var invests: int = 1 + int(p.get("economy", 0.6) * 2.0)
	for _i in range(invests):
		if kingdom.get("treasury", 0) < invest_budget:
			break
		var dev_target: int = KingdomEconomy.lowest_dev_city(world, kingdom)
		if dev_target < 0 or not KingdomEconomy.develop_city(world, kingdom, dev_target):
			break
		events.append("city_developed")

	# 2) Military — find the weakest reachable enemy city and, if we can muster a
	#    force strong enough, raise an army at the staging city and march at once.
	var plan: Dictionary = _best_target(world, kingdom)
	if not plan.is_empty():
		var target_def: int = plan["defense"]
		var from_id: int = plan["from_id"]
		var target_id: int = plan["target_id"]
		# Aggressive factions accept worse odds; cautious ones want a clear margin.
		var needed: int = maxi(3, int(float(target_def) * (1.25 - p.get("aggression", 0.6) * 0.45)))
		needed = mini(needed, CampaignSystem.MAX_ARMY_SIZE)

		# How big a force can we already field from a stationed army at from_id?
		var existing: int = _idle_army_size_at(kingdom, from_id)
		var shortfall: int = maxi(0, needed - existing)
		if shortfall > 0 and CampaignSystem.can_raise_army(world, kingdom, from_id, shortfall):
			CampaignSystem.raise_army(world, kingdom, from_id, shortfall)
			events.append("army_raised")

		# Launch if we now have the strength staged adjacent to the target.
		var army_id: int = _idle_army_id_at(kingdom, from_id)
		if army_id >= 0 and _idle_army_size_at(kingdom, from_id) >= needed:
			if CampaignSystem.launch_campaign(world, kingdom, army_id, target_id):
				events.append("campaign_launched")

	# 3) Build standing defence when there's nothing worth attacking but coffers
	#    are full — defensive factions especially keep garrisons strong.
	elif kingdom.get("treasury", 0) > 200 and rng.randf() < p.get("defense", 0.6):
		var dev_target2: int = KingdomEconomy.lowest_dev_city(world, kingdom)
		if dev_target2 >= 0 and KingdomEconomy.develop_city(world, kingdom, dev_target2):
			events.append("city_developed")

	# 4) Diplomacy — periodically squeeze a weaker neighbour for tribute.
	var diplo: String = _diplomacy(world, kingdom, tick, p)
	if diplo != "":
		events.append(diplo)

	return events

# ── Target selection ───────────────────────────────────────────────────────────

# Are these two factions at a sworn truce? (Honoured by attack targeting, so a truce
# the player negotiates actually keeps the rival's armies off their lands.)
static func _at_truce(kingdom: Dictionary, other_fid: int) -> bool:
	return String(kingdom.get("relations", {}).get(str(other_fid), "neutral")) == "truce"

# Weakest enemy city adjacent to one we own, plus the owned city to stage from.
# Skips cities held by kingdoms we're at truce with. Returns {} if no valid frontier.
static func _best_target(world: Dictionary, kingdom: Dictionary) -> Dictionary:
	var fid: int = kingdom.get("id", -1)
	var best: Dictionary = {}
	var best_def: int = 1 << 30
	for cid in CampaignMap.faction_city_ids(world, fid):
		var c: Dictionary = CampaignMap.city_by_id(world, cid)
		if c.is_empty():
			continue
		for nid in CampaignMap.neighbor_ids(c):
			var n: Dictionary = CampaignMap.city_by_id(world, nid)
			if n.is_empty() or CampaignMap.owner_of(n) == fid:
				continue
			if _at_truce(kingdom, CampaignMap.owner_of(n)):
				continue  # honour the truce — don't march on their cities
			var d: int = CampaignMap.city_defense(n)
			if d < best_def:
				best_def = d
				best = {"target_id": nid, "from_id": cid, "defense": d}
	return best

static func _idle_army_id_at(kingdom: Dictionary, city_id: int) -> int:
	for a in kingdom.get("armies", []):
		if a is Dictionary and a.get("location_city_id", -1) == city_id and a.get("path", []).is_empty():
			return a.get("id", -1)
	return -1

static func _idle_army_size_at(kingdom: Dictionary, city_id: int) -> int:
	var s: int = 0
	for a in kingdom.get("armies", []):
		if a is Dictionary and a.get("location_city_id", -1) == city_id and a.get("path", []).is_empty():
			s += a.get("size", 0)
	return s

# ── Diplomacy ──────────────────────────────────────────────────────────────────

# Extract tribute from the weakest neighbouring kingdom (transfers gold, hardens
# relations to "war"). Returns an event string, or "" if nothing happened.
static func _diplomacy(world: Dictionary, kingdom: Dictionary, tick: int, p: Dictionary) -> String:
	if tick < kingdom.get("tribute_cooldown_until", 0):
		return ""
	var fid: int = kingdom.get("id", -1)
	var my_strength: int = _kingdom_strength(world, kingdom)

	# Find neighbouring kingdoms (owners of frontier cities).
	var neighbour_fids: Dictionary = {}
	for tid in CampaignMap.frontier_targets(world, fid):
		var t: Dictionary = CampaignMap.city_by_id(world, tid)
		var ofid: int = CampaignMap.owner_of(t)
		if ofid != fid and ofid >= 0:
			neighbour_fids[ofid] = true

	var weakest_fid: int = -1
	var weakest_strength: int = 1 << 30
	for nfid in neighbour_fids.keys():
		var nk: Dictionary = CampaignMap.kingdom_by_id(world, nfid)
		if nk.is_empty() or not nk.get("is_alive", false):
			continue
		# Never silently loot the PLAYER's strategic treasury — the player faces tribute
		# through the player-facing envoy event (accept/refuse), not an automatic drain that
		# kept the lone-village player permanently broke and unable to ever expand (iter143).
		if nk.get("is_player", false):
			continue
		var s: int = _kingdom_strength(world, nk)
		if s < weakest_strength:
			weakest_strength = s
			weakest_fid = nfid

	if weakest_fid < 0 or weakest_strength >= my_strength:
		return ""

	var rival: Dictionary = CampaignMap.kingdom_by_id(world, weakest_fid)
	var amount: int = mini(rival.get("treasury", 0), 40 + int(p.get("aggression", 0.6) * 60.0))
	if amount <= 0:
		return ""
	rival["treasury"] = rival.get("treasury", 0) - amount
	kingdom["treasury"] = kingdom.get("treasury", 0) + amount
	kingdom.get("relations", {})[str(weakest_fid)] = "war"
	rival.get("relations", {})[str(fid)] = "war"
	kingdom["tribute_cooldown_until"] = tick + TICKS_PER_DAY * TRIBUTE_COOLDOWN_DAYS
	return "tribute_extracted"

# Rough overall power: treasury + summed defence of owned cities + fielded armies.
static func _kingdom_strength(world: Dictionary, kingdom: Dictionary) -> int:
	var fid: int = kingdom.get("id", -1)
	var s: int = kingdom.get("treasury", 0) / 10
	for cid in CampaignMap.faction_city_ids(world, fid):
		var c: Dictionary = CampaignMap.city_by_id(world, cid)
		s += CampaignMap.city_defense(c)
	s += CampaignSystem.total_army_size(kingdom)
	return s
